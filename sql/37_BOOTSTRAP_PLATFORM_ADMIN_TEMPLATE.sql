/* Run ONCE as a trusted SQL administrator after application schema install.
   Replace the username, display name, and email before executing.
   The first admin uses the secured bootstrap procedure; do NOT grant db_owner.
   This is not part of the automated fresh installer.
*/
USE [WorkflowPlatformV2];
GO
DECLARE @BootstrapUsername NVARCHAR(150)=N'REPLACE_WITH_ADMIN_USERNAME';
DECLARE @BootstrapDisplayName NVARCHAR(200)=N'REPLACE_WITH_ADMIN_DISPLAY_NAME';
DECLARE @BootstrapEmail NVARCHAR(320)=N'REPLACE_WITH_REAL_EMAIL';
IF @BootstrapUsername LIKE N'REPLACE_%' OR @BootstrapDisplayName LIKE N'REPLACE_%' OR @BootstrapEmail LIKE N'REPLACE_%'
 THROW 50997,'Edit admin identity placeholders before bootstrap.',1;
-- For production JWT/SSO, set the exact immutable directory oid/sub expected by the configured authority.
DECLARE @BootstrapExternalDirectoryId NVARCHAR(200)=NULL;
DECLARE @UserId BIGINT;
SET XACT_ABORT ON;
BEGIN TRAN;
IF EXISTS(SELECT 1 FROM auth.RoleAssignments a WITH(UPDLOCK,HOLDLOCK) JOIN auth.Roles r ON r.RoleId=a.RoleId WHERE r.Code='platform_admin' AND a.IsActive=1)
BEGIN ROLLBACK; THROW 50996,'Platform Admin already exists; use the authenticated user management screen for additional admins.',1; END;
EXEC auth.usp_UpsertDirectoryUser
 @UserName=@BootstrapUsername,
 @DisplayName=@BootstrapDisplayName,
 @Email=@BootstrapEmail,
 @Mobile=NULL,
 @ExternalDirectoryId=@BootstrapExternalDirectoryId,
 @DirectoryStatus='Active',
 @UserId=@UserId OUTPUT;
EXEC auth.usp_BootstrapPlatformAdmin @UserId=@UserId;
COMMIT;
SELECT u.UserId,u.UserName,u.DisplayName,u.DirectoryStatus,r.Code AS RoleCode
FROM auth.Users u
JOIN auth.RoleAssignments a ON a.UserId=u.UserId AND a.IsActive=1
JOIN auth.Roles r ON r.RoleId=a.RoleId
WHERE u.UserId=@UserId AND r.Code='platform_admin';
GO
