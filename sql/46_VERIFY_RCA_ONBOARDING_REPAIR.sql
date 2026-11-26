USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'work.usp_SubmitRca',N'P') IS NULL OR CHARINDEX(N'COLLATE Latin1_General_BIN2',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'work.usp_SubmitRca')),N'')) = 0 THROW 50927,'RCA repair missing.',1;
IF OBJECT_ID(N'work.usp_CreateCase',N'P') IS NULL OR CHARINDEX(N'JSON_QUERY(ConfigJson,''$.options'') AS OptionsJson',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase')),N'')) = 0 THROW 50928,'RCA snapshot options repair missing.',1;
IF OBJECT_ID(N'core.usp_OnboardProject',N'P') IS NULL OR CHARINDEX(N'InitialTeamCount',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'core.usp_OnboardProject')),N'')) = 0 THROW 50929,'Onboarding repair missing.',1;
IF OBJECT_ID(N'auth.usp_SaveCustomRole',N'P') IS NULL OR CHARINDEX(N'COLLATE DATABASE_DEFAULT',COALESCE(OBJECT_DEFINITION(OBJECT_ID(N'auth.usp_SaveCustomRole')),N'')) = 0 THROW 50930,'Role repair missing.',1;
SELECT p.ProjectId,p.Name,p.TemplateCode,p.Status,
 (SELECT COUNT(*) FROM teams.Teams t WHERE t.ProjectId=p.ProjectId AND t.IsActive=1) AS ActiveTeams,
 (SELECT COUNT(*) FROM flow.Definitions w WHERE w.ProjectId=p.ProjectId AND w.IsActive=1) AS ActiveWorkflows
FROM core.Projects p ORDER BY p.ProjectId DESC;
PRINT 'Repair source checks passed. Test project creation and RCA closure using the API in UAT.';
GO
