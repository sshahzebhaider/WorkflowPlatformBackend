/* Read-only final fresh installation check. SQLCMD -b exits nonzero on THROW. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
DECLARE @Required TABLE (ObjectName NVARCHAR(256), ObjectType CHAR(2));
INSERT INTO @Required VALUES
 (N'auth.Users','U'), (N'core.Projects','U'),(N'core.CaseTypes','U'),
 (N'core.CaseTypeVersions','U'),(N'core.ProjectStatusHistory','U'),
 (N'integration.DataSources','U'),(N'integration.Operations','U'),
 (N'integration.DataSourceApprovals','U'),(N'lookup.Lists','U'),
 (N'lookup.Items','U'),(N'lookup.ItemParents','U'),
 (N'work.Cases','U'),(N'work.Tasks','U'),(N'work.CaseTatBreaches','U'),
 (N'files.StagedDocuments','U'),(N'audit.Events','U'),
 (N'work.usp_CreateCase','P'),(N'work.usp_ActivateNode','P'),
 (N'core.usp_ChangeProjectStatus','P'),(N'core.usp_OnboardProject','P'),
 (N'work.usp_RecordCaseTatBreaches','P'),
 (N'work.usp_RebalanceTeamTasks','P'),
 (N'lookup.usp_CreateListWithItems','P'),
 (N'auth.usp_ReconcileLocalDirectory','P'),
 (N'integration.usp_CreateCaseFromPreview','P'),
 (N'teams.usp_SetLeaveBackup','P');
SELECT ObjectName, CASE WHEN OBJECT_ID(ObjectName,ObjectType) IS NOT NULL
 THEN 'PASS' ELSE 'MISSING' END AS Result FROM @Required ORDER BY ObjectName;
IF EXISTS(SELECT 1 FROM @Required WHERE OBJECT_ID(ObjectName,ObjectType) IS NULL)
 THROW 50990,'Fresh installation failed: missing required schema objects.',1;
IF COL_LENGTH(N'core.Projects',N'RcaEnabled') IS NULL
 OR COL_LENGTH(N'integration.Operations',N'RequestParamsJson') IS NULL
 OR COL_LENGTH(N'core.CaseTypeVersions',N'PublishedConfigJson') IS NULL
 THROW 50991,'Fresh installation failed: missing required columns.',1;
IF CHARINDEX(N'p.Status IN (''UAT'',''Live'')',
    OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase',N'P'))) = 0
 THROW 50992,'Fresh installation failed: case creation requires UAT and Live support.',1;
IF NOT EXISTS(SELECT 1 FROM sys.default_constraints d JOIN sys.columns c
  ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
  WHERE d.parent_object_id=OBJECT_ID(N'core.Projects') AND c.name='Status'
  AND d.definition LIKE '%UAT%')
 THROW 50993,'Fresh installation failed: new project default must be UAT.',1;
PRINT 'PASS: WorkflowPlatformV2 schema and required procedures exist.';
GO
