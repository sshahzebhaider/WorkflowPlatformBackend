USE [WorkflowPlatformV2];
GO
/* Case intake attachments are scanned before creating a case and consumed atomically. */
IF OBJECT_ID(N'files.Seq_StagedDocuments',N'SO') IS NULL EXEC(N'CREATE SEQUENCE files.Seq_StagedDocuments AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'files.StagedDocuments',N'U') IS NULL
CREATE TABLE files.StagedDocuments (
 StageId BIGINT NOT NULL CONSTRAINT PK_StagedDocuments PRIMARY KEY DEFAULT (NEXT VALUE FOR files.Seq_StagedDocuments),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseTypeId BIGINT NOT NULL REFERENCES core.CaseTypes(CaseTypeId),
 FormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 ActorUserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 FieldKey VARCHAR(100) NOT NULL,
 StorageKey NVARCHAR(600) NOT NULL,OriginalFileName NVARCHAR(260) NOT NULL,
 MimeType NVARCHAR(120) NOT NULL,FileSizeBytes BIGINT NOT NULL,Sha256 VARBINARY(32) NOT NULL,
 ScannedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 ExpiresAt DATETIME2(3) NOT NULL DEFAULT DATEADD(HOUR,2,SYSUTCDATETIME()),
 ConsumedCaseId BIGINT NULL REFERENCES work.Cases(CaseId),ConsumedAt DATETIME2(3) NULL
);
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
 SELECT st.ProjectId,@CaseId,st.FormVersionId,st.FieldKey,st.StorageKey,
 st.OriginalFileName,st.MimeType,st.FileSizeBytes,st.Sha256,'Clean',@ActorUserId
 FROM files.StagedDocuments AS st
 INNER JOIN @IntakeFiles AS r ON r.StageId=st.StageId;
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
 EXEC work.usp_ReindexCaseFields @CaseId;
 DECLARE @StartNodeId BIGINT=(SELECT NodeId FROM flow.Nodes WHERE WorkflowVersionId=@WorkflowVersionId AND NodeType='start');
 IF @StartNodeId IS NULL BEGIN ROLLBACK; THROW 50168,'Published workflow has no start node.',1; END;
 EXEC work.usp_ActivateNode @InstanceId,@StartNodeId,@ActorUserId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Case',@EntityId=@CaseId,@ActionCode='Create';
 COMMIT;
 SELECT @CaseId AS CaseId,@ReferenceNo AS ReferenceNo,Status FROM work.Cases WHERE CaseId=@CaseId;
END;
GO

-- The pre-case HTTP staging endpoint performs a parameterized direct INSERT and
-- requires this narrow permission; schema-level SELECT/EXECUTE grants are insufficient.
IF USER_ID(N'workflow_app_v2') IS NOT NULL
 GRANT INSERT ON OBJECT::files.StagedDocuments TO [workflow_app_v2];
GO
