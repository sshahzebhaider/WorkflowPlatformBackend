-- Applies to existing WorkflowPlatformV2; run after 13_DYNAMIC_SOURCE_APPROVAL.sql.
USE [WorkflowPlatformV2];
GO
CREATE OR ALTER PROCEDURE auth.usp_SetDirectoryStatus
 @ActorUserId BIGINT,@UserId BIGINT,@DirectoryStatus VARCHAR(20)
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,NULL)<>1 THROW 50911,'Platform Admin required.',1;
 IF @DirectoryStatus NOT IN ('Active','OnLeave','Disabled','Resigned')
  THROW 50912,'Invalid directory status.',1;
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@UserId)
  THROW 50913,'User does not exist.',1;
 IF @UserId=@ActorUserId AND @DirectoryStatus IN('Resigned','Disabled')
  THROW 50914,'You cannot deactivate your own admin account.',1;
 IF @DirectoryStatus='Resigned'
 BEGIN
  EXEC teams.usp_ApplyResignedUser @ActorUserId=@ActorUserId,@UserId=@UserId;
  RETURN;
 END;
 BEGIN TRAN;
 UPDATE auth.Users SET DirectoryStatus=@DirectoryStatus,
  IsActive=CASE WHEN @DirectoryStatus='Disabled' THEN 0 ELSE 1 END,
  UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 IF @DirectoryStatus='Disabled'
 BEGIN
  UPDATE teams.Members SET IsActive=0 WHERE UserId=@UserId;
  UPDATE auth.RoleAssignments SET IsActive=0 WHERE UserId=@UserId;
  UPDATE teams.Absences SET IsActive=0 WHERE UserId=@UserId OR BackupUserId=@UserId;
  UPDATE work.Tasks SET AssignedTo=NULL,DelegatedFor=NULL,RoutingStage='Unassigned'
   WHERE Status='Open' AND (AssignedTo=@UserId OR DelegatedFor=@UserId);
 END;
 DECLARE @DirectoryAudit NVARCHAR(MAX)=CASE @DirectoryStatus
   WHEN 'Resigned' THEN N'{"status":"Resigned"}'
   WHEN 'Disabled' THEN N'{"status":"Disabled"}'
   WHEN 'OnLeave' THEN N'{"status":"OnLeave"}'
   ELSE N'{"status":"Active"}' END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DirectoryUser',
  @EntityId=@UserId,@ActionCode='DirectoryStatusChanged',@DetailsJson=@DirectoryAudit;
 COMMIT;
END;
GO
IF USER_ID('workflow_app_v2') IS NOT NULL
 GRANT EXECUTE ON OBJECT::auth.usp_SetDirectoryStatus TO [workflow_app_v2];
GO
