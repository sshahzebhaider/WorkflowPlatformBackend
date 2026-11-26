/* Non-destructive verification. Execute after 11_REQUEST_INPUT_MAPPING.sql. */
USE [WorkflowPlatformV2];
GO
IF COL_LENGTH('integration.Operations','RequestParamsJson') IS NULL
 THROW 50400,'FAIL: integration.Operations.RequestParamsJson is missing.',1;
IF OBJECT_ID('integration.usp_SaveOperation','P') IS NULL
 THROW 50401,'FAIL: integration.usp_SaveOperation is missing.',1;
IF OBJECT_ID('integration.usp_SaveDataSource','P') IS NULL
 THROW 50402,'FAIL: integration.usp_SaveDataSource is missing.',1;
IF NOT EXISTS(SELECT 1 FROM sys.parameters
 WHERE object_id=OBJECT_ID('integration.usp_SaveOperation') AND name='@RequestParamsJson')
 THROW 50403,'FAIL: usp_SaveOperation has the old signature.',1;
PRINT 'PASS: Request input mapping schema and SQL procedures are installed.';
GO
