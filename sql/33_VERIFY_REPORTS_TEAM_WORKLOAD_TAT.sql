/* SQL 33: read-only verification of Report Builder and SQL 32. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
SELECT Name, CASE WHEN Found=1 THEN 'PASS' ELSE 'MISSING' END AS Result
FROM (VALUES
 (N'Report definitions table',CASE WHEN OBJECT_ID(N'reports.Definitions',N'U') IS NOT NULL THEN 1 ELSE 0 END),
 (N'Save report definition procedure',CASE WHEN OBJECT_ID(N'reports.usp_SaveDefinition',N'P') IS NOT NULL THEN 1 ELSE 0 END),
 (N'Rebalance team tasks procedure',CASE WHEN OBJECT_ID(N'work.usp_RebalanceTeamTasks',N'P') IS NOT NULL THEN 1 ELSE 0 END),
 (N'Elapsed-hours TAT trigger',CASE WHEN OBJECT_ID(N'work.trg_Cases_ElapsedTatDueAt',N'TR') IS NOT NULL THEN 1 ELSE 0 END),
 (N'Case Type published config',CASE WHEN COL_LENGTH(N'core.CaseTypeVersions',N'PublishedConfigJson') IS NOT NULL THEN 1 ELSE 0 END),
 (N'Case due date',CASE WHEN COL_LENGTH(N'work.Cases',N'DueAt') IS NOT NULL THEN 1 ELSE 0 END)
) AS checks(Name,Found);
GO
IF DATABASE_PRINCIPAL_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
 EXECUTE AS USER='workflow_app_v2';
 SELECT HAS_PERMS_BY_NAME(N'work.usp_RebalanceTeamTasks',N'OBJECT',N'EXECUTE') AS CanRebalanceTasks,
   HAS_PERMS_BY_NAME(N'reports.Definitions',N'OBJECT',N'SELECT') AS CanReadReportDefinitions,
   HAS_PERMS_BY_NAME(N'reports.usp_SaveDefinition',N'OBJECT',N'EXECUTE') AS CanSaveReportDefinitions;
 REVERT;
END;
GO
