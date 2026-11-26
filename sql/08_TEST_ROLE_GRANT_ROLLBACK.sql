/* SAFE / NON-PERSISTENT: verifies Platform Admin role assignment on the new numeric schema.
   Run in SSMS as SQL administrator, after bootstrapping one real active Platform Admin.
   Changes are wrapped in a transaction and rolled back. Sequence numbers are still consumed. */
USE WorkflowPlatformV2;
GO
SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @Actor BIGINT,@Target BIGINT;
 SELECT TOP(1) @Actor=a.UserId
 FROM auth.RoleAssignments a
 JOIN auth.Roles r ON r.RoleId=a.RoleId AND r.Code='platform_admin'
 JOIN auth.Users u ON u.UserId=a.UserId AND u.IsActive=1
 WHERE a.IsActive=1 AND a.ProjectId IS NULL
 ORDER BY a.AssignedAt;
 IF @Actor IS NULL THROW 53010,'Bootstrap a Platform Admin before testing the role grant.',1;
 IF auth.fn_HasPermission(@Actor,NULL,'roles.assign')<>1
    THROW 53011,'The current Platform Admin lacks roles.assign.',1;
 DECLARE @Name NVARCHAR(150)=CONCAT(N'granttest_',CONVERT(VARCHAR(8),CRYPT_GEN_RANDOM(4),2));
 EXEC auth.usp_UpsertDirectoryUser @UserName=@Name,@DisplayName=N'Role Assignment Smoke Test',
   @Email=N'granttest@example.invalid',@UserId=@Target OUTPUT;
 EXEC auth.usp_AssignRole @ActorUserId=@Actor,@UserId=@Target,@RoleCode='platform_admin';
 IF NOT EXISTS (
   SELECT 1 FROM auth.RoleAssignments a JOIN auth.Roles r ON r.RoleId=a.RoleId
   WHERE a.UserId=@Target AND r.Code='platform_admin' AND a.IsActive=1
 ) THROW 53012,'Role grant not recorded.',1;
 SELECT @Target AS TemporaryUserId,'Platform Admin assignment successful' AS VerificationResult;
 ROLLBACK TRANSACTION;
 PRINT 'PASS: Role assignment procedure succeeded; test transaction was rolled back.';
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
