USE WorkflowPlatformV2;
GO
IF COL_LENGTH(N'integration.Executions',N'ClaimVersion') IS NULL
 ALTER TABLE integration.Executions ADD ClaimVersion BIGINT NOT NULL CONSTRAINT DF_Executions_ClaimVersion DEFAULT(0);
GO
CREATE OR ALTER PROCEDURE integration.usp_ClaimWorkflowExecutions @BatchSize INT=8
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize NOT BETWEEN 1 AND 30 THROW 50320,'Invalid workflow integration batch size.',1;
 BEGIN TRAN;
 DECLARE @Expired TABLE(ExecutionId BIGINT,CaseId BIGINT,ErrorText NVARCHAR(1000));
 UPDATE e SET Status='Failed',FinishedAt=SYSUTCDATETIME(),LastError=CASE WHEN o.HttpMethod='GET' THEN N'Retry limit exhausted' ELSE N'External outcome unknown; manual reconciliation required' END
 OUTPUT inserted.ExecutionId,inserted.CaseId,inserted.LastError INTO @Expired
 FROM integration.Executions e JOIN integration.Operations o ON o.OperationId=e.OperationId
 WHERE e.NodeId IS NOT NULL AND e.CaseId IS NOT NULL AND e.Status='Running' AND e.StartedAt<DATEADD(MINUTE,-5,SYSUTCDATETIME())
 AND (e.AttemptCount>=5 OR o.HttpMethod<>'GET');
 UPDATE c SET Status='Integration failed',UpdatedAt=SYSUTCDATETIME() FROM work.Cases c WHERE c.ClosedAt IS NULL AND EXISTS(SELECT 1 FROM @Expired x WHERE x.CaseId=c.CaseId);
 INSERT work.CaseEvents(CaseId,EventType,Message) SELECT CaseId,'IntegrationFailed',ErrorText FROM @Expired;
 ;WITH nextBatch AS (
  SELECT TOP(@BatchSize) e.* FROM integration.Executions e WITH(UPDLOCK,READPAST,ROWLOCK)
  WHERE NodeId IS NOT NULL AND CaseId IS NOT NULL AND AttemptCount<5
    AND (Status='Pending' OR (EXISTS(SELECT 1 FROM integration.Operations o WHERE o.OperationId=e.OperationId AND o.HttpMethod='GET')
    AND (Status='Running' AND StartedAt<DATEADD(MINUTE,-5,SYSUTCDATETIME()) OR Status='Failed' AND FinishedAt<DATEADD(SECOND,-60,SYSUTCDATETIME()))))
  ORDER BY ExecutionId
 )
 UPDATE nextBatch SET Status='Running',StartedAt=SYSUTCDATETIME(),
  AttemptCount=AttemptCount+1,ClaimVersion=ClaimVersion+1
 OUTPUT inserted.ExecutionId,inserted.CaseId,inserted.NodeId,inserted.OperationId,inserted.IdempotencyKey,inserted.AttemptCount,inserted.ProjectId,inserted.ClaimVersion;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_RecordResult
 @ExecutionId BIGINT,@Succeeded BIT,@ResponseRedactedJson NVARCHAR(MAX)=NULL,
 @MappedFieldsJson NVARCHAR(MAX)=NULL,@Error NVARCHAR(1000)=NULL,@ClaimAttempt BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @ResponseRedactedJson IS NOT NULL AND ISJSON(@ResponseRedactedJson)<>1 THROW 50213,'Response must be JSON.',1;
 IF @MappedFieldsJson IS NOT NULL AND (ISJSON(@MappedFieldsJson)<>1 OR LEFT(LTRIM(@MappedFieldsJson),1)<>'{') THROW 50214,'Mapped response must be a JSON object.',1;
 DECLARE @CaseId BIGINT,@ProjectId BIGINT,@NodeId BIGINT,@CurrentJson NVARCHAR(MAX);
 BEGIN TRAN;
 SELECT @CaseId=CaseId,@ProjectId=ProjectId,@NodeId=NodeId FROM integration.Executions WITH(UPDLOCK,HOLDLOCK)
 WHERE ExecutionId=@ExecutionId AND ((NodeId IS NULL AND @ClaimAttempt IS NULL AND Status IN('Running','Pending','Failed')) OR (NodeId IS NOT NULL AND Status='Running' AND ClaimVersion=@ClaimAttempt));
 IF @ProjectId IS NULL BEGIN ROLLBACK; THROW 50215,'Execution does not exist or is already completed.',1; END;
 UPDATE integration.Executions SET Status=CASE WHEN @Succeeded=1 THEN 'Succeeded' ELSE 'Failed' END,
 FinishedAt=SYSUTCDATETIME(),LastError=@Error,ResponseRedactedJson=@ResponseRedactedJson,
 MappedFieldsJson=@MappedFieldsJson,AttemptCount=AttemptCount+CASE WHEN @ClaimAttempt IS NULL THEN 1 ELSE 0 END WHERE ExecutionId=@ExecutionId;
 IF @CaseId IS NOT NULL
 BEGIN
  IF @Succeeded=1 AND @MappedFieldsJson IS NOT NULL
  BEGIN
   SELECT @CurrentJson=CurrentValuesJson FROM work.Cases WITH(UPDLOCK,HOLDLOCK) WHERE CaseId=@CaseId;
   DECLARE @Key NVARCHAR(200),@Val NVARCHAR(MAX),@JsonType INT,@Path NVARCHAR(240);
   DECLARE mapped CURSOR LOCAL FAST_FORWARD FOR SELECT [key],[value],[type] FROM OPENJSON(@MappedFieldsJson);
   OPEN mapped;FETCH NEXT FROM mapped INTO @Key,@Val,@JsonType;
   WHILE @@FETCH_STATUS=0
   BEGIN
    /* Keep mapping names simple and predictable; do not execute arbitrary JSON-path expressions. */
    IF LEN(@Key)>100 OR @Key LIKE '%[^A-Za-z0-9_]%' COLLATE Latin1_General_BIN2
    BEGIN CLOSE mapped;DEALLOCATE mapped;ROLLBACK; THROW 50216,'Mapped field keys may contain only letters, numbers and underscore.',1; END;
    SET @Path=CONCAT('$.',@Key);
    SELECT @CurrentJson=CONCAT(N'{',STRING_AGG(CONVERT(NVARCHAR(MAX),CONCAT(N'"',STRING_ESCAPE(j.[key],'json'),N'":',CASE j.[type] WHEN 0 THEN N'null' WHEN 1 THEN CONCAT(N'"',STRING_ESCAPE(j.[value],'json'),N'"') ELSE j.[value] END)),N','),N'}')
    FROM (SELECT [key],[value],[type] FROM OPENJSON(@CurrentJson) WHERE [key] COLLATE Latin1_General_BIN2<>@Key COLLATE Latin1_General_BIN2
          UNION ALL SELECT @Key,@Val,@JsonType) j;
    FETCH NEXT FROM mapped INTO @Key,@Val,@JsonType;
   END;
   CLOSE mapped;DEALLOCATE mapped;
   UPDATE work.Cases SET CurrentValuesJson=@CurrentJson,UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   EXEC work.usp_ReindexCaseFields @CaseId;
  END;
  IF @Succeeded=0 UPDATE work.Cases SET Status='Integration failed',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  INSERT work.CaseEvents(CaseId,EventType,Message) VALUES(@CaseId,CASE WHEN @Succeeded=1 THEN 'IntegrationSucceeded' ELSE 'IntegrationFailed' END,
  CASE WHEN @Succeeded=1 THEN N'External integration completed' ELSE N'External integration failed; retry required' END);
 END;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE work.usp_GetCaseDetails @ActorUserId BIGINT,@ProjectId BIGINT,@CaseId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Allowed BIT=0;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.view')<>1 THROW 50224,'User is not authorized to view this case.',1;
 IF NOT EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND ProjectId=@ProjectId) THROW 50223,'Case not found in project.',1;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)=1 OR EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND CreatedBy=@ActorUserId)
  OR EXISTS(SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
    LEFT JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@ActorUserId AND m.IsActive=1
    WHERE i.CaseId=@CaseId AND (t.AssignedTo=@ActorUserId OR t.CompletedBy=@ActorUserId OR m.UserId IS NOT NULL)) SET @Allowed=1;
 IF @Allowed<>1 THROW 50224,'User is not authorized to view this case.',1;
 SELECT * FROM work.Cases WHERE CaseId=@CaseId;
 SELECT t.* FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId WHERE i.CaseId=@CaseId ORDER BY t.CreatedAt;
 SELECT EventId,EventType,Message,ActorUserId,DetailsJson,OccurredAt FROM work.CaseEvents WHERE CaseId=@CaseId ORDER BY EventId;
 SELECT AnswerId,FormVersionId,TaskId,AnswersJson,SubmittedBy,SubmittedAt FROM work.CaseFormAnswers WHERE CaseId=@CaseId ORDER BY SubmittedAt;
 SELECT DocumentId,TaskId,FieldKey,OriginalFileName,MimeType,FileSizeBytes,ScanStatus,UploadedAt FROM files.Documents WHERE CaseId=@CaseId AND IsDeleted=0 ORDER BY UploadedAt;
