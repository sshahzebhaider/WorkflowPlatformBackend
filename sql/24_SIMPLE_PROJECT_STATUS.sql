/*
  24 - Simple project status lifecycle, UAT (QA/testing) <-> Live.
  Works after the earlier application schema; can be applied whether or not migration 22 was run.
  Non-destructive: retains old release tables/history and all cases/teams/forms.
  The status in core.Projects is now the authoritative operational state.
*/
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'core.Projects', N'U') IS NULL
    THROW 50850, 'core.Projects is missing. Install the platform schema first.', 1;
GO
/* Preserve legacy Draft/Suspended/Archived values for preexisting records, but new onboarding uses UAT. */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE parent_object_id=OBJECT_ID(N'core.Projects') AND name='CK_Projects_Status')
    ALTER TABLE core.Projects DROP CONSTRAINT CK_Projects_Status;
GO
ALTER TABLE core.Projects WITH CHECK ADD CONSTRAINT CK_Projects_Status
    CHECK (Status IN ('Draft','UAT','Live','Suspended','Archived'));
GO
DECLARE @DefaultName SYSNAME, @DropStatusDefaultSql NVARCHAR(MAX);
SELECT @DefaultName=d.name FROM sys.default_constraints AS d
JOIN sys.columns AS c ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
WHERE d.parent_object_id=OBJECT_ID(N'core.Projects') AND c.name='Status';
IF @DefaultName IS NOT NULL
BEGIN
    SET @DropStatusDefaultSql=N'ALTER TABLE core.Projects DROP CONSTRAINT '+QUOTENAME(@DefaultName)+N';';
    EXEC sys.sp_executesql @DropStatusDefaultSql;
END;
ALTER TABLE core.Projects ADD CONSTRAINT DF_Projects_Status_UAT DEFAULT ('UAT') FOR Status;
GO
IF OBJECT_ID(N'core.ProjectStatusHistory',N'U') IS NULL
BEGIN
    CREATE TABLE core.ProjectStatusHistory (
        StatusChangeId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProjectStatusHistory PRIMARY KEY,
        ProjectId BIGINT NOT NULL CONSTRAINT FK_ProjectStatusHistory_Project
            REFERENCES core.Projects(ProjectId),
        FromStatus VARCHAR(20) NULL,
        ToStatus VARCHAR(20) NOT NULL,
        Description NVARCHAR(1000) NULL,
        ChangedBy BIGINT NOT NULL CONSTRAINT FK_ProjectStatusHistory_User REFERENCES auth.Users(UserId),
        ChangedAt DATETIME2(3) NOT NULL CONSTRAINT DF_ProjectStatusHistory_ChangedAt DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_ProjectStatusHistory_To CHECK (ToStatus IN ('UAT','Live'))
    );
    CREATE INDEX IX_ProjectStatusHistory_Project ON core.ProjectStatusHistory(ProjectId,StatusChangeId DESC);
