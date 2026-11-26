USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'auth.usp_CreatePlatformAdminUser',N'P') IS NULL THROW 51010,'Atomic platform admin creation procedure missing.',1;
IF NOT EXISTS(SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N'auth.usp_SaveCustomRole') AND name=N'@Description') THROW 51011,'Role editing migration missing.',1;
IF CHARINDEX(N'OptionsJson',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase')),N''))=0 THROW 51012,'RCA snapshot options missing.',1;
IF CHARINDEX(N'step3',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'core.usp_OnboardProject')),N''))=0 THROW 51013,'Onboarding workflow templates missing.',1;
IF USER_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
 DECLARE @Allowed INT;
 EXECUTE AS USER='workflow_app_v2';
 SET @Allowed=HAS_PERMS_BY_NAME(N'auth.usp_CreatePlatformAdminUser',N'OBJECT',N'EXECUTE');
 REVERT;
 IF ISNULL(@Allowed,0)<>1 THROW 51014,'Application role grant missing. Run 03_APP_PERMISSIONS.sql.',1;
END;
PRINT 'PASS: targeted functional migration object checks.';
GO
