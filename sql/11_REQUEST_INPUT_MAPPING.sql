/* Apply to an existing WorkflowPlatformV2 database BEFORE starting the upgraded API.
   Non-destructive: does not remove data, roles or existing integration operations. */
USE [WorkflowPlatformV2];
GO
IF COL_LENGTH('integration.Operations','RequestParamsJson') IS NULL
 ALTER TABLE integration.Operations ADD RequestParamsJson NVARCHAR(MAX) NULL;
GO
CREATE OR ALTER PROCEDURE integration.usp_SaveDataSource
 @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,@Kind VARCHAR(20)='REST',
 @BaseUrl NVARCHAR(1000)=NULL,@CredentialSecretRef NVARCHAR(400)=NULL,@Description NVARCHAR(700)=NULL,
 @DataSourceId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50316,'Platform Admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50317,'Invalid data source code.',1;
 IF @Kind NOT IN('REST','SOAP','DATABASE','CUSTOM') THROW 50318,'Invalid data source type.',1;
 /* URL hosts/SSRF protection must be validated and allowlisted by the backend, not SQL. */
 BEGIN TRAN;
 IF @DataSourceId IS NULL BEGIN
  SET @DataSourceId=NEXT VALUE FOR integration.Seq_DataSources;
  INSERT integration.DataSources(DataSourceId,Code,Name,Kind,BaseUrl,CredentialSecretRef,Description)
  VALUES(@DataSourceId,@Code,@Name,@Kind,@BaseUrl,NULLIF(@CredentialSecretRef,'__CLEAR__'),@Description);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM integration.DataSources WHERE DataSourceId=@DataSourceId) BEGIN ROLLBACK; THROW 50319,'Data source not found.',1; END;
  UPDATE integration.DataSources SET Name=@Name,Kind=@Kind,BaseUrl=@BaseUrl,
  CredentialSecretRef=CASE WHEN @CredentialSecretRef='__CLEAR__' THEN NULL ELSE COALESCE(@CredentialSecretRef,CredentialSecretRef) END,Description=@Description
  WHERE DataSourceId=@DataSourceId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DataSource',@EntityId=@DataSourceId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_SaveOperation
 @ActorUserId BIGINT,@DataSourceId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,
 @HttpMethod VARCHAR(12),@UrlPath NVARCHAR(1000),@RequestTemplateJson NVARCHAR(MAX)=NULL,
 @ResponseMapJson NVARCHAR(MAX)=NULL,@HeaderTemplateJson NVARCHAR(MAX)=NULL,
 @RequestParamsJson NVARCHAR(MAX)=NULL,@OperationId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50320,'Platform Admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50321,'Invalid operation code.',1;
 IF NOT EXISTS(SELECT 1 FROM integration.DataSources WHERE DataSourceId=@DataSourceId AND IsActive=1) THROW 50322,'Data source missing or inactive.',1;
 IF @HttpMethod NOT IN('GET','POST','PUT','PATCH','DELETE') THROW 50323,'Invalid HTTP method.',1;
 IF @RequestTemplateJson IS NOT NULL AND ISJSON(@RequestTemplateJson)<>1 THROW 50324,'Invalid request JSON.',1;
 IF @ResponseMapJson IS NOT NULL AND ISJSON(@ResponseMapJson)<>1 THROW 50325,'Invalid response mapping JSON.',1;
 IF @HeaderTemplateJson IS NOT NULL AND ISJSON(@HeaderTemplateJson)<>1 THROW 50326,'Invalid header template JSON.',1;
 IF @RequestParamsJson IS NOT NULL AND (ISJSON(@RequestParamsJson)<>1 OR LEFT(LTRIM(@RequestParamsJson),1)<>'[') THROW 50328,'Invalid request parameter definitions.',1;
 BEGIN TRAN;
 IF @OperationId IS NULL BEGIN
  SET @OperationId=NEXT VALUE FOR integration.Seq_Operations;
  INSERT integration.Operations(OperationId,DataSourceId,Code,Name,HttpMethod,UrlPath,RequestTemplateJson,ResponseMapJson,HeaderTemplateJson,RequestParamsJson)
  VALUES(@OperationId,@DataSourceId,@Code,@Name,@HttpMethod,@UrlPath,@RequestTemplateJson,@ResponseMapJson,@HeaderTemplateJson,@RequestParamsJson);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM integration.Operations WHERE OperationId=@OperationId AND DataSourceId=@DataSourceId)
  BEGIN ROLLBACK; THROW 50327,'Operation not found under data source.',1; END;
  UPDATE integration.Operations SET Name=@Name,HttpMethod=@HttpMethod,UrlPath=@UrlPath,
  RequestTemplateJson=@RequestTemplateJson,ResponseMapJson=@ResponseMapJson,HeaderTemplateJson=@HeaderTemplateJson,RequestParamsJson=@RequestParamsJson
  WHERE OperationId=@OperationId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DataSourceOperation',@EntityId=@OperationId,@ActionCode='Save';
 COMMIT;
END;
GO
IF COL_LENGTH('integration.Operations','RequestParamsJson') IS NULL
 THROW 50390,'Request parameter migration failed.',1;
PRINT 'PASS: integration request parameter schema installed.';
GO
