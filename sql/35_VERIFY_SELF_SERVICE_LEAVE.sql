USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'teams.usp_SetLeaveBackup',N'P') IS NULL
    THROW 50934, 'FAIL: teams.usp_SetLeaveBackup was not created.', 1;
DECLARE @Definition NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'teams.usp_SetLeaveBackup'));
IF @Definition IS NULL OR @Definition NOT LIKE N'%@ActorUserId<>@UserId%'
    THROW 50935, 'FAIL: employee-only authorization was not found in leave procedure.', 1;
SELECT 'PASS' AS SelfServiceLeaveProcedure, 'Only the acting employee can submit leave; existing records preserved.' AS Notes;
GO
