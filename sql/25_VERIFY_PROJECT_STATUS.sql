/* READ ONLY. Execute after migration 24. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
DECLARE @Failures TABLE (Issue NVARCHAR(250));
IF OBJECT_ID(N'core.ProjectStatusHistory',N'U') IS NULL INSERT @Failures VALUES('Missing status history table');
IF OBJECT_ID(N'core.usp_ChangeProjectStatus',N'P') IS NULL INSERT @Failures VALUES('Missing status update procedure');
IF OBJECT_ID(N'core.usp_OnboardProject',N'P') IS NULL INSERT @Failures VALUES('Missing onboarding procedure');
IF OBJECT_DEFINITION(OBJECT_ID(N'core.usp_OnboardProject')) NOT LIKE '%''UAT'',@RcaRequired%'
    INSERT @Failures VALUES('New project onboarding does not set UAT');
IF OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase')) NOT LIKE '%p.Status IN (''UAT'',''Live'')%'
    INSERT @Failures VALUES('Case creation still blocks UAT projects');
IF EXISTS(SELECT 1 FROM @Failures)
BEGIN
    SELECT 'FAIL' AS Result, Issue FROM @Failures;
    THROW 50890, 'Project lifecycle verification failed.', 1;
END;
SELECT 'PASS' AS Result, 'UAT/Live project status lifecycle installed' AS Details;
SELECT p.ProjectId,p.Name,p.Status,p.UpdatedAt,COUNT(h.StatusChangeId) AS HistoryEntries
FROM core.Projects p LEFT JOIN core.ProjectStatusHistory h ON h.ProjectId=p.ProjectId
GROUP BY p.ProjectId,p.Name,p.Status,p.UpdatedAt ORDER BY p.ProjectId;
GO
