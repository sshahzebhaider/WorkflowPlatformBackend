USE [WorkflowPlatformV2];
GO
/* Concurrency-controlled parallel joins and durable notification-node mapping. */
IF OBJECT_ID(N'work.ParallelJoins',N'U') IS NULL
CREATE TABLE work.ParallelJoins(
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 Resumed BIT NOT NULL DEFAULT 0, ResumedAt DATETIME2(3) NULL,
 CONSTRAINT PK_ParallelJoins PRIMARY KEY(InstanceId,NodeId));
IF OBJECT_ID(N'work.ParallelArrivals',N'U') IS NULL
CREATE TABLE work.ParallelArrivals(
 InstanceId BIGINT NOT NULL,JoinNodeId BIGINT NOT NULL,SourceNodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 ArrivedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT PK_ParallelArrivals PRIMARY KEY(InstanceId,JoinNodeId,SourceNodeId),
 CONSTRAINT FK_ParallelArrivals_Joins FOREIGN KEY(InstanceId,JoinNodeId)
 REFERENCES work.ParallelJoins(InstanceId,NodeId));
IF OBJECT_ID(N'work.SystemNotifications',N'U') IS NULL
CREATE TABLE work.SystemNotifications(
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 NotificationId BIGINT NOT NULL REFERENCES notify.Outbox(NotificationId),
 ResumedAt DATETIME2(3) NULL,
 CONSTRAINT PK_SystemNotifications PRIMARY KEY(InstanceId,NodeId),
 CONSTRAINT UQ_SystemNotifications_Notification UNIQUE(NotificationId));
