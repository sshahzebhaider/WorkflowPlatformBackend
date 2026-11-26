USE [WorkflowPlatformV2];
GO
/* Template-driven notification rule expansion. Called only within audited case/task transactions. */
CREATE OR ALTER PROCEDURE notify.usp_QueueConfiguredEvent
 @EventCode VARCHAR(65),@ProjectId BIGINT,@CaseId BIGINT,@TaskId BIGINT=NULL,
 @RecipientUserId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @EventCode NOT IN('CASE_CREATED','TASK_ASSIGNED','SLA_BREACHED','WORKFLOW_COMPLETED','CASE_CLOSED') RETURN;
 DECLARE @Ref NVARCHAR(55),@Title NVARCHAR(300),@Creator BIGINT;
 SELECT @Ref=ReferenceNo,@Title=Title,@Creator=CreatedBy FROM work.Cases
 WHERE CaseId=@CaseId AND ProjectId=@ProjectId;
 IF @Ref IS NULL RETURN;
 IF @RecipientUserId IS NULL AND @EventCode IN('TASK_ASSIGNED','SLA_BREACHED') RETURN;
 IF @RecipientUserId IS NULL SET @RecipientUserId=@Creator;
 IF @RecipientUserId IS NULL RETURN;
 INSERT notify.Outbox(ProjectId,CaseId,TaskId,TemplateId,Channel,LanguageCode,
  RecipientUserId,RecipientAddress,PayloadJson,IdempotencyKey)
 SELECT @ProjectId,@CaseId,@TaskId,t.TemplateId,t.Channel,t.LanguageCode,@RecipientUserId,
  CASE WHEN t.Channel='Email' THEN u.Email WHEN t.Channel='SMS' THEN u.Mobile END,
  (SELECT REPLACE(REPLACE(ISNULL(t.SubjectTemplate,N'Workflow notification'),N'{{reference}}',@Ref),N'{{title}}',@Title) AS subject,
    REPLACE(REPLACE(t.BodyTemplate,N'{{reference}}',@Ref),N'{{title}}',@Title) AS body FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
  CONCAT('rule:',CONVERT(VARCHAR(25),r.RuleId),':',@EventCode,':',CONVERT(VARCHAR(25),@CaseId),':',ISNULL(CONVERT(VARCHAR(25),@TaskId),'0'))
 FROM notify.Rules r JOIN notify.Templates t ON t.TemplateId=r.TemplateId AND t.IsActive=1
 JOIN auth.Users u ON u.UserId=@RecipientUserId AND u.IsActive=1
 WHERE r.ProjectId=@ProjectId AND r.EventCode=@EventCode AND r.IsEnabled=1
 AND (t.Channel='InApp' OR t.Channel='Email' AND NULLIF(u.Email,N'') IS NOT NULL
 OR t.Channel='SMS' AND NULLIF(u.Mobile,N'') IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM notify.Outbox existing WITH(UPDLOCK,HOLDLOCK)
 WHERE existing.IdempotencyKey=CONCAT('rule:',CONVERT(VARCHAR(25),r.RuleId),':',@EventCode,':',CONVERT(VARCHAR(25),@CaseId),':',ISNULL(CONVERT(VARCHAR(25),@TaskId),'0')));
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
  EXEC notify.usp_QueueConfiguredEvent 'WORKFLOW_COMPLETED',@ProjectId,@CaseId;
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
    EXEC notify.usp_QueueConfiguredEvent 'TASK_ASSIGNED',@ProjectId,@CaseId,@TaskId=@TaskId,@RecipientUserId=@Recipient;
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
CREATE OR ALTER PROCEDURE work.usp_CreateCase
 @ActorUserId BIGINT,@ProjectId BIGINT,@CaseTypeId BIGINT,
 @IntakeJson NVARCHAR(MAX),@ClassificationJson NVARCHAR(MAX)=N'{}',
 @Title NVARCHAR(300)=NULL,@IdempotencyKey VARCHAR(120)=NULL,
 @LodgementOperationId BIGINT=NULL,@LodgementMappedJson NVARCHAR(MAX)=NULL,
 @CaseId BIGINT OUTPUT,@ReferenceNo NVARCHAR(55) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.create')<>1 THROW 50160,'User cannot create cases in this project.',1;
 IF ISJSON(@IntakeJson)<>1 OR LEFT(LTRIM(@IntakeJson),1)<>'{' OR ISJSON(@ClassificationJson)<>1 OR LEFT(LTRIM(@ClassificationJson),1)<>'{'
  THROW 50161,'Intake and classification must be JSON objects.',1;
 DECLARE @RcaTemplateAtCreation BIGINT,@RcaRequired BIT,@RcaFieldsSnapshotJson NVARCHAR(MAX);
 DECLARE @CaseTypeVersionId BIGINT,@FormVersionId BIGINT,@WorkflowVersionId BIGINT,
 @SubjectKey VARCHAR(100),@SubjectValue NVARCHAR(250),@SubjectHash VARBINARY(32),
 @AllowDuplicate BIT,@Prefix VARCHAR(20),@SlaMinutes INT,@CalendarId BIGINT,@DueAt DATETIME2(3),@InstanceId BIGINT;
 SELECT @CaseTypeVersionId=t.LiveVersionId,@Prefix=p.ReferencePrefix,@CalendarId=p.CalendarId
 FROM core.CaseTypes t JOIN core.Projects p ON p.ProjectId=t.ProjectId
 WHERE t.CaseTypeId=@CaseTypeId AND t.ProjectId=@ProjectId AND t.IsActive=1 AND p.Status IN ('UAT','Live');
 IF @CaseTypeVersionId IS NULL THROW 50162,'Select a published type from a UAT or live project.',1;
 DECLARE @PublishedIntegrationId BIGINT=(SELECT TRY_CONVERT(BIGINT,JSON_VALUE(PublishedConfigJson,'$.lodgementIntegration.operationId'))
 FROM core.CaseTypeVersions WHERE CaseTypeVersionId=@CaseTypeVersionId);
 IF (@PublishedIntegrationId IS NOT NULL AND (ISNULL(@LodgementOperationId,-1)<>@PublishedIntegrationId OR
    ISJSON(@LodgementMappedJson)<>1 OR LEFT(LTRIM(@LodgementMappedJson),1)<>'{'))
 OR (@PublishedIntegrationId IS NULL AND (@LodgementOperationId IS NOT NULL OR @LodgementMappedJson IS NOT NULL))
 THROW 50313,'Required published lodgement integration did not complete successfully.',1;
 IF @LodgementOperationId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM integration.Operations o JOIN integration.ProjectDataSources p ON p.DataSourceId=o.DataSourceId
 WHERE o.OperationId=@LodgementOperationId AND p.ProjectId=@ProjectId)
 THROW 50314,'Operation is not approved for this project.',1;
 SELECT @FormVersionId=IntakeFormVersionId,@WorkflowVersionId=WorkflowVersionId,@SubjectKey=SubjectFieldKey,
 @AllowDuplicate=AllowDuplicate,@SlaMinutes=SlaMinutes FROM core.CaseTypeVersions WHERE CaseTypeVersionId=@CaseTypeVersionId;
 IF EXISTS(SELECT 1 FROM forms.VersionFields f WHERE f.FormVersionId=@FormVersionId AND f.IsRequired=1
 AND (f.FieldType='attachment' AND ISNULL(JSON_QUERY(@IntakeJson,CONCAT('$.',f.FieldKey)),N'[]')=N'[]'
 OR f.FieldType<>'attachment' AND NULLIF(LTRIM(ISNULL(JSON_VALUE(@IntakeJson,CONCAT('$.',f.FieldKey)),N'')),N'') IS NULL))
  THROW 50163,'A required intake field is missing.',1;
 IF EXISTS(SELECT 1 FROM core.CaseTypeLookups l JOIN lookup.Lists list ON list.ListId=l.ListId
 WHERE l.CaseTypeVersionId=@CaseTypeVersionId AND l.IsRequired=1
 AND NULLIF(JSON_VALUE(@ClassificationJson,CONCAT('$.classification_',LOWER(list.Code))),N'') IS NULL)
  THROW 50164,'Required classification lookup is missing.',1;
 IF EXISTS(SELECT 1 FROM core.CaseTypeLookups l JOIN lookup.Lists list ON list.ListId=l.ListId
 WHERE l.CaseTypeVersionId=@CaseTypeVersionId AND l.LockedItemId IS NOT NULL
 AND JSON_VALUE(@ClassificationJson,CONCAT('$.classification_',LOWER(list.Code)))<>CONVERT(NVARCHAR(36),l.LockedItemId))
  THROW 50165,'Locked classification value cannot be changed.',1;
 SET @SubjectValue=CASE WHEN @SubjectKey IS NOT NULL THEN LEFT(JSON_VALUE(@IntakeJson,CONCAT('$.',@SubjectKey)),250) END;
 IF @SubjectValue IS NOT NULL AND NULLIF(LTRIM(@SubjectValue),'') IS NOT NULL
  SET @SubjectHash=HASHBYTES('SHA2_256',LOWER(LTRIM(RTRIM(@SubjectValue))));
 SELECT @RcaTemplateAtCreation=RcaTemplateId,@RcaRequired=RcaRequired FROM core.Projects WHERE ProjectId=@ProjectId;
 SELECT @RcaFieldsSnapshotJson=(SELECT JSON_VALUE(ConfigJson,'$.key') AS FieldKey,
 JSON_VALUE(ConfigJson,'$.label') AS Label,JSON_VALUE(ConfigJson,'$.type') AS FieldType,
 TRY_CONVERT(BIT,JSON_VALUE(ConfigJson,'$.required')) AS Required,
 JSON_VALUE(ConfigJson,'$.parentKey') AS ParentFieldKey,
 JSON_VALUE(ConfigJson,'$.parentValue') AS ParentValue
 FROM core.ProjectRcaFields WHERE ProjectId=@ProjectId ORDER BY SortOrder FOR JSON PATH);
 IF @RcaFieldsSnapshotJson IS NULL SET @RcaFieldsSnapshotJson=N'[]';
 IF @CalendarId IS NOT NULL
  BEGIN
   IF @SlaMinutes IS NULL SET @SlaMinutes=(SELECT DefaultSlaMinutes FROM core.Projects WHERE ProjectId=@ProjectId);
   DECLARE @CaseStartAt DATETIME2(3)=SYSUTCDATETIME();
   EXEC calendar.usp_CalculateBusinessDueAt @CalendarId,@CaseStartAt,@SlaMinutes,@DueAt OUTPUT;
  END;
 BEGIN TRAN;
 IF @IdempotencyKey IS NOT NULL AND EXISTS(SELECT 1 FROM work.Cases WITH(UPDLOCK,HOLDLOCK)
  WHERE ProjectId=@ProjectId AND IdempotencyKey=@IdempotencyKey)
 BEGIN
  SELECT @CaseId=CaseId,@ReferenceNo=ReferenceNo FROM work.Cases WHERE ProjectId=@ProjectId AND IdempotencyKey=@IdempotencyKey;
  COMMIT; RETURN;
 END;
 IF @AllowDuplicate=0 AND @SubjectHash IS NOT NULL AND EXISTS(SELECT 1 FROM work.Cases WITH(UPDLOCK,HOLDLOCK)
  WHERE ProjectId=@ProjectId AND CaseTypeVersionId=@CaseTypeVersionId AND SubjectHash=@SubjectHash AND ClosedAt IS NULL)
  BEGIN ROLLBACK; THROW 50166,'An open case already exists for this subject/type.',1; END;
 DECLARE @Next TABLE(Seq BIGINT);
 UPDATE core.ProjectSequence WITH(UPDLOCK,HOLDLOCK) SET LastNumber=LastNumber+1 OUTPUT inserted.LastNumber INTO @Next
 WHERE ProjectId=@ProjectId;
 DECLARE @Seq BIGINT=(SELECT TOP(1) Seq FROM @Next);
 IF @Seq IS NULL BEGIN ROLLBACK; THROW 50167,'Project reference sequence missing.',1; END;
 SET @ReferenceNo=CONCAT(@Prefix,'-',YEAR(SYSUTCDATETIME()),'-',RIGHT(REPLICATE('0',8)+CONVERT(VARCHAR(19),@Seq),8));
 SET @CaseId=NEXT VALUE FOR work.Seq_Cases;SET @InstanceId=NEXT VALUE FOR work.Seq_Instances;
 DECLARE @CurrentIntakeValues NVARCHAR(MAX)=@IntakeJson;
 IF @LodgementMappedJson IS NOT NULL
 BEGIN
  DECLARE @ResponseKey NVARCHAR(128),@ResponseValue NVARCHAR(MAX),@ResponseType INT,@ResponsePath NVARCHAR(150);
  DECLARE mappedFields CURSOR LOCAL FAST_FORWARD FOR SELECT [key],[value],[type] FROM OPENJSON(@LodgementMappedJson);
  OPEN mappedFields;FETCH NEXT FROM mappedFields INTO @ResponseKey,@ResponseValue,@ResponseType;
  WHILE @@FETCH_STATUS=0
  BEGIN
   IF LEN(@ResponseKey)>100 OR @ResponseKey COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%'
      OR EXISTS(SELECT 1 FROM OPENJSON(@IntakeJson) WHERE [key]=@ResponseKey)
   BEGIN CLOSE mappedFields;DEALLOCATE mappedFields;ROLLBACK; THROW 50315,'Integration mapping must not replace an intake value.',1; END;
   SET @ResponsePath=CONCAT('$.',@ResponseKey);
   IF @ResponseType IN(4,5) SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,JSON_QUERY(@LodgementMappedJson,@ResponsePath));
   ELSE IF @ResponseType=2 SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,TRY_CONVERT(DECIMAL(28,8),@ResponseValue));
   ELSE IF @ResponseType=3 SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,CASE WHEN @ResponseValue='true' THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END);
   ELSE SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,@ResponseValue);
   FETCH NEXT FROM mappedFields INTO @ResponseKey,@ResponseValue,@ResponseType;
  END;
  CLOSE mappedFields;DEALLOCATE mappedFields;
 END;
 INSERT work.Cases(CaseId,ProjectId,CaseTypeVersionId,WorkflowVersionId,ReferenceNo,Title,
  SubjectValue,SubjectHash,IntakeJson,CurrentValuesJson,ClassificationJson,CreatedBy,DueAt,IdempotencyKey,
  RcaRequiredAtCreation,RcaTemplateAtCreation,RcaFieldsSnapshotJson)
 VALUES(@CaseId,@ProjectId,@CaseTypeVersionId,@WorkflowVersionId,@ReferenceNo,
  ISNULL(@Title,N'New case'),@SubjectValue,@SubjectHash,@IntakeJson,@CurrentIntakeValues,@ClassificationJson,@ActorUserId,@DueAt,@IdempotencyKey,
  @RcaRequired,@RcaTemplateAtCreation,@RcaFieldsSnapshotJson);
 /* Strictly bind pre-scanned staged files to this actor, form version and project.
    Failed validation or failed case creation rolls back consumption and document linkage. */
 DECLARE @IntakeFiles TABLE(StageId BIGINT NOT NULL PRIMARY KEY,FieldKey VARCHAR(100) NOT NULL);
 IF EXISTS (SELECT 1 FROM forms.VersionFields f
   CROSS APPLY OPENJSON(@IntakeJson,CONCAT('$.',f.FieldKey)) j
   WHERE f.FormVersionId=@FormVersionId AND f.FieldType='attachment'
   AND (TRY_CONVERT(BIGINT,j.value) IS NULL OR TRY_CONVERT(BIGINT,j.value)<=0))
 BEGIN ROLLBACK; THROW 50401,'Invalid staged attachment ID.',1; END;
 INSERT @IntakeFiles(StageId,FieldKey)
 SELECT TRY_CONVERT(BIGINT,j.value),f.FieldKey FROM forms.VersionFields f
 CROSS APPLY OPENJSON(@IntakeJson,CONCAT('$.',f.FieldKey)) j
 WHERE f.FormVersionId=@FormVersionId AND f.FieldType='attachment';
 IF EXISTS (SELECT 1 FROM @IntakeFiles ref
  LEFT JOIN files.StagedDocuments st WITH(UPDLOCK,HOLDLOCK) ON st.StageId=ref.StageId
  WHERE st.StageId IS NULL OR st.ProjectId<>@ProjectId OR st.CaseTypeId<>@CaseTypeId
  OR st.FormVersionId<>@FormVersionId OR st.ActorUserId<>@ActorUserId OR st.FieldKey<>ref.FieldKey
  OR st.ConsumedCaseId IS NOT NULL OR st.ExpiresAt<=SYSUTCDATETIME())
 BEGIN ROLLBACK; THROW 50402,'Staged attachment is unavailable, expired, or belongs to a different form/user.',1; END;
 UPDATE st SET ConsumedCaseId=@CaseId,ConsumedAt=SYSUTCDATETIME()
 FROM files.StagedDocuments st JOIN @IntakeFiles r ON r.StageId=st.StageId;
 INSERT files.Documents(ProjectId,CaseId,FormVersionId,FieldKey,StorageKey,
 OriginalFileName,MimeType,FileSizeBytes,Sha256,ScanStatus,UploadedBy)
 SELECT st.ProjectId,@CaseId,st.FormVersionId,st.FieldKey,st.StorageKey,st.OriginalFileName,st.MimeType,
 st.FileSizeBytes,st.Sha256,'Clean',@ActorUserId
 FROM files.StagedDocuments st JOIN @IntakeFiles r ON r.StageId=st.StageId;
 INSERT work.CaseFormAnswers(CaseId,FormVersionId,AnswersJson,SubmittedBy)
 VALUES(@CaseId,@FormVersionId,@IntakeJson,@ActorUserId);
 IF @LodgementOperationId IS NOT NULL
 BEGIN
  INSERT integration.Executions(ProjectId,CaseId,OperationId,IdempotencyKey,Status,AttemptCount,StartedAt,FinishedAt,MappedFieldsJson)
   VALUES(@ProjectId,@CaseId,@LodgementOperationId,@IdempotencyKey,'Succeeded',1,SYSUTCDATETIME(),SYSUTCDATETIME(),@LodgementMappedJson);
  INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
   VALUES(@CaseId,'IntegrationSucceeded',N'Approved case-type data source executed during lodgement',@ActorUserId);
 END;
 INSERT work.Instances(InstanceId,CaseId,WorkflowVersionId) VALUES(@InstanceId,@CaseId,@WorkflowVersionId);
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId) VALUES(@CaseId,'Created',N'Case lodged',@ActorUserId);
 EXEC notify.usp_QueueConfiguredEvent 'CASE_CREATED',@ProjectId,@CaseId,@RecipientUserId=@ActorUserId;
 EXEC work.usp_ReindexCaseFields @CaseId;
 DECLARE @StartNodeId BIGINT=(SELECT NodeId FROM flow.Nodes WHERE WorkflowVersionId=@WorkflowVersionId AND NodeType='start');
 IF @StartNodeId IS NULL BEGIN ROLLBACK; THROW 50168,'Published workflow has no start node.',1; END;
 EXEC work.usp_ActivateNode @InstanceId,@StartNodeId,@ActorUserId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Case',@EntityId=@CaseId,@ActionCode='Create';
 COMMIT;
 SELECT @CaseId AS CaseId,@ReferenceNo AS ReferenceNo,Status FROM work.Cases WHERE CaseId=@CaseId;
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
 DECLARE @RuleTask BIGINT,@RuleProject BIGINT,@RuleCase BIGINT,@RuleRecipient BIGINT;
 DECLARE ruleDue CURSOR LOCAL FAST_FORWARD FOR SELECT TaskId,ProjectId,CaseId,Recipient FROM @Due;
 OPEN ruleDue;FETCH NEXT FROM ruleDue INTO @RuleTask,@RuleProject,@RuleCase,@RuleRecipient;
 WHILE @@FETCH_STATUS=0
 BEGIN
  EXEC notify.usp_QueueConfiguredEvent 'SLA_BREACHED',@RuleProject,@RuleCase,@TaskId=@RuleTask,@RecipientUserId=@RuleRecipient;
  FETCH NEXT FROM ruleDue INTO @RuleTask,@RuleProject,@RuleCase,@RuleRecipient;
 END;
 CLOSE ruleDue;DEALLOCATE ruleDue;
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
