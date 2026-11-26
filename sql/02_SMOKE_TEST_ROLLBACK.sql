/*
NON-DESTRUCTIVE END-TO-END SMOKE TEST.
Run AFTER 00_CREATE_ALL.sql in SSMS, in the same SQLEXPRESS instance.
Creates temporary test records within a transaction, exercises human workflow,
then ROLLBACKs all changes. Review result sets before closing the query tab.
*/
USE WorkflowPlatformV2;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRAN;
 DECLARE @Admin BIGINT,@Head BIGINT,@Lead BIGINT,@Officer BIGINT;
 SELECT TOP(1) @Admin=a.UserId FROM auth.RoleAssignments a
 JOIN auth.Roles r ON r.RoleId=a.RoleId WHERE r.Code='platform_admin' AND a.IsActive=1;
 IF @Admin IS NULL
 BEGIN
   EXEC auth.usp_UpsertDirectoryUser
     @UserName=N'smoketest.platform',@DisplayName=N'Smoke Test Platform Admin',@Email=N'smoke@example.invalid',@UserId=@Admin OUTPUT;
   EXEC auth.usp_BootstrapPlatformAdmin @UserId=@Admin;
 END;
 EXEC auth.usp_UpsertDirectoryUser @UserName=N'smoketest.head',@DisplayName=N'Smoke Unit Head',@Email=N'head@example.invalid',@UserId=@Head OUTPUT;
 EXEC auth.usp_UpsertDirectoryUser @UserName=N'smoketest.lead',@DisplayName=N'Smoke Team Lead',@Email=N'lead@example.invalid',@UserId=@Lead OUTPUT;
 EXEC auth.usp_UpsertDirectoryUser @UserName=N'smoketest.officer',@DisplayName=N'Smoke Officer',@Email=N'officer@example.invalid',@UserId=@Officer OUTPUT;
 DECLARE @Suffix VARCHAR(8)=CONVERT(VARCHAR(8),CRYPT_GEN_RANDOM(4),2);
 DECLARE @Calendar BIGINT,@Project BIGINT,@Team BIGINT,@List BIGINT,
  @Form BIGINT,@FormVersion BIGINT,@Workflow BIGINT,@WorkflowVersion BIGINT,
  @CaseType BIGINT,@CaseTypeVersion BIGINT,@Case BIGINT,@Reference NVARCHAR(55);
 DECLARE @AdminJson NVARCHAR(MAX)=CONCAT('["',CONVERT(VARCHAR(36),@Admin),'"]');
 EXEC calendar.usp_CreateCalendar @ActorUserId=@Admin,@Code=NULL,
  @Name=N'Smoke Working Calendar',@TimeZoneId=N'Pakistan Standard Time',@CalendarId=@Calendar OUTPUT;
 DECLARE @Day TINYINT=1;
 WHILE @Day<=5 BEGIN
  EXEC calendar.usp_SetWorkingInterval @ActorUserId=@Admin,@CalendarId=@Calendar,
   @DayOfWeek=@Day,@StartMinute=540,@EndMinute=1020;
  SET @Day+=1;
 END;
 DECLARE @Holiday BIGINT;
 EXEC calendar.usp_AddHolidayRange @ActorUserId=@Admin,@CalendarId=@Calendar,@Name=N'Smoke 3-Day Eid',
  @StartDate='2027-03-15',@EndDate='2027-03-17',@HolidayId=@Holiday OUTPUT;
 EXEC calendar.usp_RemoveHolidayDate @ActorUserId=@Admin,@HolidayId=@Holiday,@DateToRemove='2027-03-16';
 EXEC core.usp_OnboardProject @ActorUserId=@Admin,@Name=N'Smoke QA Project',
  @Code=NULL,@OwnerUserId=@Admin,@CalendarId=@Calendar,@AdminIdsJson=@AdminJson,
  @TermsJson=N'{"case":"Request","cases":"Requests","subject":"Employee","referencePrefix":"SMOKE"}',
  @ProjectId=@Project OUTPUT;
 EXEC teams.usp_CreateTeam @ActorUserId=@Admin,@ProjectId=@Project,@Name=N'Smoke Review Team',@Code=NULL,@TeamId=@Team OUTPUT;
 EXEC teams.usp_SetMember @ActorUserId=@Admin,@ProjectId=@Project,@TeamId=@Team,@UserId=@Head,@TeamRole='UnitHead';
 EXEC teams.usp_SetMember @ActorUserId=@Admin,@ProjectId=@Project,@TeamId=@Team,@UserId=@Lead,@TeamRole='TeamLead';
 EXEC teams.usp_SetMember @ActorUserId=@Admin,@ProjectId=@Project,@TeamId=@Team,@UserId=@Officer,@TeamRole='Officer';
 EXEC lookup.usp_CreateList @ActorUserId=@Admin,@Name=N'Smoke Priority',@Code=NULL,@Scope='Global',@ListId=@List OUTPUT;
 EXEC core.usp_AllowProjectLookup @ActorUserId=@Admin,@ProjectId=@Project,@ListId=@List,@Allowed=1;
 EXEC lookup.usp_BulkAddItems @ActorUserId=@Admin,@ListId=@List,
   @ItemsJson=N'[{"code":"HIGH","label":"High","sortOrder":1},{"code":"LOW","label":"Low","sortOrder":2}]';
 EXEC forms.usp_CreateDefinition @ActorUserId=@Admin,@ProjectId=@Project,
  @Name=N'Smoke Intake Form',@Code=NULL,@FormId=@Form OUTPUT;
 EXEC forms.usp_SaveDraft @ActorUserId=@Admin,@FormId=@Form,
  @DefinitionJson=N'{"fields":[{"id":"subject-field","key":"subject","label":"Subject","type":"text","required":true,"searchable":true},
  {"id":"details-field","key":"details","label":"Details","type":"textarea","required":false}]}';
 EXEC forms.usp_Publish @ActorUserId=@Admin,@FormId=@Form,@VersionId=@FormVersion OUTPUT;
 EXEC flow.usp_CreateDefinition @ActorUserId=@Admin,@ProjectId=@Project,
  @Name=N'Smoke Review Workflow',@Code=NULL,@WorkflowId=@Workflow OUTPUT;
 DECLARE @Graph NVARCHAR(MAX)=CONCAT(
  N'{"nodes":[{"id":"start","data":{"kind":"start","label":"Lodge"}},',
  N'{"id":"review","data":{"kind":"task","label":"Review request","teamId":"',CONVERT(NVARCHAR(36),@Team),
  N'","assignmentMode":"hierarchy","formIds":[],"actions":["Complete"]}},',
  N'{"id":"end","data":{"kind":"end","label":"Close"}}],',
  N'"edges":[{"source":"start","target":"review"},{"source":"review","target":"end"}]}');
 EXEC flow.usp_SaveDraft @ActorUserId=@Admin,@WorkflowId=@Workflow,@GraphJson=@Graph;
 EXEC flow.usp_Publish @ActorUserId=@Admin,@WorkflowId=@Workflow,@VersionId=@WorkflowVersion OUTPUT;
 EXEC core.usp_CreateCaseType @ActorUserId=@Admin,@ProjectId=@Project,
  @Name=N'Smoke Service Request',@Code=NULL,@CaseTypeId=@CaseType OUTPUT;
 DECLARE @Config NVARCHAR(MAX)=CONCAT(N'{"formId":"',CONVERT(NVARCHAR(36),@Form),
  N'","workflowId":"',CONVERT(NVARCHAR(36),@Workflow),N'","lookupListIds":[],"requiredLookupIds":[]}');
 EXEC core.usp_PublishCaseType @ActorUserId=@Admin,@CaseTypeId=@CaseType,
  @ConfigJson=@Config,@CaseTypeVersionId=@CaseTypeVersion OUTPUT;
 EXEC work.usp_CreateCase @ActorUserId=@Admin,@ProjectId=@Project,@CaseTypeId=@CaseType,
  @IntakeJson=N'{"subject":"Smoke test case","details":"Initial request details"}',
  @ClassificationJson=N'{}',@Title=N'Smoke test',@CaseId=@Case OUTPUT,@ReferenceNo=@Reference OUTPUT;
 DECLARE @Task BIGINT=(SELECT TOP(1) t.TaskId FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
  WHERE i.CaseId=@Case ORDER BY t.CreatedAt);
 IF @Task IS NULL THROW 50901,'No first human task was assigned.',1;
 IF (SELECT RoutingStage FROM work.Tasks WHERE TaskId=@Task)<>'UnitHead' THROW 50902,'First assignment should be UnitHead.',1;
 EXEC work.usp_ForwardTask @ActorUserId=@Head,@TaskId=@Task,@ToUserId=@Lead;
 EXEC work.usp_ForwardTask @ActorUserId=@Lead,@TaskId=@Task,@ToUserId=@Officer;
 EXEC work.usp_CompleteTask @ActorUserId=@Officer,@TaskId=@Task,@Action='Complete',@AnswersByFormJson=N'{}';
 IF NOT EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@Case AND Status='Closed') THROW 50903,'Case did not close.',1;
 SELECT @Reference AS SmokeReference,@Case AS CaseId,@Project AS ProjectId,
  (SELECT Status FROM work.Cases WHERE CaseId=@Case) AS FinalStatus,
  (SELECT COUNT(*) FROM work.CaseEvents WHERE CaseId=@Case) AS AuditEventCount,
  (SELECT COUNT(*) FROM work.Tasks WHERE InstanceId=(SELECT InstanceId FROM work.Instances WHERE CaseId=@Case) AND Status='Completed') AS CompletedTaskCount;
 ROLLBACK TRAN;
 PRINT N'SMOKE TEST PASSED. All synthetic records were rolled back.';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRAN;
 DECLARE @Error NVARCHAR(2048)=CONCAT('SMOKE TEST FAILED: ',ERROR_MESSAGE(),' (line ',ERROR_LINE(),')');
 PRINT @Error;
 THROW;
END CATCH;
GO
