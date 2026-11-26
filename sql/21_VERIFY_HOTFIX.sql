-- Run in SSMS AFTER applying migrations 13..20 to WorkflowPlatformV2.
-- Read-only verification. Fail loudly if a required object or procedure is missing.
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
DECLARE @Failures TABLE(CheckName NVARCHAR(100), Details NVARCHAR(250));
IF OBJECT_ID(N'integration.DataSourceApprovals',N'U') IS NULL INSERT @Failures VALUES(N'Host approvals',N'integration.DataSourceApprovals missing');
IF OBJECT_ID(N'integration.usp_SetDataSourceApproval',N'P') IS NULL INSERT @Failures VALUES(N'Host approval operation',N'Approval procedure missing');
IF OBJECT_ID(N'auth.usp_SetDirectoryStatus',N'P') IS NULL INSERT @Failures VALUES(N'Directory management',N'Directory status procedure missing');
IF COL_LENGTH('auth.Users','DirectoryStatus') IS NULL INSERT @Failures VALUES(N'Directory status',N'auth.Users missing DirectoryStatus');
IF OBJECT_ID(N'files.StagedDocuments',N'U') IS NULL INSERT @Failures VALUES(N'Staged attachments',N'Staging table missing');
IF OBJECT_ID(N'work.ParallelJoins',N'U') IS NULL INSERT @Failures VALUES(N'Parallel joins',N'Parallel joins table missing');
IF OBJECT_ID(N'work.ParallelArrivals',N'U') IS NULL INSERT @Failures VALUES(N'Parallel arrivals',N'Parallel arrivals table missing');
IF OBJECT_ID(N'work.SystemNotifications',N'U') IS NULL INSERT @Failures VALUES(N'Notification nodes',N'Notification continuation table missing');
IF OBJECT_ID(N'work.SlaEscalations',N'U') IS NULL INSERT @Failures VALUES(N'SLA escalations',N'SLA escalation table missing');
IF OBJECT_ID(N'work.usp_EscalateOverdueTasks',N'P') IS NULL INSERT @Failures VALUES(N'SLA worker',N'SLA procedure missing');
IF OBJECT_ID(N'notify.usp_QueueConfiguredEvent',N'P') IS NULL INSERT @Failures VALUES(N'Notification rules',N'Template event procedure missing');
IF OBJECT_ID(N'notify.usp_RecordDelivery',N'P') IS NULL INSERT @Failures VALUES(N'Notification delivery',N'Provider status procedure missing');
IF OBJECT_ID(N'work.usp_CompleteTask',N'P') IS NULL INSERT @Failures VALUES(N'Case actions',N'Task completion procedure missing');
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N'work.usp_CompleteTask') AND name=N'@Comment')
 INSERT @Failures VALUES(N'Action comments',N'work.usp_CompleteTask missing @Comment');
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N'core.usp_OnboardProject') AND name=N'@TeamsJson')
 INSERT @Failures VALUES(N'Initial teams',N'core.usp_OnboardProject missing @TeamsJson');
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id=OBJECT_ID(N'work.usp_ActivateNode') AND name=N'@SourceNodeId')
 INSERT @Failures VALUES(N'Parallel routing',N'work.usp_ActivateNode missing @SourceNodeId');
IF EXISTS (SELECT 1 FROM @Failures)
BEGIN
 SELECT 'FAIL' AS Status,CheckName,Details FROM @Failures;
 THROW 50501,'Hotfix verification failed; do not deploy application until migrations have been repaired.',1;
END;
SELECT 'PASS' AS Status,N'All required hotfix tables, procedures and parameters exist' AS Details;
GO
-- Confirm application identity in its own security context. Requires EXECUTE AS permission.
SELECT DB_NAME() AS DatabaseName,COUNT(*) AS StagedFiles FROM files.StagedDocuments;
SELECT COUNT(*) AS ApprovedHostCount FROM integration.DataSourceApprovals WHERE IsApproved=1;
