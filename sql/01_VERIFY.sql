/* READ-ONLY verification. Run in SSMS after 00_CREATE_ALL.sql. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
SELECT DB_NAME() AS DatabaseName,
       SERVERPROPERTY('ProductVersion') AS ServerVersion,
       SYSDATETIMEOFFSET() AS VerifiedAt;

SELECT s.name AS SchemaName, COUNT(*) AS Tables
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE t.is_ms_shipped=0 GROUP BY s.name ORDER BY s.name;

SELECT s.name AS SchemaName, COUNT(*) AS StoredProcedures
FROM sys.procedures p JOIN sys.schemas s ON s.schema_id=p.schema_id
WHERE p.is_ms_shipped=0 GROUP BY s.name ORDER BY s.name;

SELECT COUNT(*) AS UserTables FROM sys.tables WHERE is_ms_shipped=0;
SELECT COUNT(*) AS StoredProcedures FROM sys.procedures WHERE is_ms_shipped=0;
SELECT COUNT(*) AS Functions FROM sys.objects WHERE type IN('FN','IF','TF') AND is_ms_shipped=0;
SELECT COUNT(*) AS NonConstraintIndexes
FROM sys.indexes i JOIN sys.tables t ON i.object_id=t.object_id
WHERE t.is_ms_shipped=0 AND i.index_id>0 AND i.is_primary_key=0 AND i.is_unique_constraint=0;

SELECT r.Code, r.Name, r.Scope, COUNT(rp.PermissionCode) AS PermissionCount
FROM auth.Roles r LEFT JOIN auth.RolePermissions rp ON rp.RoleId=r.RoleId
GROUP BY r.Code,r.Name,r.Scope ORDER BY r.Code;

SELECT p.PermissionGroup, COUNT(*) AS AvailablePermissions
FROM auth.Permissions p GROUP BY p.PermissionGroup ORDER BY p.PermissionGroup;

EXEC core.usp_DatabaseHealth;

/* Required objects for the active Chunk 6 UI. Missing ones are reported. */
DECLARE @Required TABLE(ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT @Required VALUES
 ('auth.Users','U'),('auth.Roles','U'),('auth.RoleAssignments','U'),
 ('core.Projects','U'),('calendar.Calendars','U'),('calendar.Holidays','U'),
 ('lookup.Lists','U'),('lookup.Items','U'),('forms.FieldLibrary','U'),
 ('forms.Versions','U'),('flow.Versions','U'),('flow.Nodes','U'),('flow.Edges','U'),
 ('work.Cases','U'),('work.Tasks','U'),('work.CaseEvents','U'),
 ('teams.Teams','U'),('teams.Members','U'),('teams.Absences','U'),
 ('core.RcaTemplates','U'),('core.ProjectRcaFields','U'),('files.Documents','U'),
 ('integration.DataSources','U'),('integration.Operations','U'),
 ('notify.Outbox','U'),('work.ForceIntimations','U'),
 ('work.usp_CreateCase','P'),('work.usp_CompleteTask','P'),
 ('work.usp_ForwardTask','P'),('work.usp_ForceIntimation','P'),
 ('forms.usp_Publish','P'),('flow.usp_Publish','P'),
 ('core.usp_OnboardProject','P');
SELECT ObjectName AS MissingObject
FROM @Required WHERE OBJECT_ID(ObjectName,ObjectType) IS NULL ORDER BY ObjectName;

PRINT 'If MissingObject has zero rows, required tables/procedures exist.';
GO
