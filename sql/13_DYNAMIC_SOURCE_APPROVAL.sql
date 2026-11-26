-- 13_DYNAMIC_SOURCE_APPROVAL.sql -- run on existing WorkflowPlatformV2 after 12_VERIFY_REQUEST_MAPPING.sql.
-- Non-destructive, rerunnable, intentionally fail-closed. Back up before applying.
USE [WorkflowPlatformV2];
GO
IF OBJECT_ID(N'integration.DataSourceApprovals',N'U') IS NULL
BEGIN
 CREATE TABLE integration.DataSourceApprovals (
  DataSourceId BIGINT NOT NULL PRIMARY KEY REFERENCES integration.DataSources(DataSourceId),
  ApprovedBaseUrl NVARCHAR(1000) NOT NULL,
  ApprovedHost NVARCHAR(253) NOT NULL,
  IsApproved BIT NOT NULL DEFAULT 0,
  ApprovedBy BIGINT NULL REFERENCES auth.Users(UserId),
  ApprovedAt DATETIME2(3) NULL,
  UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
 );
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
   WHERE DataSourceId=@DataSourceId AND IsActive=1 AND BaseUrl=@ExpectedBaseUrl)
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
-- The direct worker query needs this table; grant targeted least-privilege access.
IF USER_ID('workflow_app_v2') IS NOT NULL
BEGIN
 GRANT SELECT ON OBJECT::integration.DataSourceApprovals TO [workflow_app_v2];
 GRANT EXECUTE ON OBJECT::integration.usp_SetDataSourceApproval TO [workflow_app_v2];
END;
GO
SELECT 'OK' AS Migration, COUNT(*) AS ExistingApprovalRecords FROM integration.DataSourceApprovals;
