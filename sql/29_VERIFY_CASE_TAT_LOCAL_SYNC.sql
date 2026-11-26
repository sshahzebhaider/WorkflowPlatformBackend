/* Read-only verification of migration 28, existing case calendar behavior and local directory rights. */
USE [WorkflowPlatformV2];
GO
SELECT 'Case TAT breach table' AS CheckName,CASE WHEN OBJECT_ID(N'work.CaseTatBreaches',N'U') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END AS Result
UNION ALL SELECT 'Case TAT worker procedure',CASE WHEN OBJECT_ID(N'work.usp_RecordCaseTatBreaches',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'Local directory reconciliation',CASE WHEN OBJECT_ID(N'auth.usp_ReconcileLocalDirectory',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'RCA enabled column',CASE WHEN COL_LENGTH(N'core.Projects',N'RcaEnabled') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'RCA description column',CASE WHEN COL_LENGTH(N'core.RcaTemplateFields',N'Description') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'RCA configuration procedure',CASE WHEN OBJECT_ID(N'core.usp_SaveProjectRcaConfig',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'Business calendar TAT calculator',CASE WHEN OBJECT_ID(N'calendar.usp_CalculateBusinessDueAt',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END;
GO
SELECT TOP (30) c.CaseId,c.ProjectId,c.ReferenceNo,c.CreatedAt,c.DueAt,c.Status,
 CASE WHEN b.CaseId IS NOT NULL THEN 'Breached' WHEN c.ClosedAt IS NOT NULL THEN 'Closed'
      WHEN c.DueAt IS NULL THEN 'No TAT' WHEN c.DueAt<SYSUTCDATETIME() THEN 'Overdue - awaiting worker'
      ELSE 'On schedule' END AS TatStatus
FROM work.Cases c LEFT JOIN work.CaseTatBreaches b ON b.CaseId=c.CaseId
ORDER BY c.CaseId DESC;
GO
SELECT TOP (30) u.UserId,u.UserName,u.DirectoryStatus,u.IsActive,
 (SELECT COUNT(*) FROM auth.RoleAssignments ra WHERE ra.UserId=u.UserId AND ra.IsActive=1) AS ActiveRoles,
 (SELECT COUNT(*) FROM teams.Members m WHERE m.UserId=u.UserId AND m.IsActive=1) AS ActiveTeamMemberships
FROM auth.Users u WHERE u.DirectoryStatus='Resigned' ORDER BY u.UserId;
GO

-- Inspect database-user EXECUTE permission if this user exists.
IF USER_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
    EXECUTE AS USER = 'workflow_app_v2';
    SELECT 'workflow_app_v2 RCA save permission' AS CheckName,
           CASE WHEN HAS_PERMS_BY_NAME('core.usp_SaveProjectRcaConfig', 'OBJECT', 'EXECUTE')=1
                    THEN 'PASS' ELSE 'DENIED' END AS Result;
    REVERT;
END;
GO
