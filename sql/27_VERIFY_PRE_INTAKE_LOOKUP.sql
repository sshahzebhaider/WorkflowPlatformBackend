USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
SELECT 'Pre-intake lookup table' AS CheckName,
  IIF(OBJECT_ID(N'integration.LodgementPreviews',N'U') IS NOT NULL,'PASS','FAIL') AS Result
UNION ALL SELECT 'Save preview procedure',
  IIF(OBJECT_ID(N'integration.usp_SaveLodgementPreview',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'Atomic case + preview procedure',
  IIF(OBJECT_ID(N'integration.usp_CreateCaseFromPreview',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'Expiry cleanup procedure',
  IIF(OBJECT_ID(N'integration.usp_PurgeLodgementPreviews',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'CreateCase supports mapped integration result',
  IIF(OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase')) LIKE '%@LodgementMappedJson%','PASS','FAIL');
SELECT name AS ParamName,TYPE_NAME(user_type_id) AS DataType
FROM sys.parameters WHERE object_id=OBJECT_ID(N'integration.usp_CreateCaseFromPreview')
ORDER BY parameter_id;
GO

IF OBJECT_ID(N'integration.LodgementPreviews',N'U') IS NULL OR
   OBJECT_ID(N'integration.usp_SaveLodgementPreview',N'P') IS NULL OR
   OBJECT_ID(N'integration.usp_CreateCaseFromPreview',N'P') IS NULL OR
   OBJECT_ID(N'integration.usp_PurgeLodgementPreviews',N'P') IS NULL OR
   OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase')) NOT LIKE '%@LodgementMappedJson%'
    THROW 50610,'Pre-intake data lookup installation verification failed.',1;
PRINT 'PASS: all pre-intake lookup migration objects verified.';
GO
