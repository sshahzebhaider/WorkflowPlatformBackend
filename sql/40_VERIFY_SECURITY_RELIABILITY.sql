/* Read-only deployment gate. Run before and again after application permissions. */
USE WorkflowPlatformV2;
GO
SET NOCOUNT ON;
IF COL_LENGTH(N'integration.Executions',N'ClaimVersion') IS NULL THROW 50994,'ClaimVersion missing; install migration 39.',1;
IF OBJECT_ID(N'files.usp_CreateStagedDocument',N'P') IS NULL OR OBJECT_ID(N'files.usp_DeleteExpiredStage',N'P') IS NULL
 OR OBJECT_ID(N'integration.usp_RetryFailedRead',N'P') IS NULL THROW 50995,'Security migration procedures missing.',1;
IF NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N'integration.usp_RecordResult') AND name=N'@ClaimAttempt' AND system_type_id=TYPE_ID(N'bigint'))
 THROW 50996,'Worker claim fencing contract missing.',1;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'work.Cases') AND name=N'IX_Cases_Project_CreatedAt')
 THROW 50997,'Case pagination index missing.',1;
IF USER_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
 DECLARE @Ok BIT;
 EXECUTE AS USER='workflow_app_v2';
 SELECT @Ok=CASE WHEN HAS_PERMS_BY_NAME('files.usp_CreateStagedDocument','OBJECT','EXECUTE')=1
 AND HAS_PERMS_BY_NAME('files.StagedDocuments','OBJECT','INSERT')=0
 AND HAS_PERMS_BY_NAME('auth.usp_BootstrapPlatformAdmin','OBJECT','EXECUTE')=0
 AND HAS_PERMS_BY_NAME('integration.usp_RetryFailedRead','OBJECT','EXECUTE')=1
 AND HAS_PERMS_BY_NAME('auth.fn_IsAdmin','OBJECT','EXECUTE')=1 THEN 1 ELSE 0 END;
 REVERT;
 IF @Ok<>1 THROW 50998,'Application permissions are incorrect. Run the updated 03_APP_PERMISSIONS.sql and review role membership.',1;
END;
PRINT 'PASS: security/reliability schema and available application permission checks.';
GO
