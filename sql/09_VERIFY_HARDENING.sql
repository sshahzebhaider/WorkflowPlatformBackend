/* Read-only production hardening verification; run in SSMS as a database administrator.
   Requires 00_CREATE_ALL.sql to have been applied. No data is changed. */
USE WorkflowPlatformV2;
GO
SELECT 'Worker queue claim' AS [Check],IIF(OBJECT_ID(N'integration.usp_ClaimWorkflowExecutions',N'P') IS NOT NULL,'PASS','FAIL') AS Result
UNION ALL SELECT 'System-node resume',IIF(OBJECT_ID(N'work.usp_ResumeSystemNode',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'File scan result',IIF(OBJECT_ID(N'files.usp_RecordScanResult',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'Case type publisher',IIF(OBJECT_ID(N'core.usp_PublishCaseType',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'Activate-node installed definition',IIF(EXISTS(SELECT 1 FROM sys.sql_modules WHERE object_id=OBJECT_ID(N'work.usp_ActivateNode',N'P') AND definition LIKE N'%DECLARE @DecisionNextDepth INT = @Depth + 1%'),'PASS','FAIL')
UNION ALL SELECT 'Case create',IIF(OBJECT_ID(N'work.usp_CreateCase',N'P') IS NOT NULL,'PASS','FAIL')
UNION ALL SELECT 'Integration resumed flag',IIF(COL_LENGTH(N'integration.Executions',N'ResumedAt') IS NOT NULL,'PASS','FAIL');
SELECT Status,COUNT(*) AS Executions FROM integration.Executions GROUP BY Status;
SELECT ScanStatus,COUNT(*) AS Documents FROM files.Documents GROUP BY ScanStatus;
SELECT p.ProjectId,p.Name AS ProjectName,r.Code AS RoleCode,r.Name AS RoleName,
 u.UserName,a.IsActive FROM auth.RoleAssignments a
 JOIN auth.Users u ON u.UserId=a.UserId
 JOIN auth.Roles r ON r.RoleId=a.RoleId
 LEFT JOIN core.Projects p ON p.ProjectId=a.ProjectId
 WHERE r.Scope IN('Project','Team') ORDER BY u.UserName,p.Name,r.Name;
GO
