/* Read-only validation after executing corrected 00_CREATE_ALL_FRESH_FIXED.sql.
   This cannot replace reviewing SSMS Messages or full migration tests. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
DECLARE @Activation NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'work.usp_ActivateNode',N'P'));
DECLARE @CaseCreation NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase',N'P'));
IF @Activation IS NULL THROW 50990,'FAIL: work.usp_ActivateNode is missing.',1;
IF @CaseCreation IS NULL THROW 50991,'FAIL: work.usp_CreateCase is missing.',1;
IF CHARINDEX(N'DECLARE @JoinExpectedArrivals INT',@Activation)=0
  THROW 50992,'FAIL: parallel join variable fix missing.',1;
IF CHARINDEX(N'DECLARE @NotifyRecipientUserId BIGINT',@Activation)=0
  THROW 50993,'FAIL: notification recipient variable fix missing.',1;
IF CHARINDEX(N'SELECT st.ProjectId,@CaseId,st.FormVersionId,st.FieldKey',@CaseCreation)=0
  THROW 50994,'FAIL: staged attachment FieldKey qualification is missing.',1;
IF CHARINDEX(N'p.Status IN (''UAT'',''Live'')',@CaseCreation)=0
  THROW 50995,'FAIL: case creation does not accept UAT/Live.',1;
SELECT N'PASS' AS BaseInstallCheck,
       N'ActivateNode and CreateCase definitions are present with the targeted fixes.' AS Details;
GO