END;
GO

CREATE OR ALTER PROCEDURE files.usp_DeleteExpiredStage @StageId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 DELETE FROM files.StagedDocuments WHERE StageId=@StageId AND ConsumedCaseId IS NULL
 AND ExpiresAt<=DATEADD(MINUTE,-10,SYSUTCDATETIME());
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'files.StagedDocuments') AND name=N'IX_StagedDocuments_Expiry')
 CREATE INDEX IX_StagedDocuments_Expiry ON files.StagedDocuments(ExpiresAt,StageId) INCLUDE(StorageKey) WHERE ConsumedCaseId IS NULL;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'work.Cases') AND name=N'IX_Cases_Project_CreatedAt')
 CREATE INDEX IX_Cases_Project_CreatedAt ON work.Cases(ProjectId,CreatedAt DESC,CaseRowId DESC)
 INCLUDE(CaseId,ReferenceNo,Title,Status,Priority,CaseTypeVersionId,CreatedBy,DueAt,ClosedAt);
GO

CREATE OR ALTER PROCEDURE work.usp_ReindexCaseFields @CaseId BIGINT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Values NVARCHAR(MAX),@FormVersionId BIGINT;
 SELECT @ProjectId=c.ProjectId,@Values=c.CurrentValuesJson,@FormVersionId=t.IntakeFormVersionId
 FROM work.Cases c JOIN core.CaseTypeVersions t ON t.CaseTypeVersionId=c.CaseTypeVersionId WHERE c.CaseId=@CaseId;
 IF @ProjectId IS NULL THROW 50150,'Case not found.',1;
 DECLARE @Desired TABLE(FieldKey VARCHAR(100) PRIMARY KEY,ValueText NVARCHAR(450),ValueNumber DECIMAL(20,4),ValueDate DATE);
 INSERT @Desired SELECT f.FieldKey,LEFT(CONVERT(NVARCHAR(MAX),j.value),450),
 CASE WHEN f.FieldType='number' THEN TRY_CONVERT(DECIMAL(20,4),j.value) END,
 CASE WHEN f.FieldType='date' THEN TRY_CONVERT(DATE,j.value) END
 FROM OPENJSON(@Values) j JOIN forms.VersionFields f ON f.FormVersionId=@FormVersionId
 AND f.FieldKey=j.[key] COLLATE DATABASE_DEFAULT AND f.IsSearchable=1 WHERE j.[type] NOT IN(0,4,5);
 DELETE i FROM work.CaseFieldIndex i WHERE i.CaseId=@CaseId AND NOT EXISTS(SELECT 1 FROM @Desired d WHERE d.FieldKey=i.FieldKey);
 UPDATE i SET ValueText=d.ValueText,ValueNumber=d.ValueNumber,ValueDate=d.ValueDate,LookupItemId=NULL
 FROM work.CaseFieldIndex i JOIN @Desired d ON d.FieldKey=i.FieldKey WHERE i.CaseId=@CaseId
 AND EXISTS(SELECT i.ValueText,i.ValueNumber,i.ValueDate EXCEPT SELECT d.ValueText,d.ValueNumber,d.ValueDate);
 INSERT work.CaseFieldIndex(CaseId,ProjectId,FieldKey,ValueText,ValueNumber,ValueDate)
 SELECT @CaseId,@ProjectId,d.FieldKey,d.ValueText,d.ValueNumber,d.ValueDate FROM @Desired d
 WHERE NOT EXISTS(SELECT 1 FROM work.CaseFieldIndex i WHERE i.CaseId=@CaseId AND i.FieldKey=d.FieldKey);
