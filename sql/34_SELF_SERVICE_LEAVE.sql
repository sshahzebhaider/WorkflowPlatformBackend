-- 34: Self-service leave only. Existing leave and case history is retained.
-- SQL Server 2022+/2025; no table changes. Run once on WorkflowPlatformV2.
USE [WorkflowPlatformV2];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE teams.usp_SetLeaveBackup
 @ActorUserId BIGINT,@ProjectId BIGINT,@TeamId BIGINT,
 @UserId BIGINT,@BackupUserId BIGINT,@StartDate DATE,@EndDate DATE
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @StartDate>@EndDate THROW 50056,'Leave dates are invalid.',1;
 IF @UserId=@BackupUserId THROW 50057,'Backup cannot be the same user.',1;
 -- Strict self-service: no manager, Team Lead, Project Admin or Platform Admin may submit another employee's leave.
 IF @ActorUserId IS NULL OR @UserId IS NULL OR @ActorUserId<>@UserId
  THROW 50058,'Only the employee can submit their own leave and backup.',1;
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@ActorUserId AND IsActive=1 AND DirectoryStatus NOT IN('Resigned','Disabled'))
  THROW 50058,'Inactive directory users cannot submit leave.',1;
 IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@TeamId AND ProjectId=@ProjectId) THROW 50059,'Team not found.',1;
 IF NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND UserId=@UserId AND IsActive=1)
 OR NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND UserId=@BackupUserId AND IsActive=1)
  THROW 50060,'Both users must be active team members.',1;
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@BackupUserId AND IsActive=1 AND DirectoryStatus='Active')
  THROW 50061,'Backup directory user is not available.',1;
 IF EXISTS(SELECT 1 FROM teams.Absences WHERE ProjectId=@ProjectId AND TeamId=@TeamId AND UserId=@BackupUserId
 AND IsActive=1 AND StartDate<=@EndDate AND EndDate>=@StartDate) THROW 50062,'The backup is on leave.',1;
 BEGIN TRAN;
 UPDATE teams.Absences SET IsActive=0 WHERE ProjectId=@ProjectId AND TeamId=@TeamId AND UserId=@UserId AND IsActive=1
 AND StartDate<=@EndDate AND EndDate>=@StartDate;
 INSERT teams.Absences(ProjectId,TeamId,UserId,BackupUserId,StartDate,EndDate)
 VALUES(@ProjectId,@TeamId,@UserId,@BackupUserId,@StartDate,@EndDate);
 UPDATE work.Tasks SET AssignedTo=@BackupUserId,DelegatedFor=@UserId,AssignedAt=SYSUTCDATETIME()
 WHERE TeamId=@TeamId AND AssignedTo=@UserId AND Status='Open' AND @StartDate<=CONVERT(DATE,SYSUTCDATETIME()) AND @EndDate>=CONVERT(DATE,SYSUTCDATETIME());
 INSERT work.TaskHandoffs(TaskId,FromUserId,ToUserId,RoutingStage,ActorUserId,Reason)
 SELECT TaskId,@UserId,@BackupUserId,RoutingStage,@ActorUserId,N'Leave backup assignment'
 FROM work.Tasks WHERE TeamId=@TeamId AND DelegatedFor=@UserId AND AssignedTo=@BackupUserId AND Status='Open';
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Absence',@EntityId=@UserId,@ActionCode='BackupConfigured';
 COMMIT;
END;
GO
PRINT 'Migration 34 compiled: only the employee may submit leave/backup.';
GO