GO
CREATE OR ALTER PROCEDURE flow.usp_Publish
 @ActorUserId BIGINT,@WorkflowId BIGINT,@VersionId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Graph NVARCHAR(MAX),@VersionNumber INT;
 BEGIN TRAN;
 SELECT @ProjectId=ProjectId,@Graph=DraftGraphJson FROM flow.Definitions WITH(UPDLOCK,HOLDLOCK) WHERE WorkflowId=@WorkflowId;
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 BEGIN ROLLBACK; THROW 50124,'Workflow not found or access denied.',1; END;
 DECLARE @Nodes TABLE(
 NodeKey VARCHAR(120),NodeType VARCHAR(30),Label NVARCHAR(200),
 TeamId BIGINT,AssignmentMode VARCHAR(20),AssignedRole VARCHAR(20),SlaMinutes INT,
 EscalationRole VARCHAR(50),RequireForm BIT,AllowedActionsJson NVARCHAR(MAX),ConfigJson NVARCHAR(MAX));
 INSERT @Nodes
 SELECT JSON_VALUE(j.value,'$.id'),JSON_VALUE(j.value,'$.data.kind'),
 LEFT(ISNULL(JSON_VALUE(j.value,'$.data.label'),N'Step'),200),
 TRY_CONVERT(BIGINT,JSON_VALUE(j.value,'$.data.teamId')),
 CASE JSON_VALUE(j.value,'$.data.assignmentMode')
 WHEN 'direct' THEN 'Direct' WHEN 'roleQueue' THEN 'RoleQueue' ELSE 'Hierarchy' END,
 JSON_VALUE(j.value,'$.data.assignedRole'),
 TRY_CONVERT(INT,JSON_VALUE(j.value,'$.data.slaHours'))*60,
 JSON_VALUE(j.value,'$.data.escalationRole'),
 CASE JSON_VALUE(j.value,'$.data.requireForm') WHEN 'true' THEN 1 ELSE 0 END,
 JSON_QUERY(j.value,'$.data.actions'),ISNULL(JSON_QUERY(j.value,'$.data'),N'{}')
 FROM OPENJSON(@Graph,'$.nodes') j;
 IF (SELECT COUNT(*) FROM @Nodes WHERE NodeType='start')<>1 OR NOT EXISTS(SELECT 1 FROM @Nodes WHERE NodeType='end')
 BEGIN ROLLBACK; THROW 50125,'Workflow requires exactly one Start and at least one End.',1; END;
 IF EXISTS(SELECT NodeKey FROM @Nodes GROUP BY NodeKey HAVING COUNT(*)>1) OR EXISTS(SELECT 1 FROM @Nodes WHERE NodeKey IS NULL OR NodeType IS NULL)
 BEGIN ROLLBACK; THROW 50126,'Workflow nodes require unique identifiers and valid types.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.TeamId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM teams.Teams t WHERE t.TeamId=n.TeamId AND t.ProjectId=@ProjectId AND t.IsActive=1))
 BEGIN ROLLBACK; THROW 50127,'Workflow uses a team outside this project.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType IN('task','officerRouting','requestInfo') AND n.TeamId IS NULL)
 BEGIN ROLLBACK; THROW 50128,'Each human task requires a destination team.',1; END;
 /* Explicit split or join semantics; no ambiguous implicit parallel nodes. */
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='parallel'
  AND JSON_VALUE(n.ConfigJson,'$.parallelMode') NOT IN('split','join'))
 BEGIN ROLLBACK; THROW 50322,'Parallel node must be configured as Split or Join.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='parallel' AND (
 (JSON_VALUE(n.ConfigJson,'$.parallelMode')='split' AND
   (SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.source')=n.NodeKey)<2)
 OR (JSON_VALUE(n.ConfigJson,'$.parallelMode')='join' AND
  ((SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.target')=n.NodeKey)<2
   OR (SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.source')=n.NodeKey)<>1))))
 BEGIN ROLLBACK; THROW 50335,'Parallel split needs two outgoing edges; join needs two incoming and one outgoing edge.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='notify' AND
  (TRY_CONVERT(BIGINT,JSON_VALUE(n.ConfigJson,'$.templateId')) IS NULL
   OR NOT EXISTS (SELECT 1 FROM notify.Templates t
   WHERE t.TemplateId=TRY_CONVERT(BIGINT,JSON_VALUE(n.ConfigJson,'$.templateId'))
   AND t.IsActive=1 AND (t.ProjectId=@ProjectId OR t.ProjectId IS NULL))))
 BEGIN ROLLBACK; THROW 50336,'Notification node requires an active project notification template.',1; END;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Graph,'$.edges') e
 WHERE NOT EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeKey=JSON_VALUE(e.value,'$.source'))
 OR NOT EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeKey=JSON_VALUE(e.value,'$.target')))
 BEGIN ROLLBACK; THROW 50129,'Workflow contains an invalid edge.',1; END;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@Graph,'$.edges') e JOIN @Nodes n ON n.NodeKey=JSON_VALUE(e.value,'$.source') WHERE n.NodeType='start')
 BEGIN ROLLBACK; THROW 50130,'Start must have an outgoing connection.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n CROSS APPLY OPENJSON(n.ConfigJson,'$.formIds') j
 WHERE NOT EXISTS(SELECT 1 FROM forms.Definitions f WHERE f.FormId=TRY_CONVERT(BIGINT,j.value)
  AND f.ProjectId=@ProjectId AND f.LiveVersionId IS NOT NULL))
 BEGIN ROLLBACK; THROW 50131,'Workflow references an unpublished or foreign form.',1; END;
 SET @VersionNumber=ISNULL((SELECT MAX(VersionNumber) FROM flow.Versions WHERE WorkflowId=@WorkflowId),0)+1;
 SET @VersionId=NEXT VALUE FOR flow.Seq_Versions;
 INSERT flow.Versions(WorkflowVersionId,WorkflowId,VersionNumber,GraphJson,PublishedBy)
 VALUES(@VersionId,@WorkflowId,@VersionNumber,@Graph,@ActorUserId);
 INSERT flow.Nodes(WorkflowVersionId,NodeKey,NodeType,Label,TeamId,AssignmentMode,AssignedRole,SlaMinutes,EscalationRole,RequireForm,AllowedActionsJson,ConfigJson)
 SELECT @VersionId,NodeKey,NodeType,Label,TeamId,AssignmentMode,AssignedRole,SlaMinutes,EscalationRole,RequireForm,AllowedActionsJson,ConfigJson FROM @Nodes;
 INSERT flow.Edges(WorkflowVersionId,SourceNodeId,TargetNodeId,OutcomeCode,SortOrder)
 SELECT @VersionId,s.NodeId,t.NodeId,
 NULLIF(COALESCE(JSON_VALUE(j.value,'$.data.outcome'),JSON_VALUE(j.value,'$.label')),''),
 CONVERT(INT,j.[key])
 FROM OPENJSON(@Graph,'$.edges') j
 JOIN flow.Nodes s ON s.WorkflowVersionId=@VersionId AND s.NodeKey=JSON_VALUE(j.value,'$.source')
 JOIN flow.Nodes t ON t.WorkflowVersionId=@VersionId AND t.NodeKey=JSON_VALUE(j.value,'$.target');
 INSERT flow.NodeForms(NodeId,FormVersionId)
 SELECT n.NodeId,f.LiveVersionId FROM flow.Nodes n
 CROSS APPLY OPENJSON(n.ConfigJson,'$.formIds') j
 JOIN forms.Definitions f ON f.FormId=TRY_CONVERT(BIGINT,j.value)
 WHERE n.WorkflowVersionId=@VersionId AND f.ProjectId=@ProjectId AND f.LiveVersionId IS NOT NULL;
 UPDATE flow.Definitions SET LiveVersionId=@VersionId,UpdatedAt=SYSUTCDATETIME() WHERE WorkflowId=@WorkflowId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Workflow',@EntityId=@WorkflowId,@ActionCode='Publish';
 COMMIT;
 SELECT @VersionNumber AS PublishedVersion,@VersionId AS WorkflowVersionId;