END;
GO

CREATE OR ALTER PROCEDURE work.usp_CompleteTask
 @ActorUserId BIGINT,@TaskId BIGINT,@Action VARCHAR(60),
 @AnswersByFormJson NVARCHAR(MAX)=N'{}',@Comment NVARCHAR(1000)=NULL
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
 DECLARE @AssignmentMode VARCHAR(20);
 SELECT @AssignmentMode=AssignmentMode,@RequireForm=RequireForm,
 @AllowedActionsJson=AllowedActionsJson FROM flow.Nodes WHERE NodeId=@NodeId;
 IF @RoutingStage<>'Officer' AND @AssignmentMode<>'RoleQueue'
 BEGIN ROLLBACK; THROW 50178,'Forward through the review hierarchy before completing this step.',1; END;
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
    SELECT @CurrentJson=CONCAT(N'{',STRING_AGG(CONVERT(NVARCHAR(MAX),CONCAT(N'"',STRING_ESCAPE(j.[key],'json'),N'":',CASE j.[type] WHEN 0 THEN N'null' WHEN 1 THEN CONCAT(N'"',STRING_ESCAPE(j.[value],'json'),N'"') ELSE j.[value] END)),N','),N'}')
    FROM (SELECT [key],[value],[type] FROM OPENJSON(@CurrentJson) WHERE [key] COLLATE Latin1_General_BIN2<>@FieldKey COLLATE Latin1_General_BIN2
          UNION ALL SELECT @FieldKey,@FieldValue,@JsonType) j;
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
  (SELECT CONVERT(VARCHAR(36),@TaskId) AS taskId,@Action AS action,
   NULLIF(LTRIM(RTRIM(@Comment)),N'') AS comment FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
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

CREATE OR ALTER PROCEDURE files.usp_CreateStagedDocument
 @project BIGINT,@type BIGINT,@version BIGINT,@actor BIGINT,@field NVARCHAR(100),
 @key NVARCHAR(600),@name NVARCHAR(260),@mime NVARCHAR(120),@size BIGINT,@digest VARBINARY(32)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@actor,@project,'cases.create')<>1 THROW 50403,'Case creation permission required.',1;
 IF NOT EXISTS(SELECT 1 FROM core.CaseTypes t JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=t.LiveVersionId
 JOIN forms.VersionFields f ON f.FormVersionId=v.IntakeFormVersionId
 WHERE t.ProjectId=@project AND t.CaseTypeId=@type AND t.IsActive=1 AND f.FormVersionId=@version AND f.FieldKey=@field AND f.FieldType='attachment')
 THROW 50404,'Attachment field is no longer available.',1;
 IF @size NOT BETWEEN 1 AND 20971520 OR DATALENGTH(@digest)<>32 OR @digest IS NULL THROW 50405,'Invalid attachment metadata.',1;
 INSERT files.StagedDocuments(ProjectId,CaseTypeId,FormVersionId,ActorUserId,FieldKey,StorageKey,OriginalFileName,MimeType,FileSizeBytes,Sha256)
 OUTPUT inserted.StageId VALUES(@project,@type,@version,@actor,@field,@key,@name,@mime,@size,@digest);
