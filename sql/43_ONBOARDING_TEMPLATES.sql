USE [WorkflowPlatformV2];
GO
CREATE OR ALTER PROCEDURE core.usp_OnboardProject
 @ActorUserId BIGINT,@Name NVARCHAR(200),@Code VARCHAR(75),
 @OwnerUserId BIGINT=NULL,@CalendarId BIGINT,
 @AdminIdsJson NVARCHAR(MAX),@TermsJson NVARCHAR(MAX)=N'{}',@Description NVARCHAR(1000)=NULL,
 @TemplateCode VARCHAR(50)='blank',@RcaTemplateId BIGINT=NULL,
 @RcaRequired BIT=0,@DefaultSlaMinutes INT=1440,@TeamsJson NVARCHAR(MAX)=N'[]',@ProjectId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,NULL)<>1 AND auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1
  THROW 50020,'Only platform administrators can onboard projects.',1;
 SET @TemplateCode=LOWER(LTRIM(RTRIM(COALESCE(@TemplateCode,'blank'))));
 IF @TemplateCode NOT IN ('blank','step1','step2','step3') THROW 50925,'Invalid initial workflow template.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50021,'Project code must contain only A-Z, 0-9 and underscore.',1;
 IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL THROW 50022,'Project name is required.',1;
 IF @DefaultSlaMinutes<0 THROW 50023,'Invalid SLA minutes.',1;
 IF @AdminIdsJson IS NULL OR ISJSON(@AdminIdsJson)<>1 OR LEFT(LTRIM(@AdminIdsJson),1)<>'[' THROW 50024,'AdminIdsJson must be an array.',1;
 SET @TeamsJson=COALESCE(@TeamsJson,N'[]');
 IF ISJSON(@TeamsJson)<>1 OR LEFT(LTRIM(@TeamsJson),1)<>'[' THROW 50921,'TeamsJson must be an array.',1;
 IF (SELECT COUNT(*) FROM OPENJSON(@TeamsJson))>30 THROW 50922,'At most 30 initial teams are allowed.',1;
 IF EXISTS (SELECT 1 FROM OPENJSON(@TeamsJson) WHERE [type]<>1 OR NULLIF(LTRIM(RTRIM([value])),N'') IS NULL OR LEN([value])>160 OR core.fn_IsCode(core.fn_CodeFromName([value]))<>1) THROW 50923,'Invalid initial team name.',1;
 IF EXISTS (SELECT core.fn_CodeFromName([value]) FROM OPENJSON(@TeamsJson) GROUP BY core.fn_CodeFromName([value]) HAVING COUNT(*)>1) THROW 50924,'Duplicate initial team name.',1;
 IF @TermsJson IS NULL OR ISJSON(@TermsJson)<>1 OR LEFT(LTRIM(@TermsJson),1)<>'{' THROW 50025,'TermsJson must be an object.',1;
 IF NOT EXISTS(SELECT 1 FROM calendar.Calendars WHERE CalendarId=@CalendarId AND IsActive=1) THROW 50026,'Select an active calendar.',1;
 IF @RcaRequired=1 AND NOT EXISTS(SELECT 1 FROM core.RcaTemplates WHERE RcaTemplateId=@RcaTemplateId AND IsActive=1) THROW 50027,'Select an active RCA template.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@AdminIdsJson) WHERE TRY_CONVERT(BIGINT,[value]) IS NULL)
  THROW 50028,'Invalid project administrator ID.',1;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@AdminIdsJson)) THROW 50029,'At least one project administrator is required.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@AdminIdsJson) j
  WHERE NOT EXISTS(SELECT 1 FROM auth.Users u WHERE u.UserId=TRY_CONVERT(BIGINT,j.value) AND u.IsActive=1))
  THROW 50030,'One or more project admins are not active users.',1;
 IF @OwnerUserId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@OwnerUserId AND IsActive=1)
  THROW 50031,'Owner must be an active directory user.',1;
 BEGIN TRAN;
 SET @ProjectId=NEXT VALUE FOR core.Seq_Projects;
 INSERT core.Projects(ProjectId,Code,Name,Description,OwnerUserId,CalendarId,DefaultSlaMinutes,ReferencePrefix,TemplateCode,Status,RcaRequired,RcaTemplateId,RcaEnabled)
 VALUES(@ProjectId,@Code,@Name,@Description,@OwnerUserId,@CalendarId,@DefaultSlaMinutes,LEFT(@Code,20),@TemplateCode,'UAT',@RcaRequired,@RcaTemplateId,@RcaRequired);
 INSERT core.ProjectSequence(ProjectId,LastNumber) VALUES(@ProjectId,0);
 INSERT core.ProjectRcaFields(ProjectId,FieldKey,ConfigJson,SortOrder)
 SELECT @ProjectId,FieldKey,
 (SELECT FieldKey AS [key],Label AS [label],FieldType AS [type],Required AS [required],
 ParentFieldKey AS [parentKey],ParentValue AS [parentValue],JSON_QUERY(OptionsJson) AS [options]
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),SortOrder
 FROM core.RcaTemplateFields WHERE RcaTemplateId=@RcaTemplateId AND @RcaRequired=1;
 
 INSERT core.ProjectTerminology(ProjectId,TermKey,TermValue)
 SELECT @ProjectId,j.[key],LEFT(CONVERT(NVARCHAR(200),j.value),200)
 FROM OPENJSON(@TermsJson) j WHERE j.[type]=1 AND LEN(j.[key])<=75;
 DECLARE @ProjectAdminRole BIGINT=(SELECT RoleId FROM auth.Roles WHERE Code='project_admin');
 INSERT auth.RoleAssignments(UserId,RoleId,ProjectId,TeamId,AssignedBy)
 SELECT DISTINCT TRY_CONVERT(BIGINT,j.value),@ProjectAdminRole,@ProjectId,NULL,@ActorUserId FROM OPENJSON(@AdminIdsJson) j;
 -- Create initial teams in the same transaction as the project and admin assignments.
 INSERT teams.Teams(TeamId,ProjectId,Code,Name)
 SELECT NEXT VALUE FOR teams.Seq_Teams,@ProjectId,core.fn_CodeFromName([value]),LTRIM(RTRIM([value]))
 FROM OPENJSON(@TeamsJson);
 DECLARE @InitialTeamCount INT=@@ROWCOUNT;
 IF @InitialTeamCount<>(SELECT COUNT(*) FROM OPENJSON(@TeamsJson)) THROW 50926,'Initial team creation count mismatch.',1;
 IF @TemplateCode='step1' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'1-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-end","source":"step1","target":"end","type":"smoothstep"}]}');
 IF @TemplateCode='step2' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'2-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"step2","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"Step 2","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":820,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-step2","source":"step1","target":"step2","type":"smoothstep"},{"id":"e-step2-end","source":"step2","target":"end","type":"smoothstep"}]}');
 IF @TemplateCode='step3' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'3-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"step2","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"Step 2","kind":"task","formIds":[],"teamId":null}},{"id":"step3","type":"flowNode","position":{"x":820,"y":180},"data":{"label":"Step 3","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":1080,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-step2","source":"step1","target":"step2","type":"smoothstep"},{"id":"e-step2-step3","source":"step2","target":"step3","type":"smoothstep"},{"id":"e-step3-end","source":"step3","target":"end","type":"smoothstep"}]}');
 INSERT INTO core.ProjectStatusHistory(ProjectId,FromStatus,ToStatus,Description,ChangedBy)
 VALUES(@ProjectId,NULL,'UAT',NULL,@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Project',@EntityId=@ProjectId,@ActionCode='OnboardProject';
 COMMIT;
 SELECT ProjectId,Code,Name,Status,CalendarId,RcaRequired,@InitialTeamCount AS InitialTeamCount FROM core.Projects WHERE ProjectId=@ProjectId;
END;
GO
