/* Read-only numeric schema verification. SQL Server 2019+. Run as administrator. */
USE WorkflowPlatformV2;
GO
SET NOCOUNT ON;
SELECT DB_NAME() AS DatabaseName;
SELECT name,TYPE_NAME(system_type_id) AS SqlType
FROM sys.columns WHERE object_id=OBJECT_ID(N'auth.Users') AND name=N'UserId';
SELECT name AS SequenceName,SCHEMA_NAME(schema_id) AS SchemaName,current_value
FROM sys.sequences ORDER BY SchemaName,SequenceName;
IF EXISTS (
  SELECT 1 FROM sys.columns c
  JOIN sys.tables t ON t.object_id=c.object_id
  WHERE c.system_type_id=TYPE_ID(N'uniqueidentifier') AND t.is_ms_shipped=0
) THROW 53001,'Persistent relational identifier migration is incomplete: found a uniqueidentifier column.',1;
IF (SELECT COUNT(*) FROM sys.sequences WHERE is_ms_shipped=0)<>38
  THROW 53002,'Expected exactly 38 numeric ID sequences.',1;
IF NOT EXISTS (
 SELECT 1 FROM sys.default_constraints d
 JOIN sys.columns c ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
 WHERE d.parent_object_id=OBJECT_ID(N'auth.Users') AND c.name=N'UserId'
 AND d.definition LIKE '%NEXT VALUE FOR%'
) THROW 53003,'UserId does not auto-increment from the database sequence.',1;
SELECT COUNT(*) AS UserTables FROM sys.tables WHERE is_ms_shipped=0;
SELECT COUNT(*) AS Procedures FROM sys.procedures WHERE is_ms_shipped=0;
PRINT 'Numeric ID schema checks passed.';
GO