END;
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
  IF @CalendarId IS NOT NULL AND @SlaMinutes>0
   EXEC calendar.usp_CalculateBusinessDueAt @CalendarId,@StartAt,@SlaMinutes,@DueAt OUTPUT;
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
CREATE OR ALTER PROCEDURE work.usp_CompleteTask
 @ActorUserId BIGINT,@TaskId BIGINT,@Action VARCHAR(60),
 @AnswersByFormJson NVARCHAR(MAX)=N'{}'
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@AnswersByFormJson)<>1 THROW 50175,'Task form answers must be JSON.',1;
 DECLARE @CaseId BIGINT,@ProjectId BIGINT,@InstanceId BIGINT,
 @NodeId BIGINT,@WorkflowVersionId BIGINT,@AssignedTo BIGINT,
 @RoutingStage VARCHAR(15),@RequireForm BIT,@AllowedActionsJson NVARCHAR(MAX),@CurrentJson NVARCHAR(MAX),
 @NextNodeId BIGINT,@TeamId BIGINT;
 BEGIN TRAN;
 SELECT @CaseId=i.CaseId,@ProjectId=c.ProjectId,@InstanceId=i.InstanceId,@WorkflowVersionId=i.WorkflowVersionId,
 @NodeId=t.NodeId,@AssignedTo=t.AssignedTo,@RoutingStage=t.RoutingStage,@TeamId=t.TeamId
 FROM work.Tasks t WITH(UPDLOCK,HOLDLOCK) JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId WHERE t.TaskId=@TaskId AND t.Status='Open';
 IF @CaseId IS NULL BEGIN ROLLBACK; THROW 50176,'Task already completed or not found.',1; END;
 IF @AssignedTo IS NULL OR @AssignedTo<>@ActorUserId BEGIN ROLLBACK; THROW 50177,'Task is not assigned to this user.',1; END;
 IF @RoutingStage<>'Officer' BEGIN ROLLBACK; THROW 50178,'Forward the task through its required review hierarchy first.',1; END;
 SELECT @RequireForm=RequireForm,@AllowedActionsJson=AllowedActionsJson FROM flow.Nodes WHERE NodeId=@NodeId;
 IF @AllowedActionsJson IS NOT NULL AND NOT EXISTS(SELECT 1 FROM OPENJSON(@AllowedActionsJson) WHERE value=@Action)
 BEGIN ROLLBACK; THROW 50179,'This workflow action is not allowed.',1; END;
 IF @AllowedActionsJson IS NULL AND @Action NOT IN('Complete','Approve','Reject','Return','Forward','Request information')
 BEGIN ROLLBACK; THROW 50180,'Unknown task action.',1; END;
 IF @RequireForm=1 AND EXISTS(SELECT 1 FROM flow.NodeForms nf JOIN forms.Versions v ON v.FormVersionId=nf.FormVersionId
  WHERE nf.NodeId=@NodeId AND JSON_QUERY(@AnswersByFormJson,CONCAT('$."',CONVERT(VARCHAR(36),v.FormId),'"')) IS NULL)
 BEGIN ROLLBACK; THROW 50181,'Complete every required step form before submitting.',1; END;
 /* Stored answers are individual immutable submissions; never overwrite original intake answers. */
 DECLARE @FormVersionId BIGINT,@FormId BIGINT,@FormAnswers NVARCHAR(MAX);
 DECLARE formAnswers CURSOR LOCAL FAST_FORWARD FOR
 SELECT nf.FormVersionId,v.FormId,JSON_QUERY(@AnswersByFormJson,CONCAT('$."',CONVERT(VARCHAR(36),v.FormId),'"'))
 FROM flow.NodeForms nf JOIN forms.Versions v ON v.FormVersionId=nf.FormVersionId
 WHERE nf.NodeId=@NodeId;
 OPEN formAnswers;FETCH NEXT FROM formAnswers INTO @FormVersionId,@FormId,@FormAnswers;
 SET @CurrentJson=(SELECT CurrentValuesJson FROM work.Cases WHERE CaseId=@CaseId);
 WHILE @@FETCH_STATUS=0
 BEGIN
  IF @FormAnswers IS NOT NULL
  BEGIN
   INSERT work.CaseFormAnswers(CaseId,FormVersionId,TaskId,AnswersJson,SubmittedBy)
   VALUES(@CaseId,@FormVersionId,@TaskId,@FormAnswers,@ActorUserId);
   DECLARE @FieldKey VARCHAR(100),@FieldValue NVARCHAR(MAX),@JsonType INT,@Path NVARCHAR(240);
   DECLARE fields CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.[key],j.value,j.[type] FROM OPENJSON(@FormAnswers) j
    JOIN forms.VersionFields f ON f.FormVersionId=@FormVersionId AND f.FieldKey=j.[key] COLLATE DATABASE_DEFAULT;
   OPEN fields;FETCH NEXT FROM fields INTO @FieldKey,@FieldValue,@JsonType;
   WHILE @@FETCH_STATUS=0
   BEGIN
    SET @Path=CONCAT('$.',@FieldKey);
    IF @JsonType IN(4,5) SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,JSON_QUERY(@FormAnswers,@Path));
    ELSE SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,@FieldValue);
    FETCH NEXT FROM fields INTO @FieldKey,@FieldValue,@JsonType;
   END;
   CLOSE fields;DEALLOCATE fields;
  END;
  FETCH NEXT FROM formAnswers INTO @FormVersionId,@FormId,@FormAnswers;
 END;
 CLOSE formAnswers;DEALLOCATE formAnswers;
 UPDATE work.Cases SET CurrentValuesJson=@CurrentJson,UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 EXEC work.usp_ReindexCaseFields @CaseId;
 UPDATE work.Tasks SET Status='Completed',CompletedAt=SYSUTCDATETIME(),CompletedBy=@ActorUserId,
  ActionCode=@Action,ActionValuesJson=@AnswersByFormJson WHERE TaskId=@TaskId;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 VALUES(@CaseId,'TaskCompleted',CONCAT(@Action,' · Human task completed'),@ActorUserId,
  (SELECT CONVERT(VARCHAR(36),@TaskId) AS taskId,@Action AS action FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 /* A group review advances only when every task at the same node is complete. */
 IF EXISTS(SELECT 1 FROM work.Tasks WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Open')
 BEGIN COMMIT; RETURN; END;
 SELECT TOP(1) @NextNodeId=e.TargetNodeId FROM flow.Edges e
 WHERE e.WorkflowVersionId=@WorkflowVersionId AND e.SourceNodeId=@NodeId
 AND (e.OutcomeCode=@Action OR e.OutcomeCode IS NULL)
 ORDER BY CASE WHEN e.OutcomeCode=@Action THEN 0 ELSE 1 END,e.SortOrder;
 IF @NextNodeId IS NULL
 BEGIN
  IF @Action='Reject'
  BEGIN
   IF EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND RcaRequiredAtCreation=1)
    UPDATE work.Cases SET Status='Pending RCA',PendingFinalStatus='Rejected',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   ELSE UPDATE work.Cases SET Status='Rejected',ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   UPDATE work.Instances SET Status='Completed',CompletedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId;
  END ELSE IF @Action IN('RequestInfo','RequestInformation')
   UPDATE work.Cases SET Status='Waiting for information',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  ELSE BEGIN ROLLBACK; THROW 50316,'No outgoing workflow transition matches the completed action.',1; END;
  INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
  VALUES(@CaseId,'NoTransition',N'No matching outgoing transition configured',@ActorUserId);
 END ELSE
  EXEC work.usp_ActivateNode @InstanceId,@NextNodeId,@ActorUserId,@SourceNodeId=@NodeId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Task',@EntityId=@TaskId,@ActionCode='Complete';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE work.usp_ResumeSystemNode
 @InstanceId BIGINT,@NodeId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @CaseId BIGINT,@VersionId BIGINT,@NextNodeId BIGINT,@Kind VARCHAR(30);
 BEGIN TRAN;
 SELECT @CaseId=CaseId,@VersionId=WorkflowVersionId FROM work.Instances WITH(UPDLOCK,HOLDLOCK)
 WHERE InstanceId=@InstanceId AND Status IN('Running','Waiting');
 SELECT @Kind=NodeType FROM flow.Nodes WHERE NodeId=@NodeId AND WorkflowVersionId=@VersionId;
 IF @CaseId IS NULL OR @Kind NOT IN('dataSource','wait','notify') BEGIN ROLLBACK; THROW 50217,'Invalid instance/system node.',1; END;
 IF @Kind='dataSource'
 BEGIN
  /* Only one continuation may consume each successfully executed node. Transactional
     marker survives crashes and concurrent workers, and the rollback restores it. */
  UPDATE integration.Executions SET ResumedAt=SYSUTCDATETIME()
   WHERE ExecutionId=(SELECT TOP(1) ExecutionId FROM integration.Executions WITH(UPDLOCK,HOLDLOCK)
    WHERE CaseId=@CaseId AND NodeId=@NodeId AND Status='Succeeded' AND ResumedAt IS NULL
    ORDER BY ExecutionId);
  IF @@ROWCOUNT=0 BEGIN ROLLBACK; THROW 50218,'Cannot resume an uncompleted or previously resumed integration.',1; END;
 END;
 IF @Kind='wait'
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM work.PendingTimers WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Pending' AND WakeAtUtc<=SYSUTCDATETIME())
  BEGIN ROLLBACK; THROW 50219,'Timer is not due.',1; END;
  UPDATE work.PendingTimers SET Status='Resumed' WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Pending';
 END;
 IF @Kind='notify'
 BEGIN
  UPDATE sn SET ResumedAt=SYSUTCDATETIME() FROM work.SystemNotifications sn WITH(UPDLOCK,HOLDLOCK)
  JOIN notify.Outbox o ON o.NotificationId=sn.NotificationId AND o.State IN('Accepted','Delivered','Preview')
  WHERE sn.InstanceId=@InstanceId AND sn.NodeId=@NodeId AND sn.ResumedAt IS NULL;
  IF @@ROWCOUNT=0 BEGIN ROLLBACK; THROW 50220,'Notification has not been accepted or was previously resumed.',1; END;
 END;
 SELECT TOP(1) @NextNodeId=TargetNodeId FROM flow.Edges
 WHERE WorkflowVersionId=@VersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
 IF @NextNodeId IS NULL BEGIN ROLLBACK; THROW 50221,'System node has no outgoing connection.',1; END;
 UPDATE work.Cases SET Status='In progress',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 UPDATE work.Instances SET Status='Running' WHERE InstanceId=@InstanceId;
 EXEC work.usp_ActivateNode @InstanceId,@NextNodeId,@SourceNodeId=@NodeId;
 COMMIT;
END;
GO
