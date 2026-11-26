USE [WorkflowPlatformV2];
GO
/* One escalation per task; no automatic approval of a human task. */
IF OBJECT_ID(N'work.SlaEscalations',N'U') IS NULL
CREATE TABLE work.SlaEscalations(
 TaskId BIGINT NOT NULL CONSTRAINT PK_SlaEscalations PRIMARY KEY REFERENCES work.Tasks(TaskId),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 EscalatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 NotificationId BIGINT NULL REFERENCES notify.Outbox(NotificationId));
GO
CREATE OR ALTER PROCEDURE work.usp_ActivateNode
 @InstanceId BIGINT,@NodeId BIGINT,@ActorUserId BIGINT=NULL,@Depth INT=0,@SourceNodeId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @Depth>25 THROW 50151,'Workflow contains a cycle or exceeds safe activation depth.',1;
 DECLARE @WorkflowVersionId BIGINT,@CaseId BIGINT,@ProjectId BIGINT,
 @Kind VARCHAR(30),@TeamId BIGINT,@Mode VARCHAR(20),@Role VARCHAR(20),@SlaMinutes INT,
 @NodeConfig NVARCHAR(MAX),@StartAt DATETIME2(3)=SYSUTCDATETIME(),@DueAt DATETIME2(3),@CalendarId BIGINT;
 SELECT @WorkflowVersionId=i.WorkflowVersionId,@CaseId=i.CaseId,@ProjectId=c.ProjectId,@CalendarId=p.CalendarId
 FROM work.Instances i JOIN work.Cases c ON c.CaseId=i.CaseId
 JOIN core.Projects p ON p.ProjectId=c.ProjectId WHERE i.InstanceId=@InstanceId;
 SELECT @Kind=NodeType,@TeamId=TeamId,@Mode=AssignmentMode,@Role=AssignedRole,@SlaMinutes=SlaMinutes,@NodeConfig=ConfigJson
 FROM flow.Nodes WHERE NodeId=@NodeId AND WorkflowVersionId=@WorkflowVersionId;
 IF @Kind IS NULL THROW 50152,'Node is not part of this workflow version.',1;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 VALUES(@CaseId,'StepEntered',CONCAT('Entered ',@Kind),@ActorUserId,(SELECT CONVERT(NVARCHAR(36),@NodeId) AS nodeId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 IF @Kind='start'
 BEGIN
  DECLARE @FirstNode BIGINT;
  SELECT TOP(1) @FirstNode=TargetNodeId FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
  IF @FirstNode IS NULL THROW 50153,'Start node has no outgoing connection.',1;
  DECLARE @NextDepth INT=@Depth+1;
  EXEC work.usp_ActivateNode @InstanceId,@FirstNode,@ActorUserId,@Depth=@NextDepth,@SourceNodeId=@NodeId;
  RETURN;
 END;
 IF @Kind='decision'
 BEGIN
  DECLARE @Field VARCHAR(100)=JSON_VALUE(@NodeConfig,'$.conditionField');
  DECLARE @Operator VARCHAR(25)=ISNULL(JSON_VALUE(@NodeConfig,'$.conditionOperator'),'equals');
  DECLARE @Expected NVARCHAR(1000)=ISNULL(JSON_VALUE(@NodeConfig,'$.conditionValue'),N'');
  DECLARE @Actual NVARCHAR(1000),@Yes BIT=0,@TargetNode BIGINT;
  IF NULLIF(@Field,'') IS NULL OR @Field COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%' OR LEN(@Field)>100
    THROW 50323,'Decision must select a valid case field.',1;
  IF @Field='title' SELECT @Actual=Title FROM work.Cases WHERE CaseId=@CaseId;
  ELSE SELECT @Actual=JSON_VALUE(CurrentValuesJson,CONCAT('$.',@Field)) FROM work.Cases WHERE CaseId=@CaseId;
  SET @Yes=CASE @Operator
   WHEN 'equals' THEN CASE WHEN ISNULL(@Actual,N'')=@Expected THEN 1 ELSE 0 END
   WHEN 'notEquals' THEN CASE WHEN ISNULL(@Actual,N'')<>@Expected THEN 1 ELSE 0 END
   WHEN 'contains' THEN CASE WHEN CHARINDEX(@Expected,ISNULL(@Actual,N''))>0 THEN 1 ELSE 0 END
   WHEN 'greaterThan' THEN CASE WHEN TRY_CONVERT(DECIMAL(28,8),@Actual)>TRY_CONVERT(DECIMAL(28,8),@Expected) THEN 1 ELSE 0 END
   WHEN 'isEmpty' THEN CASE WHEN NULLIF(LTRIM(RTRIM(@Actual)),N'') IS NULL THEN 1 ELSE 0 END
   WHEN 'notEmpty' THEN CASE WHEN NULLIF(LTRIM(RTRIM(@Actual)),N'') IS NOT NULL THEN 1 ELSE 0 END
   ELSE NULL END;
  IF @Yes IS NULL THROW 50324,'Unsupported decision comparison.',1;
  SELECT TOP(1) @TargetNode=TargetNodeId FROM flow.Edges
  WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId
    AND LOWER(OutcomeCode)=CASE WHEN @Yes=1 THEN 'yes' ELSE 'no' END ORDER BY SortOrder;
  IF @TargetNode IS NULL THROW 50325,'Decision is missing its Yes/No outgoing edge.',1;
  INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
  VALUES(@CaseId,'DecisionEvaluated',CASE WHEN @Yes=1 THEN N'Decision matched' ELSE N'Decision not matched' END,
    (SELECT CONVERT(NVARCHAR(36),@NodeId) AS nodeId,CASE WHEN @Yes=1 THEN 'Yes' ELSE 'No' END AS branch FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
  DECLARE @DecisionNextDepth INT = @Depth + 1;
  EXEC work.usp_ActivateNode @InstanceId,@TargetNode,@ActorUserId,@Depth=@DecisionNextDepth,@SourceNodeId=@NodeId;
  RETURN;
 END;
 IF @Kind='parallel'
 BEGIN
  DECLARE @ParallelMode VARCHAR(15)=JSON_VALUE(@NodeConfig,'$.parallelMode');
  IF @ParallelMode='split'
  BEGIN
   DECLARE @SplitTarget BIGINT,@SplitDepth INT=@Depth+1;
   DECLARE splitEdges CURSOR LOCAL FAST_FORWARD FOR SELECT TargetNodeId FROM flow.Edges
    WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
   OPEN splitEdges;FETCH NEXT FROM splitEdges INTO @SplitTarget;
   WHILE @@FETCH_STATUS=0
   BEGIN
    EXEC work.usp_ActivateNode @InstanceId,@SplitTarget,@ActorUserId,@Depth=@SplitDepth,@SourceNodeId=@NodeId;
    FETCH NEXT FROM splitEdges INTO @SplitTarget;
   END;
   CLOSE splitEdges;DEALLOCATE splitEdges;
   RETURN;
  END;
  IF @ParallelMode='join'
  BEGIN
   IF @SourceNodeId IS NULL OR NOT EXISTS(SELECT 1 FROM flow.Edges
      WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@SourceNodeId AND TargetNodeId=@NodeId)
     THROW 50337,'Join must receive a valid incoming workflow branch.',1;
   /* Serialize arrivals for this instance; concurrent worker continuations do not double-resume. */
   DECLARE @JoinGuard BIGINT;
   SELECT @JoinGuard=InstanceId FROM work.Instances WITH(UPDLOCK,HOLDLOCK) WHERE InstanceId=@InstanceId;
   IF NOT EXISTS(SELECT 1 FROM work.ParallelJoins WHERE InstanceId=@InstanceId AND NodeId=@NodeId)
     INSERT work.ParallelJoins(InstanceId,NodeId) VALUES(@InstanceId,@NodeId);
   IF EXISTS(SELECT 1 FROM work.ParallelJoins WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Resumed=1) RETURN;
   IF NOT EXISTS(SELECT 1 FROM work.ParallelArrivals WHERE InstanceId=@InstanceId
      AND JoinNodeId=@NodeId AND SourceNodeId=@SourceNodeId)
     INSERT work.ParallelArrivals(InstanceId,JoinNodeId,SourceNodeId)
     VALUES(@InstanceId,@NodeId,@SourceNodeId);
   DECLARE @JoinExpectedArrivals INT=(SELECT COUNT(*) FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId AND TargetNodeId=@NodeId);
   DECLARE @Arrived INT=(SELECT COUNT(*) FROM work.ParallelArrivals WHERE InstanceId=@InstanceId AND JoinNodeId=@NodeId);
   IF @Arrived<@JoinExpectedArrivals RETURN;
   UPDATE work.ParallelJoins SET Resumed=1,ResumedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Resumed=0;
   DECLARE @JoinNext BIGINT=(SELECT TOP(1) TargetNodeId FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId
      AND SourceNodeId=@NodeId ORDER BY SortOrder);
   DECLARE @JoinDepth INT=@Depth+1;
   EXEC work.usp_ActivateNode @InstanceId,@JoinNext,@ActorUserId,@Depth=@JoinDepth,@SourceNodeId=@NodeId;
   RETURN;
  END;
  THROW 50338,'Parallel node has no supported execution mode.',1;
 END;
 IF @Kind='end'
 BEGIN
  IF EXISTS(SELECT 1 FROM work.Tasks WHERE InstanceId=@InstanceId AND Status='Open') RETURN;
  IF EXISTS(SELECT 1 FROM integration.Executions WHERE CaseId=@CaseId AND Status IN('Pending','Running','Failed')) RETURN;
  IF EXISTS(SELECT 1 FROM work.PendingTimers WHERE InstanceId=@InstanceId AND Status='Pending') RETURN;
  IF EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND RcaRequiredAtCreation=1)
   UPDATE work.Cases SET Status='Pending RCA',PendingFinalStatus='Closed',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  ELSE UPDATE work.Cases SET Status='Closed',ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  UPDATE work.Instances SET Status='Completed',CompletedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId;
  INSERT work.CaseEvents(CaseId,EventType,Message) VALUES(@CaseId,'WorkflowCompleted','Workflow reached an end state');
  RETURN;
 END;
 IF @Kind IN('task','officerRouting','requestInfo','groupReview')
 BEGIN
  DECLARE @TeamIds TABLE(TeamId BIGINT PRIMARY KEY);
  IF @Kind='groupReview'
   INSERT @TeamIds(TeamId) SELECT DISTINCT TRY_CONVERT(BIGINT,value)
   FROM OPENJSON(@NodeConfig,'$.teamIds') WHERE TRY_CONVERT(BIGINT,value) IS NOT NULL;
  ELSE IF @TeamId IS NOT NULL INSERT @TeamIds VALUES(@TeamId);
  IF NOT EXISTS(SELECT 1 FROM @TeamIds) THROW 50154,'Human task needs a project team.',1;
  IF @SlaMinutes>0
  BEGIN
   IF @CalendarId IS NOT NULL EXEC calendar.usp_CalculateBusinessDueAt @CalendarId,@StartAt,@SlaMinutes,@DueAt OUTPUT;
   ELSE SET @DueAt=DATEADD(MINUTE,@SlaMinutes,@StartAt);
  END;
  DECLARE @ThisTeam BIGINT,@Recipient BIGINT,@RoutingStage VARCHAR(15),@TaskId BIGINT;
  DECLARE taskTeams CURSOR LOCAL FAST_FORWARD FOR SELECT TeamId FROM @TeamIds;
  OPEN taskTeams;FETCH NEXT FROM taskTeams INTO @ThisTeam;
  WHILE @@FETCH_STATUS=0
  BEGIN
    IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@ThisTeam AND ProjectId=@ProjectId AND IsActive=1)
     THROW 50155,'Workflow step uses an unavailable team.',1;
    SET @Recipient=NULL;SET @RoutingStage='Unassigned';
    SELECT TOP(1) @Recipient=m.UserId,@RoutingStage=m.TeamRole
    FROM teams.Members m JOIN auth.Users u ON u.UserId=m.UserId
    WHERE m.TeamId=@ThisTeam AND m.IsActive=1 AND u.IsActive=1 AND u.DirectoryStatus='Active'
    AND ( @Mode='Hierarchy' OR @Mode='Direct' AND m.TeamRole='Officer'
      OR @Mode='RoleQueue' AND m.TeamRole=CASE @Role WHEN 'unit_head' THEN 'UnitHead' WHEN 'team_lead' THEN 'TeamLead' ELSE 'Officer' END )
    AND NOT EXISTS(SELECT 1 FROM teams.Absences a WHERE a.TeamId=@ThisTeam AND a.UserId=m.UserId AND a.IsActive=1
     AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN a.StartDate AND a.EndDate)
    ORDER BY CASE WHEN @Mode='Hierarchy' THEN CASE m.TeamRole WHEN 'UnitHead' THEN 1 WHEN 'TeamLead' THEN 2 ELSE 3 END ELSE 1 END,u.UserName;
    SET @TaskId=NEXT VALUE FOR work.Seq_Tasks;
    INSERT work.Tasks(TaskId,InstanceId,NodeId,TeamId,AssignedTo,RoutingStage,Status,Priority,DueAt,AssignedAt)
    VALUES(@TaskId,@InstanceId,@NodeId,@ThisTeam,@Recipient,@RoutingStage,'Open','Normal',@DueAt,
    CASE WHEN @Recipient IS NOT NULL THEN SYSUTCDATETIME() END);
    INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
    VALUES(@CaseId,'TaskAssigned',CASE WHEN @Recipient IS NULL THEN 'Task awaiting assignment' ELSE 'Human task assigned' END,
     (SELECT CONVERT(NVARCHAR(36),@TaskId) AS taskId,CONVERT(NVARCHAR(36),@Recipient) AS userId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    FETCH NEXT FROM taskTeams INTO @ThisTeam;
  END;
  CLOSE taskTeams;DEALLOCATE taskTeams;
  UPDATE work.Cases SET Status='In progress',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='wait'
 BEGIN
  DECLARE @Minutes INT=TRY_CONVERT(INT,JSON_VALUE(@NodeConfig,'$.delayMinutes'));
  INSERT work.PendingTimers(InstanceId,NodeId,WakeAtUtc)
  VALUES(@InstanceId,@NodeId,DATEADD(MINUTE,ISNULL(NULLIF(@Minutes,0),60),SYSUTCDATETIME()));
  UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='notify'
 BEGIN
  DECLARE @TemplateId BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.templateId'));
  DECLARE @NotifyRecipientUserId BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.recipientUserId'));
  DECLARE @NChannel VARCHAR(15),@NSubject NVARCHAR(300),@NBody NVARCHAR(MAX),@NAddress NVARCHAR(320);
  SELECT @NChannel=Channel,@NSubject=SubjectTemplate,@NBody=BodyTemplate
  FROM notify.Templates WHERE TemplateId=@TemplateId AND IsActive=1 AND (ProjectId=@ProjectId OR ProjectId IS NULL);
  IF @NChannel IS NULL THROW 50339,'Notification template is unavailable.',1;
  IF @NotifyRecipientUserId IS NULL SELECT @NotifyRecipientUserId=CreatedBy FROM work.Cases WHERE CaseId=@CaseId;
  SELECT @NAddress=CASE WHEN @NChannel='SMS' THEN Mobile ELSE Email END
   FROM auth.Users WHERE UserId=@NotifyRecipientUserId AND IsActive=1;
  IF @NChannel IN('Email','SMS') AND NULLIF(LTRIM(RTRIM(@NAddress)),N'') IS NULL
    THROW 50340,'Notification recipient has no destination address.',1;
  DECLARE @NotificationId BIGINT=NEXT VALUE FOR notify.Seq_Outbox;
  INSERT notify.Outbox(NotificationId,ProjectId,CaseId,Channel,RecipientUserId,RecipientAddress,
   TemplateId,PayloadJson,IdempotencyKey)
  VALUES(@NotificationId,@ProjectId,@CaseId,@NChannel,@NotifyRecipientUserId,@NAddress,@TemplateId,
   (SELECT @NSubject AS subject,@NBody AS body,@CaseId AS caseId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
   CONCAT('node:',CONVERT(VARCHAR(36),@InstanceId),':',CONVERT(VARCHAR(36),@NodeId)));
  INSERT work.SystemNotifications(InstanceId,NodeId,NotificationId) VALUES(@InstanceId,@NodeId,@NotificationId);
  UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='dataSource'
 BEGIN
  DECLARE @OperationId BIGINT,@Src BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.dataSourceId'));
  DECLARE @OpCode VARCHAR(75)=JSON_VALUE(@NodeConfig,'$.operationCode');
  SELECT @OperationId=o.OperationId FROM integration.Operations o
  JOIN integration.ProjectDataSources p ON p.DataSourceId=o.DataSourceId AND p.ProjectId=@ProjectId
  WHERE o.DataSourceId=@Src AND o.Code=@OpCode AND o.IsActive=1;
  IF @OperationId IS NULL THROW 50156,'Data-source operation is not approved for this project.',1;
  INSERT integration.Executions(ProjectId,CaseId,NodeId,OperationId,IdempotencyKey)
  VALUES(@ProjectId,@CaseId,@NodeId,@OperationId,CONCAT(CONVERT(VARCHAR(36),@InstanceId),':',CONVERT(VARCHAR(36),@NodeId)));
  UPDATE work.Cases SET Status='Waiting for integration',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 /* Unsupported published legacy nodes must fail explicitly; never silently strand a case. */
 UPDATE work.Instances SET Status='Waiting' WHERE InstanceId=@InstanceId;
 UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 INSERT work.CaseEvents(CaseId,EventType,Message)
 VALUES(@CaseId,'EnginePending',CONCAT('Backend workflow executor required for node type ',@Kind));
END;
GO
CREATE OR ALTER PROCEDURE notify.usp_ClaimOutbox @BatchSize INT=50
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize<1 OR @BatchSize>500 THROW 50210,'BatchSize must be 1–500.',1;
 BEGIN TRAN;
 ;WITH nextBatch AS (
  SELECT TOP (@BatchSize) * FROM notify.Outbox WITH(UPDLOCK,READPAST,ROWLOCK)
  WHERE (State IN('Pending','Failed','Sending')) AND NextAttemptAt<=SYSUTCDATETIME() AND Attempts<8
  ORDER BY NextAttemptAt,CreatedAt
 )
 UPDATE nextBatch SET State='Sending',Attempts=Attempts+1,
  NextAttemptAt=DATEADD(MINUTE,2,SYSUTCDATETIME())
 OUTPUT inserted.NotificationId,inserted.ProjectId,inserted.Channel,inserted.LanguageCode,
 inserted.RecipientUserId,inserted.RecipientAddress,inserted.PayloadJson,inserted.Attempts;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE work.usp_EscalateOverdueTasks @BatchSize INT=50
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize NOT BETWEEN 1 AND 200 THROW 50410,'Invalid SLA batch size.',1;
 BEGIN TRAN;
 DECLARE @Due TABLE(TaskId BIGINT PRIMARY KEY,ProjectId BIGINT,CaseId BIGINT,Recipient BIGINT,
  Address NVARCHAR(320),ReferenceNo NVARCHAR(55));
 INSERT @Due
 SELECT TOP(@BatchSize) t.TaskId,c.ProjectId,c.CaseId,t.AssignedTo,u.Email,c.ReferenceNo
 FROM work.Tasks t WITH(UPDLOCK,READPAST,ROWLOCK)
 JOIN work.Instances inst ON inst.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=inst.CaseId
 LEFT JOIN auth.Users u ON u.UserId=t.AssignedTo AND u.IsActive=1
 WHERE t.Status='Open' AND t.DueAt IS NOT NULL AND t.DueAt<=SYSUTCDATETIME()
 AND NOT EXISTS(SELECT 1 FROM work.SlaEscalations sla WHERE sla.TaskId=t.TaskId)
 ORDER BY t.DueAt,t.TaskId;
 INSERT work.SlaEscalations(TaskId,ProjectId) SELECT TaskId,ProjectId FROM @Due;
 UPDATE t SET Priority='Urgent' FROM work.Tasks t JOIN @Due d ON d.TaskId=t.TaskId;
 INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
 SELECT CaseId,'TaskSlaBreached',N'Task SLA breached; escalated to urgent priority',
 (SELECT d.TaskId AS taskId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM @Due d;
 DECLARE @TaskId BIGINT,@ProjectId BIGINT,@CaseId BIGINT,@Recipient BIGINT,@Address NVARCHAR(320),@Ref NVARCHAR(55),@NotificationId BIGINT;
 DECLARE dueTasks CURSOR LOCAL FAST_FORWARD FOR SELECT TaskId,ProjectId,CaseId,Recipient,Address,ReferenceNo FROM @Due WHERE NULLIF(Address,'') IS NOT NULL;
 OPEN dueTasks;FETCH NEXT FROM dueTasks INTO @TaskId,@ProjectId,@CaseId,@Recipient,@Address,@Ref;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @NotificationId=NEXT VALUE FOR notify.Seq_Outbox;
  INSERT notify.Outbox(NotificationId,ProjectId,CaseId,TaskId,Channel,RecipientUserId,RecipientAddress,PayloadJson,IdempotencyKey)
   VALUES(@NotificationId,@ProjectId,@CaseId,@TaskId,'Email',@Recipient,@Address,
   (SELECT CONCAT(N'SLA overdue: ',@Ref) AS subject,
    CONCAT(N'The assigned task for case ',@Ref,N' is overdue. Please take action.') AS body FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
    CONCAT('sla:',CONVERT(VARCHAR(36),@TaskId)));
  UPDATE work.SlaEscalations SET NotificationId=@NotificationId WHERE TaskId=@TaskId;
  FETCH NEXT FROM dueTasks INTO @TaskId,@ProjectId,@CaseId,@Recipient,@Address,@Ref;
 END;
 CLOSE dueTasks;DEALLOCATE dueTasks;
 COMMIT;
 SELECT (SELECT COUNT(*) FROM @Due) AS EscalatedCount;
END;
GO
IF USER_ID(N'workflow_app_v2') IS NOT NULL
 GRANT EXECUTE ON OBJECT::work.usp_EscalateOverdueTasks TO [workflow_app_v2];
GO
