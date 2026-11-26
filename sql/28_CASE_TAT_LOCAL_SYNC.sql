/*
 Migration 28: case-level business-calendar TAT monitoring and local directory reconciliation.
 Requires 00–27 (in particular calendar calculations, directory status and notification rules).
 Non-destructive. Safe to rerun. Case due dates are already computed at creation by
 work.usp_CreateCase from core.CaseTypeVersions.SlaMinutes and project calendar.
 */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'work.Cases',N'U') IS NULL OR OBJECT_ID(N'work.CaseEvents',N'U') IS NULL
    OR OBJECT_ID(N'auth.Users',N'U') IS NULL
    THROW 50880,'Required base tables are missing. Install the existing platform first.',1;
GO
IF OBJECT_ID(N'work.CaseTatBreaches',N'U') IS NULL
BEGIN
  CREATE TABLE work.CaseTatBreaches (
      CaseId BIGINT NOT NULL CONSTRAINT PK_CaseTatBreaches PRIMARY KEY
        REFERENCES work.Cases(CaseId),
      ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
      DueAtUtc DATETIME2(3) NOT NULL,
      BreachedAtUtc DATETIME2(3) NOT NULL CONSTRAINT DF_CaseTatBreaches_At DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_CaseTatBreaches_Project ON work.CaseTatBreaches(ProjectId,BreachedAtUtc DESC);
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Cases_TatDue'
              AND object_id=OBJECT_ID(N'work.Cases'))
    CREATE INDEX IX_Cases_TatDue ON work.Cases(DueAt,CaseId)
      INCLUDE(ProjectId,CreatedBy,Status)
      WHERE ClosedAt IS NULL AND DueAt IS NOT NULL;
