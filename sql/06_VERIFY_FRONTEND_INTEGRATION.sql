/* Safe to run repeatedly: inspection only, no data changes. */
USE [WorkflowPlatformV2];
GO
SELECT p.ProcedureName,
       CASE WHEN OBJECT_ID(p.ProcedureName,'P') IS NOT NULL THEN 'PRESENT' ELSE 'MISSING' END AS Status
FROM (VALUES
 (N'core.usp_SaveCaseTypeDraft'),
 (N'teams.usp_UpdateTeamDetails'),
 (N'calendar.usp_UpdateCalendarDetails'),
 (N'calendar.usp_ReplaceSchedule'),
 (N'forms.usp_Publish'),
 (N'flow.usp_Publish'),
 (N'core.usp_PublishCaseType'),
 (N'work.usp_CreateCase'),
 (N'work.usp_GetCaseDetails'),
 (N'work.usp_CompleteTask'),
 (N'work.usp_ForceIntimation'),
 (N'work.usp_ReindexCaseFields')
) AS p(ProcedureName)
ORDER BY ProcedureName;
SELECT COUNT(*) AS UserTableCount FROM sys.tables WHERE is_ms_shipped=0;
SELECT COUNT(*) AS UserIndexCount FROM sys.indexes i JOIN sys.tables t ON t.object_id=i.object_id
 WHERE t.is_ms_shipped=0 AND i.is_hypothetical=0 AND i.index_id>0;
GO
