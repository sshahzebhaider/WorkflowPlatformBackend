/* SQL 32 — non-destructive: team workload redistribution and elapsed-hour TAT.
   Run only after the existing platform migrations through 30 have completed.
   This script does not overwrite work.usp_CreateCase or existing case deadlines. */
USE [WorkflowPlatformV2];
GO
SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE work.usp_RebalanceTeamTasks
 @ActorUserId BIGINT,
 @ProjectId BIGINT,
 @TeamId BIGINT,
 @TaskIdsJson NVARCHAR(MAX),
 @ToUserId BIGINT,
 @Reason NVARCHAR(500) = NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF @ProjectId IS NULL OR @TeamId IS NULL OR @ToUserId IS NULL
     THROW 50410, 'Project, team and recipient are required.', 1;
 IF ISJSON(@TaskIdsJson)<>1 OR LEFT(LTRIM(@TaskIdsJson),1)<>N'['
     THROW 50411, 'Task IDs must be a JSON array.', 1;
 IF LEN(ISNULL(@Reason,N''))>500 THROW 50412, 'Reason cannot exceed 500 characters.', 1;

 DECLARE @Ids TABLE (TaskId BIGINT NOT NULL PRIMARY KEY);
 IF EXISTS(SELECT 1 FROM OPENJSON(@TaskIdsJson)
   WHERE TRY_CONVERT(BIGINT,[value]) IS NULL OR TRY_CONVERT(BIGINT,[value])<=0 OR [type] NOT IN(1,2))
     THROW 50413, 'Invalid task ID in selection.', 1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@TaskIdsJson)
    GROUP BY TRY_CONVERT(BIGINT,[value]) HAVING COUNT(*)>1)
     THROW 50414, 'Duplicate task IDs are not allowed.', 1;
 INSERT @Ids(TaskId) SELECT TRY_CONVERT(BIGINT,[value]) FROM OPENJSON(@TaskIdsJson);
 DECLARE @Total INT=(SELECT COUNT(*) FROM @Ids);
 IF @Total<1 OR @Total>50 THROW 50415, 'Choose between 1 and 50 tasks.', 1;

 BEGIN TRANSACTION;
 IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@TeamId AND ProjectId=@ProjectId AND IsActive=1)
 BEGIN ROLLBACK; THROW 50416, 'Team does not belong to the active project.', 1; END;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 AND NOT EXISTS(
     SELECT 1 FROM teams.Members m WHERE m.TeamId=@TeamId AND m.UserId=@ActorUserId
       AND m.IsActive=1 AND m.TeamRole IN('TeamLead','UnitHead'))
 BEGIN ROLLBACK; THROW 50417, 'Only a Team Lead, Unit Head or Project Admin can rebalance work.', 1; END;
 IF NOT EXISTS(SELECT 1 FROM auth.Users u JOIN teams.Members m ON m.UserId=u.UserId
   WHERE u.UserId=@ToUserId AND m.TeamId=@TeamId AND m.IsActive=1
     AND u.IsActive=1 AND u.DirectoryStatus='Active')
 BEGIN ROLLBACK; THROW 50418, 'Recipient must be an active team member.', 1; END;
 IF EXISTS(SELECT 1 FROM teams.Absences a WHERE a.TeamId=@TeamId AND a.UserId=@ToUserId AND a.IsActive=1
     AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN a.StartDate AND a.EndDate)
 BEGIN ROLLBACK; THROW 50419, 'Recipient is currently on leave.', 1; END;

 -- Acquire task row locks and verify every selected task before making any change.
 DECLARE @Before TABLE (TaskId BIGINT PRIMARY KEY,CaseId BIGINT NOT NULL,
   OldUserId BIGINT NULL,RoutingStage VARCHAR(15) NOT NULL);
 INSERT @Before(TaskId,CaseId,OldUserId,RoutingStage)
 SELECT t.TaskId,c.CaseId,t.AssignedTo,t.RoutingStage
 FROM work.Tasks t WITH (UPDLOCK,HOLDLOCK)
 JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId
 JOIN @Ids selected ON selected.TaskId=t.TaskId
 WHERE c.ProjectId=@ProjectId AND t.TeamId=@TeamId AND t.Status='Open';
 IF (SELECT COUNT(*) FROM @Before)<>@Total
 BEGIN ROLLBACK; THROW 50420, 'Task selection contains an unavailable, completed or cross-project task.', 1; END;
 IF EXISTS(SELECT 1 FROM @Before WHERE OldUserId=@ToUserId)
 BEGIN ROLLBACK; THROW 50421, 'Recipient already owns one of the selected tasks.', 1; END;
 IF EXISTS(SELECT 1 FROM @Before b WHERE NOT EXISTS(
   SELECT 1 FROM teams.Members m WHERE m.TeamId=@TeamId AND m.UserId=@ToUserId AND m.IsActive=1
   AND m.TeamRole=CASE WHEN b.RoutingStage='Unassigned' THEN 'Officer' ELSE b.RoutingStage END))
 BEGIN ROLLBACK; THROW 50422, 'Recipient must belong to the same workflow review role for each task.', 1; END;

 UPDATE t SET AssignedTo=@ToUserId,DelegatedFor=NULL,
   AssignedAt=SYSUTCDATETIME(),
   RoutingStage=CASE WHEN t.RoutingStage='Unassigned' THEN 'Officer' ELSE t.RoutingStage END
 FROM work.Tasks t JOIN @Before b ON b.TaskId=t.TaskId;

 INSERT work.TaskHandoffs(TaskId,FromUserId,ToUserId,RoutingStage,ActorUserId,Reason)
 SELECT b.TaskId,b.OldUserId,@ToUserId,
   CASE WHEN b.RoutingStage='Unassigned' THEN 'Officer' ELSE b.RoutingStage END,
   @ActorUserId,COALESCE(NULLIF(LTRIM(RTRIM(@Reason)),N''),N'Manager workload balancing')
 FROM @Before b;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 SELECT b.CaseId,'TaskRebalanced',N'Team manager redistributed an open task',@ActorUserId,
   (SELECT b.TaskId AS taskId,b.OldUserId AS previousUserId,@ToUserId AS newUserId
      FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
 FROM @Before b;
 INSERT audit.Events(ProjectId,ActorUserId,EntityType,EntityId,ActionCode,DetailsJson)
 SELECT @ProjectId,@ActorUserId,'Task',b.TaskId,'Rebalance',
   (SELECT @TeamId AS teamId,b.OldUserId AS previousUserId,@ToUserId AS newUserId
      FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
 FROM @Before b;
 COMMIT;
 SELECT @Total AS ReassignedCount;
END;
GO

/* Case Type configuration already persists in PublishedConfigJson. No new column needed.
   The existing work.usp_CreateCase handles Working Hours; this INSERT trigger adjusts only
   newly created Calendar Hours cases, before the transaction commits. */
CREATE OR ALTER TRIGGER work.trg_Cases_ElapsedTatDueAt
ON work.Cases
AFTER INSERT
AS
BEGIN
 SET NOCOUNT ON;
 UPDATE c SET DueAt=DATEADD(MINUTE,COALESCE(v.SlaMinutes,p.DefaultSlaMinutes),c.CreatedAt)
 FROM work.Cases c
 JOIN inserted i ON i.CaseId=c.CaseId
 JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=i.CaseTypeVersionId
 JOIN core.Projects p ON p.ProjectId=i.ProjectId
 WHERE JSON_VALUE(v.PublishedConfigJson,'$.tatMode')='elapsed'
   AND COALESCE(v.SlaMinutes,p.DefaultSlaMinutes) IS NOT NULL;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'workflow_app_v2') IS NOT NULL
 GRANT EXECUTE ON OBJECT::work.usp_RebalanceTeamTasks TO [workflow_app_v2];
GO
-- Fail loudly: do not report a misleading success after a failed migration.
IF OBJECT_ID(N'work.usp_RebalanceTeamTasks',N'P') IS NULL
    THROW 50430,'Missing work.usp_RebalanceTeamTasks',1;
IF OBJECT_ID(N'work.trg_Cases_ElapsedTatDueAt',N'TR') IS NULL
    THROW 50431,'Missing work.trg_Cases_ElapsedTatDueAt',1;
PRINT N'PASS: workload rebalancing and elapsed-hour case TAT installed.';
GO