END;
GO

CREATE OR ALTER PROCEDURE integration.usp_RetryFailedRead @ActorUserId BIGINT,@ProjectId BIGINT,@ExecutionId BIGINT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50406,'Administrator permission required.',1;
 BEGIN TRAN;
 UPDATE e SET Status='Pending',AttemptCount=0,StartedAt=NULL,FinishedAt=NULL,LastError=NULL
 FROM integration.Executions e JOIN integration.Operations o ON o.OperationId=e.OperationId
 JOIN integration.DataSources s ON s.DataSourceId=o.DataSourceId
 JOIN integration.ProjectDataSources p ON p.DataSourceId=s.DataSourceId AND p.ProjectId=e.ProjectId
 JOIN integration.DataSourceApprovals a ON a.DataSourceId=s.DataSourceId AND a.IsApproved=1 AND a.ApprovedBaseUrl=s.BaseUrl
 WHERE e.ExecutionId=@ExecutionId AND e.ProjectId=@ProjectId AND e.Status='Failed' AND e.NodeId IS NOT NULL
 AND e.CaseId IS NOT NULL AND o.IsActive=1 AND s.IsActive=1 AND o.HttpMethod='GET'
 AND e.ResumedAt IS NULL AND EXISTS(SELECT 1 FROM work.Instances i WHERE i.CaseId=e.CaseId AND i.Status IN('Running','Waiting'));
 IF @@ROWCOUNT<>1 BEGIN ROLLBACK; THROW 50407,'Only an approved failed read in an active workflow may be retried.',1; END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='IntegrationExecution',@EntityId=@ExecutionId,@ActionCode='RetryFailedRead';
 COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE integration.usp_SetDataSourceApproval
 @ActorUserId BIGINT,@DataSourceId BIGINT,@ExpectedBaseUrl NVARCHAR(1000),
 @ApprovedHost NVARCHAR(253),@Approved BIT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,NULL)<>1 THROW 50901,'Platform administrator required.',1;
 IF LEN(@ApprovedHost)=0 OR @ApprovedHost LIKE '%[^a-zA-Z0-9.-]%'
  THROW 50902,'Invalid hostname.',1;
 BEGIN TRAN;
 IF NOT EXISTS(SELECT 1 FROM integration.DataSources WITH(UPDLOCK,HOLDLOCK)
   WHERE DataSourceId=@DataSourceId AND IsActive=1 AND BaseUrl COLLATE Latin1_General_BIN2=@ExpectedBaseUrl COLLATE Latin1_General_BIN2)
  BEGIN ROLLBACK;THROW 50903,'Data source changed. Refresh and review its URL.',1; END;
 IF EXISTS(SELECT 1 FROM integration.DataSourceApprovals WHERE DataSourceId=@DataSourceId)
  UPDATE integration.DataSourceApprovals
  SET ApprovedBaseUrl=@ExpectedBaseUrl,ApprovedHost=LOWER(@ApprovedHost),
      IsApproved=@Approved,ApprovedBy=@ActorUserId,
      ApprovedAt=CASE WHEN @Approved=1 THEN SYSUTCDATETIME() ELSE NULL END,
      UpdatedAt=SYSUTCDATETIME()
  WHERE DataSourceId=@DataSourceId;
 ELSE INSERT integration.DataSourceApprovals
  (DataSourceId,ApprovedBaseUrl,ApprovedHost,IsApproved,ApprovedBy,ApprovedAt)
  VALUES(@DataSourceId,@ExpectedBaseUrl,LOWER(@ApprovedHost),@Approved,@ActorUserId,
  CASE WHEN @Approved=1 THEN SYSUTCDATETIME() END);
 DECLARE @ApprovalAudit NVARCHAR(MAX)=CASE WHEN @Approved=1 THEN N'{"approved":true}' ELSE N'{"approved":false}' END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DataSource',
  @EntityId=@DataSourceId,@ActionCode='HostApprovalChanged',@DetailsJson=@ApprovalAudit;
 COMMIT;
END;
GO
