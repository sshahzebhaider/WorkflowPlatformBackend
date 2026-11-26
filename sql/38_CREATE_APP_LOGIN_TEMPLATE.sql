/* Run ONCE in SSMS as SQL Server admin. Do not store this file with a real password. */
USE [master];
GO
DECLARE @LoginPassword NVARCHAR(128)=N''; -- Enter a randomly generated password temporarily.
IF LEN(@LoginPassword)<20
 THROW 50995,'Supply a strong 20+ character password before creating workflow_app_v2.',1;
IF SUSER_ID(N'workflow_app_v2') IS NOT NULL
 THROW 50996,'Login already exists. Do not overwrite an existing credential.',1;
DECLARE @sql NVARCHAR(MAX) = N'CREATE LOGIN [workflow_app_v2] WITH PASSWORD = '
    + QUOTENAME(@LoginPassword,'''') + N', CHECK_POLICY = ON;';
EXEC sys.sp_executesql @sql;
GO
-- Run 03_APP_PERMISSIONS.sql AFTER this, using a SQL administrator.
