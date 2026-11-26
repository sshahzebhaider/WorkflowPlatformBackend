USE [WorkflowPlatformV2];
GO
/* Targeted onboarding, role, directory and RCA fixes. */
CREATE OR ALTER PROCEDURE auth.usp_UpsertDirectoryUser
 @UserName NVARCHAR(150),@DisplayName NVARCHAR(200),@Email NVARCHAR(320)=NULL,
 @ExternalDirectoryId NVARCHAR(200)=NULL,@DirectoryStatus VARCHAR(20)='Active',
 @Mobile NVARCHAR(40)=NULL,@UserId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF NULLIF(LTRIM(RTRIM(@UserName)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@DisplayName)),N'') IS NULL THROW 50010,'Username and display name are required.',1;
 IF @DirectoryStatus NOT IN('Active','Resigned','Disabled','OnLeave') THROW 50011,'Invalid directory status.',1;
 BEGIN TRAN;
 SET @UserId=NULL;
 SELECT @UserId=UserId FROM auth.Users WITH(UPDLOCK,HOLDLOCK)
 WHERE UserName=@UserName OR (@ExternalDirectoryId IS NOT NULL AND ExternalDirectoryId=@ExternalDirectoryId);
 IF @UserId IS NULL BEGIN
  SET @UserId=NEXT VALUE FOR auth.Seq_Users;
  INSERT auth.Users(UserId,UserName,DisplayName,Email,Mobile,ExternalDirectoryId,DirectoryStatus,IsActive,LastDirectorySyncAt)
  VALUES(@UserId,@UserName,@DisplayName,@Email,@Mobile,@ExternalDirectoryId,@DirectoryStatus,CASE WHEN @DirectoryStatus IN('Resigned','Disabled') THEN 0 ELSE 1 END,SYSUTCDATETIME());
 END ELSE BEGIN
  UPDATE auth.Users SET DisplayName=@DisplayName,Email=COALESCE(@Email,Email),Mobile=COALESCE(@Mobile,Mobile),
   ExternalDirectoryId=COALESCE(@ExternalDirectoryId,ExternalDirectoryId),
   DirectoryStatus=@DirectoryStatus,IsActive=CASE WHEN @DirectoryStatus IN('Resigned','Disabled') THEN 0 ELSE 1 END,
   LastDirectorySyncAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 END;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE auth.usp_CreatePlatformAdminUser
 @ActorUserId BIGINT,@UserName NVARCHAR(150),@DisplayName NVARCHAR(200),@Email NVARCHAR(320)=NULL,@UserId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,NULL)<>1 THROW 51001,'Platform Admin required.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM auth.Users WITH(UPDLOCK,HOLDLOCK) WHERE UserName=@UserName)
 BEGIN ROLLBACK; THROW 51002,'Username already exists. Use Grant Platform Admin on the existing user.',1; END;
 EXEC auth.usp_UpsertDirectoryUser @UserName=@UserName,@DisplayName=@DisplayName,@Email=@Email,@UserId=@UserId OUTPUT;
 EXEC auth.usp_AssignRole @ActorUserId=@ActorUserId,@UserId=@UserId,@RoleCode='platform_admin';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE auth.usp_SaveCustomRole
 @ActorUserId BIGINT,@Name NVARCHAR(150),@Code VARCHAR(65)=NULL,
 @Scope VARCHAR(16)='Project',@PermissionsJson NVARCHAR(MAX),@RoleId BIGINT OUTPUT,@Description NVARCHAR(500)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,NULL)<>1 THROW 50300,'Platform Admin required to manage role definitions.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF NOT EXISTS(SELECT 1 FROM auth.Roles WHERE RoleId=@RoleId AND IsSystem=1) AND core.fn_IsCode(@Code)<>1 THROW 50301,'Invalid role code.',1;
 IF @Scope NOT IN('Project','Team') THROW 50302,'Custom roles may only have project or team scope.',1;
 IF @PermissionsJson IS NULL OR ISJSON(@PermissionsJson)<>1 OR LEFT(LTRIM(@PermissionsJson),1)<>'[' THROW 50303,'Permissions must be a JSON array.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@PermissionsJson) j WHERE NOT EXISTS(
 SELECT 1 FROM auth.Permissions p WHERE p.PermissionCode COLLATE DATABASE_DEFAULT=j.value COLLATE DATABASE_DEFAULT)) THROW 50304,'Unknown permission code.',1;
 BEGIN TRAN;
 IF @RoleId IS NULL
 BEGIN
  IF EXISTS(SELECT 1 FROM auth.Roles WHERE Code=@Code) BEGIN ROLLBACK; THROW 50305,'Role code already exists.',1; END;
  SET @RoleId=NEXT VALUE FOR auth.Seq_Roles;
  INSERT auth.Roles(RoleId,Code,Name,Scope,IsSystem) VALUES(@RoleId,@Code,@Name,@Scope,0);
 END ELSE
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM auth.Roles WITH(UPDLOCK,HOLDLOCK) WHERE RoleId=@RoleId AND Scope<>'Platform') BEGIN ROLLBACK; THROW 50306,'Role not found or protected platform role.',1; END;
  IF EXISTS(SELECT 1 FROM auth.Roles WHERE RoleId=@RoleId AND IsSystem=1)
  BEGIN
   IF EXISTS(SELECT 1 FROM auth.Roles WHERE RoleId=@RoleId AND (Code<>@Code OR Scope<>@Scope OR Name<>@Name)) BEGIN ROLLBACK; THROW 50316,'Built-in role name, code and scope are immutable.',1; END;
  END ELSE UPDATE auth.Roles SET Name=@Name,Code=@Code,Scope=@Scope WHERE RoleId=@RoleId;
 END;
 UPDATE auth.Roles SET Description=COALESCE(@Description,Description) WHERE RoleId=@RoleId;
 DELETE FROM auth.RolePermissions WHERE RoleId=@RoleId;
 INSERT auth.RolePermissions(RoleId,PermissionCode) SELECT DISTINCT @RoleId,p.PermissionCode FROM OPENJSON(@PermissionsJson) j JOIN auth.Permissions p ON p.PermissionCode COLLATE DATABASE_DEFAULT=j.value COLLATE DATABASE_DEFAULT;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='Role',@EntityId=@RoleId,@ActionCode='SaveRoleRights';
 COMMIT;
