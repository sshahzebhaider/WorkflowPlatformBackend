USE [WorkflowPlatformV2];
GO
SET XACT_ABORT ON;
GO
/*
  Migration 26 - optional pre-intake data lookup. No existing case rows are changed.
  The saved preview is an opaque, expiring receipt. Case creation and receipt
  consumption happen in one SQL transaction; the external API is not called twice.
*/
IF OBJECT_ID(N'integration.LodgementPreviews',N'U') IS NULL
BEGIN
    CREATE TABLE integration.LodgementPreviews (
        PreviewId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LodgementPreviews PRIMARY KEY,
        ProjectId BIGINT NOT NULL,
        CaseTypeId BIGINT NOT NULL,
        CaseTypeVersionId BIGINT NOT NULL,
        ActorUserId BIGINT NOT NULL,
        OperationId BIGINT NOT NULL,
        TokenHash VARBINARY(32) NOT NULL,
        MappedFieldsJson NVARCHAR(MAX) NOT NULL,
        DisplayJson NVARCHAR(MAX) NOT NULL,
        CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_LodgementPreviews_CreatedAt DEFAULT SYSUTCDATETIME(),
        ExpiresAt DATETIME2(3) NOT NULL,
        UsedCaseId BIGINT NULL,
        UsedAt DATETIME2(3) NULL,
        CONSTRAINT UQ_LodgementPreviews_TokenHash UNIQUE(TokenHash),
        CONSTRAINT CK_LodgementPreviews_Mapped CHECK(ISJSON(MappedFieldsJson)=1),
        CONSTRAINT CK_LodgementPreviews_Display CHECK(ISJSON(DisplayJson)=1)
    );
    CREATE INDEX IX_LodgementPreviews_Expires ON integration.LodgementPreviews(ExpiresAt)
       INCLUDE (UsedCaseId);
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_SaveLodgementPreview
    @ActorUserId BIGINT,
    @ProjectId BIGINT,
    @CaseTypeId BIGINT,
    @CaseTypeVersionId BIGINT,
    @OperationId BIGINT,
    @TokenHash VARBINARY(32),
    @MappedFieldsJson NVARCHAR(MAX),
    @DisplayJson NVARCHAR(MAX),
    @PreviewId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.create')<>1
        THROW 50600,'Case creation permission is required for a data-source lookup.',1;
    IF NOT EXISTS (
        SELECT 1 FROM core.CaseTypes t
        JOIN core.CaseTypeVersions v ON v.CaseTypeVersionId=t.LiveVersionId
        JOIN integration.Operations op ON op.OperationId=@OperationId AND op.IsActive=1
        JOIN integration.DataSources src ON src.DataSourceId=op.DataSourceId AND src.IsActive=1 AND src.Kind='REST'
        JOIN integration.ProjectDataSources pds ON pds.DataSourceId=src.DataSourceId AND pds.ProjectId=@ProjectId
        WHERE t.CaseTypeId=@CaseTypeId AND t.ProjectId=@ProjectId AND t.IsActive=1
          AND v.CaseTypeVersionId=@CaseTypeVersionId
          AND TRY_CONVERT(BIGINT,JSON_VALUE(v.PublishedConfigJson,'$.lodgementIntegration.operationId'))=@OperationId
    ) THROW 50601,'The configured operation is not published and approved for this Case Type.',1;
    IF DATALENGTH(@TokenHash)<>32 OR ISJSON(@MappedFieldsJson)<>1
       OR LEFT(LTRIM(@MappedFieldsJson),1)<>'{' OR NOT EXISTS (SELECT 1 FROM OPENJSON(@MappedFieldsJson) WHERE [key]='api_response')
       OR ISJSON(@DisplayJson)<>1 OR LEFT(LTRIM(@DisplayJson),1)<>'['
       OR DATALENGTH(@MappedFieldsJson)>262144 OR DATALENGTH(@DisplayJson)>100000
        THROW 50602,'The verified data-source response is invalid or too large.',1;
    INSERT integration.LodgementPreviews(ProjectId,CaseTypeId,CaseTypeVersionId,
        ActorUserId,OperationId,TokenHash,MappedFieldsJson,DisplayJson,ExpiresAt)
    VALUES(@ProjectId,@CaseTypeId,@CaseTypeVersionId,@ActorUserId,@OperationId,
        @TokenHash,@MappedFieldsJson,@DisplayJson,DATEADD(MINUTE,60,SYSUTCDATETIME()));
    SET @PreviewId=CONVERT(BIGINT,SCOPE_IDENTITY());