GO
CREATE OR ALTER PROCEDURE work.usp_RecordCaseTatBreaches
    @BatchSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @BatchSize NOT BETWEEN 1 AND 200 THROW 50881,'Invalid TAT batch size.',1;
    DECLARE @Due TABLE(CaseId BIGINT PRIMARY KEY,ProjectId BIGINT,DueAt DATETIME2(3),CreatedBy BIGINT);
    BEGIN TRAN;
      INSERT @Due(CaseId,ProjectId,DueAt,CreatedBy)
      SELECT TOP (@BatchSize) c.CaseId,c.ProjectId,c.DueAt,c.CreatedBy
      FROM work.Cases c WITH (UPDLOCK,READPAST,ROWLOCK)
      WHERE c.ClosedAt IS NULL AND c.Status NOT IN('Closed','Rejected','Cancelled')
        AND c.DueAt IS NOT NULL AND c.DueAt <= SYSUTCDATETIME()
        AND NOT EXISTS(SELECT 1 FROM work.CaseTatBreaches b WHERE b.CaseId=c.CaseId)
      ORDER BY c.DueAt,c.CaseId;

      INSERT work.CaseTatBreaches(CaseId,ProjectId,DueAtUtc)
      SELECT CaseId,ProjectId,DueAt FROM @Due;

      INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
      SELECT d.CaseId,'CaseTatBreached',N'Case TAT / SLA breached',
         (SELECT d.DueAt AS dueAtUtc FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
      FROM @Due d;

      INSERT audit.Events(ProjectId,EntityType,EntityId,ActionCode,DetailsJson)
      SELECT d.ProjectId,'Case',d.CaseId,'TAT_BREACHED',
         (SELECT d.DueAt AS dueAtUtc FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
      FROM @Due d;
    COMMIT;
    -- Notification rules are optional; do not auto-close or auto-approve a case.
    DECLARE @ProjectId BIGINT,@CaseId BIGINT,@CreatedBy BIGINT;
    DECLARE breachCursor CURSOR LOCAL FAST_FORWARD FOR
      SELECT ProjectId,CaseId,CreatedBy FROM @Due WHERE CreatedBy IS NOT NULL;
    OPEN breachCursor;
    FETCH NEXT FROM breachCursor INTO @ProjectId,@CaseId,@CreatedBy;
    WHILE @@FETCH_STATUS=0
    BEGIN
      BEGIN TRY
        EXEC notify.usp_QueueConfiguredEvent @EventCode='SLA_BREACHED',
          @ProjectId=@ProjectId,@CaseId=@CaseId,@RecipientUserId=@CreatedBy;
      END TRY
      BEGIN CATCH
        -- Preserve durable breach events; a notification configuration error
        -- should be logged and retried by an operator, never roll back the breach.
        DECLARE @Message NVARCHAR(800)=LEFT(ERROR_MESSAGE(),800);
        INSERT audit.Events(ProjectId,EntityType,EntityId,ActionCode,DetailsJson)
        VALUES(@ProjectId,'Case',@CaseId,'TAT_NOTIFICATION_FAILED',
          (SELECT @Message AS error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
      END CATCH;
      FETCH NEXT FROM breachCursor INTO @ProjectId,@CaseId,@CreatedBy;
    END;
    CLOSE breachCursor;
    DEALLOCATE breachCursor;
    SELECT COUNT(*) AS RecordedBreaches FROM @Due;
END;
GO
CREATE OR ALTER PROCEDURE auth.usp_ReconcileLocalDirectory
    @ActorUserId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF ISNULL(auth.fn_IsAdmin(@ActorUserId,NULL),0)<>1
      THROW 50882,'Only a Platform Admin can reconcile the local directory.',1;
    DECLARE @ResignedUsers INT=0,@RolesRevoked INT=0,@MembershipsRevoked INT=0,
            @OpenTasksUnassigned INT=0,@AbsencesRevoked INT=0;
    BEGIN TRAN;
      SELECT @ResignedUsers=COUNT(*) FROM auth.Users WITH(UPDLOCK,HOLDLOCK)
      WHERE DirectoryStatus='Resigned';
      UPDATE auth.Users SET IsActive=0,UpdatedAt=SYSUTCDATETIME()
      WHERE DirectoryStatus='Resigned' AND IsActive=1;

      UPDATE ra SET IsActive=0
      FROM auth.RoleAssignments ra JOIN auth.Users u ON u.UserId=ra.UserId
      WHERE u.DirectoryStatus='Resigned' AND ra.IsActive=1;
      SET @RolesRevoked=@@ROWCOUNT;

      UPDATE m SET IsActive=0
      FROM teams.Members m JOIN auth.Users u ON u.UserId=m.UserId
      WHERE u.DirectoryStatus='Resigned' AND m.IsActive=1;
      SET @MembershipsRevoked=@@ROWCOUNT;

      UPDATE a SET IsActive=0 FROM teams.Absences a
      WHERE a.IsActive=1 AND EXISTS(SELECT 1 FROM auth.Users u
        WHERE u.DirectoryStatus='Resigned' AND u.UserId IN(a.UserId,a.BackupUserId));
      SET @AbsencesRevoked=@@ROWCOUNT;

      DECLARE @Requeued TABLE(TaskId BIGINT PRIMARY KEY,InstanceId BIGINT,PreviousAssignee BIGINT);
      UPDATE t SET AssignedTo=NULL,DelegatedFor=NULL,RoutingStage='Unassigned'
        OUTPUT inserted.TaskId,inserted.InstanceId,deleted.AssignedTo
        INTO @Requeued(TaskId,InstanceId,PreviousAssignee)
      FROM work.Tasks t
      WHERE t.Status='Open' AND EXISTS(SELECT 1 FROM auth.Users u
        WHERE u.DirectoryStatus='Resigned' AND u.UserId IN(t.AssignedTo,t.DelegatedFor));
      SET @OpenTasksUnassigned=@@ROWCOUNT;
      INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
      SELECT i.CaseId,'TaskRequeuedAfterResignation',
         N'Open task returned to queue after staff resignation',@ActorUserId,
         (SELECT q.TaskId AS taskId,q.PreviousAssignee AS previousAssignee FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)
      FROM @Requeued q JOIN work.Instances i ON i.InstanceId=q.InstanceId;

      DECLARE @DetailsJson NVARCHAR(MAX)=(SELECT @ResignedUsers AS resignedUsers,
        @RolesRevoked AS rolesRevoked,@MembershipsRevoked AS membershipsRevoked,
        @OpenTasksUnassigned AS openTasksUnassigned,@AbsencesRevoked AS absencesRevoked
        FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
      EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='LocalDirectory',
        @ActionCode='ReconciledResignedUsers',@DetailsJson=@DetailsJson;
    COMMIT;
    SELECT @ResignedUsers AS resignedUsers,@RolesRevoked AS rolesRevoked,
      @MembershipsRevoked AS membershipsRevoked,
      @OpenTasksUnassigned AS openTasksUnassigned,@AbsencesRevoked AS absencesRevoked;
END;
GO

/* RCA field descriptions and conditions must survive SQL round-trips. */
IF COL_LENGTH(N'core.RcaTemplateFields',N'Description') IS NULL
    ALTER TABLE core.RcaTemplateFields ADD Description NVARCHAR(500) NULL;
GO
CREATE OR ALTER PROCEDURE core.usp_SaveRcaTemplate
    @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,
    @FieldsJson NVARCHAR(MAX),@RcaTemplateId BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;SET XACT_ABORT ON;
    IF ISNULL(auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage'),0)<>1
        THROW 50890,'Platform Admin required.',1;
    IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL
        THROW 50891,'Template name required.',1;
    IF @FieldsJson IS NULL OR ISJSON(@FieldsJson)<>1 OR LEFT(LTRIM(@FieldsJson),1)<>'['
        THROW 50892,'RCA fields must be an array.',1;
    IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
    IF core.fn_IsCode(@Code)<>1 THROW 50893,'Invalid RCA template code.',1;
    IF EXISTS(SELECT JSON_VALUE(value,'$.key') FROM OPENJSON(@FieldsJson)
      GROUP BY JSON_VALUE(value,'$.key') HAVING COUNT(*)>1)
      THROW 50894,'RCA field keys must be unique.',1;
    IF EXISTS(SELECT 1 FROM OPENJSON(@FieldsJson) j
      WHERE JSON_VALUE(j.value,'$.key') IS NULL OR JSON_VALUE(j.value,'$.label') IS NULL
        OR JSON_VALUE(j.value,'$.type') NOT IN('select','number','toggle','text','textarea','date'))
      THROW 50895,'Invalid RCA field definition.',1;
    BEGIN TRAN;
       IF @RcaTemplateId IS NULL
       BEGIN
         SET @RcaTemplateId=NEXT VALUE FOR core.Seq_RcaTemplates;
         INSERT core.RcaTemplates(RcaTemplateId,Code,Name)
         VALUES(@RcaTemplateId,@Code,@Name);
       END
       ELSE
       BEGIN
         IF NOT EXISTS(SELECT 1 FROM core.RcaTemplates WHERE RcaTemplateId=@RcaTemplateId)
            THROW 50896,'RCA template not found.',1;
         UPDATE core.RcaTemplates SET Name=@Name,Version=Version+1 WHERE RcaTemplateId=@RcaTemplateId;
       END;
       DELETE FROM core.RcaTemplateFields WHERE RcaTemplateId=@RcaTemplateId;
       INSERT core.RcaTemplateFields(RcaTemplateId,FieldKey,Label,FieldType,Required,
         ParentFieldKey,ParentValue,OptionsJson,SortOrder,Description)
       SELECT @RcaTemplateId,JSON_VALUE(j.value,'$.key'),JSON_VALUE(j.value,'$.label'),
         JSON_VALUE(j.value,'$.type'),
         CASE JSON_VALUE(j.value,'$.required') WHEN 'true' THEN 1 ELSE 0 END,
         JSON_VALUE(j.value,'$.parentKey'),JSON_VALUE(j.value,'$.parentValue'),
         JSON_QUERY(j.value,'$.options'),TRY_CONVERT(INT,j.[key]),
         LEFT(JSON_VALUE(j.value,'$.description'),500)
       FROM OPENJSON(@FieldsJson) j;
       EXEC audit.usp_Write @ActorUserId=@ActorUserId,
         @EntityType='RcaTemplate',@EntityId=@RcaTemplateId,@ActionCode='Save';
    COMMIT;
END;
GO
/* RCA project configuration: persist Enabled/Required separately, and fields atomically. */
IF OBJECT_ID(N'core.Projects',N'U') IS NULL
    THROW 50897,'core.Projects is missing; install base platform first.',1;
GO
-- SQL Server binds static column references at compile time, before ALTER runs.
-- Dynamic SQL compiles the backfill only AFTER the new column is created.
-- Backfill only on first introduction so reruns respect saved RCA settings.
IF COL_LENGTH(N'core.Projects',N'RcaEnabled') IS NULL
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        ALTER TABLE core.Projects ADD RcaEnabled BIT NOT NULL
           CONSTRAINT DF_Projects_RcaEnabled DEFAULT (0);
        EXEC sys.sp_executesql
            N'UPDATE core.Projects SET RcaEnabled = 1 WHERE RcaRequired = 1;';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
IF COL_LENGTH(N'core.Projects',N'RcaEnabled') IS NULL
    THROW 50898,'RcaEnabled migration did not complete.',1;
GO
CREATE OR ALTER PROCEDURE core.usp_SaveProjectRcaConfig
    @ActorUserId BIGINT,@ProjectId BIGINT,@Enabled BIT,@RequiredOnClose BIT,
    @TemplateId BIGINT=NULL,@FieldsJson NVARCHAR(MAX)=N'[]'
AS
BEGIN
    SET NOCOUNT ON;SET XACT_ABORT ON;
    IF ISNULL(auth.fn_IsAdmin(@ActorUserId,@ProjectId),0)<>1
        THROW 50884,'Project Admin required to manage RCA configuration.',1;
    IF @Enabled=0 AND @RequiredOnClose=1
        THROW 50885,'RCA cannot be required when disabled.',1;
    IF @FieldsJson IS NULL OR ISJSON(@FieldsJson)<>1 OR LEFT(LTRIM(@FieldsJson),1)<>'['
        THROW 50886,'RCA fields must be an array.',1;
    IF @TemplateId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM core.RcaTemplates
        WHERE RcaTemplateId=@TemplateId AND IsActive=1)
        THROW 50887,'RCA template is not active.',1;
    IF EXISTS(SELECT JSON_VALUE(value,'$.key') FROM OPENJSON(@FieldsJson)
      GROUP BY JSON_VALUE(value,'$.key') HAVING COUNT(*)>1)
        THROW 50888,'RCA field keys must be unique.',1;
    BEGIN TRAN;
      UPDATE core.Projects SET RcaEnabled=@Enabled,RcaRequired=@RequiredOnClose,
        RcaTemplateId=@TemplateId,UpdatedAt=SYSUTCDATETIME()
      WHERE ProjectId=@ProjectId;
      IF @@ROWCOUNT=0 THROW 50889,'Project not found.',1;
      DELETE FROM core.ProjectRcaFields WHERE ProjectId=@ProjectId;
      INSERT core.ProjectRcaFields(ProjectId,FieldKey,ConfigJson,SortOrder)
      SELECT @ProjectId,JSON_VALUE(j.value,'$.key'),j.value,CONVERT(INT,j.[key])
      FROM OPENJSON(@FieldsJson) j;
      DECLARE @Details NVARCHAR(MAX)=(SELECT @Enabled AS enabled,
       @RequiredOnClose AS requiredOnClose,@TemplateId AS templateId
       FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
      EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,
          @EntityType='ProjectRCA',@EntityId=@ProjectId,
          @ActionCode='SaveConfiguration',@DetailsJson=@Details;
    COMMIT;
END;
GO
IF USER_ID(N'workflow_app_v2') IS NOT NULL
BEGIN
    GRANT EXECUTE ON OBJECT::work.usp_RecordCaseTatBreaches TO [workflow_app_v2];
    GRANT EXECUTE ON OBJECT::auth.usp_ReconcileLocalDirectory TO [workflow_app_v2];
    GRANT EXECUTE ON OBJECT::core.usp_SaveProjectRcaConfig TO [workflow_app_v2];
END;
GO
IF COL_LENGTH(N'core.Projects',N'RcaEnabled') IS NULL OR
   OBJECT_ID(N'work.CaseTatBreaches',N'U') IS NULL OR
   OBJECT_ID(N'work.usp_RecordCaseTatBreaches',N'P') IS NULL OR
   OBJECT_ID(N'auth.usp_ReconcileLocalDirectory',N'P') IS NULL OR
   OBJECT_ID(N'core.usp_SaveProjectRcaConfig',N'P') IS NULL
    THROW 50883,'Migration 28 verification failed.',1;
PRINT 'Migration 28 installed: case TAT breach tracking and local directory reconciliation.';
GO