END;
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
CREATE OR ALTER PROCEDURE work.usp_SubmitRca
 @ActorUserId BIGINT,@CaseId BIGINT,@Summary NVARCHAR(MAX)=NULL,
 @FieldsJson NVARCHAR(MAX),@RootReasonItemId BIGINT=NULL,@FormAnswersJson NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 SET @Summary=COALESCE(@Summary,N''); -- Legacy storage column; template fields are authoritative.
 IF @FieldsJson IS NULL OR ISJSON(@FieldsJson)<>1 OR LEFT(LTRIM(@FieldsJson),1)<>'{' THROW 50187,'RCA field answers must be a JSON object.',1;
 IF @FormAnswersJson IS NOT NULL AND ISJSON(@FormAnswersJson)<>1 THROW 50188,'RCA form answers must be JSON.',1;
 DECLARE @ProjectId BIGINT,@TemplateId BIGINT,@FinalStatus VARCHAR(30),@RcaFieldsSnapshotJson NVARCHAR(MAX);
 BEGIN TRAN;
 SELECT @ProjectId=c.ProjectId,@FinalStatus=c.PendingFinalStatus,@TemplateId=c.RcaTemplateAtCreation,@RcaFieldsSnapshotJson=c.RcaFieldsSnapshotJson
 FROM work.Cases c WITH(UPDLOCK,HOLDLOCK)
 WHERE c.CaseId=@CaseId AND c.Status='Pending RCA';
 IF @ProjectId IS NULL BEGIN ROLLBACK; THROW 50189,'Case is not awaiting RCA.',1; END;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.manage')<>1 BEGIN ROLLBACK; THROW 50190,'Permission to manage the case is required.',1; END;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 AND NOT EXISTS(
  SELECT 1 FROM work.Cases c WHERE c.CaseId=@CaseId AND c.CreatedBy=@ActorUserId
  UNION ALL
  SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
  WHERE i.CaseId=@CaseId AND (t.AssignedTo=@ActorUserId OR t.CompletedBy=@ActorUserId)
  UNION ALL
  SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
  JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@ActorUserId AND m.IsActive=1
  WHERE i.CaseId=@CaseId
 ) BEGIN ROLLBACK; THROW 50192,'You are not involved in this case.',1; END;
 IF @RcaFieldsSnapshotJson IS NULL OR ISJSON(@RcaFieldsSnapshotJson)<>1 OR LEFT(LTRIM(@RcaFieldsSnapshotJson),1)<>'[' BEGIN ROLLBACK; THROW 51005,'Invalid saved RCA template. Ask an administrator to review the case.',1; END;
 DECLARE @RcaSchema TABLE(FieldKey NVARCHAR(90) COLLATE Latin1_General_BIN2 PRIMARY KEY,FieldType VARCHAR(20),Required BIT,ParentFieldKey NVARCHAR(90) COLLATE Latin1_General_BIN2,ParentValue NVARCHAR(150) COLLATE Latin1_General_BIN2,OptionsJson NVARCHAR(MAX));
 INSERT @RcaSchema SELECT FieldKey,FieldType,Required,ParentFieldKey,ParentValue,OptionsJson FROM OPENJSON(@RcaFieldsSnapshotJson) WITH(
 FieldKey NVARCHAR(90) '$.FieldKey',FieldType VARCHAR(20) '$.FieldType',Required BIT '$.Required',ParentFieldKey NVARCHAR(90) '$.ParentFieldKey',ParentValue NVARCHAR(150) '$.ParentValue',OptionsJson NVARCHAR(MAX) '$.OptionsJson' AS JSON);
 IF EXISTS(SELECT [key] FROM OPENJSON(@FieldsJson) GROUP BY [key] HAVING COUNT(*)>1)
 OR EXISTS(SELECT 1 FROM OPENJSON(@FieldsJson) a WHERE NOT EXISTS(SELECT 1 FROM @RcaSchema s WHERE s.FieldKey=a.[key] COLLATE Latin1_General_BIN2))
 BEGIN ROLLBACK; THROW 51005,'Invalid RCA field keys.',1; END;
 -- Older snapshots did not retain options. Only use the matching project field's current options as a fallback.
 UPDATE s SET OptionsJson=JSON_QUERY(p.ConfigJson,'$.options') FROM @RcaSchema s
 JOIN core.ProjectRcaFields p ON p.ProjectId=@ProjectId AND p.FieldKey COLLATE Latin1_General_BIN2=s.FieldKey
 WHERE s.OptionsJson IS NULL AND s.FieldType='select';
 IF EXISTS(SELECT 1 FROM @RcaSchema f
 LEFT JOIN OPENJSON(@FieldsJson) parent ON parent.[key] COLLATE Latin1_General_BIN2=f.ParentFieldKey
 LEFT JOIN OPENJSON(@FieldsJson) a ON a.[key] COLLATE Latin1_General_BIN2=f.FieldKey
 WHERE (f.ParentFieldKey IS NULL OR (NULLIF(LTRIM(RTRIM(parent.value)),N'') IS NOT NULL AND parent.type IN(1,2,3) AND (NULLIF(f.ParentValue,N'') IS NULL OR parent.value COLLATE Latin1_General_BIN2=f.ParentValue)))
 AND (f.Required=1 AND (a.type IS NULL OR a.type=0 OR NULLIF(LTRIM(RTRIM(a.value)),N'') IS NULL)
 OR a.type IN(4,5)
 OR a.type IN(1,2,3) AND NULLIF(LTRIM(RTRIM(a.value)),N'') IS NOT NULL AND (
   f.FieldType='select' AND (f.OptionsJson IS NULL OR NOT EXISTS(SELECT 1 FROM OPENJSON(f.OptionsJson) opt WHERE opt.value COLLATE Latin1_General_BIN2=a.value COLLATE Latin1_General_BIN2))
   OR f.FieldType='toggle' AND a.value COLLATE Latin1_General_BIN2 NOT IN('Yes','No')
   OR f.FieldType='number' AND (a.type<>2 OR TRY_CONVERT(DECIMAL(28,8),a.value) IS NULL OR TRY_CONVERT(DECIMAL(28,8),a.value)<0)
   OR f.FieldType='date' AND (a.type<>1 OR TRY_CONVERT(DATE,a.value,23) IS NULL OR LEN(a.value)<>10)
   OR f.FieldType IN('text','textarea') AND a.type<>1)))
 BEGIN ROLLBACK; THROW 50191,'Complete all required visible RCA fields with valid values.',1; END;
 INSERT work.CaseRca(CaseId,TemplateId,RootReasonItemId,Summary,FieldsJson,FormAnswersJson,CompletedBy)
 VALUES(@CaseId,@TemplateId,@RootReasonItemId,@Summary,@FieldsJson,@FormAnswersJson,@ActorUserId);
 UPDATE work.Cases SET Status=CASE WHEN @FinalStatus='Rejected' THEN 'Rejected' ELSE 'Closed' END,
 ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME(),PendingFinalStatus=NULL WHERE CaseId=@CaseId;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId) VALUES(@CaseId,'RcaCompleted',N'RCA submitted and case closed',@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='RCA',@EntityId=@CaseId,@ActionCode='Complete';
 COMMIT;
END;
GO
/* Complete shipped case-creation procedure from migration 19, with RCA option snapshot.
   No dynamic rewriting of installed procedure declarations. */
CREATE OR ALTER PROCEDURE work.usp_CreateCase
 @ActorUserId BIGINT,@ProjectId BIGINT,@CaseTypeId BIGINT,
 @IntakeJson NVARCHAR(MAX),@ClassificationJson NVARCHAR(MAX)=N'{}',
 @Title NVARCHAR(300)=NULL,@IdempotencyKey VARCHAR(120)=NULL,
 @LodgementOperationId BIGINT=NULL,@LodgementMappedJson NVARCHAR(MAX)=NULL,
 @CaseId BIGINT OUTPUT,@ReferenceNo NVARCHAR(55) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.create')<>1 THROW 50160,'User cannot create cases in this project.',1;
 IF ISJSON(@IntakeJson)<>1 OR LEFT(LTRIM(@IntakeJson),1)<>'{' OR ISJSON(@ClassificationJson)<>1 OR LEFT(LTRIM(@ClassificationJson),1)<>'{'
  THROW 50161,'Intake and classification must be JSON objects.',1;
 DECLARE @RcaTemplateAtCreation BIGINT,@RcaRequired BIT,@RcaFieldsSnapshotJson NVARCHAR(MAX);
 DECLARE @CaseTypeVersionId BIGINT,@FormVersionId BIGINT,@WorkflowVersionId BIGINT,
 @SubjectKey VARCHAR(100),@SubjectValue NVARCHAR(250),@SubjectHash VARBINARY(32),
 @AllowDuplicate BIT,@Prefix VARCHAR(20),@SlaMinutes INT,@CalendarId BIGINT,@DueAt DATETIME2(3),@InstanceId BIGINT;
 SELECT @CaseTypeVersionId=t.LiveVersionId,@Prefix=p.ReferencePrefix,@CalendarId=p.CalendarId
 FROM core.CaseTypes t JOIN core.Projects p ON p.ProjectId=t.ProjectId
 WHERE t.CaseTypeId=@CaseTypeId AND t.ProjectId=@ProjectId AND t.IsActive=1 AND p.Status IN ('UAT','Live');
 IF @CaseTypeVersionId IS NULL THROW 50162,'Select a published type from a UAT or live project.',1;
 DECLARE @PublishedIntegrationId BIGINT=(SELECT TRY_CONVERT(BIGINT,JSON_VALUE(PublishedConfigJson,'$.lodgementIntegration.operationId'))
 FROM core.CaseTypeVersions WHERE CaseTypeVersionId=@CaseTypeVersionId);
 IF (@PublishedIntegrationId IS NOT NULL AND (ISNULL(@LodgementOperationId,-1)<>@PublishedIntegrationId OR
    ISJSON(@LodgementMappedJson)<>1 OR LEFT(LTRIM(@LodgementMappedJson),1)<>'{'))
 OR (@PublishedIntegrationId IS NULL AND (@LodgementOperationId IS NOT NULL OR @LodgementMappedJson IS NOT NULL))
 THROW 50313,'Required published lodgement integration did not complete successfully.',1;
 IF @LodgementOperationId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM integration.Operations o JOIN integration.ProjectDataSources p ON p.DataSourceId=o.DataSourceId
 WHERE o.OperationId=@LodgementOperationId AND p.ProjectId=@ProjectId)
 THROW 50314,'Operation is not approved for this project.',1;
 SELECT @FormVersionId=IntakeFormVersionId,@WorkflowVersionId=WorkflowVersionId,@SubjectKey=SubjectFieldKey,
 @AllowDuplicate=AllowDuplicate,@SlaMinutes=SlaMinutes FROM core.CaseTypeVersions WHERE CaseTypeVersionId=@CaseTypeVersionId;
 IF EXISTS(SELECT 1 FROM forms.VersionFields f WHERE f.FormVersionId=@FormVersionId AND f.IsRequired=1
 AND (f.FieldType='attachment' AND ISNULL(JSON_QUERY(@IntakeJson,CONCAT('$.',f.FieldKey)),N'[]')=N'[]'
 OR f.FieldType<>'attachment' AND NULLIF(LTRIM(ISNULL(JSON_VALUE(@IntakeJson,CONCAT('$.',f.FieldKey)),N'')),N'') IS NULL))
  THROW 50163,'A required intake field is missing.',1;
 IF EXISTS(SELECT 1 FROM core.CaseTypeLookups l JOIN lookup.Lists list ON list.ListId=l.ListId
 WHERE l.CaseTypeVersionId=@CaseTypeVersionId AND l.IsRequired=1
 AND NULLIF(JSON_VALUE(@ClassificationJson,CONCAT('$.classification_',LOWER(list.Code))),N'') IS NULL)
  THROW 50164,'Required classification lookup is missing.',1;
 IF EXISTS(SELECT 1 FROM core.CaseTypeLookups l JOIN lookup.Lists list ON list.ListId=l.ListId
 WHERE l.CaseTypeVersionId=@CaseTypeVersionId AND l.LockedItemId IS NOT NULL
 AND JSON_VALUE(@ClassificationJson,CONCAT('$.classification_',LOWER(list.Code)))<>CONVERT(NVARCHAR(36),l.LockedItemId))
  THROW 50165,'Locked classification value cannot be changed.',1;
 SET @SubjectValue=CASE WHEN @SubjectKey IS NOT NULL THEN LEFT(JSON_VALUE(@IntakeJson,CONCAT('$.',@SubjectKey)),250) END;
 IF @SubjectValue IS NOT NULL AND NULLIF(LTRIM(@SubjectValue),'') IS NOT NULL
  SET @SubjectHash=HASHBYTES('SHA2_256',LOWER(LTRIM(RTRIM(@SubjectValue))));
 SELECT @RcaTemplateAtCreation=RcaTemplateId,@RcaRequired=RcaRequired FROM core.Projects WHERE ProjectId=@ProjectId;
 SELECT @RcaFieldsSnapshotJson=(SELECT JSON_VALUE(ConfigJson,'$.key') AS FieldKey,
 JSON_VALUE(ConfigJson,'$.label') AS Label,JSON_VALUE(ConfigJson,'$.type') AS FieldType,
 TRY_CONVERT(BIT,JSON_VALUE(ConfigJson,'$.required')) AS Required,
 JSON_VALUE(ConfigJson,'$.parentKey') AS ParentFieldKey,
 JSON_VALUE(ConfigJson,'$.parentValue') AS ParentValue,
 JSON_QUERY(ConfigJson,'$.options') AS OptionsJson
 FROM core.ProjectRcaFields WHERE ProjectId=@ProjectId ORDER BY SortOrder FOR JSON PATH);
 IF @RcaFieldsSnapshotJson IS NULL SET @RcaFieldsSnapshotJson=N'[]';
 IF @CalendarId IS NOT NULL
  BEGIN
   IF @SlaMinutes IS NULL SET @SlaMinutes=(SELECT DefaultSlaMinutes FROM core.Projects WHERE ProjectId=@ProjectId);
   DECLARE @CaseStartAt DATETIME2(3)=SYSUTCDATETIME();
   EXEC calendar.usp_CalculateBusinessDueAt @CalendarId,@CaseStartAt,@SlaMinutes,@DueAt OUTPUT;
  END;
 BEGIN TRAN;
 IF @IdempotencyKey IS NOT NULL AND EXISTS(SELECT 1 FROM work.Cases WITH(UPDLOCK,HOLDLOCK)
  WHERE ProjectId=@ProjectId AND IdempotencyKey=@IdempotencyKey)
 BEGIN
  SELECT @CaseId=CaseId,@ReferenceNo=ReferenceNo FROM work.Cases WHERE ProjectId=@ProjectId AND IdempotencyKey=@IdempotencyKey;
  COMMIT; RETURN;
 END;
 IF @AllowDuplicate=0 AND @SubjectHash IS NOT NULL AND EXISTS(SELECT 1 FROM work.Cases WITH(UPDLOCK,HOLDLOCK)
  WHERE ProjectId=@ProjectId AND CaseTypeVersionId=@CaseTypeVersionId AND SubjectHash=@SubjectHash AND ClosedAt IS NULL)
  BEGIN ROLLBACK; THROW 50166,'An open case already exists for this subject/type.',1; END;
 DECLARE @Next TABLE(Seq BIGINT);
 UPDATE core.ProjectSequence WITH(UPDLOCK,HOLDLOCK) SET LastNumber=LastNumber+1 OUTPUT inserted.LastNumber INTO @Next
 WHERE ProjectId=@ProjectId;
 DECLARE @Seq BIGINT=(SELECT TOP(1) Seq FROM @Next);
 IF @Seq IS NULL BEGIN ROLLBACK; THROW 50167,'Project reference sequence missing.',1; END;
 SET @ReferenceNo=CONCAT(@Prefix,'-',YEAR(SYSUTCDATETIME()),'-',RIGHT(REPLICATE('0',8)+CONVERT(VARCHAR(19),@Seq),8));
 SET @CaseId=NEXT VALUE FOR work.Seq_Cases;SET @InstanceId=NEXT VALUE FOR work.Seq_Instances;
 DECLARE @CurrentIntakeValues NVARCHAR(MAX)=@IntakeJson;
 IF @LodgementMappedJson IS NOT NULL
 BEGIN
  DECLARE @ResponseKey NVARCHAR(128),@ResponseValue NVARCHAR(MAX),@ResponseType INT,@ResponsePath NVARCHAR(150);
  DECLARE mappedFields CURSOR LOCAL FAST_FORWARD FOR SELECT [key],[value],[type] FROM OPENJSON(@LodgementMappedJson);
  OPEN mappedFields;FETCH NEXT FROM mappedFields INTO @ResponseKey,@ResponseValue,@ResponseType;
  WHILE @@FETCH_STATUS=0
  BEGIN
   IF LEN(@ResponseKey)>100 OR @ResponseKey COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%'
      OR EXISTS(SELECT 1 FROM OPENJSON(@IntakeJson) WHERE [key]=@ResponseKey)
   BEGIN CLOSE mappedFields;DEALLOCATE mappedFields;ROLLBACK; THROW 50315,'Integration mapping must not replace an intake value.',1; END;
   SET @ResponsePath=CONCAT('$.',@ResponseKey);
   IF @ResponseType IN(4,5) SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,JSON_QUERY(@LodgementMappedJson,@ResponsePath));
   ELSE IF @ResponseType=2 SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,TRY_CONVERT(DECIMAL(28,8),@ResponseValue));
   ELSE IF @ResponseType=3 SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,CASE WHEN @ResponseValue='true' THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END);
   ELSE SET @CurrentIntakeValues=JSON_MODIFY(@CurrentIntakeValues,@ResponsePath,@ResponseValue);
   FETCH NEXT FROM mappedFields INTO @ResponseKey,@ResponseValue,@ResponseType;
  END;
  CLOSE mappedFields;DEALLOCATE mappedFields;
 END;
 INSERT work.Cases(CaseId,ProjectId,CaseTypeVersionId,WorkflowVersionId,ReferenceNo,Title,
  SubjectValue,SubjectHash,IntakeJson,CurrentValuesJson,ClassificationJson,CreatedBy,DueAt,IdempotencyKey,
  RcaRequiredAtCreation,RcaTemplateAtCreation,RcaFieldsSnapshotJson)
 VALUES(@CaseId,@ProjectId,@CaseTypeVersionId,@WorkflowVersionId,@ReferenceNo,
  ISNULL(@Title,N'New case'),@SubjectValue,@SubjectHash,@IntakeJson,@CurrentIntakeValues,@ClassificationJson,@ActorUserId,@DueAt,@IdempotencyKey,
  @RcaRequired,@RcaTemplateAtCreation,@RcaFieldsSnapshotJson);
 /* Strictly bind pre-scanned staged files to this actor, form version and project.
    Failed validation or failed case creation rolls back consumption and document linkage. */
 DECLARE @IntakeFiles TABLE(StageId BIGINT NOT NULL PRIMARY KEY,FieldKey VARCHAR(100) NOT NULL);
 IF EXISTS (SELECT 1 FROM forms.VersionFields f
   CROSS APPLY OPENJSON(@IntakeJson,CONCAT('$.',f.FieldKey)) j
   WHERE f.FormVersionId=@FormVersionId AND f.FieldType='attachment'
   AND (TRY_CONVERT(BIGINT,j.value) IS NULL OR TRY_CONVERT(BIGINT,j.value)<=0))
 BEGIN ROLLBACK; THROW 50401,'Invalid staged attachment ID.',1; END;
 INSERT @IntakeFiles(StageId,FieldKey)
 SELECT TRY_CONVERT(BIGINT,j.value),f.FieldKey FROM forms.VersionFields f
 CROSS APPLY OPENJSON(@IntakeJson,CONCAT('$.',f.FieldKey)) j
 WHERE f.FormVersionId=@FormVersionId AND f.FieldType='attachment';
 IF EXISTS (SELECT 1 FROM @IntakeFiles ref
  LEFT JOIN files.StagedDocuments st WITH(UPDLOCK,HOLDLOCK) ON st.StageId=ref.StageId
  WHERE st.StageId IS NULL OR st.ProjectId<>@ProjectId OR st.CaseTypeId<>@CaseTypeId
  OR st.FormVersionId<>@FormVersionId OR st.ActorUserId<>@ActorUserId OR st.FieldKey<>ref.FieldKey
  OR st.ConsumedCaseId IS NOT NULL OR st.ExpiresAt<=SYSUTCDATETIME())
 BEGIN ROLLBACK; THROW 50402,'Staged attachment is unavailable, expired, or belongs to a different form/user.',1; END;
 UPDATE st SET ConsumedCaseId=@CaseId,ConsumedAt=SYSUTCDATETIME()
 FROM files.StagedDocuments st JOIN @IntakeFiles r ON r.StageId=st.StageId;
 INSERT files.Documents(ProjectId,CaseId,FormVersionId,FieldKey,StorageKey,
 OriginalFileName,MimeType,FileSizeBytes,Sha256,ScanStatus,UploadedBy)
 SELECT st.ProjectId,@CaseId,st.FormVersionId,st.FieldKey,st.StorageKey,st.OriginalFileName,st.MimeType,
 st.FileSizeBytes,st.Sha256,'Clean',@ActorUserId
 FROM files.StagedDocuments st JOIN @IntakeFiles r ON r.StageId=st.StageId;
 INSERT work.CaseFormAnswers(CaseId,FormVersionId,AnswersJson,SubmittedBy)
 VALUES(@CaseId,@FormVersionId,@IntakeJson,@ActorUserId);
 IF @LodgementOperationId IS NOT NULL
 BEGIN
  INSERT integration.Executions(ProjectId,CaseId,OperationId,IdempotencyKey,Status,AttemptCount,StartedAt,FinishedAt,MappedFieldsJson)
   VALUES(@ProjectId,@CaseId,@LodgementOperationId,@IdempotencyKey,'Succeeded',1,SYSUTCDATETIME(),SYSUTCDATETIME(),@LodgementMappedJson);
  INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
   VALUES(@CaseId,'IntegrationSucceeded',N'Approved case-type data source executed during lodgement',@ActorUserId);
 END;
 INSERT work.Instances(InstanceId,CaseId,WorkflowVersionId) VALUES(@InstanceId,@CaseId,@WorkflowVersionId);
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId) VALUES(@CaseId,'Created',N'Case lodged',@ActorUserId);
 EXEC notify.usp_QueueConfiguredEvent 'CASE_CREATED',@ProjectId,@CaseId,@RecipientUserId=@ActorUserId;
 EXEC work.usp_ReindexCaseFields @CaseId;
 DECLARE @StartNodeId BIGINT=(SELECT NodeId FROM flow.Nodes WHERE WorkflowVersionId=@WorkflowVersionId AND NodeType='start');
 IF @StartNodeId IS NULL BEGIN ROLLBACK; THROW 50168,'Published workflow has no start node.',1; END;
 EXEC work.usp_ActivateNode @InstanceId,@StartNodeId,@ActorUserId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Case',@EntityId=@CaseId,@ActionCode='Create';
 COMMIT;
 SELECT @CaseId AS CaseId,@ReferenceNo AS ReferenceNo,Status FROM work.Cases WHERE CaseId=@CaseId;
END;
GO

IF USER_ID(N'workflow_app_v2') IS NOT NULL GRANT EXECUTE ON OBJECT::auth.usp_CreatePlatformAdminUser TO [workflow_app_v2];
GO