END;
GO
/*
  Wrapper uses the already installed work.usp_CreateCase, preserving all
  attachments, workflow activation, RCA and SQL validations. Its nested
  transaction is committed only after the preview is marked as consumed.
*/
CREATE OR ALTER PROCEDURE integration.usp_CreateCaseFromPreview
    @ActorUserId BIGINT,
    @ProjectId BIGINT,
    @CaseTypeId BIGINT,
    @IntakeJson NVARCHAR(MAX),
    @ClassificationJson NVARCHAR(MAX)=N'{}',
    @Title NVARCHAR(300)=NULL,
    @IdempotencyKey VARCHAR(120)=NULL,
    @CaseId BIGINT OUTPUT,
    @ReferenceNo NVARCHAR(55) OUTPUT,
    @PreviewId BIGINT,
    @PreviewTokenHash VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @OperationId BIGINT,@MappedFieldsJson NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRAN;
        SELECT @OperationId=p.OperationId,@MappedFieldsJson=p.MappedFieldsJson
        FROM integration.LodgementPreviews p WITH (UPDLOCK,HOLDLOCK)
        JOIN core.CaseTypes t ON t.CaseTypeId=p.CaseTypeId AND t.ProjectId=p.ProjectId
        WHERE p.PreviewId=@PreviewId AND p.TokenHash=@PreviewTokenHash
          AND p.ProjectId=@ProjectId AND p.CaseTypeId=@CaseTypeId AND p.ActorUserId=@ActorUserId
          AND p.CaseTypeVersionId=t.LiveVersionId
          AND p.UsedCaseId IS NULL AND p.ExpiresAt>SYSUTCDATETIME()
          AND EXISTS(SELECT 1 FROM integration.Operations op
                     JOIN integration.DataSources src ON src.DataSourceId=op.DataSourceId AND src.IsActive=1
                     JOIN integration.DataSourceApprovals approval ON approval.DataSourceId=src.DataSourceId
                       AND approval.IsApproved=1 AND approval.ApprovedBaseUrl=src.BaseUrl
                     JOIN integration.ProjectDataSources ds ON ds.DataSourceId=op.DataSourceId
                     WHERE op.OperationId=p.OperationId AND op.IsActive=1 AND ds.ProjectId=@ProjectId);
        IF @OperationId IS NULL
            THROW 50603,'Data-source lookup expired, was used, or is no longer approved. Fetch the data again.',1;
        EXEC work.usp_CreateCase
            @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@CaseTypeId=@CaseTypeId,
            @IntakeJson=@IntakeJson,@ClassificationJson=@ClassificationJson,
            @Title=@Title,@IdempotencyKey=@IdempotencyKey,
            @LodgementOperationId=@OperationId,@LodgementMappedJson=@MappedFieldsJson,
            @CaseId=@CaseId OUTPUT,@ReferenceNo=@ReferenceNo OUTPUT;
        UPDATE integration.LodgementPreviews
           SET UsedCaseId=@CaseId,UsedAt=SYSUTCDATETIME()
        WHERE PreviewId=@PreviewId;
        COMMIT;
        SELECT @CaseId AS CaseId,@ReferenceNo AS ReferenceNo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_PurgeLodgementPreviews
AS
BEGIN
    SET NOCOUNT ON;
    -- Keep unconsumed/consumed receipts briefly for diagnostics only. The
    -- durable case context is in work.Cases; expired preview payloads are PII.
    DELETE TOP (2000) FROM integration.LodgementPreviews
    WHERE ExpiresAt<DATEADD(HOUR,-24,SYSUTCDATETIME());
END;
GO
IF DATABASE_PRINCIPAL_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
    GRANT EXECUTE ON OBJECT::integration.usp_SaveLodgementPreview TO [workflow_app_v2];
    GRANT EXECUTE ON OBJECT::integration.usp_CreateCaseFromPreview TO [workflow_app_v2];
    GRANT EXECUTE ON OBJECT::integration.usp_PurgeLodgementPreviews TO [workflow_app_v2];
END;
GO
IF OBJECT_ID(N'integration.LodgementPreviews',N'U') IS NULL
    OR OBJECT_ID(N'integration.usp_SaveLodgementPreview',N'P') IS NULL
    OR OBJECT_ID(N'integration.usp_CreateCaseFromPreview',N'P') IS NULL
    THROW 50604,'Pre-intake lookup migration did not install.',1;
PRINT 'PASS: pre-intake lookup database objects installed.';
GO