END;
GO
/* Update onboarding atomically, retaining initial teams, access grants, terminology and RCA. */
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
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50021,'Project code must contain only A-Z, 0-9 and underscore.',1;
 IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL THROW 50022,'Project name is required.',1;
 IF @DefaultSlaMinutes<0 THROW 50023,'Invalid SLA minutes.',1;
 IF @AdminIdsJson IS NULL OR ISJSON(@AdminIdsJson)<>1 OR LEFT(LTRIM(@AdminIdsJson),1)<>'[' THROW 50024,'AdminIdsJson must be an array.',1;
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
 INSERT core.Projects(ProjectId,Code,Name,Description,OwnerUserId,CalendarId,DefaultSlaMinutes,ReferencePrefix,TemplateCode,Status,RcaRequired,RcaTemplateId)
 VALUES(@ProjectId,@Code,@Name,@Description,@OwnerUserId,@CalendarId,@DefaultSlaMinutes,LEFT(@Code,20),@TemplateCode,'UAT',@RcaRequired,@RcaTemplateId);
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
 INSERT INTO core.ProjectStatusHistory(ProjectId,FromStatus,ToStatus,Description,ChangedBy)
 VALUES(@ProjectId,NULL,'UAT',NULL,@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Project',@EntityId=@ProjectId,@ActionCode='OnboardProject';
 COMMIT;
 SELECT ProjectId,Code,Name,Status,CalendarId,RcaRequired FROM core.Projects WHERE ProjectId=@ProjectId;
END;
GO

/* Platform Admin only. Update actual project Status and history in the same transaction. */
CREATE OR ALTER PROCEDURE core.usp_ChangeProjectStatus
    @ActorUserId BIGINT,
    @ProjectId BIGINT,
    @TargetStatus VARCHAR(20),
    @ExpectedStatus VARCHAR(20),
    @Description NVARCHAR(1000)=NULL,
    @StatusChangeId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ActorUserId IS NULL OR auth.fn_IsAdmin(@ActorUserId,NULL) <> 1
        THROW 50851, 'Only a Platform Admin can change the project status.', 1;
    IF @TargetStatus IS NULL OR @TargetStatus NOT IN ('UAT','Live')
        THROW 50852, 'Project status must be UAT or Live.', 1;
    IF @ExpectedStatus IS NULL OR @ExpectedStatus NOT IN ('Draft','UAT','Live')
        THROW 50853, 'Specify the current project status and refresh if it changed.', 1;
    IF LEN(@Description)>1000
        THROW 50854, 'Description must be at most 1000 characters.', 1;
    SET @Description=NULLIF(LTRIM(RTRIM(@Description)),N'');

    DECLARE @CurrentStatus VARCHAR(20), @Now DATETIME2(3)=SYSUTCDATETIME();
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @CurrentStatus=p.Status
        FROM core.Projects p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.ProjectId=@ProjectId;
        IF @CurrentStatus IS NULL THROW 50855, 'Project not found.', 1;
        IF @CurrentStatus<>@ExpectedStatus
            THROW 50856, 'Project status changed since it was loaded. Refresh and retry.', 1;
        IF @CurrentStatus=@TargetStatus
            THROW 50857, 'Project is already in that status.', 1;
        IF NOT (
            (@CurrentStatus='Draft' AND @TargetStatus='UAT') OR
            (@CurrentStatus='UAT' AND @TargetStatus='Live') OR
            (@CurrentStatus='Live' AND @TargetStatus='UAT')
        ) THROW 50858, 'Invalid project status transition.', 1;

        UPDATE core.Projects SET Status=@TargetStatus, UpdatedAt=@Now WHERE ProjectId=@ProjectId;
        INSERT core.ProjectStatusHistory(ProjectId,FromStatus,ToStatus,Description,ChangedBy,ChangedAt)
        VALUES (@ProjectId,@CurrentStatus,@TargetStatus,@Description,@ActorUserId,@Now);
        SET @StatusChangeId=CONVERT(BIGINT,SCOPE_IDENTITY());
        INSERT audit.Events(ProjectId,ActorUserId,EntityType,EntityId,ActionCode,DetailsJson)
        VALUES (@ProjectId,@ActorUserId,'ProjectStatus',@StatusChangeId,'ProjectStatusChanged',
            (SELECT @CurrentStatus AS fromStatus, @TargetStatus AS toStatus,
                    @Description AS description FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
/* Fresh installations already define work.usp_CreateCase for UAT and Live in SQL 00.
   Fail if any preceding migration restored the old Live-only predicate. */
IF OBJECT_ID(N'work.usp_CreateCase', N'P') IS NULL
    THROW 50892, 'Missing work.usp_CreateCase.', 1;
IF CHARINDEX(N'p.Status IN (''UAT'',''Live'')',
             OBJECT_DEFINITION(OBJECT_ID(N'work.usp_CreateCase',N'P'))) = 0
    THROW 50902, 'The case creation procedure does not accept UAT and Live.', 1;
GO
PRINT 'PASS: UAT/Live status default, history, and case-creation predicate are installed.';
GO
