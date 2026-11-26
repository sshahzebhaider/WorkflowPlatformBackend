/*
Workflow Platform database | baseline: React JSX Chunk 6 (owner/node/regex)
SQL Server 2019+; intended for SQL Server 2022 Express/Developer.
SSMS: Open this script and press F5. No DROP statements or demo projects.
Requires permissions to CREATE DATABASE, CREATE SCHEMA, TABLE, INDEX, PROCEDURE.
Do NOT run as the application's least-privilege database login.
The stored procedures assume a server-authenticated actor identity supplied by a trusted API.
*/
USE [master];
GO
IF DB_ID(N'WorkflowPlatformV2') IS NULL
    EXEC(N'CREATE DATABASE [WorkflowPlatformV2]');
GO
USE [WorkflowPlatformV2];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'auth') EXEC(N'CREATE SCHEMA [auth]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'core') EXEC(N'CREATE SCHEMA [core]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'calendar') EXEC(N'CREATE SCHEMA [calendar]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'lookup') EXEC(N'CREATE SCHEMA [lookup]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'forms') EXEC(N'CREATE SCHEMA [forms]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'flow') EXEC(N'CREATE SCHEMA [flow]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'work') EXEC(N'CREATE SCHEMA [work]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'teams') EXEC(N'CREATE SCHEMA [teams]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'integration') EXEC(N'CREATE SCHEMA [integration]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'notify') EXEC(N'CREATE SCHEMA [notify]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'reports') EXEC(N'CREATE SCHEMA [reports]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'files') EXEC(N'CREATE SCHEMA [files]');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'audit') EXEC(N'CREATE SCHEMA [audit]');
GO

-- All persistent entity identifiers are 64-bit, database-generated, monotonically increasing keys.
IF OBJECT_ID(N'auth.Seq_Users',N'SO') IS NULL EXEC(N'CREATE SEQUENCE auth.Seq_Users AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'auth.Seq_Roles',N'SO') IS NULL EXEC(N'CREATE SEQUENCE auth.Seq_Roles AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'calendar.Seq_Calendars',N'SO') IS NULL EXEC(N'CREATE SEQUENCE calendar.Seq_Calendars AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'calendar.Seq_Holidays',N'SO') IS NULL EXEC(N'CREATE SEQUENCE calendar.Seq_Holidays AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_Projects',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_Projects AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_ProjectOnboardingDrafts',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_ProjectOnboardingDrafts AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'teams.Seq_Teams',N'SO') IS NULL EXEC(N'CREATE SEQUENCE teams.Seq_Teams AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'teams.Seq_Absences',N'SO') IS NULL EXEC(N'CREATE SEQUENCE teams.Seq_Absences AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'auth.Seq_RoleAssignments',N'SO') IS NULL EXEC(N'CREATE SEQUENCE auth.Seq_RoleAssignments AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'lookup.Seq_Lists',N'SO') IS NULL EXEC(N'CREATE SEQUENCE lookup.Seq_Lists AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'lookup.Seq_Items',N'SO') IS NULL EXEC(N'CREATE SEQUENCE lookup.Seq_Items AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_RcaTemplates',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_RcaTemplates AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_RcaTemplateFields',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_RcaTemplateFields AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'integration.Seq_DataSources',N'SO') IS NULL EXEC(N'CREATE SEQUENCE integration.Seq_DataSources AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'integration.Seq_Operations',N'SO') IS NULL EXEC(N'CREATE SEQUENCE integration.Seq_Operations AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'forms.Seq_FieldLibrary',N'SO') IS NULL EXEC(N'CREATE SEQUENCE forms.Seq_FieldLibrary AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'forms.Seq_Definitions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE forms.Seq_Definitions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'forms.Seq_Versions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE forms.Seq_Versions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'forms.Seq_VersionFields',N'SO') IS NULL EXEC(N'CREATE SEQUENCE forms.Seq_VersionFields AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'flow.Seq_Definitions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE flow.Seq_Definitions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'flow.Seq_Versions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE flow.Seq_Versions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'flow.Seq_Nodes',N'SO') IS NULL EXEC(N'CREATE SEQUENCE flow.Seq_Nodes AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'flow.Seq_Edges',N'SO') IS NULL EXEC(N'CREATE SEQUENCE flow.Seq_Edges AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_CaseTypes',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_CaseTypes AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'core.Seq_CaseTypeVersions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE core.Seq_CaseTypeVersions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_Cases',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_Cases AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_Instances',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_Instances AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_Tasks',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_Tasks AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_CaseFormAnswers',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_CaseFormAnswers AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'files.Seq_Documents',N'SO') IS NULL EXEC(N'CREATE SEQUENCE files.Seq_Documents AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'notify.Seq_Templates',N'SO') IS NULL EXEC(N'CREATE SEQUENCE notify.Seq_Templates AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'notify.Seq_Rules',N'SO') IS NULL EXEC(N'CREATE SEQUENCE notify.Seq_Rules AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'notify.Seq_Outbox',N'SO') IS NULL EXEC(N'CREATE SEQUENCE notify.Seq_Outbox AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_ForceIntimations',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_ForceIntimations AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'integration.Seq_Executions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE integration.Seq_Executions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'reports.Seq_Definitions',N'SO') IS NULL EXEC(N'CREATE SEQUENCE reports.Seq_Definitions AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'reports.Seq_Runs',N'SO') IS NULL EXEC(N'CREATE SEQUENCE reports.Seq_Runs AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'work.Seq_PendingTimers',N'SO') IS NULL EXEC(N'CREATE SEQUENCE work.Seq_PendingTimers AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
GO


/* 1: Directory and role catalog. Directory sync must be performed by the API/AD connector. */
IF OBJECT_ID(N'auth.Users',N'U') IS NULL
CREATE TABLE auth.Users (
  UserId BIGINT NOT NULL CONSTRAINT PK_Users PRIMARY KEY DEFAULT (NEXT VALUE FOR auth.Seq_Users),
  ExternalDirectoryId NVARCHAR(200) NULL,
  UserName NVARCHAR(150) NOT NULL,
  DisplayName NVARCHAR(200) NOT NULL,
  Email NVARCHAR(320) NULL,
  Mobile NVARCHAR(40) NULL,
  DirectoryStatus VARCHAR(20) NOT NULL CONSTRAINT DF_Users_DirectoryStatus DEFAULT 'Active',
  IsActive BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1,
  LastDirectorySyncAt DATETIME2(3) NULL,
  CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Users_Created DEFAULT SYSUTCDATETIME(),
  UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_Users_Updated DEFAULT SYSUTCDATETIME(),
  RowVer ROWVERSION,
  CONSTRAINT CK_Users_Status CHECK(DirectoryStatus IN('Active','Resigned','Disabled','OnLeave'))
);
GO
IF OBJECT_ID(N'auth.Permissions',N'U') IS NULL
CREATE TABLE auth.Permissions (
 PermissionCode VARCHAR(90) NOT NULL CONSTRAINT PK_Permissions PRIMARY KEY,
 PermissionGroup VARCHAR(70) NOT NULL, DisplayName NVARCHAR(200) NOT NULL
);
IF OBJECT_ID(N'auth.Roles',N'U') IS NULL
CREATE TABLE auth.Roles (
 RoleId BIGINT NOT NULL CONSTRAINT PK_Roles PRIMARY KEY DEFAULT (NEXT VALUE FOR auth.Seq_Roles),
 Code VARCHAR(65) NOT NULL, Name NVARCHAR(150) NOT NULL, Description NVARCHAR(500) NULL,
 Scope VARCHAR(16) NOT NULL, IsSystem BIT NOT NULL DEFAULT 0, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_Roles_Code UNIQUE(Code),
 CONSTRAINT CK_Roles_Scope CHECK(Scope IN ('Platform','Project','Team'))
);
IF OBJECT_ID(N'auth.RolePermissions',N'U') IS NULL
CREATE TABLE auth.RolePermissions (
 RoleId BIGINT NOT NULL REFERENCES auth.Roles(RoleId),
 PermissionCode VARCHAR(90) NOT NULL REFERENCES auth.Permissions(PermissionCode),
 CONSTRAINT PK_RolePermissions PRIMARY KEY(RoleId,PermissionCode)
);
GO
/* 2: Calendars, project metadata and global configuration. */
IF OBJECT_ID(N'calendar.Calendars',N'U') IS NULL
CREATE TABLE calendar.Calendars (
 CalendarId BIGINT NOT NULL CONSTRAINT PK_Calendars PRIMARY KEY DEFAULT (NEXT VALUE FOR calendar.Seq_Calendars),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL, TimeZoneId SYSNAME NOT NULL DEFAULT N'Pakistan Standard Time',
 Description NVARCHAR(500) NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_Calendars_Code UNIQUE(Code)
);
IF OBJECT_ID(N'calendar.WorkingIntervals',N'U') IS NULL
CREATE TABLE calendar.WorkingIntervals (
 WorkingIntervalId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WorkingIntervals PRIMARY KEY,
 CalendarId BIGINT NOT NULL REFERENCES calendar.Calendars(CalendarId),
 DayOfWeek TINYINT NOT NULL, StartMinute SMALLINT NOT NULL, EndMinute SMALLINT NOT NULL,
 CONSTRAINT CK_WorkIntervals_Day CHECK(DayOfWeek BETWEEN 1 AND 7), -- 1 Monday ... 7 Sunday
 CONSTRAINT CK_WorkIntervals_Minute CHECK(StartMinute BETWEEN 0 AND 1439 AND EndMinute BETWEEN 1 AND 1440 AND StartMinute<EndMinute),
 CONSTRAINT UQ_WorkIntervals UNIQUE(CalendarId,DayOfWeek,StartMinute)
);
IF OBJECT_ID(N'calendar.Holidays',N'U') IS NULL
CREATE TABLE calendar.Holidays (
 HolidayId BIGINT NOT NULL CONSTRAINT PK_Holidays PRIMARY KEY DEFAULT (NEXT VALUE FOR calendar.Seq_Holidays),
 CalendarId BIGINT NOT NULL REFERENCES calendar.Calendars(CalendarId),
 Name NVARCHAR(180) NOT NULL, StartDate DATE NOT NULL, EndDate DATE NOT NULL,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_Holidays_Range CHECK(EndDate>=StartDate)
);
IF OBJECT_ID(N'core.Projects',N'U') IS NULL
CREATE TABLE core.Projects (
 ProjectId BIGINT NOT NULL CONSTRAINT PK_Projects PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_Projects),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(200) NOT NULL,
 Description NVARCHAR(1000) NULL,
 OwnerUserId BIGINT NULL REFERENCES auth.Users(UserId),
 CalendarId BIGINT NULL REFERENCES calendar.Calendars(CalendarId),
 DefaultSlaMinutes INT NOT NULL DEFAULT 1440,
 ReferencePrefix VARCHAR(20) NOT NULL DEFAULT 'CASE',
 TemplateCode VARCHAR(50) NOT NULL DEFAULT 'blank',
 Status VARCHAR(20) NOT NULL DEFAULT 'Draft',
 RcaRequired BIT NOT NULL DEFAULT 0,
 RcaTemplateId BIGINT NULL, -- FK added after RCA templates
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 RowVer ROWVERSION,
 CONSTRAINT UQ_Projects_Code UNIQUE(Code),
 CONSTRAINT CK_Projects_Status CHECK(Status IN('Draft','Live','Suspended','Archived')),
 CONSTRAINT CK_Projects_SLA CHECK(DefaultSlaMinutes>=0)
);
IF OBJECT_ID(N'core.ProjectTerminology',N'U') IS NULL
CREATE TABLE core.ProjectTerminology (
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 TermKey VARCHAR(75) NOT NULL, TermValue NVARCHAR(200) NOT NULL,
 CONSTRAINT PK_ProjectTerminology PRIMARY KEY(ProjectId,TermKey)
);
IF OBJECT_ID(N'core.ProjectSequence',N'U') IS NULL
CREATE TABLE core.ProjectSequence (
 ProjectId BIGINT NOT NULL CONSTRAINT PK_ProjectSequence PRIMARY KEY REFERENCES core.Projects(ProjectId),
 LastNumber BIGINT NOT NULL DEFAULT 0
);
IF OBJECT_ID(N'core.ProjectOnboardingDrafts',N'U') IS NULL
CREATE TABLE core.ProjectOnboardingDrafts (
 DraftId BIGINT NOT NULL CONSTRAINT PK_ProjectDrafts PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_ProjectOnboardingDrafts),
 CreatedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 DraftJson NVARCHAR(MAX) NOT NULL, UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_ProjectDrafts_JSON CHECK(ISJSON(DraftJson)=1)
);
GO
/* 3: Teams and roles scoped to projects and teams. */
IF OBJECT_ID(N'teams.Teams',N'U') IS NULL
CREATE TABLE teams.Teams (
 TeamId BIGINT NOT NULL CONSTRAINT PK_Teams PRIMARY KEY DEFAULT (NEXT VALUE FOR teams.Seq_Teams),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL, Description NVARCHAR(500) NULL,
 IsActive BIT NOT NULL DEFAULT 1, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_Teams_Project_Code UNIQUE(ProjectId,Code),
 CONSTRAINT UQ_Teams_IdProject UNIQUE(TeamId,ProjectId)
);
IF OBJECT_ID(N'teams.Members',N'U') IS NULL
CREATE TABLE teams.Members (
 TeamId BIGINT NOT NULL REFERENCES teams.Teams(TeamId),
 UserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 TeamRole VARCHAR(20) NOT NULL,
 IsActive BIT NOT NULL DEFAULT 1, JoinedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT PK_TeamMembers PRIMARY KEY(TeamId,UserId,TeamRole),
 CONSTRAINT CK_TeamMembers_Role CHECK(TeamRole IN('UnitHead','TeamLead','Officer'))
);
IF OBJECT_ID(N'teams.Absences',N'U') IS NULL
CREATE TABLE teams.Absences (
 AbsenceId BIGINT NOT NULL CONSTRAINT PK_Absences PRIMARY KEY DEFAULT (NEXT VALUE FOR teams.Seq_Absences),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 TeamId BIGINT NOT NULL,
 UserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 BackupUserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 StartDate DATE NOT NULL, EndDate DATE NOT NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT FK_Absences_TeamProject FOREIGN KEY(TeamId,ProjectId) REFERENCES teams.Teams(TeamId,ProjectId),
 CONSTRAINT CK_Absences_Dates CHECK(StartDate<=EndDate),
 CONSTRAINT CK_Absences_Backup CHECK(UserId<>BackupUserId)
);
IF OBJECT_ID(N'auth.RoleAssignments',N'U') IS NULL
CREATE TABLE auth.RoleAssignments (
 AssignmentId BIGINT NOT NULL CONSTRAINT PK_RoleAssignments PRIMARY KEY DEFAULT (NEXT VALUE FOR auth.Seq_RoleAssignments),
 UserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 RoleId BIGINT NOT NULL REFERENCES auth.Roles(RoleId),
 ProjectId BIGINT NULL REFERENCES core.Projects(ProjectId),
 TeamId BIGINT NULL REFERENCES teams.Teams(TeamId),
 IsActive BIT NOT NULL DEFAULT 1, AssignedBy BIGINT NULL REFERENCES auth.Users(UserId),
 AssignedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_RoleAssignments_Scope CHECK(TeamId IS NULL OR ProjectId IS NOT NULL)
);
GO
/* 4: Lookup Manager including global/project scope, list parent and item parent. */
IF OBJECT_ID(N'lookup.Lists',N'U') IS NULL
CREATE TABLE lookup.Lists (
 ListId BIGINT NOT NULL CONSTRAINT PK_LookupLists PRIMARY KEY DEFAULT (NEXT VALUE FOR lookup.Seq_Lists),
 ProjectId BIGINT NULL REFERENCES core.Projects(ProjectId),
 Scope VARCHAR(10) NOT NULL, ParentListId BIGINT NULL REFERENCES lookup.Lists(ListId),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_LookupLists_Scope CHECK((Scope='Global' AND ProjectId IS NULL) OR (Scope='Project' AND ProjectId IS NOT NULL)),
 CONSTRAINT CK_LookupLists_Parent CHECK(ParentListId IS NULL OR ParentListId<>ListId)
);
IF OBJECT_ID(N'lookup.Items',N'U') IS NULL
CREATE TABLE lookup.Items (
 ItemId BIGINT NOT NULL CONSTRAINT PK_LookupItems PRIMARY KEY DEFAULT (NEXT VALUE FOR lookup.Seq_Items),
 ListId BIGINT NOT NULL REFERENCES lookup.Lists(ListId),
 ParentItemId BIGINT NULL REFERENCES lookup.Items(ItemId),
 Code VARCHAR(100) NOT NULL, Label NVARCHAR(240) NOT NULL,
 SortOrder INT NOT NULL DEFAULT 0, IsActive BIT NOT NULL DEFAULT 1,
 MetadataJson NVARCHAR(MAX) NULL, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_LookupItems_ListCode UNIQUE(ListId,Code),
 CONSTRAINT CK_LookupItems_Meta CHECK(MetadataJson IS NULL OR ISJSON(MetadataJson)=1)
);
IF OBJECT_ID(N'lookup.ProjectLists',N'U') IS NULL
CREATE TABLE lookup.ProjectLists (
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 ListId BIGINT NOT NULL REFERENCES lookup.Lists(ListId),
 CONSTRAINT PK_ProjectLists PRIMARY KEY(ProjectId,ListId)
);
GO
/* 5: Reusable RCA templates and project settings. */
IF OBJECT_ID(N'core.RcaTemplates',N'U') IS NULL
CREATE TABLE core.RcaTemplates (
 RcaTemplateId BIGINT NOT NULL CONSTRAINT PK_RcaTemplates PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_RcaTemplates),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL,
 Description NVARCHAR(500) NULL, IsActive BIT NOT NULL DEFAULT 1,
 Version INT NOT NULL DEFAULT 1, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_RcaTemplates_Code UNIQUE(Code)
);
IF OBJECT_ID(N'core.RcaTemplateFields',N'U') IS NULL
CREATE TABLE core.RcaTemplateFields (
 RcaFieldId BIGINT NOT NULL CONSTRAINT PK_RcaTemplateFields PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_RcaTemplateFields),
 RcaTemplateId BIGINT NOT NULL REFERENCES core.RcaTemplates(RcaTemplateId),
 FieldKey VARCHAR(90) NOT NULL, Label NVARCHAR(180) NOT NULL,
 FieldType VARCHAR(20) NOT NULL, Required BIT NOT NULL DEFAULT 0,
 ParentFieldKey VARCHAR(90) NULL, ParentValue NVARCHAR(150) NULL,
 OptionsJson NVARCHAR(MAX) NULL, SortOrder INT NOT NULL DEFAULT 0,
 CONSTRAINT UQ_RcaTemplate_Field UNIQUE(RcaTemplateId,FieldKey),
 CONSTRAINT CK_RcaField_Type CHECK(FieldType IN('select','number','toggle','text','textarea','date')),
 CONSTRAINT CK_RcaField_Options CHECK(OptionsJson IS NULL OR ISJSON(OptionsJson)=1)
);
IF OBJECT_ID(N'core.ProjectRcaFields',N'U') IS NULL
CREATE TABLE core.ProjectRcaFields (
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 FieldKey VARCHAR(90) NOT NULL,
 ConfigJson NVARCHAR(MAX) NOT NULL,
 SortOrder INT NOT NULL DEFAULT 0,
 CONSTRAINT PK_ProjectRcaFields PRIMARY KEY(ProjectId,FieldKey),
 CONSTRAINT CK_ProjectRcaFields_JSON CHECK(ISJSON(ConfigJson)=1)
);
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Projects_RcaTemplate')
 ALTER TABLE core.Projects ADD CONSTRAINT FK_Projects_RcaTemplate FOREIGN KEY(RcaTemplateId) REFERENCES core.RcaTemplates(RcaTemplateId);
GO
/* 6: Data source registry and integration operations: no credentials stored as plaintext. */
IF OBJECT_ID(N'integration.DataSources',N'U') IS NULL
CREATE TABLE integration.DataSources (
 DataSourceId BIGINT NOT NULL CONSTRAINT PK_DataSources PRIMARY KEY DEFAULT (NEXT VALUE FOR integration.Seq_DataSources),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL, Kind VARCHAR(20) NOT NULL DEFAULT 'REST',
 BaseUrl NVARCHAR(1000) NULL, CredentialSecretRef NVARCHAR(400) NULL,
 Description NVARCHAR(700) NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_DataSources_Code UNIQUE(Code),
 CONSTRAINT CK_DataSources_Kind CHECK(Kind IN('REST','SOAP','DATABASE','CUSTOM'))
);
IF OBJECT_ID(N'integration.Operations',N'U') IS NULL
CREATE TABLE integration.Operations (
 OperationId BIGINT NOT NULL CONSTRAINT PK_Operations PRIMARY KEY DEFAULT (NEXT VALUE FOR integration.Seq_Operations),
 DataSourceId BIGINT NOT NULL REFERENCES integration.DataSources(DataSourceId),
 Code VARCHAR(75) NOT NULL, Name NVARCHAR(160) NOT NULL,
 HttpMethod VARCHAR(12) NOT NULL DEFAULT 'GET', UrlPath NVARCHAR(1000) NOT NULL DEFAULT N'/',
 RequestTemplateJson NVARCHAR(MAX) NULL, ResponseMapJson NVARCHAR(MAX) NULL,
 HeaderTemplateJson NVARCHAR(MAX) NULL, RequestParamsJson NVARCHAR(MAX) NULL, TimeoutSeconds INT NOT NULL DEFAULT 30,
 IsActive BIT NOT NULL DEFAULT 1,
 CONSTRAINT UQ_Operations_SourceCode UNIQUE(DataSourceId,Code),
 CONSTRAINT CK_Operations_Method CHECK(HttpMethod IN('GET','POST','PUT','PATCH','DELETE')),
 CONSTRAINT CK_Operations_Timeout CHECK(TimeoutSeconds BETWEEN 1 AND 120),
 CONSTRAINT CK_Operations_Request CHECK(RequestTemplateJson IS NULL OR ISJSON(RequestTemplateJson)=1),
 CONSTRAINT CK_Operations_Response CHECK(ResponseMapJson IS NULL OR ISJSON(ResponseMapJson)=1),
 CONSTRAINT CK_Operations_Headers CHECK(HeaderTemplateJson IS NULL OR ISJSON(HeaderTemplateJson)=1),
 CONSTRAINT CK_Operations_Params CHECK(RequestParamsJson IS NULL OR ISJSON(RequestParamsJson)=1)
);
IF COL_LENGTH('integration.Operations','RequestParamsJson') IS NULL
 ALTER TABLE integration.Operations ADD RequestParamsJson NVARCHAR(MAX) NULL;
IF OBJECT_ID(N'integration.ProjectDataSources',N'U') IS NULL
CREATE TABLE integration.ProjectDataSources (
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 DataSourceId BIGINT NOT NULL REFERENCES integration.DataSources(DataSourceId),
 CONSTRAINT PK_ProjectDataSources PRIMARY KEY(ProjectId,DataSourceId)
);
GO
/* 7: Reusable fields, form definitions, immutable published form versions. */
IF OBJECT_ID(N'forms.FieldLibrary',N'U') IS NULL
CREATE TABLE forms.FieldLibrary (
 LibraryFieldId BIGINT NOT NULL CONSTRAINT PK_FieldLibrary PRIMARY KEY DEFAULT (NEXT VALUE FOR forms.Seq_FieldLibrary),
 ProjectId BIGINT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(90) NOT NULL, Label NVARCHAR(200) NOT NULL, FieldType VARCHAR(25) NOT NULL,
 DefaultConfigJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}', IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_Library_Config CHECK(ISJSON(DefaultConfigJson)=1),
 CONSTRAINT CK_Library_Type CHECK(FieldType IN('text','textarea','number','date','select','checkbox','email','attachment'))
);
IF OBJECT_ID(N'forms.Definitions',N'U') IS NULL
CREATE TABLE forms.Definitions (
 FormId BIGINT NOT NULL CONSTRAINT PK_FormDefinitions PRIMARY KEY DEFAULT (NEXT VALUE FOR forms.Seq_Definitions),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(90) NOT NULL, Name NVARCHAR(200) NOT NULL, Description NVARCHAR(700) NULL,
 DraftJson NVARCHAR(MAX) NOT NULL DEFAULT N'{"fields":[]}', LiveVersionId BIGINT NULL,
 IsActive BIT NOT NULL DEFAULT 1, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), RowVer ROWVERSION,
 CONSTRAINT UQ_Forms_ProjectCode UNIQUE(ProjectId,Code),
 CONSTRAINT CK_Forms_Draft CHECK(ISJSON(DraftJson)=1)
);
IF OBJECT_ID(N'forms.Versions',N'U') IS NULL
CREATE TABLE forms.Versions (
 FormVersionId BIGINT NOT NULL CONSTRAINT PK_FormVersions PRIMARY KEY DEFAULT (NEXT VALUE FOR forms.Seq_Versions),
 FormId BIGINT NOT NULL REFERENCES forms.Definitions(FormId),
 VersionNumber INT NOT NULL, DefinitionJson NVARCHAR(MAX) NOT NULL,
 PublishedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), PublishedBy BIGINT NULL REFERENCES auth.Users(UserId),
 CONSTRAINT UQ_FormVersion_Number UNIQUE(FormId,VersionNumber),
 CONSTRAINT CK_FormVersion_Json CHECK(ISJSON(DefinitionJson)=1)
);
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Form_LiveVersion')
 ALTER TABLE forms.Definitions ADD CONSTRAINT FK_Form_LiveVersion FOREIGN KEY(LiveVersionId) REFERENCES forms.Versions(FormVersionId);
IF OBJECT_ID(N'forms.VersionFields',N'U') IS NULL
CREATE TABLE forms.VersionFields (
 FieldId BIGINT NOT NULL CONSTRAINT PK_FormVersionFields PRIMARY KEY DEFAULT (NEXT VALUE FOR forms.Seq_VersionFields),
 FormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 LibraryFieldId BIGINT NULL REFERENCES forms.FieldLibrary(LibraryFieldId),
 FieldKey VARCHAR(100) NOT NULL, Label NVARCHAR(200) NOT NULL,
 FieldType VARCHAR(25) NOT NULL, IsRequired BIT NOT NULL DEFAULT 0,
 LookupListId BIGINT NULL REFERENCES lookup.Lists(ListId),
 ParentFieldKey VARCHAR(100) NULL,
 RegexPattern NVARCHAR(800) NULL, RegexMessage NVARCHAR(240) NULL,
 MaxFiles SMALLINT NULL, MaxFileMB SMALLINT NULL, AllowedExtensions NVARCHAR(300) NULL,
 IsSearchable BIT NOT NULL DEFAULT 0, SortOrder INT NOT NULL DEFAULT 0,
 ConfigJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 CONSTRAINT UQ_FormField_Key UNIQUE(FormVersionId,FieldKey),
 CONSTRAINT CK_FormField_Type CHECK(FieldType IN('text','textarea','number','date','select','checkbox','email','attachment')),
 CONSTRAINT CK_FormField_Attach CHECK((MaxFiles IS NULL OR MaxFiles BETWEEN 1 AND 10) AND (MaxFileMB IS NULL OR MaxFileMB BETWEEN 1 AND 20)),
 CONSTRAINT CK_FormField_Config CHECK(ISJSON(ConfigJson)=1)
);
GO
/* 8: Workflow graph definitions/versions. The API executes the graph, SQL stores durable state. */
IF OBJECT_ID(N'flow.Definitions',N'U') IS NULL
CREATE TABLE flow.Definitions (
 WorkflowId BIGINT NOT NULL CONSTRAINT PK_WorkflowDefinitions PRIMARY KEY DEFAULT (NEXT VALUE FOR flow.Seq_Definitions),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(90) NOT NULL, Name NVARCHAR(200) NOT NULL,
 DraftGraphJson NVARCHAR(MAX) NOT NULL DEFAULT N'{"nodes":[],"edges":[]}',
 LiveVersionId BIGINT NULL,
 IsActive BIT NOT NULL DEFAULT 1, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), RowVer ROWVERSION,
 CONSTRAINT UQ_Workflows_ProjectCode UNIQUE(ProjectId,Code),
 CONSTRAINT CK_Workflow_Draft CHECK(ISJSON(DraftGraphJson)=1)
);
IF OBJECT_ID(N'flow.Versions',N'U') IS NULL
CREATE TABLE flow.Versions (
 WorkflowVersionId BIGINT NOT NULL CONSTRAINT PK_WorkflowVersions PRIMARY KEY DEFAULT (NEXT VALUE FOR flow.Seq_Versions),
 WorkflowId BIGINT NOT NULL REFERENCES flow.Definitions(WorkflowId),
 VersionNumber INT NOT NULL, GraphJson NVARCHAR(MAX) NOT NULL,
 PublishedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), PublishedBy BIGINT NULL REFERENCES auth.Users(UserId),
 CONSTRAINT UQ_WorkflowVersion_Number UNIQUE(WorkflowId,VersionNumber),
 CONSTRAINT CK_WorkflowVersion_Json CHECK(ISJSON(GraphJson)=1)
);
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Workflow_LiveVersion')
 ALTER TABLE flow.Definitions ADD CONSTRAINT FK_Workflow_LiveVersion FOREIGN KEY(LiveVersionId) REFERENCES flow.Versions(WorkflowVersionId);
IF OBJECT_ID(N'flow.Nodes',N'U') IS NULL
CREATE TABLE flow.Nodes (
 NodeId BIGINT NOT NULL CONSTRAINT PK_FlowNodes PRIMARY KEY DEFAULT (NEXT VALUE FOR flow.Seq_Nodes),
 WorkflowVersionId BIGINT NOT NULL REFERENCES flow.Versions(WorkflowVersionId),
 NodeKey VARCHAR(120) NOT NULL, NodeType VARCHAR(30) NOT NULL, Label NVARCHAR(200) NOT NULL,
 TeamId BIGINT NULL REFERENCES teams.Teams(TeamId),
 AssignmentMode VARCHAR(20) NOT NULL DEFAULT 'Hierarchy',
 AssignedRole VARCHAR(20) NULL, SlaMinutes INT NULL,
 EscalationRole VARCHAR(50) NULL,
 RequireForm BIT NOT NULL DEFAULT 0, AllowedActionsJson NVARCHAR(MAX) NULL,
 ConfigJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 CONSTRAINT UQ_FlowNode_VersionKey UNIQUE(WorkflowVersionId,NodeKey),
 CONSTRAINT UQ_FlowNode_VersionId UNIQUE(WorkflowVersionId,NodeId),
 CONSTRAINT CK_FlowNode_Type CHECK(NodeType IN('start','end','task','officerRouting','requestInfo','groupReview','decision','parallel','wait','dataSource','notify')),
 CONSTRAINT CK_FlowNode_Mode CHECK(AssignmentMode IN('Hierarchy','Direct','RoleQueue')),
 CONSTRAINT CK_FlowNode_Actions CHECK(AllowedActionsJson IS NULL OR ISJSON(AllowedActionsJson)=1),
 CONSTRAINT CK_FlowNode_Config CHECK(ISJSON(ConfigJson)=1)
);
IF OBJECT_ID(N'flow.Edges',N'U') IS NULL
CREATE TABLE flow.Edges (
 EdgeId BIGINT NOT NULL CONSTRAINT PK_FlowEdges PRIMARY KEY DEFAULT (NEXT VALUE FOR flow.Seq_Edges),
 WorkflowVersionId BIGINT NOT NULL REFERENCES flow.Versions(WorkflowVersionId),
 SourceNodeId BIGINT NOT NULL, TargetNodeId BIGINT NOT NULL,
 OutcomeCode VARCHAR(60) NULL, SortOrder INT NOT NULL DEFAULT 0,
 CONSTRAINT FK_FlowEdge_Source FOREIGN KEY(WorkflowVersionId,SourceNodeId) REFERENCES flow.Nodes(WorkflowVersionId,NodeId),
 CONSTRAINT FK_FlowEdge_Target FOREIGN KEY(WorkflowVersionId,TargetNodeId) REFERENCES flow.Nodes(WorkflowVersionId,NodeId),
 CONSTRAINT CK_FlowEdge_Different CHECK(SourceNodeId<>TargetNodeId)
);
IF OBJECT_ID(N'flow.NodeForms',N'U') IS NULL
CREATE TABLE flow.NodeForms (
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 FormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 CONSTRAINT PK_NodeForms PRIMARY KEY(NodeId,FormVersionId)
);
GO
/* 9: Project-specific case/request types and immutable published versions. */
IF OBJECT_ID(N'core.CaseTypes',N'U') IS NULL
CREATE TABLE core.CaseTypes (
 CaseTypeId BIGINT NOT NULL CONSTRAINT PK_CaseTypes PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_CaseTypes),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(90) NOT NULL, Name NVARCHAR(200) NOT NULL,
 Description NVARCHAR(700) NULL,
 DraftJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 LiveVersionId BIGINT NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_CaseTypes_ProjectCode UNIQUE(ProjectId,Code),
 CONSTRAINT CK_CaseType_Draft CHECK(ISJSON(DraftJson)=1)
);
IF OBJECT_ID(N'core.CaseTypeVersions',N'U') IS NULL
CREATE TABLE core.CaseTypeVersions (
 CaseTypeVersionId BIGINT NOT NULL CONSTRAINT PK_CaseTypeVersions PRIMARY KEY DEFAULT (NEXT VALUE FOR core.Seq_CaseTypeVersions),
 CaseTypeId BIGINT NOT NULL REFERENCES core.CaseTypes(CaseTypeId),
 VersionNumber INT NOT NULL,
 IntakeFormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 WorkflowVersionId BIGINT NOT NULL REFERENCES flow.Versions(WorkflowVersionId),
 SubjectFieldKey VARCHAR(100) NULL, SlaMinutes INT NULL, AllowDuplicate BIT NOT NULL DEFAULT 0,
 PublishedConfigJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 PublishedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_CaseTypeVersion_Number UNIQUE(CaseTypeId,VersionNumber),
 CONSTRAINT CK_CaseTypeVersion_JSON CHECK(ISJSON(PublishedConfigJson)=1)
);
IF NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_CaseType_LiveVersion')
 ALTER TABLE core.CaseTypes ADD CONSTRAINT FK_CaseType_LiveVersion FOREIGN KEY(LiveVersionId) REFERENCES core.CaseTypeVersions(CaseTypeVersionId);
IF OBJECT_ID(N'core.CaseTypeLookups',N'U') IS NULL
CREATE TABLE core.CaseTypeLookups (
 CaseTypeVersionId BIGINT NOT NULL REFERENCES core.CaseTypeVersions(CaseTypeVersionId),
 ListId BIGINT NOT NULL REFERENCES lookup.Lists(ListId),
 IsRequired BIT NOT NULL DEFAULT 0, LockedItemId BIGINT NULL REFERENCES lookup.Items(ItemId),
 SortOrder INT NOT NULL DEFAULT 0,
 CONSTRAINT PK_CaseTypeLookups PRIMARY KEY(CaseTypeVersionId,ListId)
);
GO
/* 10: Cases, durable workflow execution state and high-volume indexable values. */
IF OBJECT_ID(N'work.Cases',N'U') IS NULL
CREATE TABLE work.Cases (
 CaseRowId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cases PRIMARY KEY CLUSTERED,
 CaseId BIGINT NOT NULL CONSTRAINT UQ_Cases_CaseId UNIQUE NONCLUSTERED DEFAULT (NEXT VALUE FOR work.Seq_Cases),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseTypeVersionId BIGINT NOT NULL REFERENCES core.CaseTypeVersions(CaseTypeVersionId),
 WorkflowVersionId BIGINT NOT NULL REFERENCES flow.Versions(WorkflowVersionId),
 ReferenceNo NVARCHAR(55) NOT NULL,
 Title NVARCHAR(300) NULL, SubjectValue NVARCHAR(250) NULL,
 SubjectHash VARBINARY(32) NULL, -- hash for duplicate lookup; avoid using raw CNIC as an index
 Status VARCHAR(30) NOT NULL DEFAULT 'Open',
 Priority VARCHAR(12) NOT NULL DEFAULT 'Normal',
 IntakeJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 CurrentValuesJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 ClassificationJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 IntegrationValuesJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 CreatedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), UpdatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 ClosedAt DATETIME2(3) NULL, DueAt DATETIME2(3) NULL,
 IdempotencyKey VARCHAR(120) NULL, RowVer ROWVERSION,
 CONSTRAINT UQ_Cases_ProjectReference UNIQUE(ProjectId,ReferenceNo),
 CONSTRAINT CK_Cases_Status CHECK(Status IN('Open','In progress','Waiting','Waiting for information','Waiting for integration','Integration failed','Pending RCA','Closed','Rejected','Cancelled')),
 CONSTRAINT CK_Cases_Priority CHECK(Priority IN('Normal','High','Urgent')),
 CONSTRAINT CK_Cases_Json CHECK(ISJSON(IntakeJson)=1 AND ISJSON(CurrentValuesJson)=1 AND ISJSON(ClassificationJson)=1 AND ISJSON(IntegrationValuesJson)=1)
);
IF OBJECT_ID(N'work.CaseFieldIndex',N'U') IS NULL
CREATE TABLE work.CaseFieldIndex (
 CaseId BIGINT NOT NULL REFERENCES work.Cases(CaseId),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 FieldKey VARCHAR(100) NOT NULL,
 ValueText NVARCHAR(450) NULL, ValueNumber DECIMAL(20,4) NULL,
 ValueDate DATE NULL, LookupItemId BIGINT NULL REFERENCES lookup.Items(ItemId),
 CONSTRAINT PK_CaseFieldIndex PRIMARY KEY(CaseId,FieldKey)
);
IF OBJECT_ID(N'work.Instances',N'U') IS NULL
CREATE TABLE work.Instances (
 InstanceId BIGINT NOT NULL CONSTRAINT PK_Instances PRIMARY KEY DEFAULT (NEXT VALUE FOR work.Seq_Instances),
 CaseId BIGINT NOT NULL REFERENCES work.Cases(CaseId),
 WorkflowVersionId BIGINT NOT NULL REFERENCES flow.Versions(WorkflowVersionId),
 Status VARCHAR(20) NOT NULL DEFAULT 'Running',
 StartedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), CompletedAt DATETIME2(3) NULL,
 RowVer ROWVERSION,
 CONSTRAINT UQ_Instances_Case UNIQUE(CaseId),
 CONSTRAINT CK_Instances_Status CHECK(Status IN('Running','Waiting','Completed','Failed','Cancelled'))
);
IF OBJECT_ID(N'work.Tasks',N'U') IS NULL
CREATE TABLE work.Tasks (
 TaskId BIGINT NOT NULL CONSTRAINT PK_Tasks PRIMARY KEY DEFAULT (NEXT VALUE FOR work.Seq_Tasks),
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 TeamId BIGINT NULL REFERENCES teams.Teams(TeamId),
 AssignedTo BIGINT NULL REFERENCES auth.Users(UserId),
 DelegatedFor BIGINT NULL REFERENCES auth.Users(UserId),
 RoutingStage VARCHAR(15) NOT NULL DEFAULT 'Unassigned',
 Status VARCHAR(20) NOT NULL DEFAULT 'Open', Priority VARCHAR(12) NOT NULL DEFAULT 'Normal',
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), DueAt DATETIME2(3) NULL,
 AssignedAt DATETIME2(3) NULL, CompletedAt DATETIME2(3) NULL,
 CompletedBy BIGINT NULL REFERENCES auth.Users(UserId),
 ActionCode VARCHAR(60) NULL, ActionValuesJson NVARCHAR(MAX) NULL,
 RowVer ROWVERSION,
 CONSTRAINT CK_Tasks_Status CHECK(Status IN('Open','Completed','Cancelled')),
 CONSTRAINT CK_Tasks_Stage CHECK(RoutingStage IN('UnitHead','TeamLead','Officer','Unassigned')),
 CONSTRAINT CK_Tasks_Priority CHECK(Priority IN('Normal','High','Urgent')),
 CONSTRAINT CK_Tasks_Answers CHECK(ActionValuesJson IS NULL OR ISJSON(ActionValuesJson)=1)
);
IF OBJECT_ID(N'work.TaskHandoffs',N'U') IS NULL
CREATE TABLE work.TaskHandoffs (
 HandoffId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TaskHandoffs PRIMARY KEY,
 TaskId BIGINT NOT NULL REFERENCES work.Tasks(TaskId),
 FromUserId BIGINT NULL REFERENCES auth.Users(UserId),
 ToUserId BIGINT NULL REFERENCES auth.Users(UserId),
 RoutingStage VARCHAR(15) NOT NULL, ActorUserId BIGINT NULL REFERENCES auth.Users(UserId),
 Reason NVARCHAR(500) NULL, CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
IF OBJECT_ID(N'work.CaseFormAnswers',N'U') IS NULL
CREATE TABLE work.CaseFormAnswers (
 AnswerId BIGINT NOT NULL CONSTRAINT PK_CaseFormAnswers PRIMARY KEY DEFAULT (NEXT VALUE FOR work.Seq_CaseFormAnswers),
 CaseId BIGINT NOT NULL REFERENCES work.Cases(CaseId),
 FormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 TaskId BIGINT NULL REFERENCES work.Tasks(TaskId),
 AnswersJson NVARCHAR(MAX) NOT NULL, SubmittedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 SubmittedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_CaseFormAnswers_Json CHECK(ISJSON(AnswersJson)=1)
);
IF OBJECT_ID(N'work.CaseEvents',N'U') IS NULL
CREATE TABLE work.CaseEvents (
 EventId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CaseEvents PRIMARY KEY,
 CaseId BIGINT NOT NULL REFERENCES work.Cases(CaseId),
 EventType VARCHAR(60) NOT NULL, Message NVARCHAR(800) NOT NULL,
 ActorUserId BIGINT NULL REFERENCES auth.Users(UserId),
 DetailsJson NVARCHAR(MAX) NULL, OccurredAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_CaseEvents_Json CHECK(DetailsJson IS NULL OR ISJSON(DetailsJson)=1)
);
IF OBJECT_ID(N'work.CaseRca',N'U') IS NULL
CREATE TABLE work.CaseRca (
 CaseId BIGINT NOT NULL CONSTRAINT PK_CaseRca PRIMARY KEY REFERENCES work.Cases(CaseId),
 TemplateId BIGINT NULL REFERENCES core.RcaTemplates(RcaTemplateId),
 RootReasonItemId BIGINT NULL REFERENCES lookup.Items(ItemId),
 Summary NVARCHAR(MAX) NOT NULL,
 FieldsJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}', FormAnswersJson NVARCHAR(MAX) NULL,
 CompletedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 CompletedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_CaseRca_Json CHECK(ISJSON(FieldsJson)=1 AND (FormAnswersJson IS NULL OR ISJSON(FormAnswersJson)=1))
);
GO
/* 11: Attachments store secure object-storage references, not blobs in SQL or browser localStorage. */
IF OBJECT_ID(N'files.Documents',N'U') IS NULL
CREATE TABLE files.Documents (
 DocumentId BIGINT NOT NULL CONSTRAINT PK_Documents PRIMARY KEY DEFAULT (NEXT VALUE FOR files.Seq_Documents),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseId BIGINT NULL REFERENCES work.Cases(CaseId),
 TaskId BIGINT NULL REFERENCES work.Tasks(TaskId),
 FormVersionId BIGINT NULL REFERENCES forms.Versions(FormVersionId),
 FieldKey VARCHAR(100) NULL,
 StorageKey NVARCHAR(600) NOT NULL, OriginalFileName NVARCHAR(260) NOT NULL,
 MimeType NVARCHAR(120) NOT NULL, FileSizeBytes BIGINT NOT NULL, Sha256 VARBINARY(32) NULL,
 ScanStatus VARCHAR(20) NOT NULL DEFAULT 'Pending',
 UploadedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 UploadedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), IsDeleted BIT NOT NULL DEFAULT 0,
 CONSTRAINT CK_Docs_Size CHECK(FileSizeBytes>0),
 CONSTRAINT CK_Docs_Scan CHECK(ScanStatus IN('Pending','Clean','Rejected'))
);
GO
/* Case intake attachments are scanned before creating a case and consumed atomically. */
IF OBJECT_ID(N'files.Seq_StagedDocuments',N'SO') IS NULL EXEC(N'CREATE SEQUENCE files.Seq_StagedDocuments AS BIGINT START WITH 1 INCREMENT BY 1 CACHE 50');
IF OBJECT_ID(N'files.StagedDocuments',N'U') IS NULL
CREATE TABLE files.StagedDocuments (
 StageId BIGINT NOT NULL CONSTRAINT PK_StagedDocuments PRIMARY KEY DEFAULT (NEXT VALUE FOR files.Seq_StagedDocuments),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseTypeId BIGINT NOT NULL REFERENCES core.CaseTypes(CaseTypeId),
 FormVersionId BIGINT NOT NULL REFERENCES forms.Versions(FormVersionId),
 ActorUserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 FieldKey VARCHAR(100) NOT NULL,
 StorageKey NVARCHAR(600) NOT NULL,OriginalFileName NVARCHAR(260) NOT NULL,
 MimeType NVARCHAR(120) NOT NULL,FileSizeBytes BIGINT NOT NULL,Sha256 VARBINARY(32) NOT NULL,
 ScannedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 ExpiresAt DATETIME2(3) NOT NULL DEFAULT DATEADD(HOUR,2,SYSUTCDATETIME()),
 ConsumedCaseId BIGINT NULL REFERENCES work.Cases(CaseId),ConsumedAt DATETIME2(3) NULL
);
GO
/* 12: Notifications and auditable escalations. Delivery must happen in an API background worker. */
IF OBJECT_ID(N'notify.Templates',N'U') IS NULL
CREATE TABLE notify.Templates (
 TemplateId BIGINT NOT NULL CONSTRAINT PK_NotificationTemplates PRIMARY KEY DEFAULT (NEXT VALUE FOR notify.Seq_Templates),
 ProjectId BIGINT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(85) NOT NULL, Name NVARCHAR(180) NOT NULL,
 Channel VARCHAR(15) NOT NULL, LanguageCode VARCHAR(5) NOT NULL DEFAULT 'en',
 SubjectTemplate NVARCHAR(300) NULL, BodyTemplate NVARCHAR(MAX) NOT NULL,
 IsActive BIT NOT NULL DEFAULT 1,
 CONSTRAINT CK_Notify_Channel CHECK(Channel IN('Email','SMS','InApp')),
 CONSTRAINT CK_Notify_Language CHECK(LanguageCode IN('en','ur'))
);
IF OBJECT_ID(N'notify.Rules',N'U') IS NULL
CREATE TABLE notify.Rules (
 RuleId BIGINT NOT NULL CONSTRAINT PK_NotifyRules PRIMARY KEY DEFAULT (NEXT VALUE FOR notify.Seq_Rules),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 EventCode VARCHAR(65) NOT NULL, TemplateId BIGINT NOT NULL REFERENCES notify.Templates(TemplateId),
 IsEnabled BIT NOT NULL DEFAULT 1, RecipientRuleJson NVARCHAR(MAX) NOT NULL DEFAULT N'{}',
 CONSTRAINT CK_NotifyRules_Json CHECK(ISJSON(RecipientRuleJson)=1)
);
IF OBJECT_ID(N'notify.Outbox',N'U') IS NULL
CREATE TABLE notify.Outbox (
 NotificationId BIGINT NOT NULL CONSTRAINT PK_NotifyOutbox PRIMARY KEY DEFAULT (NEXT VALUE FOR notify.Seq_Outbox),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseId BIGINT NULL REFERENCES work.Cases(CaseId),
 TaskId BIGINT NULL REFERENCES work.Tasks(TaskId),
 TemplateId BIGINT NULL REFERENCES notify.Templates(TemplateId),
 Channel VARCHAR(15) NOT NULL, LanguageCode VARCHAR(5) NOT NULL DEFAULT 'en',
 RecipientUserId BIGINT NULL REFERENCES auth.Users(UserId),
 RecipientAddress NVARCHAR(320) NULL, PayloadJson NVARCHAR(MAX) NOT NULL,
 State VARCHAR(20) NOT NULL DEFAULT 'Pending',
 Attempts INT NOT NULL DEFAULT 0, NextAttemptAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 LastError NVARCHAR(800) NULL, ProviderMessageId NVARCHAR(200) NULL,
 IdempotencyKey VARCHAR(150) NULL,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), SentAt DATETIME2(3) NULL,
 CONSTRAINT CK_Outbox_State CHECK(State IN('Pending','Sending','Accepted','Delivered','Failed','Cancelled','Preview')),
 CONSTRAINT CK_Outbox_Payload CHECK(ISJSON(PayloadJson)=1),
 CONSTRAINT CK_Outbox_Channel CHECK(Channel IN('Email','SMS','InApp'))
);
IF OBJECT_ID(N'notify.DeliveryAttempts',N'U') IS NULL
CREATE TABLE notify.DeliveryAttempts (
 DeliveryAttemptId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DeliveryAttempts PRIMARY KEY,
 NotificationId BIGINT NOT NULL REFERENCES notify.Outbox(NotificationId),
 AttemptedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 Outcome VARCHAR(20) NOT NULL, HttpStatus INT NULL, ProviderResponse NVARCHAR(1000) NULL
);
IF OBJECT_ID(N'work.ForceIntimations',N'U') IS NULL
CREATE TABLE work.ForceIntimations (
 ForceIntimationId BIGINT NOT NULL CONSTRAINT PK_ForceIntimations PRIMARY KEY DEFAULT (NEXT VALUE FOR work.Seq_ForceIntimations),
 TaskId BIGINT NOT NULL REFERENCES work.Tasks(TaskId),
 ManagerUserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 TargetUserId BIGINT NOT NULL REFERENCES auth.Users(UserId),
 NewPriority VARCHAR(12) NOT NULL, Reason NVARCHAR(1000) NOT NULL,
 NotificationId BIGINT NULL REFERENCES notify.Outbox(NotificationId),
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_Force_Priority CHECK(NewPriority IN('High','Urgent'))
);
GO
/* Concurrency-controlled parallel joins and durable notification-node mapping. */
IF OBJECT_ID(N'work.ParallelJoins',N'U') IS NULL
CREATE TABLE work.ParallelJoins(
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 Resumed BIT NOT NULL DEFAULT 0, ResumedAt DATETIME2(3) NULL,
 CONSTRAINT PK_ParallelJoins PRIMARY KEY(InstanceId,NodeId));
IF OBJECT_ID(N'work.ParallelArrivals',N'U') IS NULL
CREATE TABLE work.ParallelArrivals(
 InstanceId BIGINT NOT NULL,JoinNodeId BIGINT NOT NULL,SourceNodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 ArrivedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT PK_ParallelArrivals PRIMARY KEY(InstanceId,JoinNodeId,SourceNodeId),
 CONSTRAINT FK_ParallelArrivals_Joins FOREIGN KEY(InstanceId,JoinNodeId)
 REFERENCES work.ParallelJoins(InstanceId,NodeId));
IF OBJECT_ID(N'work.SystemNotifications',N'U') IS NULL
CREATE TABLE work.SystemNotifications(
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 NotificationId BIGINT NOT NULL REFERENCES notify.Outbox(NotificationId),
 ResumedAt DATETIME2(3) NULL,
 CONSTRAINT PK_SystemNotifications PRIMARY KEY(InstanceId,NodeId),
 CONSTRAINT UQ_SystemNotifications_Notification UNIQUE(NotificationId));
GO
/* One escalation per task; no automatic approval of a human task. */
IF OBJECT_ID(N'work.SlaEscalations',N'U') IS NULL
CREATE TABLE work.SlaEscalations(
 TaskId BIGINT NOT NULL CONSTRAINT PK_SlaEscalations PRIMARY KEY REFERENCES work.Tasks(TaskId),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 EscalatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 NotificationId BIGINT NULL REFERENCES notify.Outbox(NotificationId));
GO
/* Template-driven notification rule expansion. Called only within audited case/task transactions. */
CREATE OR ALTER PROCEDURE notify.usp_QueueConfiguredEvent
 @EventCode VARCHAR(65),@ProjectId BIGINT,@CaseId BIGINT,@TaskId BIGINT=NULL,
 @RecipientUserId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @EventCode NOT IN('CASE_CREATED','TASK_ASSIGNED','SLA_BREACHED','WORKFLOW_COMPLETED','CASE_CLOSED') RETURN;
 DECLARE @Ref NVARCHAR(55),@Title NVARCHAR(300),@Creator BIGINT;
 SELECT @Ref=ReferenceNo,@Title=Title,@Creator=CreatedBy FROM work.Cases
 WHERE CaseId=@CaseId AND ProjectId=@ProjectId;
 IF @Ref IS NULL RETURN;
 IF @RecipientUserId IS NULL AND @EventCode IN('TASK_ASSIGNED','SLA_BREACHED') RETURN;
 IF @RecipientUserId IS NULL SET @RecipientUserId=@Creator;
 IF @RecipientUserId IS NULL RETURN;
 INSERT notify.Outbox(ProjectId,CaseId,TaskId,TemplateId,Channel,LanguageCode,
  RecipientUserId,RecipientAddress,PayloadJson,IdempotencyKey)
 SELECT @ProjectId,@CaseId,@TaskId,t.TemplateId,t.Channel,t.LanguageCode,@RecipientUserId,
  CASE WHEN t.Channel='Email' THEN u.Email WHEN t.Channel='SMS' THEN u.Mobile END,
  (SELECT REPLACE(REPLACE(ISNULL(t.SubjectTemplate,N'Workflow notification'),N'{{reference}}',@Ref),N'{{title}}',@Title) AS subject,
    REPLACE(REPLACE(t.BodyTemplate,N'{{reference}}',@Ref),N'{{title}}',@Title) AS body FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
  CONCAT('rule:',CONVERT(VARCHAR(25),r.RuleId),':',@EventCode,':',CONVERT(VARCHAR(25),@CaseId),':',ISNULL(CONVERT(VARCHAR(25),@TaskId),'0'))
 FROM notify.Rules r JOIN notify.Templates t ON t.TemplateId=r.TemplateId AND t.IsActive=1
 JOIN auth.Users u ON u.UserId=@RecipientUserId AND u.IsActive=1
 WHERE r.ProjectId=@ProjectId AND r.EventCode=@EventCode AND r.IsEnabled=1
 AND (t.Channel='InApp' OR t.Channel='Email' AND NULLIF(u.Email,N'') IS NOT NULL
 OR t.Channel='SMS' AND NULLIF(u.Mobile,N'') IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM notify.Outbox existing WITH(UPDLOCK,HOLDLOCK)
 WHERE existing.IdempotencyKey=CONCAT('rule:',CONVERT(VARCHAR(25),r.RuleId),':',@EventCode,':',CONVERT(VARCHAR(25),@CaseId),':',ISNULL(CONVERT(VARCHAR(25),@TaskId),'0')));
END;
GO
/* 13: Data-source execution logging, reporting, durable global audit. */
IF OBJECT_ID(N'integration.Executions',N'U') IS NULL
CREATE TABLE integration.Executions (
 ExecutionId BIGINT NOT NULL CONSTRAINT PK_IntegrationExec PRIMARY KEY DEFAULT (NEXT VALUE FOR integration.Seq_Executions),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 CaseId BIGINT NULL REFERENCES work.Cases(CaseId),
 NodeId BIGINT NULL REFERENCES flow.Nodes(NodeId),
 OperationId BIGINT NOT NULL REFERENCES integration.Operations(OperationId),
 IdempotencyKey VARCHAR(140) NULL, Status VARCHAR(20) NOT NULL DEFAULT 'Pending',
 AttemptCount INT NOT NULL DEFAULT 0, StartedAt DATETIME2(3) NULL, FinishedAt DATETIME2(3) NULL,
 RequestRedactedJson NVARCHAR(MAX) NULL, ResponseRedactedJson NVARCHAR(MAX) NULL, MappedFieldsJson NVARCHAR(MAX) NULL,
 LastError NVARCHAR(1000) NULL,
 CONSTRAINT CK_Exec_Status CHECK(Status IN('Pending','Running','Succeeded','Failed','Cancelled')),
 CONSTRAINT CK_Exec_Request CHECK(RequestRedactedJson IS NULL OR ISJSON(RequestRedactedJson)=1),
 CONSTRAINT CK_Exec_Response CHECK(ResponseRedactedJson IS NULL OR ISJSON(ResponseRedactedJson)=1),
 CONSTRAINT CK_Exec_Mapped CHECK(MappedFieldsJson IS NULL OR ISJSON(MappedFieldsJson)=1)
);
/* Exactly-once continuation marker for a successful system-node operation. */
IF COL_LENGTH(N'integration.Executions',N'ResumedAt') IS NULL
 ALTER TABLE integration.Executions ADD ResumedAt DATETIME2(3) NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Integration_Queue' AND object_id=OBJECT_ID(N'integration.Executions'))
 CREATE INDEX IX_Integration_Queue ON integration.Executions(Status,FinishedAt,StartedAt)
 INCLUDE(CaseId,NodeId,OperationId,AttemptCount,ResumedAt);
IF OBJECT_ID(N'reports.Definitions',N'U') IS NULL
CREATE TABLE reports.Definitions (
 ReportId BIGINT NOT NULL CONSTRAINT PK_Reports PRIMARY KEY DEFAULT (NEXT VALUE FOR reports.Seq_Definitions),
 ProjectId BIGINT NOT NULL REFERENCES core.Projects(ProjectId),
 Code VARCHAR(80) NOT NULL, Name NVARCHAR(200) NOT NULL,
 ConfigJson NVARCHAR(MAX) NOT NULL, IsActive BIT NOT NULL DEFAULT 1,
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT UQ_Reports_ProjectCode UNIQUE(ProjectId,Code),
 CONSTRAINT CK_Reports_Config CHECK(ISJSON(ConfigJson)=1)
);
IF OBJECT_ID(N'reports.Runs',N'U') IS NULL
CREATE TABLE reports.Runs (
 RunId BIGINT NOT NULL CONSTRAINT PK_ReportRuns PRIMARY KEY DEFAULT (NEXT VALUE FOR reports.Seq_Runs),
 ReportId BIGINT NOT NULL REFERENCES reports.Definitions(ReportId),
 RequestedBy BIGINT NOT NULL REFERENCES auth.Users(UserId),
 State VARCHAR(20) NOT NULL DEFAULT 'Pending',
 ResultStorageKey NVARCHAR(600) NULL,
 RequestedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(), FinishedAt DATETIME2(3) NULL
);
IF OBJECT_ID(N'audit.Events',N'U') IS NULL
CREATE TABLE audit.Events (
 AuditId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Audit PRIMARY KEY,
 ProjectId BIGINT NULL REFERENCES core.Projects(ProjectId),
 ActorUserId BIGINT NULL REFERENCES auth.Users(UserId),
 EntityType VARCHAR(80) NOT NULL, EntityId BIGINT NULL, ActionCode VARCHAR(80) NOT NULL,
 DetailsJson NVARCHAR(MAX) NULL, OccurredAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_Audit_Json CHECK(DetailsJson IS NULL OR ISJSON(DetailsJson)=1)
);
GO
/* 14: Key uniqueness, tenant-filtered indexes, and fast operational queries. */
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_Users_UserName' AND object_id=OBJECT_ID(N'auth.Users'))
 CREATE UNIQUE INDEX UX_Users_UserName ON auth.Users(UserName);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_Users_ExternalDirectoryId' AND object_id=OBJECT_ID(N'auth.Users'))
 CREATE UNIQUE INDEX UX_Users_ExternalDirectoryId ON auth.Users(ExternalDirectoryId) WHERE ExternalDirectoryId IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Users_DirectoryStatus' AND object_id=OBJECT_ID(N'auth.Users'))
 CREATE INDEX IX_Users_DirectoryStatus ON auth.Users(DirectoryStatus,IsActive) INCLUDE(DisplayName,Email);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_RoleAssignments_Active' AND object_id=OBJECT_ID(N'auth.RoleAssignments'))
 CREATE UNIQUE INDEX UX_RoleAssignments_Active ON auth.RoleAssignments(UserId,RoleId,ProjectId,TeamId) WHERE IsActive=1;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_RoleAssignments_ProjectUser' AND object_id=OBJECT_ID(N'auth.RoleAssignments'))
 CREATE INDEX IX_RoleAssignments_ProjectUser ON auth.RoleAssignments(ProjectId,UserId,IsActive) INCLUDE(RoleId,TeamId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Teams_Project' AND object_id=OBJECT_ID(N'teams.Teams'))
 CREATE INDEX IX_Teams_Project ON teams.Teams(ProjectId,IsActive) INCLUDE(Name);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Members_User' AND object_id=OBJECT_ID(N'teams.Members'))
 CREATE INDEX IX_Members_User ON teams.Members(UserId,IsActive,TeamId) INCLUDE(TeamRole);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Absences_Range' AND object_id=OBJECT_ID(N'teams.Absences'))
 CREATE INDEX IX_Absences_Range ON teams.Absences(ProjectId,UserId,StartDate,EndDate) INCLUDE(TeamId,BackupUserId,IsActive);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Calendar_Intervals' AND object_id=OBJECT_ID(N'calendar.WorkingIntervals'))
 CREATE INDEX IX_Calendar_Intervals ON calendar.WorkingIntervals(CalendarId,DayOfWeek,StartMinute);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Calendar_Holidays' AND object_id=OBJECT_ID(N'calendar.Holidays'))
 CREATE INDEX IX_Calendar_Holidays ON calendar.Holidays(CalendarId,StartDate,EndDate);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_GlobalLookupCode' AND object_id=OBJECT_ID(N'lookup.Lists'))
 CREATE UNIQUE INDEX UX_GlobalLookupCode ON lookup.Lists(Code) WHERE Scope='Global';
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_ProjectLookupCode' AND object_id=OBJECT_ID(N'lookup.Lists'))
 CREATE UNIQUE INDEX UX_ProjectLookupCode ON lookup.Lists(ProjectId,Code) WHERE Scope='Project';
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_LookupItems_Parent' AND object_id=OBJECT_ID(N'lookup.Items'))
 CREATE INDEX IX_LookupItems_Parent ON lookup.Items(ListId,ParentItemId,IsActive,SortOrder) INCLUDE(Code,Label);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_ProjectResources_Lookup' AND object_id=OBJECT_ID(N'lookup.ProjectLists'))
 CREATE INDEX IX_ProjectResources_Lookup ON lookup.ProjectLists(ListId,ProjectId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Library_Project' AND object_id=OBJECT_ID(N'forms.FieldLibrary'))
 CREATE INDEX IX_Library_Project ON forms.FieldLibrary(ProjectId,IsActive) INCLUDE(Code,Label,FieldType);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FormVersions_Form' AND object_id=OBJECT_ID(N'forms.Versions'))
 CREATE INDEX IX_FormVersions_Form ON forms.Versions(FormId,VersionNumber DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FormFields_Lookup' AND object_id=OBJECT_ID(N'forms.VersionFields'))
 CREATE INDEX IX_FormFields_Lookup ON forms.VersionFields(LookupListId,FormVersionId) WHERE LookupListId IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FlowVersions_Workflow' AND object_id=OBJECT_ID(N'flow.Versions'))
 CREATE INDEX IX_FlowVersions_Workflow ON flow.Versions(WorkflowId,VersionNumber DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FlowEdges_Source' AND object_id=OBJECT_ID(N'flow.Edges'))
 CREATE INDEX IX_FlowEdges_Source ON flow.Edges(WorkflowVersionId,SourceNodeId,SortOrder) INCLUDE(TargetNodeId,OutcomeCode);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_CaseTypes_Project' AND object_id=OBJECT_ID(N'core.CaseTypes'))
 CREATE INDEX IX_CaseTypes_Project ON core.CaseTypes(ProjectId,IsActive) INCLUDE(Name,LiveVersionId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Cases_ProjectStatusDate' AND object_id=OBJECT_ID(N'work.Cases'))
 CREATE INDEX IX_Cases_ProjectStatusDate ON work.Cases(ProjectId,Status,CreatedAt DESC) INCLUDE(ReferenceNo,Priority,CaseTypeVersionId,CreatedBy,DueAt);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Cases_Creator' AND object_id=OBJECT_ID(N'work.Cases'))
 CREATE INDEX IX_Cases_Creator ON work.Cases(ProjectId,CreatedBy,CreatedAt DESC) INCLUDE(Status,ReferenceNo);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Cases_SubjectHash' AND object_id=OBJECT_ID(N'work.Cases'))
 CREATE INDEX IX_Cases_SubjectHash ON work.Cases(ProjectId,CaseTypeVersionId,SubjectHash) WHERE SubjectHash IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_Cases_Idempotency' AND object_id=OBJECT_ID(N'work.Cases'))
 CREATE UNIQUE INDEX UX_Cases_Idempotency ON work.Cases(ProjectId,IdempotencyKey) WHERE IdempotencyKey IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Cases_OpenDue' AND object_id=OBJECT_ID(N'work.Cases'))
 CREATE INDEX IX_Cases_OpenDue ON work.Cases(ProjectId,DueAt) INCLUDE(ReferenceNo,Priority,Status) WHERE ClosedAt IS NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FieldIndex_Text' AND object_id=OBJECT_ID(N'work.CaseFieldIndex'))
 CREATE INDEX IX_FieldIndex_Text ON work.CaseFieldIndex(ProjectId,FieldKey,ValueText) INCLUDE(CaseId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FieldIndex_Number' AND object_id=OBJECT_ID(N'work.CaseFieldIndex'))
 CREATE INDEX IX_FieldIndex_Number ON work.CaseFieldIndex(ProjectId,FieldKey,ValueNumber) INCLUDE(CaseId) WHERE ValueNumber IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_FieldIndex_Date' AND object_id=OBJECT_ID(N'work.CaseFieldIndex'))
 CREATE INDEX IX_FieldIndex_Date ON work.CaseFieldIndex(ProjectId,FieldKey,ValueDate) INCLUDE(CaseId) WHERE ValueDate IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Tasks_AssigneeOpen' AND object_id=OBJECT_ID(N'work.Tasks'))
 CREATE INDEX IX_Tasks_AssigneeOpen ON work.Tasks(AssignedTo,Priority,DueAt,CreatedAt DESC) INCLUDE(TaskId,InstanceId,TeamId,RoutingStage) WHERE Status='Open';
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Tasks_TeamOpen' AND object_id=OBJECT_ID(N'work.Tasks'))
 CREATE INDEX IX_Tasks_TeamOpen ON work.Tasks(TeamId,CreatedAt DESC) INCLUDE(TaskId,AssignedTo,DueAt,RoutingStage) WHERE Status='Open';
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Tasks_Instance' AND object_id=OBJECT_ID(N'work.Tasks'))
 CREATE INDEX IX_Tasks_Instance ON work.Tasks(InstanceId,Status,NodeId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_TaskHandoffs_Task' AND object_id=OBJECT_ID(N'work.TaskHandoffs'))
 CREATE INDEX IX_TaskHandoffs_Task ON work.TaskHandoffs(TaskId,CreatedAt DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_CaseAnswers_Case' AND object_id=OBJECT_ID(N'work.CaseFormAnswers'))
 CREATE INDEX IX_CaseAnswers_Case ON work.CaseFormAnswers(CaseId,SubmittedAt DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_CaseEvents_Case' AND object_id=OBJECT_ID(N'work.CaseEvents'))
 CREATE INDEX IX_CaseEvents_Case ON work.CaseEvents(CaseId,OccurredAt DESC,EventId DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Documents_Case' AND object_id=OBJECT_ID(N'files.Documents'))
 CREATE INDEX IX_Documents_Case ON files.Documents(CaseId,IsDeleted,UploadedAt DESC) INCLUDE(StorageKey,OriginalFileName,MimeType,FileSizeBytes);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_Documents_StorageKey' AND object_id=OBJECT_ID(N'files.Documents'))
 CREATE UNIQUE INDEX UX_Documents_StorageKey ON files.Documents(StorageKey);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Outbox_Ready' AND object_id=OBJECT_ID(N'notify.Outbox'))
 CREATE INDEX IX_Outbox_Ready ON notify.Outbox(State,NextAttemptAt) INCLUDE(Channel,Attempts,ProjectId) WHERE State IN('Pending','Failed');
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_Outbox_Idempotency' AND object_id=OBJECT_ID(N'notify.Outbox'))
 CREATE UNIQUE INDEX UX_Outbox_Idempotency ON notify.Outbox(ProjectId,IdempotencyKey) WHERE IdempotencyKey IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_NotificationProject' AND object_id=OBJECT_ID(N'notify.Outbox'))
 CREATE INDEX IX_NotificationProject ON notify.Outbox(ProjectId,CreatedAt DESC) INCLUDE(State,Channel,CaseId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_IntegrationExecution_Key' AND object_id=OBJECT_ID(N'integration.Executions'))
 CREATE UNIQUE INDEX UX_IntegrationExecution_Key ON integration.Executions(ProjectId,IdempotencyKey) WHERE IdempotencyKey IS NOT NULL;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_IntegrationExecutions_Ready' AND object_id=OBJECT_ID(N'integration.Executions'))
 CREATE INDEX IX_IntegrationExecutions_Ready ON integration.Executions(Status,ProjectId,StartedAt) INCLUDE(OperationId,CaseId);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_ReportRuns_Requested' AND object_id=OBJECT_ID(N'reports.Runs'))
 CREATE INDEX IX_ReportRuns_Requested ON reports.Runs(ReportId,RequestedAt DESC);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Audit_ProjectTime' AND object_id=OBJECT_ID(N'audit.Events'))
 CREATE INDEX IX_Audit_ProjectTime ON audit.Events(ProjectId,OccurredAt DESC) INCLUDE(ActorUserId,EntityType,ActionCode,EntityId);
GO
/* Seed ONLY stable role/permission catalog (not projects, fake users or fake cases). */
MERGE auth.Permissions AS tgt USING (VALUES
 ('project.view','Workspace','View project'),('cases.view','Cases','View cases'),('cases.create','Cases','Create cases'),
 ('cases.manage','Cases','Process/manage cases'),('reports.view','Reports','View reports'),
 ('teams.view','Teams','View teams'),('teams.manage','Teams','Manage teams'),
 ('roles.assign','Security','Assign roles'),('settings.view','Setup','View project setup'),('settings.manage','Setup','Manage project setup'),
 ('forms.view','Setup','View forms'),('forms.manage','Setup','Design and publish forms'),
 ('workflows.view','Setup','View workflows'),('workflows.manage','Setup','Design and publish workflows'),
 ('lookups.view','Setup','View lookups'),('lookups.manage','Setup','Manage lookups'),
 ('notifications.view','Notifications','View notifications'),('notifications.manage','Notifications','Manage notification settings'),
 ('audit.view','Audit','View audit history')
) src(Code,PermissionGroup,DisplayName) ON tgt.PermissionCode=src.Code
WHEN NOT MATCHED THEN INSERT(PermissionCode,PermissionGroup,DisplayName) VALUES(src.Code,src.PermissionGroup,src.DisplayName);
GO
MERGE auth.Roles AS tgt USING (VALUES
 ('platform_admin','Platform Admin','Platform',1),('project_admin','Project Admin','Project',1),
 ('unit_head','Unit Head','Team',1),('team_lead','Team Lead','Team',1),
 ('team_member','Team Member','Team',1),('viewer','Viewer','Project',1)
) src(Code,Name,Scope,IsSystem) ON tgt.Code=src.Code
WHEN NOT MATCHED THEN INSERT(Code,Name,Scope,IsSystem) VALUES(src.Code,src.Name,src.Scope,src.IsSystem);
GO
INSERT auth.RolePermissions(RoleId,PermissionCode)
SELECT r.RoleId,p.PermissionCode FROM auth.Roles r CROSS JOIN auth.Permissions p
WHERE r.Code IN('platform_admin','project_admin')
AND NOT EXISTS(SELECT 1 FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId AND rp.PermissionCode=p.PermissionCode);
INSERT auth.RolePermissions(RoleId,PermissionCode)
SELECT r.RoleId,p.PermissionCode FROM auth.Roles r JOIN auth.Permissions p
 ON p.PermissionCode IN('project.view','cases.view','cases.create','cases.manage','reports.view','teams.view')
WHERE r.Code IN('unit_head','team_lead')
AND NOT EXISTS(SELECT 1 FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId AND rp.PermissionCode=p.PermissionCode);
INSERT auth.RolePermissions(RoleId,PermissionCode)
SELECT r.RoleId,p.PermissionCode FROM auth.Roles r JOIN auth.Permissions p
 ON p.PermissionCode IN('project.view','cases.view','cases.create','cases.manage','reports.view')
WHERE r.Code='team_member'
AND NOT EXISTS(SELECT 1 FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId AND rp.PermissionCode=p.PermissionCode);
INSERT auth.RolePermissions(RoleId,PermissionCode)
SELECT r.RoleId,p.PermissionCode FROM auth.Roles r JOIN auth.Permissions p
 ON p.PermissionCode IN('project.view','cases.view','reports.view')
WHERE r.Code='viewer'
AND NOT EXISTS(SELECT 1 FROM auth.RolePermissions rp WHERE rp.RoleId=r.RoleId AND rp.PermissionCode=p.PermissionCode);
GO
/* Common helpers: normalized auto-generated codes are expected from the API; this guards them. */
CREATE OR ALTER FUNCTION core.fn_CodeFromName(@Name NVARCHAR(200)) RETURNS VARCHAR(75) AS
BEGIN
 DECLARE @Output VARCHAR(75)='',@Text NVARCHAR(200)=UPPER(LTRIM(RTRIM(ISNULL(@Name,N'')))),
 @Index INT=1,@Character NCHAR(1);
 WHILE @Index<=LEN(@Text) AND LEN(@Output)<24
 BEGIN
  SET @Character=SUBSTRING(@Text,@Index,1);
  IF @Character COLLATE Latin1_General_BIN2 LIKE N'[A-Z0-9]'
   SET @Output=@Output+CONVERT(VARCHAR(1),@Character);
  ELSE IF LEN(@Output)>0 AND RIGHT(@Output,1)<>'_' SET @Output=@Output+'_';
  SET @Index=@Index+1;
 END;
 WHILE RIGHT(@Output,1)='_' AND LEN(@Output)>0 SET @Output=LEFT(@Output,LEN(@Output)-1);
 RETURN @Output;
END;
GO
CREATE OR ALTER FUNCTION core.fn_IsCode(@Code VARCHAR(100)) RETURNS BIT AS
BEGIN
 RETURN (CASE WHEN @Code IS NOT NULL AND LEN(@Code) BETWEEN 1 AND 100
  AND @Code NOT LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN2 THEN 1 ELSE 0 END);
END;
GO
CREATE OR ALTER FUNCTION auth.fn_HasPermission(
 @ActorUserId BIGINT,@ProjectId BIGINT,@PermissionCode VARCHAR(90))
RETURNS BIT AS
BEGIN
 DECLARE @Yes BIT=0;
 IF @ActorUserId IS NULL RETURN 0;
 IF EXISTS(SELECT 1 FROM auth.Users u WHERE u.UserId=@ActorUserId AND u.IsActive=1 AND u.DirectoryStatus<>'Resigned')
 AND EXISTS(
  SELECT 1 FROM auth.RoleAssignments a
  JOIN auth.Roles r ON r.RoleId=a.RoleId AND r.IsActive=1
  JOIN auth.RolePermissions rp ON rp.RoleId=r.RoleId AND rp.PermissionCode=@PermissionCode
  WHERE a.UserId=@ActorUserId AND a.IsActive=1
    AND (r.Scope='Platform' AND a.ProjectId IS NULL
      OR a.ProjectId=@ProjectId AND (r.Scope='Project' OR r.Scope='Team' AND a.TeamId IS NOT NULL))
 ) SET @Yes=1;
 RETURN @Yes;
END;
GO
CREATE OR ALTER FUNCTION auth.fn_IsAdmin(@ActorUserId BIGINT,@ProjectId BIGINT)
RETURNS BIT AS
BEGIN
 DECLARE @Yes BIT=0;
 IF EXISTS(
 SELECT 1 FROM auth.RoleAssignments a JOIN auth.Roles r ON r.RoleId=a.RoleId
 JOIN auth.Users u ON u.UserId=a.UserId
 WHERE a.UserId=@ActorUserId AND a.IsActive=1 AND r.IsActive=1 AND u.IsActive=1 AND u.DirectoryStatus<>'Resigned'
 AND ((r.Code='platform_admin' AND a.ProjectId IS NULL) OR (r.Code='project_admin' AND a.ProjectId=@ProjectId))
 ) SET @Yes=1;
 RETURN @Yes;
END;
GO
CREATE OR ALTER PROCEDURE audit.usp_Write
 @ActorUserId BIGINT=NULL,@ProjectId BIGINT=NULL,
 @EntityType VARCHAR(80),@EntityId BIGINT=NULL,@ActionCode VARCHAR(80),@DetailsJson NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @DetailsJson IS NOT NULL AND ISJSON(@DetailsJson)<>1 THROW 50001,'Audit details must be JSON.',1;
 INSERT audit.Events(ProjectId,ActorUserId,EntityType,EntityId,ActionCode,DetailsJson)
 VALUES(@ProjectId,@ActorUserId,@EntityType,@EntityId,@ActionCode,@DetailsJson);
END;
GO
/* 15: Directory sync ingestion and tightly controlled first administrator bootstrap. */
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
  UPDATE auth.Users SET DisplayName=@DisplayName,Email=@Email,Mobile=@Mobile,
   ExternalDirectoryId=COALESCE(@ExternalDirectoryId,ExternalDirectoryId),
   DirectoryStatus=@DirectoryStatus,IsActive=CASE WHEN @DirectoryStatus IN('Resigned','Disabled') THEN 0 ELSE 1 END,
   LastDirectorySyncAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 END;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE auth.usp_BootstrapPlatformAdmin @UserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 /* Run once manually as a SQL administrator AFTER provisioning an actual directory user. */
 DECLARE @RoleId BIGINT;
 SELECT @RoleId=RoleId FROM auth.Roles WHERE Code='platform_admin';
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@UserId AND IsActive=1 AND DirectoryStatus='Active') THROW 50012,'Bootstrap user not found/active.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM auth.RoleAssignments a WITH(UPDLOCK,HOLDLOCK)
  JOIN auth.Roles r ON r.RoleId=a.RoleId WHERE r.Code='platform_admin' AND a.IsActive=1)
  BEGIN ROLLBACK; THROW 50013,'Platform administrator already bootstrapped.',1; END;
 INSERT auth.RoleAssignments(UserId,RoleId,ProjectId,TeamId,IsActive) VALUES(@UserId,@RoleId,NULL,NULL,1);
 EXEC audit.usp_Write @ActorUserId=@UserId,@ProjectId=NULL,@EntityType='Role',@EntityId=@RoleId,@ActionCode='BootstrapPlatformAdmin';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE auth.usp_AssignRole
 @ActorUserId BIGINT,@UserId BIGINT,@RoleCode VARCHAR(65),
 @ProjectId BIGINT=NULL,@TeamId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @RoleId BIGINT,@Scope VARCHAR(16);
 SELECT @RoleId=RoleId,@Scope=Scope FROM auth.Roles WHERE Code=@RoleCode AND IsActive=1;
 IF @RoleId IS NULL THROW 50014,'Role does not exist.',1;
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@UserId AND IsActive=1 AND DirectoryStatus<>'Resigned') THROW 50015,'Target user is not active.',1;
 IF (@Scope='Platform' AND (@ProjectId IS NOT NULL OR @TeamId IS NOT NULL))
   OR (@Scope='Project' AND (@ProjectId IS NULL OR @TeamId IS NOT NULL))
   OR (@Scope='Team' AND (@ProjectId IS NULL OR @TeamId IS NULL)) THROW 50016,'Role scope mismatch.',1;
 IF @Scope='Platform' AND auth.fn_HasPermission(@ActorUserId,NULL,'roles.assign')<>1 THROW 50017,'Only a platform administrator can grant a platform role.',1;
 IF @Scope<>'Platform' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50018,'Project setup administration required.',1;
 IF @TeamId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@TeamId AND ProjectId=@ProjectId) THROW 50019,'Team is outside the project.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM auth.RoleAssignments WITH(UPDLOCK,HOLDLOCK) WHERE UserId=@UserId AND RoleId=@RoleId AND
  (ProjectId=@ProjectId OR ProjectId IS NULL AND @ProjectId IS NULL) AND (TeamId=@TeamId OR TeamId IS NULL AND @TeamId IS NULL))
  UPDATE auth.RoleAssignments SET IsActive=1,AssignedBy=@ActorUserId,AssignedAt=SYSUTCDATETIME()
  WHERE UserId=@UserId AND RoleId=@RoleId AND (ProjectId=@ProjectId OR ProjectId IS NULL AND @ProjectId IS NULL)
    AND (TeamId=@TeamId OR TeamId IS NULL AND @TeamId IS NULL);
 ELSE INSERT auth.RoleAssignments(UserId,RoleId,ProjectId,TeamId,AssignedBy)
  VALUES(@UserId,@RoleId,@ProjectId,@TeamId,@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='RoleAssignment',@EntityId=@UserId,@ActionCode='AssignRole';
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
 VALUES(@ProjectId,@Code,@Name,@Description,@OwnerUserId,@CalendarId,@DefaultSlaMinutes,LEFT(@Code,20),@TemplateCode,'Live',@RcaRequired,@RcaTemplateId);
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
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Project',@EntityId=@ProjectId,@ActionCode='OnboardProject';
 COMMIT;
 SELECT ProjectId,Code,Name,Status,CalendarId,RcaRequired FROM core.Projects WHERE ProjectId=@ProjectId;
END;
GO
CREATE OR ALTER PROCEDURE core.usp_SetTerminology
 @ActorUserId BIGINT,@ProjectId BIGINT,@TermsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50032,'Project administration required.',1;
 IF ISJSON(@TermsJson)<>1 OR LEFT(LTRIM(@TermsJson),1)<>'{' THROW 50033,'Terminology must be a JSON object.',1;
 BEGIN TRAN;
 UPDATE t SET TermValue=LEFT(j.value,200)
 FROM core.ProjectTerminology t JOIN OPENJSON(@TermsJson) j ON j.[key] COLLATE DATABASE_DEFAULT=t.TermKey
 WHERE t.ProjectId=@ProjectId AND j.[type]=1;
 INSERT core.ProjectTerminology(ProjectId,TermKey,TermValue)
 SELECT @ProjectId,j.[key],LEFT(j.value,200) FROM OPENJSON(@TermsJson) j
 WHERE j.[type]=1 AND LEN(j.[key])<=75 AND NOT EXISTS(
 SELECT 1 FROM core.ProjectTerminology t WHERE t.ProjectId=@ProjectId AND t.TermKey=j.[key] COLLATE DATABASE_DEFAULT);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Terminology',@EntityId=@ProjectId,@ActionCode='Update';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_CreateCalendar
 @ActorUserId BIGINT,@Code VARCHAR(75),@Name NVARCHAR(160),@TimeZoneId SYSNAME=N'Pakistan Standard Time',
 @CalendarId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50034,'Platform admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50035,'Invalid calendar code.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.time_zone_info WHERE name=@TimeZoneId) THROW 50036,'Invalid Windows time zone name.',1;
 SET @CalendarId=NEXT VALUE FOR calendar.Seq_Calendars;
 INSERT calendar.Calendars(CalendarId,Code,Name,TimeZoneId) VALUES(@CalendarId,@Code,@Name,@TimeZoneId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='Calendar',@EntityId=@CalendarId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_SetWorkingInterval
 @ActorUserId BIGINT,@CalendarId BIGINT,@DayOfWeek TINYINT,
 @StartMinute SMALLINT,@EndMinute SMALLINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50037,'Platform admin required.',1;
 IF @DayOfWeek NOT BETWEEN 1 AND 7 OR @StartMinute<0 OR @EndMinute>1440 OR @StartMinute>=@EndMinute
  THROW 50038,'Invalid working day/time interval.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM calendar.WorkingIntervals WITH(UPDLOCK,HOLDLOCK) WHERE CalendarId=@CalendarId AND DayOfWeek=@DayOfWeek
 AND StartMinute<@EndMinute AND EndMinute>@StartMinute)
  BEGIN ROLLBACK; THROW 50039,'Working hours overlap an existing interval.',1; END;
 INSERT calendar.WorkingIntervals(CalendarId,DayOfWeek,StartMinute,EndMinute)
 VALUES(@CalendarId,@DayOfWeek,@StartMinute,@EndMinute);
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_AddHolidayRange
 @ActorUserId BIGINT,@CalendarId BIGINT,
 @Name NVARCHAR(180),@StartDate DATE,@EndDate DATE,@HolidayId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50040,'Platform admin required.',1;
 IF @EndDate<@StartDate THROW 50041,'Holiday end date must not precede start.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM calendar.Holidays WITH(UPDLOCK,HOLDLOCK)
  WHERE CalendarId=@CalendarId AND StartDate<=@EndDate AND EndDate>=@StartDate)
  BEGIN ROLLBACK; THROW 50042,'Holiday range overlaps an existing holiday.',1; END;
 SET @HolidayId=NEXT VALUE FOR calendar.Seq_Holidays;
 INSERT calendar.Holidays(HolidayId,CalendarId,Name,StartDate,EndDate) VALUES(@HolidayId,@CalendarId,@Name,@StartDate,@EndDate);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='Holiday',@EntityId=@HolidayId,@ActionCode='AddRange';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_RemoveHolidayDate
 @ActorUserId BIGINT,@HolidayId BIGINT,@DateToRemove DATE=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50043,'Platform admin required.',1;
 DECLARE @CalendarId BIGINT,@Start DATE,@End DATE,@Name NVARCHAR(180);
 BEGIN TRAN;
 SELECT @CalendarId=CalendarId,@Start=StartDate,@End=EndDate,@Name=Name FROM calendar.Holidays WITH(UPDLOCK,HOLDLOCK) WHERE HolidayId=@HolidayId;
 IF @CalendarId IS NULL BEGIN ROLLBACK; THROW 50044,'Holiday not found.',1; END;
 IF @DateToRemove IS NULL OR (@Start=@End AND @DateToRemove=@Start)
  DELETE FROM calendar.Holidays WHERE HolidayId=@HolidayId;
 ELSE BEGIN
  IF @DateToRemove<@Start OR @DateToRemove>@End BEGIN ROLLBACK; THROW 50045,'Date is not in the selected holiday.',1; END;
  IF @DateToRemove=@Start UPDATE calendar.Holidays SET StartDate=DATEADD(DAY,1,@Start) WHERE HolidayId=@HolidayId;
  ELSE IF @DateToRemove=@End UPDATE calendar.Holidays SET EndDate=DATEADD(DAY,-1,@End) WHERE HolidayId=@HolidayId;
  ELSE BEGIN
   UPDATE calendar.Holidays SET EndDate=DATEADD(DAY,-1,@DateToRemove) WHERE HolidayId=@HolidayId;
   INSERT calendar.Holidays(CalendarId,Name,StartDate,EndDate)
   VALUES(@CalendarId,@Name,DATEADD(DAY,1,@DateToRemove),@End);
  END;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='Holiday',@EntityId=@HolidayId,@ActionCode='RemoveDateOrRange';
 COMMIT;
END;
GO
/* Calculate SLA deadlines using the selected calendar (working minutes only). Windows time-zone names. */
CREATE OR ALTER PROCEDURE calendar.usp_CalculateBusinessDueAt
 @CalendarId BIGINT,@StartAtUtc DATETIME2(3),@WorkingMinutes INT,
 @DueAtUtc DATETIME2(3) OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @TimeZone SYSNAME=(SELECT TimeZoneId FROM calendar.Calendars WHERE CalendarId=@CalendarId);
 IF @TimeZone IS NULL THROW 50046,'Calendar not found.',1;
 IF @WorkingMinutes<0 THROW 50047,'Working minutes must be >= 0.',1;
 IF @WorkingMinutes=0 BEGIN SET @DueAtUtc=@StartAtUtc; RETURN; END;
 DECLARE @Local DATETIME2(3)=CAST((@StartAtUtc AT TIME ZONE 'UTC' AT TIME ZONE @TimeZone) AS DATETIME2(3));
 DECLARE @Remaining INT=@WorkingMinutes,@Day DATE,@DayNo INT,@StartMinute SMALLINT,@EndMinute SMALLINT;
 DECLARE @WindowStart DATETIME2(3),@WindowEnd DATETIME2(3),@Available INT,@Iteration INT=0;
 WHILE @Remaining>0
 BEGIN
  SET @Iteration+=1;
  IF @Iteration>36500 THROW 50048,'Business calendar has insufficient working hours.',1;
  SET @Day=CAST(@Local AS DATE);
  SET @DayNo=(DATEDIFF(DAY,CONVERT(DATE,'19000101'),@Day)%7)+1; -- Monday=1
  IF EXISTS(SELECT 1 FROM calendar.Holidays WHERE CalendarId=@CalendarId AND StartDate<=@Day AND EndDate>=@Day)
  BEGIN SET @Local=DATEADD(DAY,1,CONVERT(DATETIME2(3),@Day)); CONTINUE; END;
  DECLARE windows CURSOR LOCAL FAST_FORWARD FOR
   SELECT StartMinute,EndMinute FROM calendar.WorkingIntervals
   WHERE CalendarId=@CalendarId AND DayOfWeek=@DayNo ORDER BY StartMinute;
  OPEN windows;
  FETCH NEXT FROM windows INTO @StartMinute,@EndMinute;
  WHILE @@FETCH_STATUS=0 AND @Remaining>0
  BEGIN
    SET @WindowStart=DATEADD(MINUTE,@StartMinute,CONVERT(DATETIME2(3),@Day));
    SET @WindowEnd=DATEADD(MINUTE,@EndMinute,CONVERT(DATETIME2(3),@Day));
    IF @Local<@WindowStart SET @Local=@WindowStart;
    IF @Local<@WindowEnd
    BEGIN
      SET @Available=DATEDIFF(MINUTE,@Local,@WindowEnd);
      IF @Available>=@Remaining
      BEGIN SET @Local=DATEADD(MINUTE,@Remaining,@Local);SET @Remaining=0; END
      ELSE BEGIN SET @Remaining-=@Available;SET @Local=@WindowEnd;END;
    END;
    FETCH NEXT FROM windows INTO @StartMinute,@EndMinute;
  END;
  CLOSE windows;DEALLOCATE windows;
  IF @Remaining>0 SET @Local=DATEADD(DAY,1,CONVERT(DATETIME2(3),@Day));
 END;
 SET @DueAtUtc=CAST((@Local AT TIME ZONE @TimeZone AT TIME ZONE 'UTC') AS DATETIME2(3));
END;
GO
CREATE OR ALTER PROCEDURE teams.usp_CreateTeam
 @ActorUserId BIGINT,@ProjectId BIGINT,@Code VARCHAR(75),@Name NVARCHAR(160),@TeamId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50050,'Project administration required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50051,'Invalid team code.',1;
 SET @TeamId=NEXT VALUE FOR teams.Seq_Teams;
 INSERT teams.Teams(TeamId,ProjectId,Code,Name) VALUES(@TeamId,@ProjectId,@Code,@Name);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Team',@EntityId=@TeamId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE teams.usp_SetMember
 @ActorUserId BIGINT,@ProjectId BIGINT,@TeamId BIGINT,
 @UserId BIGINT,@TeamRole VARCHAR(20),@IsActive BIT=1
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50052,'Project administration required.',1;
 IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@TeamId AND ProjectId=@ProjectId AND IsActive=1) THROW 50053,'Team not found in project.',1;
 IF @TeamRole NOT IN('UnitHead','TeamLead','Officer') THROW 50054,'Invalid team role.',1;
 IF @IsActive=1 AND NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@UserId AND IsActive=1 AND DirectoryStatus<>'Resigned') THROW 50055,'User is not active.',1;
 DECLARE @RoleCode VARCHAR(65)=CASE @TeamRole WHEN 'UnitHead' THEN 'unit_head' WHEN 'TeamLead' THEN 'team_lead' ELSE 'team_member' END;
 DECLARE @RoleId BIGINT=(SELECT RoleId FROM auth.Roles WHERE Code=@RoleCode);
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM teams.Members WITH(UPDLOCK,HOLDLOCK) WHERE TeamId=@TeamId AND UserId=@UserId AND TeamRole=@TeamRole)
  UPDATE teams.Members SET IsActive=@IsActive WHERE TeamId=@TeamId AND UserId=@UserId AND TeamRole=@TeamRole;
 ELSE INSERT teams.Members(TeamId,UserId,TeamRole,IsActive) VALUES(@TeamId,@UserId,@TeamRole,@IsActive);
 IF EXISTS(SELECT 1 FROM auth.RoleAssignments WHERE UserId=@UserId AND RoleId=@RoleId AND ProjectId=@ProjectId AND TeamId=@TeamId)
  UPDATE auth.RoleAssignments SET IsActive=@IsActive WHERE UserId=@UserId AND RoleId=@RoleId AND ProjectId=@ProjectId AND TeamId=@TeamId;
 ELSE IF @IsActive=1
  INSERT auth.RoleAssignments(UserId,RoleId,ProjectId,TeamId,AssignedBy) VALUES(@UserId,@RoleId,@ProjectId,@TeamId,@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='TeamMember',@EntityId=@UserId,@ActionCode='MembershipChanged';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE teams.usp_SetLeaveBackup
 @ActorUserId BIGINT,@ProjectId BIGINT,@TeamId BIGINT,
 @UserId BIGINT,@BackupUserId BIGINT,@StartDate DATE,@EndDate DATE
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @StartDate>@EndDate THROW 50056,'Leave dates are invalid.',1;
 IF @UserId=@BackupUserId THROW 50057,'Backup cannot be the same user.',1;
 IF @ActorUserId<>@UserId AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1
 AND NOT EXISTS(SELECT 1 FROM teams.Members m JOIN teams.Members actor ON actor.TeamId=m.TeamId
  WHERE m.TeamId=@TeamId AND m.UserId=@UserId AND m.IsActive=1 AND actor.UserId=@ActorUserId AND actor.IsActive=1
  AND actor.TeamRole IN('UnitHead','TeamLead')) THROW 50058,'You cannot manage this user leave.',1;
 IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@TeamId AND ProjectId=@ProjectId) THROW 50059,'Team not found.',1;
 IF NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND UserId=@UserId AND IsActive=1)
 OR NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND UserId=@BackupUserId AND IsActive=1)
  THROW 50060,'Both users must be active team members.',1;
 IF NOT EXISTS(SELECT 1 FROM auth.Users WHERE UserId=@BackupUserId AND IsActive=1 AND DirectoryStatus='Active')
  THROW 50061,'Backup directory user is not available.',1;
 IF EXISTS(SELECT 1 FROM teams.Absences WHERE ProjectId=@ProjectId AND TeamId=@TeamId AND UserId=@BackupUserId
 AND IsActive=1 AND StartDate<=@EndDate AND EndDate>=@StartDate) THROW 50062,'The backup is on leave.',1;
 BEGIN TRAN;
 UPDATE teams.Absences SET IsActive=0 WHERE ProjectId=@ProjectId AND TeamId=@TeamId AND UserId=@UserId AND IsActive=1
 AND StartDate<=@EndDate AND EndDate>=@StartDate;
 INSERT teams.Absences(ProjectId,TeamId,UserId,BackupUserId,StartDate,EndDate)
 VALUES(@ProjectId,@TeamId,@UserId,@BackupUserId,@StartDate,@EndDate);
 UPDATE work.Tasks SET AssignedTo=@BackupUserId,DelegatedFor=@UserId,AssignedAt=SYSUTCDATETIME()
 WHERE TeamId=@TeamId AND AssignedTo=@UserId AND Status='Open' AND @StartDate<=CONVERT(DATE,SYSUTCDATETIME()) AND @EndDate>=CONVERT(DATE,SYSUTCDATETIME());
 INSERT work.TaskHandoffs(TaskId,FromUserId,ToUserId,RoutingStage,ActorUserId,Reason)
 SELECT TaskId,@UserId,@BackupUserId,RoutingStage,@ActorUserId,N'Leave backup assignment'
 FROM work.Tasks WHERE TeamId=@TeamId AND DelegatedFor=@UserId AND AssignedTo=@BackupUserId AND Status='Open';
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Absence',@EntityId=@UserId,@ActionCode='BackupConfigured';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE teams.usp_ApplyResignedUser
 @ActorUserId BIGINT,@UserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50063,'Platform administrator required for directory sync.',1;
 BEGIN TRAN;
 UPDATE auth.Users SET DirectoryStatus='Resigned',IsActive=0,UpdatedAt=SYSUTCDATETIME() WHERE UserId=@UserId;
 UPDATE teams.Members SET IsActive=0 WHERE UserId=@UserId;
 UPDATE auth.RoleAssignments SET IsActive=0 WHERE UserId=@UserId;
 UPDATE teams.Absences SET IsActive=0 WHERE UserId=@UserId OR BackupUserId=@UserId;
 /* Task reassignment is explicit: do not assign a resigned person's work to an unverified user. */
 UPDATE work.Tasks SET AssignedTo=NULL,DelegatedFor=NULL,RoutingStage='Unassigned'
 WHERE Status='Open' AND (AssignedTo=@UserId OR DelegatedFor=@UserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DirectoryUser',@EntityId=@UserId,@ActionCode='ResignedAndUnassigned';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE core.usp_AllowProjectDataSource
 @ActorUserId BIGINT,@ProjectId BIGINT,@DataSourceId BIGINT,@Allowed BIT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50064,'Project admin required.',1;
 IF @Allowed=1 AND NOT EXISTS(SELECT 1 FROM integration.DataSources WHERE DataSourceId=@DataSourceId AND IsActive=1) THROW 50065,'Data source inactive.',1;
 IF @Allowed=1 AND NOT EXISTS(SELECT 1 FROM integration.ProjectDataSources WHERE ProjectId=@ProjectId AND DataSourceId=@DataSourceId)
  INSERT integration.ProjectDataSources(ProjectId,DataSourceId) VALUES(@ProjectId,@DataSourceId);
 IF @Allowed=0 DELETE FROM integration.ProjectDataSources WHERE ProjectId=@ProjectId AND DataSourceId=@DataSourceId;
END;
GO
CREATE OR ALTER PROCEDURE core.usp_AllowProjectLookup
 @ActorUserId BIGINT,@ProjectId BIGINT,@ListId BIGINT,@Allowed BIT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50066,'Project admin required.',1;
 IF @Allowed=1 AND NOT EXISTS(SELECT 1 FROM lookup.Lists WHERE ListId=@ListId AND Scope='Global' AND IsActive=1)
  THROW 50067,'Only active global lookups may be shared.',1;
 IF @Allowed=1 AND NOT EXISTS(SELECT 1 FROM lookup.ProjectLists WHERE ProjectId=@ProjectId AND ListId=@ListId)
  INSERT lookup.ProjectLists(ProjectId,ListId) VALUES(@ProjectId,@ListId);
 IF @Allowed=0 AND EXISTS(SELECT 1 FROM lookup.Lists child WHERE child.ProjectId=@ProjectId AND child.ParentListId=@ListId)
  THROW 50068,'A child lookup still depends on this shared parent.',1;
 IF @Allowed=0 DELETE FROM lookup.ProjectLists WHERE ProjectId=@ProjectId AND ListId=@ListId;
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_CreateList
 @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75),@Scope VARCHAR(10),
 @ProjectId BIGINT=NULL,@ParentListId BIGINT=NULL,@ListId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50069,'Lookup code is invalid.',1;
 IF @Scope NOT IN('Global','Project') THROW 50070,'Lookup scope is invalid.',1;
 IF @Scope='Global' AND @ProjectId IS NOT NULL OR @Scope='Project' AND @ProjectId IS NULL THROW 50071,'Lookup scope/project mismatch.',1;
 IF @Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1
  THROW 50072,'Platform administrator required.',1;
 IF @Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50073,'Project admin required.',1;
 IF @ParentListId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lookup.Lists parent WHERE parent.ListId=@ParentListId AND parent.IsActive=1
  AND (parent.Scope='Global' OR parent.ProjectId=@ProjectId)) THROW 50074,'Parent lookup is not available in this scope.',1;
 SET @ListId=NEXT VALUE FOR lookup.Seq_Lists;
 INSERT lookup.Lists(ListId,ProjectId,Scope,ParentListId,Code,Name)
 VALUES(@ListId,@ProjectId,@Scope,@ParentListId,@Code,@Name);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='LookupList',@EntityId=@ListId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_SetParentList
 @ActorUserId BIGINT,@ListId BIGINT,@ParentListId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Scope VARCHAR(10);
 SELECT @ProjectId=ProjectId,@Scope=Scope FROM lookup.Lists WHERE ListId=@ListId;
 IF @Scope IS NULL THROW 50075,'Lookup list not found.',1;
 IF @Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1
 OR @Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50076,'Lookup admin required.',1;
 IF @ParentListId=@ListId THROW 50077,'List cannot parent itself.',1;
 IF @ParentListId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lookup.Lists WHERE ListId=@ParentListId AND (Scope='Global' OR ProjectId=@ProjectId))
  THROW 50078,'Parent is not available in this project.',1;
 /* Walk upwards to prevent cycles. */
 DECLARE @Walk BIGINT=@ParentListId,@Next BIGINT,@Depth INT=0;
 WHILE @Walk IS NOT NULL
 BEGIN
  IF @Walk=@ListId THROW 50079,'Cyclic lookup relationships are not allowed.',1;
  SET @Depth+=1;IF @Depth>50 THROW 50080,'Lookup nesting is too deep.',1;
  SET @Next=(SELECT ParentListId FROM lookup.Lists WHERE ListId=@Walk);
  SET @Walk=@Next;
 END;
 BEGIN TRAN;
 UPDATE lookup.Lists SET ParentListId=@ParentListId,UpdatedAt=SYSUTCDATETIME() WHERE ListId=@ListId;
 UPDATE lookup.Items SET ParentItemId=NULL WHERE ListId=@ListId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='LookupList',@EntityId=@ListId,@ActionCode='ChangeParent';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_BulkAddItems
 @ActorUserId BIGINT,@ListId BIGINT,@ItemsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@ItemsJson)<>1 OR LEFT(LTRIM(@ItemsJson),1)<>'[' THROW 50081,'ItemsJson must be an array.',1;
 DECLARE @ProjectId BIGINT,@Scope VARCHAR(10),@ParentListId BIGINT;
 SELECT @ProjectId=ProjectId,@Scope=Scope,@ParentListId=ParentListId FROM lookup.Lists WHERE ListId=@ListId AND IsActive=1;
 IF @Scope IS NULL THROW 50082,'Lookup list not found/active.',1;
 IF @Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1
 OR @Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50083,'Lookup admin required.',1;
 DECLARE @Input TABLE(Code VARCHAR(100),Label NVARCHAR(240),ParentCode VARCHAR(100),SortOrder INT,IsActive BIT);
 INSERT @Input(Code,Label,ParentCode,SortOrder,IsActive)
 SELECT Code,Label,ParentCode,ISNULL(SortOrder,0),ISNULL(IsActive,1)
 FROM OPENJSON(@ItemsJson) WITH(Code VARCHAR(100) '$.code',Label NVARCHAR(240) '$.label',
 ParentCode VARCHAR(100) '$.parentCode',SortOrder INT '$.sortOrder',IsActive BIT '$.active');
 IF NOT EXISTS(SELECT 1 FROM @Input) OR (SELECT COUNT(1) FROM @Input)>200 THROW 50084,'Enter 1–200 items.',1;
 IF EXISTS(SELECT 1 FROM @Input WHERE core.fn_IsCode(Code)<>1 OR NULLIF(LTRIM(RTRIM(Label)),N'') IS NULL)
  THROW 50085,'Every item must have a valid code and label.',1;
 IF EXISTS(SELECT Code FROM @Input GROUP BY Code HAVING COUNT(*)>1) THROW 50086,'Duplicate codes in this batch.',1;
 IF EXISTS(SELECT 1 FROM @Input WHERE ParentCode IS NOT NULL AND @ParentListId IS NULL)
  THROW 50087,'This list has no parent lookup.',1;
 IF EXISTS(SELECT 1 FROM @Input i WHERE i.ParentCode IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM lookup.Items p WHERE p.ListId=@ParentListId AND p.Code=i.ParentCode AND p.IsActive=1))
  THROW 50088,'A parent item code is not present in the parent list.',1;
 BEGIN TRAN;
 IF EXISTS(SELECT 1 FROM @Input i JOIN lookup.Items existing WITH(UPDLOCK,HOLDLOCK)
 ON existing.ListId=@ListId AND existing.Code=i.Code)
  BEGIN ROLLBACK; THROW 50089,'An item code already exists in this list.',1; END;
 INSERT lookup.Items(ListId,ParentItemId,Code,Label,SortOrder,IsActive)
 SELECT @ListId,p.ItemId,i.Code,i.Label,i.SortOrder,i.IsActive
 FROM @Input i LEFT JOIN lookup.Items p ON p.ListId=@ParentListId AND p.Code=i.ParentCode;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='LookupList',@EntityId=@ListId,@ActionCode='BulkAddItems';
 COMMIT;
 SELECT ItemId,Code,Label,SortOrder,ParentItemId,IsActive FROM lookup.Items WHERE ListId=@ListId ORDER BY SortOrder,Label;
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_GetOptions
 @ProjectId BIGINT,@ListId BIGINT,@ParentItemId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM lookup.Lists l WHERE l.ListId=@ListId AND l.IsActive=1
  AND (l.ProjectId=@ProjectId OR l.Scope='Global' AND EXISTS(SELECT 1 FROM lookup.ProjectLists pl WHERE pl.ProjectId=@ProjectId AND pl.ListId=l.ListId)))
 THROW 50090,'Lookup is not allowed for this project.',1;
 SELECT ItemId,Code,Label,ParentItemId,SortOrder FROM lookup.Items
 WHERE ListId=@ListId AND IsActive=1 AND (@ParentItemId IS NULL AND ParentItemId IS NULL OR @ParentItemId IS NOT NULL AND ParentItemId=@ParentItemId)
 ORDER BY SortOrder,Label;
END;
GO
/* 16: Publish reusable forms with all fields and validation settings retained per version. */
CREATE OR ALTER PROCEDURE forms.usp_CreateDefinition
 @ActorUserId BIGINT,@ProjectId BIGINT,@Code VARCHAR(90),
 @Name NVARCHAR(200),@Description NVARCHAR(700)=NULL,@FormId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50100,'Only project admins may create forms.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50101,'Invalid form code.',1;
 SET @FormId=NEXT VALUE FOR forms.Seq_Definitions;
 INSERT forms.Definitions(FormId,ProjectId,Code,Name,Description) VALUES(@FormId,@ProjectId,@Code,@Name,@Description);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Form',@EntityId=@FormId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE forms.usp_SaveDraft
 @ActorUserId BIGINT,@FormId BIGINT,@DefinitionJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @ProjectId BIGINT=(SELECT ProjectId FROM forms.Definitions WHERE FormId=@FormId);
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50102,'Form not found or not authorized.',1;
 IF ISJSON(@DefinitionJson)<>1 OR JSON_QUERY(@DefinitionJson,'$.fields') IS NULL THROW 50103,'Form must contain a fields array.',1;
 UPDATE forms.Definitions SET DraftJson=@DefinitionJson,UpdatedAt=SYSUTCDATETIME() WHERE FormId=@FormId;
END;
GO
CREATE OR ALTER PROCEDURE forms.usp_Publish
 @ActorUserId BIGINT,@FormId BIGINT,@VersionId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@DefinitionJson NVARCHAR(MAX),@VersionNumber INT;
 BEGIN TRAN;
 SELECT @ProjectId=ProjectId,@DefinitionJson=DraftJson FROM forms.Definitions WITH(UPDLOCK,HOLDLOCK) WHERE FormId=@FormId;
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 BEGIN ROLLBACK; THROW 50104,'Form not found or not authorized.',1; END;
 DECLARE @Fields TABLE(
 FieldKey VARCHAR(100),Label NVARCHAR(200),FieldType VARCHAR(25),IsRequired BIT,
 LibraryFieldId BIGINT,LookupListId BIGINT,ParentFieldKey VARCHAR(100),
 RegexPattern NVARCHAR(800),RegexMessage NVARCHAR(240),MaxFiles SMALLINT,MaxFileMB SMALLINT,
 AllowedExtensions NVARCHAR(300),IsSearchable BIT,SortOrder INT,ConfigJson NVARCHAR(MAX));
 INSERT @Fields
 SELECT f.FieldKey,f.Label,f.FieldType,ISNULL(f.IsRequired,0),f.LibraryFieldId,f.LookupListId,
 f.ParentFieldKey,f.RegexPattern,f.RegexMessage,f.MaxFiles,f.MaxFileMB,f.AllowedExtensions,
 ISNULL(f.IsSearchable,0),ISNULL(f.SortOrder,CONVERT(INT,j.[key])),j.value
 FROM OPENJSON(@DefinitionJson,'$.fields') j
 CROSS APPLY OPENJSON(j.value) WITH(
 FieldKey VARCHAR(100) '$.key',Label NVARCHAR(200) '$.label',FieldType VARCHAR(25) '$.type',
 IsRequired BIT '$.required',LibraryFieldId BIGINT '$.libraryFieldId',LookupListId BIGINT '$.lookupId',
 ParentFieldKey VARCHAR(100) '$.parentFieldKey',RegexPattern NVARCHAR(800) '$.regex',
 RegexMessage NVARCHAR(240) '$.regexMessage',MaxFiles SMALLINT '$.maxFiles',MaxFileMB SMALLINT '$.maxFileMB',
 AllowedExtensions NVARCHAR(300) '$.allowedFileTypes',IsSearchable BIT '$.searchable',SortOrder INT '$.sortOrder') f;
 IF NOT EXISTS(SELECT 1 FROM @Fields) BEGIN ROLLBACK; THROW 50105,'Add at least one field to publish.',1; END;
 IF EXISTS(SELECT FieldKey FROM @Fields GROUP BY FieldKey HAVING COUNT(*)>1) OR EXISTS(SELECT 1 FROM @Fields WHERE FieldKey IS NULL OR Label IS NULL)
 BEGIN ROLLBACK; THROW 50106,'Form fields need unique keys and labels.',1; END;
 IF EXISTS(SELECT 1 FROM @Fields WHERE FieldType NOT IN('text','textarea','number','date','select','checkbox','email','attachment'))
 BEGIN ROLLBACK; THROW 50107,'Unsupported field type.',1; END;
 IF EXISTS(SELECT 1 FROM @Fields f WHERE f.FieldType='select' AND (f.LookupListId IS NULL OR NOT EXISTS(
 SELECT 1 FROM lookup.Lists l WHERE l.ListId=f.LookupListId AND l.IsActive=1 AND
 (l.ProjectId=@ProjectId OR l.Scope='Global' AND EXISTS(SELECT 1 FROM lookup.ProjectLists pl WHERE pl.ProjectId=@ProjectId AND pl.ListId=l.ListId)))))
 BEGIN ROLLBACK; THROW 50108,'A dropdown lookup is missing or not available to this project.',1; END;
 IF EXISTS(SELECT 1 FROM @Fields f JOIN lookup.Lists l ON l.ListId=f.LookupListId AND l.ParentListId IS NOT NULL
 WHERE f.ParentFieldKey IS NULL OR NOT EXISTS(SELECT 1 FROM @Fields parent WHERE parent.FieldKey=f.ParentFieldKey AND parent.LookupListId=l.ParentListId))
 BEGIN ROLLBACK; THROW 50109,'Dependent lookup requires its parent field in the same form.',1; END;
 IF EXISTS(SELECT 1 FROM @Fields WHERE (MaxFiles IS NOT NULL AND MaxFiles NOT BETWEEN 1 AND 10)
 OR (MaxFileMB IS NOT NULL AND MaxFileMB NOT BETWEEN 1 AND 20))
 BEGIN ROLLBACK; THROW 50110,'Attachment limits are invalid.',1; END;
 SET @VersionNumber=ISNULL((SELECT MAX(VersionNumber) FROM forms.Versions WHERE FormId=@FormId),0)+1;
 SET @VersionId=NEXT VALUE FOR forms.Seq_Versions;
 INSERT forms.Versions(FormVersionId,FormId,VersionNumber,DefinitionJson,PublishedBy)
 VALUES(@VersionId,@FormId,@VersionNumber,@DefinitionJson,@ActorUserId);
 INSERT forms.VersionFields(FormVersionId,LibraryFieldId,FieldKey,Label,FieldType,IsRequired,
 LookupListId,ParentFieldKey,RegexPattern,RegexMessage,MaxFiles,MaxFileMB,AllowedExtensions,IsSearchable,SortOrder,ConfigJson)
 SELECT @VersionId,LibraryFieldId,FieldKey,Label,FieldType,IsRequired,LookupListId,ParentFieldKey,
 RegexPattern,RegexMessage,MaxFiles,MaxFileMB,AllowedExtensions,IsSearchable,SortOrder,ConfigJson FROM @Fields;
 UPDATE forms.Definitions SET LiveVersionId=@VersionId,UpdatedAt=SYSUTCDATETIME() WHERE FormId=@FormId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Form',@EntityId=@FormId,@ActionCode='Publish';
 COMMIT;
 SELECT @VersionNumber AS PublishedVersion,@VersionId AS FormVersionId;
END;
GO
/* 17: Publish immutable workflow graph with relational nodes and edges for efficient execution. */
CREATE OR ALTER PROCEDURE flow.usp_CreateDefinition
 @ActorUserId BIGINT,@ProjectId BIGINT,@Code VARCHAR(90),
 @Name NVARCHAR(200),@WorkflowId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50120,'Only project admins may create workflows.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50121,'Invalid workflow code.',1;
 SET @WorkflowId=NEXT VALUE FOR flow.Seq_Definitions;
 INSERT flow.Definitions(WorkflowId,ProjectId,Code,Name) VALUES(@WorkflowId,@ProjectId,@Code,@Name);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Workflow',@EntityId=@WorkflowId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE flow.usp_SaveDraft
 @ActorUserId BIGINT,@WorkflowId BIGINT,@GraphJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @ProjectId BIGINT=(SELECT ProjectId FROM flow.Definitions WHERE WorkflowId=@WorkflowId);
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50122,'Workflow not found or access denied.',1;
 IF ISJSON(@GraphJson)<>1 OR JSON_QUERY(@GraphJson,'$.nodes') IS NULL OR JSON_QUERY(@GraphJson,'$.edges') IS NULL
 THROW 50123,'Graph requires nodes and edges arrays.',1;
 UPDATE flow.Definitions SET DraftGraphJson=@GraphJson,UpdatedAt=SYSUTCDATETIME() WHERE WorkflowId=@WorkflowId;
END;
GO
CREATE OR ALTER PROCEDURE flow.usp_Publish
 @ActorUserId BIGINT,@WorkflowId BIGINT,@VersionId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Graph NVARCHAR(MAX),@VersionNumber INT;
 BEGIN TRAN;
 SELECT @ProjectId=ProjectId,@Graph=DraftGraphJson FROM flow.Definitions WITH(UPDLOCK,HOLDLOCK) WHERE WorkflowId=@WorkflowId;
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 BEGIN ROLLBACK; THROW 50124,'Workflow not found or access denied.',1; END;
 DECLARE @Nodes TABLE(
 NodeKey VARCHAR(120),NodeType VARCHAR(30),Label NVARCHAR(200),
 TeamId BIGINT,AssignmentMode VARCHAR(20),AssignedRole VARCHAR(20),SlaMinutes INT,
 EscalationRole VARCHAR(50),RequireForm BIT,AllowedActionsJson NVARCHAR(MAX),ConfigJson NVARCHAR(MAX));
 INSERT @Nodes
 SELECT JSON_VALUE(j.value,'$.id'),JSON_VALUE(j.value,'$.data.kind'),
 LEFT(ISNULL(JSON_VALUE(j.value,'$.data.label'),N'Step'),200),
 TRY_CONVERT(BIGINT,JSON_VALUE(j.value,'$.data.teamId')),
 CASE JSON_VALUE(j.value,'$.data.assignmentMode')
 WHEN 'direct' THEN 'Direct' WHEN 'roleQueue' THEN 'RoleQueue' ELSE 'Hierarchy' END,
 JSON_VALUE(j.value,'$.data.assignedRole'),
 TRY_CONVERT(INT,JSON_VALUE(j.value,'$.data.slaHours'))*60,
 JSON_VALUE(j.value,'$.data.escalationRole'),
 CASE JSON_VALUE(j.value,'$.data.requireForm') WHEN 'true' THEN 1 ELSE 0 END,
 JSON_QUERY(j.value,'$.data.actions'),ISNULL(JSON_QUERY(j.value,'$.data'),N'{}')
 FROM OPENJSON(@Graph,'$.nodes') j;
 IF (SELECT COUNT(*) FROM @Nodes WHERE NodeType='start')<>1 OR NOT EXISTS(SELECT 1 FROM @Nodes WHERE NodeType='end')
 BEGIN ROLLBACK; THROW 50125,'Workflow requires exactly one Start and at least one End.',1; END;
 IF EXISTS(SELECT NodeKey FROM @Nodes GROUP BY NodeKey HAVING COUNT(*)>1) OR EXISTS(SELECT 1 FROM @Nodes WHERE NodeKey IS NULL OR NodeType IS NULL)
 BEGIN ROLLBACK; THROW 50126,'Workflow nodes require unique identifiers and valid types.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.TeamId IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM teams.Teams t WHERE t.TeamId=n.TeamId AND t.ProjectId=@ProjectId AND t.IsActive=1))
 BEGIN ROLLBACK; THROW 50127,'Workflow uses a team outside this project.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType IN('task','officerRouting','requestInfo') AND n.TeamId IS NULL)
 BEGIN ROLLBACK; THROW 50128,'Each human task requires a destination team.',1; END;
 /* Explicit split or join semantics; no ambiguous implicit parallel nodes. */
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='parallel'
  AND JSON_VALUE(n.ConfigJson,'$.parallelMode') NOT IN('split','join'))
 BEGIN ROLLBACK; THROW 50322,'Parallel node must be configured as Split or Join.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='parallel' AND (
 (JSON_VALUE(n.ConfigJson,'$.parallelMode')='split' AND
   (SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.source')=n.NodeKey)<2)
 OR (JSON_VALUE(n.ConfigJson,'$.parallelMode')='join' AND
  ((SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.target')=n.NodeKey)<2
   OR (SELECT COUNT(*) FROM OPENJSON(@Graph,'$.edges') e WHERE JSON_VALUE(e.value,'$.source')=n.NodeKey)<>1))))
 BEGIN ROLLBACK; THROW 50335,'Parallel split needs two outgoing edges; join needs two incoming and one outgoing edge.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeType='notify' AND
  (TRY_CONVERT(BIGINT,JSON_VALUE(n.ConfigJson,'$.templateId')) IS NULL
   OR NOT EXISTS (SELECT 1 FROM notify.Templates t
   WHERE t.TemplateId=TRY_CONVERT(BIGINT,JSON_VALUE(n.ConfigJson,'$.templateId'))
   AND t.IsActive=1 AND (t.ProjectId=@ProjectId OR t.ProjectId IS NULL))))
 BEGIN ROLLBACK; THROW 50336,'Notification node requires an active project notification template.',1; END;
 IF EXISTS(SELECT 1 FROM OPENJSON(@Graph,'$.edges') e
 WHERE NOT EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeKey=JSON_VALUE(e.value,'$.source'))
 OR NOT EXISTS(SELECT 1 FROM @Nodes n WHERE n.NodeKey=JSON_VALUE(e.value,'$.target')))
 BEGIN ROLLBACK; THROW 50129,'Workflow contains an invalid edge.',1; END;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@Graph,'$.edges') e JOIN @Nodes n ON n.NodeKey=JSON_VALUE(e.value,'$.source') WHERE n.NodeType='start')
 BEGIN ROLLBACK; THROW 50130,'Start must have an outgoing connection.',1; END;
 IF EXISTS(SELECT 1 FROM @Nodes n CROSS APPLY OPENJSON(n.ConfigJson,'$.formIds') j
 WHERE NOT EXISTS(SELECT 1 FROM forms.Definitions f WHERE f.FormId=TRY_CONVERT(BIGINT,j.value)
  AND f.ProjectId=@ProjectId AND f.LiveVersionId IS NOT NULL))
 BEGIN ROLLBACK; THROW 50131,'Workflow references an unpublished or foreign form.',1; END;
 SET @VersionNumber=ISNULL((SELECT MAX(VersionNumber) FROM flow.Versions WHERE WorkflowId=@WorkflowId),0)+1;
 SET @VersionId=NEXT VALUE FOR flow.Seq_Versions;
 INSERT flow.Versions(WorkflowVersionId,WorkflowId,VersionNumber,GraphJson,PublishedBy)
 VALUES(@VersionId,@WorkflowId,@VersionNumber,@Graph,@ActorUserId);
 INSERT flow.Nodes(WorkflowVersionId,NodeKey,NodeType,Label,TeamId,AssignmentMode,AssignedRole,SlaMinutes,EscalationRole,RequireForm,AllowedActionsJson,ConfigJson)
 SELECT @VersionId,NodeKey,NodeType,Label,TeamId,AssignmentMode,AssignedRole,SlaMinutes,EscalationRole,RequireForm,AllowedActionsJson,ConfigJson FROM @Nodes;
 INSERT flow.Edges(WorkflowVersionId,SourceNodeId,TargetNodeId,OutcomeCode,SortOrder)
 SELECT @VersionId,s.NodeId,t.NodeId,
 NULLIF(COALESCE(JSON_VALUE(j.value,'$.data.outcome'),JSON_VALUE(j.value,'$.label')),''),
 CONVERT(INT,j.[key])
 FROM OPENJSON(@Graph,'$.edges') j
 JOIN flow.Nodes s ON s.WorkflowVersionId=@VersionId AND s.NodeKey=JSON_VALUE(j.value,'$.source')
 JOIN flow.Nodes t ON t.WorkflowVersionId=@VersionId AND t.NodeKey=JSON_VALUE(j.value,'$.target');
 INSERT flow.NodeForms(NodeId,FormVersionId)
 SELECT n.NodeId,f.LiveVersionId FROM flow.Nodes n
 CROSS APPLY OPENJSON(n.ConfigJson,'$.formIds') j
 JOIN forms.Definitions f ON f.FormId=TRY_CONVERT(BIGINT,j.value)
 WHERE n.WorkflowVersionId=@VersionId AND f.ProjectId=@ProjectId AND f.LiveVersionId IS NOT NULL;
 UPDATE flow.Definitions SET LiveVersionId=@VersionId,UpdatedAt=SYSUTCDATETIME() WHERE WorkflowId=@WorkflowId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Workflow',@EntityId=@WorkflowId,@ActionCode='Publish';
 COMMIT;
 SELECT @VersionNumber AS PublishedVersion,@VersionId AS WorkflowVersionId;
END;
GO
/* 18: Publish a case/request type from the current live form and workflow versions. */
CREATE OR ALTER PROCEDURE core.usp_CreateCaseType
 @ActorUserId BIGINT,@ProjectId BIGINT,@Code VARCHAR(90),@Name NVARCHAR(200),
 @CaseTypeId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50140,'Project admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50141,'Invalid case type code.',1;
 SET @CaseTypeId=NEXT VALUE FOR core.Seq_CaseTypes;
 INSERT core.CaseTypes(CaseTypeId,ProjectId,Code,Name) VALUES(@CaseTypeId,@ProjectId,@Code,@Name);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='CaseType',@EntityId=@CaseTypeId,@ActionCode='Create';
END;
GO
CREATE OR ALTER PROCEDURE core.usp_PublishCaseType
 @ActorUserId BIGINT,@CaseTypeId BIGINT,@ConfigJson NVARCHAR(MAX),
 @CaseTypeVersionId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@ConfigJson)<>1 THROW 50142,'Invalid case type JSON.',1;
 DECLARE @ProjectId BIGINT,@FormId BIGINT,@WorkflowId BIGINT,
 @FormVersionId BIGINT,@WorkflowVersionId BIGINT,@Version INT,@SubjectFieldKey VARCHAR(100);
 BEGIN TRAN;
 SELECT @ProjectId=ProjectId FROM core.CaseTypes WITH(UPDLOCK,HOLDLOCK) WHERE CaseTypeId=@CaseTypeId;
 IF @ProjectId IS NULL OR auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 BEGIN ROLLBACK; THROW 50143,'Case type not found/access denied.',1; END;
 SET @FormId=TRY_CONVERT(BIGINT,JSON_VALUE(@ConfigJson,'$.formId'));
 SET @WorkflowId=TRY_CONVERT(BIGINT,JSON_VALUE(@ConfigJson,'$.workflowId'));
 SELECT @FormVersionId=LiveVersionId FROM forms.Definitions WHERE FormId=@FormId AND ProjectId=@ProjectId;
 SELECT @WorkflowVersionId=LiveVersionId FROM flow.Definitions WHERE WorkflowId=@WorkflowId AND ProjectId=@ProjectId;
 IF @FormVersionId IS NULL OR @WorkflowVersionId IS NULL BEGIN ROLLBACK; THROW 50144,'A published intake form and workflow from this project are required.',1; END;
 SET @SubjectFieldKey=JSON_VALUE(@ConfigJson,'$.subjectField');
 IF @SubjectFieldKey IS NOT NULL AND NOT EXISTS(SELECT 1 FROM forms.VersionFields WHERE FormVersionId=@FormVersionId AND FieldKey=@SubjectFieldKey)
 BEGIN ROLLBACK; THROW 50145,'Duplicate subject field is not in the intake form.',1; END;
 IF EXISTS(SELECT 1 FROM OPENJSON(@ConfigJson,'$.lookupListIds') j WHERE NOT EXISTS(
 SELECT 1 FROM lookup.Lists l WHERE l.ListId=TRY_CONVERT(BIGINT,j.value) AND l.IsActive=1 AND
 (l.ProjectId=@ProjectId OR l.Scope='Global' AND EXISTS(SELECT 1 FROM lookup.ProjectLists pl WHERE pl.ProjectId=@ProjectId AND pl.ListId=l.ListId))))
 BEGIN ROLLBACK; THROW 50146,'A selected lookup is unavailable to the project.',1; END;
 DECLARE @LodgementOperationId BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@ConfigJson,'$.lodgementIntegration.operationId'));
 IF JSON_QUERY(@ConfigJson,'$.lodgementIntegration') IS NOT NULL
 BEGIN
  IF @LodgementOperationId IS NULL OR NOT EXISTS(
   SELECT 1 FROM integration.Operations o JOIN integration.DataSources s ON s.DataSourceId=o.DataSourceId
   JOIN integration.ProjectDataSources pd ON pd.DataSourceId=s.DataSourceId AND pd.ProjectId=@ProjectId
   WHERE o.OperationId=@LodgementOperationId AND o.IsActive=1 AND s.IsActive=1 AND s.Kind='REST')
   BEGIN ROLLBACK; THROW 50310,'Selected case-type integration is not approved or active.',1; END;
  IF ISJSON(JSON_QUERY(@ConfigJson,'$.lodgementIntegration.inputMap'))<>1
   BEGIN ROLLBACK; THROW 50311,'Lodgement integration inputs must be a mapping object.',1; END;
  IF EXISTS (SELECT 1 FROM OPENJSON(@ConfigJson,'$.lodgementIntegration.inputMap') im
     WHERE im.[type]<>1 OR (im.value<>'title' AND NOT EXISTS(
      SELECT 1 FROM forms.VersionFields f WHERE f.FormVersionId=@FormVersionId AND im.value=CONCAT('fields.',f.FieldKey))
     AND NOT EXISTS(SELECT 1 FROM OPENJSON(@ConfigJson,'$.lookupListIds') l
      JOIN lookup.Lists d ON d.ListId=TRY_CONVERT(BIGINT,l.value)
      WHERE im.value=CONCAT('classification.classification_',LOWER(d.Code)))))
   BEGIN ROLLBACK; THROW 50312,'Lodgement inputs must reference published intake or classification fields.',1; END;
 END;
 SET @Version=ISNULL((SELECT MAX(VersionNumber) FROM core.CaseTypeVersions WHERE CaseTypeId=@CaseTypeId),0)+1;
 SET @CaseTypeVersionId=NEXT VALUE FOR core.Seq_CaseTypeVersions;
 INSERT core.CaseTypeVersions(CaseTypeVersionId,CaseTypeId,VersionNumber,IntakeFormVersionId,WorkflowVersionId,SubjectFieldKey,SlaMinutes,AllowDuplicate,PublishedConfigJson)
 VALUES(@CaseTypeVersionId,@CaseTypeId,@Version,@FormVersionId,@WorkflowVersionId,@SubjectFieldKey,
 TRY_CONVERT(INT,JSON_VALUE(@ConfigJson,'$.slaHours'))*60,
 CASE JSON_VALUE(@ConfigJson,'$.allowDuplicate') WHEN 'true' THEN 1 ELSE 0 END,@ConfigJson);
 INSERT core.CaseTypeLookups(CaseTypeVersionId,ListId,IsRequired,LockedItemId,SortOrder)
 SELECT @CaseTypeVersionId,l.ListId,
 CASE WHEN EXISTS(SELECT 1 FROM OPENJSON(@ConfigJson,'$.requiredLookupIds') required WHERE TRY_CONVERT(BIGINT,required.value)=l.ListId) THEN 1 ELSE 0 END,
 locked.ItemId,CONVERT(INT,j.[key])
 FROM OPENJSON(@ConfigJson,'$.lookupListIds') j
 JOIN lookup.Lists l ON l.ListId=TRY_CONVERT(BIGINT,j.value)
 OUTER APPLY(SELECT TOP(1) i.ItemId FROM lookup.Items i
 WHERE i.ListId=l.ListId AND (CONVERT(NVARCHAR(36),i.ItemId)=JSON_VALUE(@ConfigJson,CONCAT('$.lockedValues.classification_',LOWER(l.Code)))
 OR i.Code=JSON_VALUE(@ConfigJson,CONCAT('$.lockedValues.classification_',LOWER(l.Code))))) locked;
 UPDATE core.CaseTypes SET LiveVersionId=@CaseTypeVersionId,DraftJson=@ConfigJson,UpdatedAt=SYSUTCDATETIME() WHERE CaseTypeId=@CaseTypeId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='CaseType',@EntityId=@CaseTypeId,@ActionCode='Publish';
 COMMIT;
 SELECT @Version AS PublishedVersion,@CaseTypeVersionId AS CaseTypeVersionId;
END;
GO
/* 19: Additional durable scheduling and final-status metadata. */
IF COL_LENGTH(N'work.Cases',N'PendingFinalStatus') IS NULL
 ALTER TABLE work.Cases ADD PendingFinalStatus VARCHAR(30) NULL;
IF COL_LENGTH(N'work.Cases',N'RcaRequiredAtCreation') IS NULL
 ALTER TABLE work.Cases ADD RcaRequiredAtCreation BIT NOT NULL CONSTRAINT DF_Cases_RcaRequired DEFAULT 0;
IF COL_LENGTH(N'work.Cases',N'RcaTemplateAtCreation') IS NULL
 ALTER TABLE work.Cases ADD RcaTemplateAtCreation BIGINT NULL;
IF COL_LENGTH(N'work.Cases',N'RcaFieldsSnapshotJson') IS NULL
 ALTER TABLE work.Cases ADD RcaFieldsSnapshotJson NVARCHAR(MAX) NULL;
IF OBJECT_ID(N'work.PendingTimers',N'U') IS NULL
CREATE TABLE work.PendingTimers (
 TimerId BIGINT NOT NULL CONSTRAINT PK_PendingTimers PRIMARY KEY DEFAULT (NEXT VALUE FOR work.Seq_PendingTimers),
 InstanceId BIGINT NOT NULL REFERENCES work.Instances(InstanceId),
 NodeId BIGINT NOT NULL REFERENCES flow.Nodes(NodeId),
 WakeAtUtc DATETIME2(3) NOT NULL,
 Status VARCHAR(20) NOT NULL DEFAULT 'Pending',
 CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT CK_Timers_Status CHECK(Status IN('Pending','Resumed','Cancelled'))
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_Timers_Due' AND object_id=OBJECT_ID(N'work.PendingTimers'))
 CREATE INDEX IX_Timers_Due ON work.PendingTimers(WakeAtUtc) INCLUDE(InstanceId,NodeId) WHERE Status='Pending';
GO
/* Maintain indexed copies of explicitly searchable fields; never JSON-scan millions of cases. */
CREATE OR ALTER PROCEDURE work.usp_ReindexCaseFields @CaseId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Values NVARCHAR(MAX),@FormVersionId BIGINT;
 SELECT @ProjectId=c.ProjectId,@Values=c.CurrentValuesJson,@FormVersionId=t.IntakeFormVersionId
 FROM work.Cases c JOIN core.CaseTypeVersions t ON t.CaseTypeVersionId=c.CaseTypeVersionId
 WHERE c.CaseId=@CaseId;
 IF @ProjectId IS NULL THROW 50150,'Case not found.',1;
 DELETE FROM work.CaseFieldIndex WHERE CaseId=@CaseId;
 INSERT work.CaseFieldIndex(CaseId,ProjectId,FieldKey,ValueText,ValueNumber,ValueDate)
 SELECT @CaseId,@ProjectId,f.FieldKey,LEFT(CONVERT(NVARCHAR(MAX),j.value),450),
  CASE WHEN f.FieldType='number' THEN TRY_CONVERT(DECIMAL(20,4),j.value) END,
  CASE WHEN f.FieldType='date' THEN TRY_CONVERT(DATE,j.value) END
 FROM OPENJSON(@Values) j
 JOIN forms.VersionFields f ON f.FormVersionId=@FormVersionId AND f.FieldKey=j.[key] COLLATE DATABASE_DEFAULT AND f.IsSearchable=1
 WHERE j.[type] NOT IN(0,4,5);  -- do not index NULL, arrays or object bodies
END;
GO
/* Activates Start/End and human task nodes transactionally. Advanced graph runtime remains backend-owned. */
CREATE OR ALTER PROCEDURE work.usp_ActivateNode
 @InstanceId BIGINT,@NodeId BIGINT,@ActorUserId BIGINT=NULL,@Depth INT=0,@SourceNodeId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @Depth>25 THROW 50151,'Workflow contains a cycle or exceeds safe activation depth.',1;
 DECLARE @WorkflowVersionId BIGINT,@CaseId BIGINT,@ProjectId BIGINT,
 @Kind VARCHAR(30),@TeamId BIGINT,@Mode VARCHAR(20),@Role VARCHAR(20),@SlaMinutes INT,
 @NodeConfig NVARCHAR(MAX),@StartAt DATETIME2(3)=SYSUTCDATETIME(),@DueAt DATETIME2(3),@CalendarId BIGINT;
 SELECT @WorkflowVersionId=i.WorkflowVersionId,@CaseId=i.CaseId,@ProjectId=c.ProjectId,@CalendarId=p.CalendarId
 FROM work.Instances i JOIN work.Cases c ON c.CaseId=i.CaseId
 JOIN core.Projects p ON p.ProjectId=c.ProjectId WHERE i.InstanceId=@InstanceId;
 SELECT @Kind=NodeType,@TeamId=TeamId,@Mode=AssignmentMode,@Role=AssignedRole,@SlaMinutes=SlaMinutes,@NodeConfig=ConfigJson
 FROM flow.Nodes WHERE NodeId=@NodeId AND WorkflowVersionId=@WorkflowVersionId;
 IF @Kind IS NULL THROW 50152,'Node is not part of this workflow version.',1;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 VALUES(@CaseId,'StepEntered',CONCAT('Entered ',@Kind),@ActorUserId,(SELECT CONVERT(NVARCHAR(36),@NodeId) AS nodeId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 IF @Kind='start'
 BEGIN
  DECLARE @FirstNode BIGINT;
  SELECT TOP(1) @FirstNode=TargetNodeId FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
  IF @FirstNode IS NULL THROW 50153,'Start node has no outgoing connection.',1;
  DECLARE @NextDepth INT=@Depth+1;
  EXEC work.usp_ActivateNode @InstanceId,@FirstNode,@ActorUserId,@Depth=@NextDepth,@SourceNodeId=@NodeId;
  RETURN;
 END;
 IF @Kind='decision'
 BEGIN
  DECLARE @Field VARCHAR(100)=JSON_VALUE(@NodeConfig,'$.conditionField');
  DECLARE @Operator VARCHAR(25)=ISNULL(JSON_VALUE(@NodeConfig,'$.conditionOperator'),'equals');
  DECLARE @Expected NVARCHAR(1000)=ISNULL(JSON_VALUE(@NodeConfig,'$.conditionValue'),N'');
  DECLARE @Actual NVARCHAR(1000),@Yes BIT=0,@TargetNode BIGINT;
  IF NULLIF(@Field,'') IS NULL OR @Field COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%' OR LEN(@Field)>100
    THROW 50323,'Decision must select a valid case field.',1;
  IF @Field='title' SELECT @Actual=Title FROM work.Cases WHERE CaseId=@CaseId;
  ELSE SELECT @Actual=JSON_VALUE(CurrentValuesJson,CONCAT('$.',@Field)) FROM work.Cases WHERE CaseId=@CaseId;
  SET @Yes=CASE @Operator
   WHEN 'equals' THEN CASE WHEN ISNULL(@Actual,N'')=@Expected THEN 1 ELSE 0 END
   WHEN 'notEquals' THEN CASE WHEN ISNULL(@Actual,N'')<>@Expected THEN 1 ELSE 0 END
   WHEN 'contains' THEN CASE WHEN CHARINDEX(@Expected,ISNULL(@Actual,N''))>0 THEN 1 ELSE 0 END
   WHEN 'greaterThan' THEN CASE WHEN TRY_CONVERT(DECIMAL(28,8),@Actual)>TRY_CONVERT(DECIMAL(28,8),@Expected) THEN 1 ELSE 0 END
   WHEN 'isEmpty' THEN CASE WHEN NULLIF(LTRIM(RTRIM(@Actual)),N'') IS NULL THEN 1 ELSE 0 END
   WHEN 'notEmpty' THEN CASE WHEN NULLIF(LTRIM(RTRIM(@Actual)),N'') IS NOT NULL THEN 1 ELSE 0 END
   ELSE NULL END;
  IF @Yes IS NULL THROW 50324,'Unsupported decision comparison.',1;
  SELECT TOP(1) @TargetNode=TargetNodeId FROM flow.Edges
  WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId
    AND LOWER(OutcomeCode)=CASE WHEN @Yes=1 THEN 'yes' ELSE 'no' END ORDER BY SortOrder;
  IF @TargetNode IS NULL THROW 50325,'Decision is missing its Yes/No outgoing edge.',1;
  INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
  VALUES(@CaseId,'DecisionEvaluated',CASE WHEN @Yes=1 THEN N'Decision matched' ELSE N'Decision not matched' END,
    (SELECT CONVERT(NVARCHAR(36),@NodeId) AS nodeId,CASE WHEN @Yes=1 THEN 'Yes' ELSE 'No' END AS branch FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
  DECLARE @DecisionNextDepth INT = @Depth + 1;
  EXEC work.usp_ActivateNode @InstanceId,@TargetNode,@ActorUserId,@Depth=@DecisionNextDepth,@SourceNodeId=@NodeId;
  RETURN;
 END;
 IF @Kind='parallel'
 BEGIN
  DECLARE @ParallelMode VARCHAR(15)=JSON_VALUE(@NodeConfig,'$.parallelMode');
  IF @ParallelMode='split'
  BEGIN
   DECLARE @SplitTarget BIGINT,@SplitDepth INT=@Depth+1;
   DECLARE splitEdges CURSOR LOCAL FAST_FORWARD FOR SELECT TargetNodeId FROM flow.Edges
    WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
   OPEN splitEdges;FETCH NEXT FROM splitEdges INTO @SplitTarget;
   WHILE @@FETCH_STATUS=0
   BEGIN
    EXEC work.usp_ActivateNode @InstanceId,@SplitTarget,@ActorUserId,@Depth=@SplitDepth,@SourceNodeId=@NodeId;
    FETCH NEXT FROM splitEdges INTO @SplitTarget;
   END;
   CLOSE splitEdges;DEALLOCATE splitEdges;
   RETURN;
  END;
  IF @ParallelMode='join'
  BEGIN
   IF @SourceNodeId IS NULL OR NOT EXISTS(SELECT 1 FROM flow.Edges
      WHERE WorkflowVersionId=@WorkflowVersionId AND SourceNodeId=@SourceNodeId AND TargetNodeId=@NodeId)
     THROW 50337,'Join must receive a valid incoming workflow branch.',1;
   /* Serialize arrivals for this instance; concurrent worker continuations do not double-resume. */
   DECLARE @JoinGuard BIGINT;
   SELECT @JoinGuard=InstanceId FROM work.Instances WITH(UPDLOCK,HOLDLOCK) WHERE InstanceId=@InstanceId;
   IF NOT EXISTS(SELECT 1 FROM work.ParallelJoins WHERE InstanceId=@InstanceId AND NodeId=@NodeId)
     INSERT work.ParallelJoins(InstanceId,NodeId) VALUES(@InstanceId,@NodeId);
   IF EXISTS(SELECT 1 FROM work.ParallelJoins WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Resumed=1) RETURN;
   IF NOT EXISTS(SELECT 1 FROM work.ParallelArrivals WHERE InstanceId=@InstanceId
      AND JoinNodeId=@NodeId AND SourceNodeId=@SourceNodeId)
     INSERT work.ParallelArrivals(InstanceId,JoinNodeId,SourceNodeId)
     VALUES(@InstanceId,@NodeId,@SourceNodeId);
   DECLARE @JoinExpectedArrivals INT=(SELECT COUNT(*) FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId AND TargetNodeId=@NodeId);
   DECLARE @Arrived INT=(SELECT COUNT(*) FROM work.ParallelArrivals WHERE InstanceId=@InstanceId AND JoinNodeId=@NodeId);
   IF @Arrived<@JoinExpectedArrivals RETURN;
   UPDATE work.ParallelJoins SET Resumed=1,ResumedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Resumed=0;
   DECLARE @JoinNext BIGINT=(SELECT TOP(1) TargetNodeId FROM flow.Edges WHERE WorkflowVersionId=@WorkflowVersionId
      AND SourceNodeId=@NodeId ORDER BY SortOrder);
   DECLARE @JoinDepth INT=@Depth+1;
   EXEC work.usp_ActivateNode @InstanceId,@JoinNext,@ActorUserId,@Depth=@JoinDepth,@SourceNodeId=@NodeId;
   RETURN;
  END;
  THROW 50338,'Parallel node has no supported execution mode.',1;
 END;
 IF @Kind='end'
 BEGIN
  IF EXISTS(SELECT 1 FROM work.Tasks WHERE InstanceId=@InstanceId AND Status='Open') RETURN;
  IF EXISTS(SELECT 1 FROM integration.Executions WHERE CaseId=@CaseId AND Status IN('Pending','Running','Failed')) RETURN;
  IF EXISTS(SELECT 1 FROM work.PendingTimers WHERE InstanceId=@InstanceId AND Status='Pending') RETURN;
  IF EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND RcaRequiredAtCreation=1)
   UPDATE work.Cases SET Status='Pending RCA',PendingFinalStatus='Closed',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  ELSE UPDATE work.Cases SET Status='Closed',ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  UPDATE work.Instances SET Status='Completed',CompletedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId;
  INSERT work.CaseEvents(CaseId,EventType,Message) VALUES(@CaseId,'WorkflowCompleted','Workflow reached an end state');
  EXEC notify.usp_QueueConfiguredEvent 'WORKFLOW_COMPLETED',@ProjectId,@CaseId;
  RETURN;
 END;
 IF @Kind IN('task','officerRouting','requestInfo','groupReview')
 BEGIN
  DECLARE @TeamIds TABLE(TeamId BIGINT PRIMARY KEY);
  IF @Kind='groupReview'
   INSERT @TeamIds(TeamId) SELECT DISTINCT TRY_CONVERT(BIGINT,value)
   FROM OPENJSON(@NodeConfig,'$.teamIds') WHERE TRY_CONVERT(BIGINT,value) IS NOT NULL;
  ELSE IF @TeamId IS NOT NULL INSERT @TeamIds VALUES(@TeamId);
  IF NOT EXISTS(SELECT 1 FROM @TeamIds) THROW 50154,'Human task needs a project team.',1;
  IF @SlaMinutes>0
  BEGIN
   IF @CalendarId IS NOT NULL EXEC calendar.usp_CalculateBusinessDueAt @CalendarId,@StartAt,@SlaMinutes,@DueAt OUTPUT;
   ELSE SET @DueAt=DATEADD(MINUTE,@SlaMinutes,@StartAt);
  END;
  DECLARE @ThisTeam BIGINT,@Recipient BIGINT,@RoutingStage VARCHAR(15),@TaskId BIGINT;
  DECLARE taskTeams CURSOR LOCAL FAST_FORWARD FOR SELECT TeamId FROM @TeamIds;
  OPEN taskTeams;FETCH NEXT FROM taskTeams INTO @ThisTeam;
  WHILE @@FETCH_STATUS=0
  BEGIN
    IF NOT EXISTS(SELECT 1 FROM teams.Teams WHERE TeamId=@ThisTeam AND ProjectId=@ProjectId AND IsActive=1)
     THROW 50155,'Workflow step uses an unavailable team.',1;
    SET @Recipient=NULL;SET @RoutingStage='Unassigned';
    SELECT TOP(1) @Recipient=m.UserId,@RoutingStage=m.TeamRole
    FROM teams.Members m JOIN auth.Users u ON u.UserId=m.UserId
    WHERE m.TeamId=@ThisTeam AND m.IsActive=1 AND u.IsActive=1 AND u.DirectoryStatus='Active'
    AND ( @Mode='Hierarchy' OR @Mode='Direct' AND m.TeamRole='Officer'
      OR @Mode='RoleQueue' AND m.TeamRole=CASE @Role WHEN 'unit_head' THEN 'UnitHead' WHEN 'team_lead' THEN 'TeamLead' ELSE 'Officer' END )
    AND NOT EXISTS(SELECT 1 FROM teams.Absences a WHERE a.TeamId=@ThisTeam AND a.UserId=m.UserId AND a.IsActive=1
     AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN a.StartDate AND a.EndDate)
    ORDER BY CASE WHEN @Mode='Hierarchy' THEN CASE m.TeamRole WHEN 'UnitHead' THEN 1 WHEN 'TeamLead' THEN 2 ELSE 3 END ELSE 1 END,u.UserName;
    SET @TaskId=NEXT VALUE FOR work.Seq_Tasks;
    INSERT work.Tasks(TaskId,InstanceId,NodeId,TeamId,AssignedTo,RoutingStage,Status,Priority,DueAt,AssignedAt)
    VALUES(@TaskId,@InstanceId,@NodeId,@ThisTeam,@Recipient,@RoutingStage,'Open','Normal',@DueAt,
    CASE WHEN @Recipient IS NOT NULL THEN SYSUTCDATETIME() END);
    INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
    VALUES(@CaseId,'TaskAssigned',CASE WHEN @Recipient IS NULL THEN 'Task awaiting assignment' ELSE 'Human task assigned' END,
     (SELECT CONVERT(NVARCHAR(36),@TaskId) AS taskId,CONVERT(NVARCHAR(36),@Recipient) AS userId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
    EXEC notify.usp_QueueConfiguredEvent 'TASK_ASSIGNED',@ProjectId,@CaseId,@TaskId=@TaskId,@RecipientUserId=@Recipient;
    FETCH NEXT FROM taskTeams INTO @ThisTeam;
  END;
  CLOSE taskTeams;DEALLOCATE taskTeams;
  UPDATE work.Cases SET Status='In progress',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='wait'
 BEGIN
  DECLARE @Minutes INT=TRY_CONVERT(INT,JSON_VALUE(@NodeConfig,'$.delayMinutes'));
  INSERT work.PendingTimers(InstanceId,NodeId,WakeAtUtc)
  VALUES(@InstanceId,@NodeId,DATEADD(MINUTE,ISNULL(NULLIF(@Minutes,0),60),SYSUTCDATETIME()));
  UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='notify'
 BEGIN
  DECLARE @TemplateId BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.templateId'));
  DECLARE @NotifyRecipientUserId BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.recipientUserId'));
  DECLARE @NChannel VARCHAR(15),@NSubject NVARCHAR(300),@NBody NVARCHAR(MAX),@NAddress NVARCHAR(320);
  SELECT @NChannel=Channel,@NSubject=SubjectTemplate,@NBody=BodyTemplate
  FROM notify.Templates WHERE TemplateId=@TemplateId AND IsActive=1 AND (ProjectId=@ProjectId OR ProjectId IS NULL);
  IF @NChannel IS NULL THROW 50339,'Notification template is unavailable.',1;
  IF @NotifyRecipientUserId IS NULL SELECT @NotifyRecipientUserId=CreatedBy FROM work.Cases WHERE CaseId=@CaseId;
  SELECT @NAddress=CASE WHEN @NChannel='SMS' THEN Mobile ELSE Email END
   FROM auth.Users WHERE UserId=@NotifyRecipientUserId AND IsActive=1;
  IF @NChannel IN('Email','SMS') AND NULLIF(LTRIM(RTRIM(@NAddress)),N'') IS NULL
    THROW 50340,'Notification recipient has no destination address.',1;
  DECLARE @NotificationId BIGINT=NEXT VALUE FOR notify.Seq_Outbox;
  INSERT notify.Outbox(NotificationId,ProjectId,CaseId,Channel,RecipientUserId,RecipientAddress,
   TemplateId,PayloadJson,IdempotencyKey)
  VALUES(@NotificationId,@ProjectId,@CaseId,@NChannel,@NotifyRecipientUserId,@NAddress,@TemplateId,
   (SELECT @NSubject AS subject,@NBody AS body,@CaseId AS caseId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
   CONCAT('node:',CONVERT(VARCHAR(36),@InstanceId),':',CONVERT(VARCHAR(36),@NodeId)));
  INSERT work.SystemNotifications(InstanceId,NodeId,NotificationId) VALUES(@InstanceId,@NodeId,@NotificationId);
  UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 IF @Kind='dataSource'
 BEGIN
  DECLARE @OperationId BIGINT,@Src BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@NodeConfig,'$.dataSourceId'));
  DECLARE @OpCode VARCHAR(75)=JSON_VALUE(@NodeConfig,'$.operationCode');
  SELECT @OperationId=o.OperationId FROM integration.Operations o
  JOIN integration.ProjectDataSources p ON p.DataSourceId=o.DataSourceId AND p.ProjectId=@ProjectId
  WHERE o.DataSourceId=@Src AND o.Code=@OpCode AND o.IsActive=1;
  IF @OperationId IS NULL THROW 50156,'Data-source operation is not approved for this project.',1;
  INSERT integration.Executions(ProjectId,CaseId,NodeId,OperationId,IdempotencyKey)
  VALUES(@ProjectId,@CaseId,@NodeId,@OperationId,CONCAT(CONVERT(VARCHAR(36),@InstanceId),':',CONVERT(VARCHAR(36),@NodeId)));
  UPDATE work.Cases SET Status='Waiting for integration',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  RETURN;
 END;
 /* Unsupported published legacy nodes must fail explicitly; never silently strand a case. */
 UPDATE work.Instances SET Status='Waiting' WHERE InstanceId=@InstanceId;
 UPDATE work.Cases SET Status='Waiting',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 INSERT work.CaseEvents(CaseId,EventType,Message)
 VALUES(@CaseId,'EnginePending',CONCAT('Backend workflow executor required for node type ',@Kind));
END;
GO
/* Create one case with published version pinning, duplicate checks, atomic sequence, and first task. */
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
 JSON_VALUE(ConfigJson,'$.parentValue') AS ParentValue
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
/* 20: Unit Head -> Team Lead -> Officer handoff, with active leave backup. */
CREATE OR ALTER PROCEDURE work.usp_ForwardTask
 @ActorUserId BIGINT,@TaskId BIGINT,@ToUserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @Stage VARCHAR(15),@Next VARCHAR(15),@TeamId BIGINT,@CaseId BIGINT,
 @ProjectId BIGINT,@AssignedTo BIGINT,@ResolvedTo BIGINT,@DelegatedFor BIGINT=NULL;
 BEGIN TRAN;
 SELECT @Stage=t.RoutingStage,@TeamId=t.TeamId,@AssignedTo=t.AssignedTo,@CaseId=i.CaseId,@ProjectId=c.ProjectId
 FROM work.Tasks t WITH(UPDLOCK,HOLDLOCK) JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId WHERE t.TaskId=@TaskId AND t.Status='Open';
 IF @CaseId IS NULL BEGIN ROLLBACK; THROW 50170,'Task not found or completed.',1; END;
 IF @AssignedTo<>@ActorUserId BEGIN ROLLBACK; THROW 50171,'Only assigned reviewer may forward this task.',1; END;
 SET @Next=CASE @Stage WHEN 'UnitHead' THEN 'TeamLead' WHEN 'TeamLead' THEN 'Officer' END;
 IF @Next IS NULL BEGIN ROLLBACK; THROW 50172,'This task is ready for action, not further forwarding.',1; END;
 IF @Stage='UnitHead' AND NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND TeamRole='TeamLead' AND IsActive=1)
  SET @Next='Officer';
 IF NOT EXISTS(SELECT 1 FROM teams.Members m JOIN auth.Users u ON u.UserId=m.UserId
  WHERE m.TeamId=@TeamId AND m.UserId=@ToUserId AND m.TeamRole=@Next AND m.IsActive=1 AND u.IsActive=1 AND u.DirectoryStatus<>'Resigned')
 BEGIN ROLLBACK; THROW 50173,'Recipient is not an active member of the next team role.',1; END;
 SET @ResolvedTo=@ToUserId;
 IF EXISTS(SELECT 1 FROM teams.Absences WHERE TeamId=@TeamId AND UserId=@ToUserId AND IsActive=1
 AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN StartDate AND EndDate)
 BEGIN
  SELECT TOP(1) @ResolvedTo=a.BackupUserId,@DelegatedFor=@ToUserId
  FROM teams.Absences a JOIN auth.Users u ON u.UserId=a.BackupUserId AND u.IsActive=1 AND u.DirectoryStatus='Active'
  JOIN teams.Members m ON m.TeamId=a.TeamId AND m.UserId=a.BackupUserId AND m.IsActive=1
  WHERE a.TeamId=@TeamId AND a.UserId=@ToUserId AND a.IsActive=1
  AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN a.StartDate AND a.EndDate
  AND NOT EXISTS(SELECT 1 FROM teams.Absences other WHERE other.UserId=a.BackupUserId AND other.IsActive=1
   AND CAST(SYSUTCDATETIME() AS DATE) BETWEEN other.StartDate AND other.EndDate);
  IF @DelegatedFor IS NULL BEGIN ROLLBACK; THROW 50174,'Selected recipient is on leave without an available backup.',1; END;
 END;
 UPDATE work.Tasks SET AssignedTo=@ResolvedTo,DelegatedFor=@DelegatedFor,RoutingStage=@Next,AssignedAt=SYSUTCDATETIME()
 WHERE TaskId=@TaskId;
 INSERT work.TaskHandoffs(TaskId,FromUserId,ToUserId,RoutingStage,ActorUserId,Reason)
 VALUES(@TaskId,@ActorUserId,@ResolvedTo,@Next,@ActorUserId,N'Forwarded to next review role');
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 VALUES(@CaseId,'TaskForwarded',CONCAT('Forwarded to ',@Next),@ActorUserId,
  (SELECT CONVERT(NVARCHAR(36),@ResolvedTo) AS assignedTo FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Task',@EntityId=@TaskId,@ActionCode='Forward';
 COMMIT;
 SELECT TaskId,RoutingStage,AssignedTo,DelegatedFor FROM work.Tasks WHERE TaskId=@TaskId;
END;
GO
/* Complete one human task. The stored procedure supports sequential and group-review fan-out;
   decisions/parallel joins/custom system nodes need a dedicated backend orchestrator. */
CREATE OR ALTER PROCEDURE work.usp_CompleteTask
 @ActorUserId BIGINT,@TaskId BIGINT,@Action VARCHAR(60),
 @AnswersByFormJson NVARCHAR(MAX)=N'{}',@Comment NVARCHAR(1000)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF ISJSON(@AnswersByFormJson)<>1 THROW 50175,'Task form answers must be JSON.',1;
 DECLARE @CaseId BIGINT,@ProjectId BIGINT,@InstanceId BIGINT,
 @NodeId BIGINT,@WorkflowVersionId BIGINT,@AssignedTo BIGINT,
 @RoutingStage VARCHAR(15),@RequireForm BIT,@AllowedActionsJson NVARCHAR(MAX),@CurrentJson NVARCHAR(MAX),
 @NextNodeId BIGINT,@TeamId BIGINT;
 BEGIN TRAN;
 SELECT @CaseId=i.CaseId,@ProjectId=c.ProjectId,@InstanceId=i.InstanceId,@WorkflowVersionId=i.WorkflowVersionId,
 @NodeId=t.NodeId,@AssignedTo=t.AssignedTo,@RoutingStage=t.RoutingStage,@TeamId=t.TeamId
 FROM work.Tasks t WITH(UPDLOCK,HOLDLOCK) JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId WHERE t.TaskId=@TaskId AND t.Status='Open';
 IF @CaseId IS NULL BEGIN ROLLBACK; THROW 50176,'Task already completed or not found.',1; END;
 IF @AssignedTo IS NULL OR @AssignedTo<>@ActorUserId BEGIN ROLLBACK; THROW 50177,'Task is not assigned to this user.',1; END;
 DECLARE @AssignmentMode VARCHAR(20);
 SELECT @AssignmentMode=AssignmentMode,@RequireForm=RequireForm,
 @AllowedActionsJson=AllowedActionsJson FROM flow.Nodes WHERE NodeId=@NodeId;
 IF @RoutingStage<>'Officer' AND @AssignmentMode<>'RoleQueue'
 BEGIN ROLLBACK; THROW 50178,'Forward through the review hierarchy before completing this step.',1; END;
 IF @AllowedActionsJson IS NOT NULL AND NOT EXISTS(SELECT 1 FROM OPENJSON(@AllowedActionsJson) WHERE value=@Action)
 BEGIN ROLLBACK; THROW 50179,'This workflow action is not allowed.',1; END;
 IF @AllowedActionsJson IS NULL AND @Action NOT IN('Complete','Approve','Reject','Return','Forward','Request information')
 BEGIN ROLLBACK; THROW 50180,'Unknown task action.',1; END;
 IF @RequireForm=1 AND EXISTS(SELECT 1 FROM flow.NodeForms nf JOIN forms.Versions v ON v.FormVersionId=nf.FormVersionId
  WHERE nf.NodeId=@NodeId AND JSON_QUERY(@AnswersByFormJson,CONCAT('$."',CONVERT(VARCHAR(36),v.FormId),'"')) IS NULL)
 BEGIN ROLLBACK; THROW 50181,'Complete every required step form before submitting.',1; END;
 /* Stored answers are individual immutable submissions; never overwrite original intake answers. */
 DECLARE @FormVersionId BIGINT,@FormId BIGINT,@FormAnswers NVARCHAR(MAX);
 DECLARE formAnswers CURSOR LOCAL FAST_FORWARD FOR
 SELECT nf.FormVersionId,v.FormId,JSON_QUERY(@AnswersByFormJson,CONCAT('$."',CONVERT(VARCHAR(36),v.FormId),'"'))
 FROM flow.NodeForms nf JOIN forms.Versions v ON v.FormVersionId=nf.FormVersionId
 WHERE nf.NodeId=@NodeId;
 OPEN formAnswers;FETCH NEXT FROM formAnswers INTO @FormVersionId,@FormId,@FormAnswers;
 SET @CurrentJson=(SELECT CurrentValuesJson FROM work.Cases WHERE CaseId=@CaseId);
 WHILE @@FETCH_STATUS=0
 BEGIN
  IF @FormAnswers IS NOT NULL
  BEGIN
   INSERT work.CaseFormAnswers(CaseId,FormVersionId,TaskId,AnswersJson,SubmittedBy)
   VALUES(@CaseId,@FormVersionId,@TaskId,@FormAnswers,@ActorUserId);
   DECLARE @FieldKey VARCHAR(100),@FieldValue NVARCHAR(MAX),@JsonType INT,@Path NVARCHAR(240);
   DECLARE fields CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.[key],j.value,j.[type] FROM OPENJSON(@FormAnswers) j
    JOIN forms.VersionFields f ON f.FormVersionId=@FormVersionId AND f.FieldKey=j.[key] COLLATE DATABASE_DEFAULT;
   OPEN fields;FETCH NEXT FROM fields INTO @FieldKey,@FieldValue,@JsonType;
   WHILE @@FETCH_STATUS=0
   BEGIN
    SET @Path=CONCAT('$.',@FieldKey);
    IF @JsonType IN(4,5) SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,JSON_QUERY(@FormAnswers,@Path));
    ELSE SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,@FieldValue);
    FETCH NEXT FROM fields INTO @FieldKey,@FieldValue,@JsonType;
   END;
   CLOSE fields;DEALLOCATE fields;
  END;
  FETCH NEXT FROM formAnswers INTO @FormVersionId,@FormId,@FormAnswers;
 END;
 CLOSE formAnswers;DEALLOCATE formAnswers;
 UPDATE work.Cases SET CurrentValuesJson=@CurrentJson,UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 EXEC work.usp_ReindexCaseFields @CaseId;
 UPDATE work.Tasks SET Status='Completed',CompletedAt=SYSUTCDATETIME(),CompletedBy=@ActorUserId,
  ActionCode=@Action,ActionValuesJson=@AnswersByFormJson WHERE TaskId=@TaskId;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId,DetailsJson)
 VALUES(@CaseId,'TaskCompleted',CONCAT(@Action,' · Human task completed'),@ActorUserId,
  (SELECT CONVERT(VARCHAR(36),@TaskId) AS taskId,@Action AS action,
   NULLIF(LTRIM(RTRIM(@Comment)),N'') AS comment FOR JSON PATH,WITHOUT_ARRAY_WRAPPER));
 /* A group review advances only when every task at the same node is complete. */
 IF EXISTS(SELECT 1 FROM work.Tasks WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Open')
 BEGIN COMMIT; RETURN; END;
 SELECT TOP(1) @NextNodeId=e.TargetNodeId FROM flow.Edges e
 WHERE e.WorkflowVersionId=@WorkflowVersionId AND e.SourceNodeId=@NodeId
 AND (e.OutcomeCode=@Action OR e.OutcomeCode IS NULL)
 ORDER BY CASE WHEN e.OutcomeCode=@Action THEN 0 ELSE 1 END,e.SortOrder;
 IF @NextNodeId IS NULL
 BEGIN
  IF @Action='Reject'
  BEGIN
   IF EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND RcaRequiredAtCreation=1)
    UPDATE work.Cases SET Status='Pending RCA',PendingFinalStatus='Rejected',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   ELSE UPDATE work.Cases SET Status='Rejected',ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   UPDATE work.Instances SET Status='Completed',CompletedAt=SYSUTCDATETIME() WHERE InstanceId=@InstanceId;
  END ELSE IF @Action IN('RequestInfo','RequestInformation')
   UPDATE work.Cases SET Status='Waiting for information',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  ELSE BEGIN ROLLBACK; THROW 50316,'No outgoing workflow transition matches the completed action.',1; END;
  INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
  VALUES(@CaseId,'NoTransition',N'No matching outgoing transition configured',@ActorUserId);
 END ELSE
  EXEC work.usp_ActivateNode @InstanceId,@NextNodeId,@ActorUserId,@SourceNodeId=@NodeId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Task',@EntityId=@TaskId,@ActionCode='Complete';
 COMMIT;
END;
GO
/* Managers can prioritize subordinate tasks and queue an auditable email; nothing is sent by SQL. */
CREATE OR ALTER PROCEDURE work.usp_ForceIntimation
 @ActorUserId BIGINT,@TaskId BIGINT,@Priority VARCHAR(12),@Reason NVARCHAR(1000),
 @NotificationId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @Priority NOT IN('High','Urgent') OR NULLIF(LTRIM(RTRIM(@Reason)),N'') IS NULL THROW 50182,'Priority and reason are required.',1;
 DECLARE @TeamId BIGINT,@AssignedTo BIGINT,@Stage VARCHAR(15),
 @ProjectId BIGINT,@CaseId BIGINT,@Ref NVARCHAR(55),@RecipientEmail NVARCHAR(320);
 BEGIN TRAN;
 SELECT @TeamId=t.TeamId,@AssignedTo=t.AssignedTo,@Stage=t.RoutingStage,
 @ProjectId=c.ProjectId,@CaseId=c.CaseId,@Ref=c.ReferenceNo,@RecipientEmail=u.Email
 FROM work.Tasks t WITH(UPDLOCK,HOLDLOCK) JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId LEFT JOIN auth.Users u ON u.UserId=t.AssignedTo
 WHERE t.TaskId=@TaskId AND t.Status='Open';
 IF @CaseId IS NULL OR @AssignedTo IS NULL BEGIN ROLLBACK; THROW 50183,'Active assigned task not found.',1; END;
 IF @ActorUserId=@AssignedTo BEGIN ROLLBACK; THROW 50184,'Cannot intimate yourself.',1; END;
 IF NOT EXISTS(SELECT 1 FROM teams.Members WHERE TeamId=@TeamId AND UserId=@ActorUserId AND IsActive=1
 AND (TeamRole='UnitHead' AND @Stage IN('TeamLead','Officer') OR TeamRole='TeamLead' AND @Stage='Officer'))
 BEGIN ROLLBACK; THROW 50185,'Only a Unit Head or Team Lead can intimate subordinate tasks.',1; END;
 UPDATE work.Tasks SET Priority=@Priority WHERE TaskId=@TaskId;
 SET @NotificationId=NEXT VALUE FOR notify.Seq_Outbox;
 INSERT notify.Outbox(NotificationId,ProjectId,CaseId,TaskId,Channel,LanguageCode,RecipientUserId,RecipientAddress,PayloadJson,State,IdempotencyKey)
 VALUES(@NotificationId,@ProjectId,@CaseId,@TaskId,'Email','en',@AssignedTo,@RecipientEmail,
  (SELECT @Ref AS reference,@Priority AS priority,@Reason AS reason FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
  'Pending',CONCAT('intimation:',CONVERT(VARCHAR(36),@TaskId),':',CONVERT(VARCHAR(36),@NotificationId)));
 INSERT work.ForceIntimations(TaskId,ManagerUserId,TargetUserId,NewPriority,Reason,NotificationId)
 VALUES(@TaskId,@ActorUserId,@AssignedTo,@Priority,@Reason,@NotificationId);
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
 VALUES(@CaseId,'ForceIntimation',CONCAT('Force intimation · ',@Priority,' · Email queued (not sent)'),@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Task',@EntityId=@TaskId,@ActionCode='ForceIntimation';
 COMMIT;
END;
GO
/* Submission of configured RCA is the actual closure gate, with a permanent audit event. */
CREATE OR ALTER PROCEDURE work.usp_SubmitRca
 @ActorUserId BIGINT,@CaseId BIGINT,@Summary NVARCHAR(MAX),
 @FieldsJson NVARCHAR(MAX),@RootReasonItemId BIGINT=NULL,@FormAnswersJson NVARCHAR(MAX)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF NULLIF(LTRIM(RTRIM(@Summary)),N'') IS NULL THROW 50186,'RCA summary is required.',1;
 IF ISJSON(@FieldsJson)<>1 THROW 50187,'RCA field answers must be a JSON object.',1;
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
 IF EXISTS(SELECT 1 FROM OPENJSON(@RcaFieldsSnapshotJson) WITH(
 FieldKey VARCHAR(90) '$.FieldKey',Required BIT '$.Required',ParentFieldKey VARCHAR(90) '$.ParentFieldKey',ParentValue NVARCHAR(150) '$.ParentValue') f
 WHERE f.Required=1 AND (f.ParentFieldKey IS NULL OR JSON_VALUE(@FieldsJson,CONCAT('$.',f.ParentFieldKey))=f.ParentValue)
 AND NULLIF(LTRIM(ISNULL(JSON_VALUE(@FieldsJson,CONCAT('$.',f.FieldKey)),N'')),N'') IS NULL)
 BEGIN ROLLBACK; THROW 50191,'Complete all required visible RCA fields.',1; END;
 INSERT work.CaseRca(CaseId,TemplateId,RootReasonItemId,Summary,FieldsJson,FormAnswersJson,CompletedBy)
 VALUES(@CaseId,@TemplateId,@RootReasonItemId,@Summary,@FieldsJson,@FormAnswersJson,@ActorUserId);
 UPDATE work.Cases SET Status=CASE WHEN @FinalStatus='Rejected' THEN 'Rejected' ELSE 'Closed' END,
 ClosedAt=SYSUTCDATETIME(),UpdatedAt=SYSUTCDATETIME(),PendingFinalStatus=NULL WHERE CaseId=@CaseId;
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId) VALUES(@CaseId,'RcaCompleted',N'RCA submitted and case closed',@ActorUserId);
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='RCA',@EntityId=@CaseId,@ActionCode='Complete';
 COMMIT;
END;
GO
/* Assign an unassigned task (e.g., after AD resignation or missing hierarchy role). */
CREATE OR ALTER PROCEDURE work.usp_AssignUnassignedTask
 @ActorUserId BIGINT,@TaskId BIGINT,@ToUserId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@TeamId BIGINT,@CaseId BIGINT,@Stage VARCHAR(15);
 BEGIN TRAN;
 SELECT @ProjectId=c.ProjectId,@TeamId=t.TeamId,@CaseId=c.CaseId
 FROM work.Tasks t WITH(UPDLOCK,HOLDLOCK) JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId WHERE t.TaskId=@TaskId AND t.Status='Open' AND t.AssignedTo IS NULL;
 IF @CaseId IS NULL BEGIN ROLLBACK; THROW 50200,'No unassigned open task found.',1; END;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 AND NOT EXISTS(SELECT 1 FROM teams.Members
  WHERE TeamId=@TeamId AND UserId=@ActorUserId AND IsActive=1 AND TeamRole IN('UnitHead','TeamLead'))
 BEGIN ROLLBACK; THROW 50201,'Only the project admin or a team manager can assign this task.',1; END;
 SELECT TOP(1) @Stage=m.TeamRole FROM teams.Members m JOIN auth.Users u ON u.UserId=m.UserId
 WHERE m.TeamId=@TeamId AND m.UserId=@ToUserId AND m.IsActive=1 AND u.IsActive=1 AND u.DirectoryStatus='Active';
 IF @Stage IS NULL BEGIN ROLLBACK; THROW 50202,'Recipient is not active in this team.',1; END;
 UPDATE work.Tasks SET AssignedTo=@ToUserId,RoutingStage=@Stage,AssignedAt=SYSUTCDATETIME() WHERE TaskId=@TaskId;
 INSERT work.TaskHandoffs(TaskId,ToUserId,RoutingStage,ActorUserId,Reason)
 VALUES(@TaskId,@ToUserId,@Stage,@ActorUserId,'Manual assignment of unallocated task');
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
 VALUES(@CaseId,'TaskAssigned',N'Manager assigned previously unassigned work',@ActorUserId);
 COMMIT;
END;
GO
/* File binary uploads, malware scan and signed download URLs are implemented in the API/storage layer. */
CREATE OR ALTER PROCEDURE files.usp_RegisterDocument
 @ActorUserId BIGINT,@ProjectId BIGINT,@CaseId BIGINT,
 @TaskId BIGINT=NULL,@FormVersionId BIGINT=NULL,
 @FieldKey VARCHAR(100)=NULL,@StorageKey NVARCHAR(600),@OriginalFileName NVARCHAR(260),
 @MimeType NVARCHAR(120),@FileSizeBytes BIGINT,@Sha256 VARBINARY(32)=NULL,
 @DocumentId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.manage')<>1
 AND auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.create')<>1 THROW 50203,'No file upload permission.',1;
 IF NOT EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND ProjectId=@ProjectId) THROW 50204,'Case is outside the project.',1;
 IF @TaskId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
 WHERE t.TaskId=@TaskId AND i.CaseId=@CaseId) THROW 50205,'Task is outside the case.',1;
 IF @FileSizeBytes<=0 OR @FileSizeBytes>20971520 THROW 50206,'File size must be between 1 byte and 20 MB.',1;
 IF NULLIF(LTRIM(@StorageKey),N'') IS NULL THROW 50207,'External storage key is required.',1;
 IF @FormVersionId IS NOT NULL AND @FieldKey IS NOT NULL AND NOT EXISTS(SELECT 1 FROM forms.VersionFields
 WHERE FormVersionId=@FormVersionId AND FieldKey=@FieldKey AND FieldType='attachment')
 THROW 50208,'Selected form field is not an attachment field.',1;
 IF @FormVersionId IS NOT NULL AND @FieldKey IS NOT NULL AND EXISTS(SELECT 1 FROM forms.VersionFields
 WHERE FormVersionId=@FormVersionId AND FieldKey=@FieldKey AND MaxFileMB IS NOT NULL AND @FileSizeBytes>CONVERT(BIGINT,MaxFileMB)*1048576)
 THROW 50209,'File exceeds this field size limit.',1;
 DECLARE @FieldFileLimit SMALLINT,@AllowedExtensions NVARCHAR(300),@FileExtension NVARCHAR(30);
 SELECT @FieldFileLimit=MaxFiles,@AllowedExtensions=AllowedExtensions FROM forms.VersionFields
 WHERE FormVersionId=@FormVersionId AND FieldKey=@FieldKey;
 IF @FieldFileLimit IS NOT NULL AND (SELECT COUNT(*) FROM files.Documents
 WHERE CaseId=@CaseId AND FormVersionId=@FormVersionId AND FieldKey=@FieldKey AND IsDeleted=0)>=@FieldFileLimit
 THROW 50226,'This field has reached its file-count limit.',1;
 SET @FileExtension=CASE WHEN CHARINDEX('.',REVERSE(@OriginalFileName))=0 THEN N''
 ELSE LOWER(RIGHT(@OriginalFileName,CHARINDEX('.',REVERSE(@OriginalFileName)))) END;
 IF NULLIF(LTRIM(@AllowedExtensions),N'') IS NOT NULL AND
  CHARINDEX(CONCAT(',',@FileExtension,','),CONCAT(',',REPLACE(LOWER(@AllowedExtensions),' ',''),','))=0
 THROW 50227,'This file extension is not allowed for the field.',1;
 BEGIN TRAN;
 SET @DocumentId=NEXT VALUE FOR files.Seq_Documents;
 INSERT files.Documents(DocumentId,ProjectId,CaseId,TaskId,FormVersionId,FieldKey,StorageKey,
 OriginalFileName,MimeType,FileSizeBytes,Sha256,UploadedBy)
 VALUES(@DocumentId,@ProjectId,@CaseId,@TaskId,@FormVersionId,@FieldKey,@StorageKey,
 @OriginalFileName,@MimeType,@FileSizeBytes,@Sha256,@ActorUserId);
 INSERT work.CaseEvents(CaseId,EventType,Message,ActorUserId)
 VALUES(@CaseId,'DocumentRegistered',N'Document registered; awaiting security scan',@ActorUserId);
 COMMIT;
END;
GO
/* Provider processing is external. Outbox states distinguish accepted vs delivered. */
CREATE OR ALTER PROCEDURE notify.usp_ClaimOutbox @BatchSize INT=50
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize<1 OR @BatchSize>500 THROW 50210,'BatchSize must be 1–500.',1;
 BEGIN TRAN;
 ;WITH nextBatch AS (
  SELECT TOP (@BatchSize) * FROM notify.Outbox WITH(UPDLOCK,READPAST,ROWLOCK)
  WHERE (State IN('Pending','Failed','Sending')) AND NextAttemptAt<=SYSUTCDATETIME() AND Attempts<8
  ORDER BY NextAttemptAt,CreatedAt
 )
 UPDATE nextBatch SET State='Sending',Attempts=Attempts+1,
  NextAttemptAt=DATEADD(MINUTE,2,SYSUTCDATETIME())
 OUTPUT inserted.NotificationId,inserted.ProjectId,inserted.Channel,inserted.LanguageCode,
 inserted.RecipientUserId,inserted.RecipientAddress,inserted.PayloadJson,inserted.Attempts;
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE notify.usp_RecordDelivery
 @NotificationId BIGINT,@Outcome VARCHAR(20),@ProviderMessageId NVARCHAR(200)=NULL,
 @HttpStatus INT=NULL,@Error NVARCHAR(800)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @Outcome NOT IN('Accepted','Delivered','Failed','Preview') THROW 50211,'Invalid delivery outcome.',1;
 BEGIN TRAN;
 UPDATE notify.Outbox SET State=@Outcome,ProviderMessageId=@ProviderMessageId,LastError=@Error,
  NextAttemptAt=CASE WHEN @Outcome='Failed' THEN DATEADD(MINUTE,POWER(CONVERT(FLOAT,2),CASE WHEN Attempts>6 THEN 6 ELSE Attempts END),SYSUTCDATETIME()) ELSE NextAttemptAt END,
  SentAt=CASE WHEN @Outcome IN('Accepted','Delivered') THEN SYSUTCDATETIME() ELSE SentAt END
 WHERE NotificationId=@NotificationId AND State IN('Sending','Accepted');
 IF @@ROWCOUNT=0 BEGIN ROLLBACK; THROW 50212,'Notification not in a deliverable state.',1; END;
 INSERT notify.DeliveryAttempts(NotificationId,Outcome,HttpStatus,ProviderResponse)
 VALUES(@NotificationId,@Outcome,@HttpStatus,LEFT(@Error,1000));
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE work.usp_EscalateOverdueTasks @BatchSize INT=50
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize NOT BETWEEN 1 AND 200 THROW 50410,'Invalid SLA batch size.',1;
 BEGIN TRAN;
 DECLARE @Due TABLE(TaskId BIGINT PRIMARY KEY,ProjectId BIGINT,CaseId BIGINT,Recipient BIGINT,
  Address NVARCHAR(320),ReferenceNo NVARCHAR(55));
 INSERT @Due
 SELECT TOP(@BatchSize) t.TaskId,c.ProjectId,c.CaseId,t.AssignedTo,u.Email,c.ReferenceNo
 FROM work.Tasks t WITH(UPDLOCK,READPAST,ROWLOCK)
 JOIN work.Instances inst ON inst.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=inst.CaseId
 LEFT JOIN auth.Users u ON u.UserId=t.AssignedTo AND u.IsActive=1
 WHERE t.Status='Open' AND t.DueAt IS NOT NULL AND t.DueAt<=SYSUTCDATETIME()
 AND NOT EXISTS(SELECT 1 FROM work.SlaEscalations sla WHERE sla.TaskId=t.TaskId)
 ORDER BY t.DueAt,t.TaskId;
 INSERT work.SlaEscalations(TaskId,ProjectId) SELECT TaskId,ProjectId FROM @Due;
 UPDATE t SET Priority='Urgent' FROM work.Tasks t JOIN @Due d ON d.TaskId=t.TaskId;
 INSERT work.CaseEvents(CaseId,EventType,Message,DetailsJson)
 SELECT CaseId,'TaskSlaBreached',N'Task SLA breached; escalated to urgent priority',
 (SELECT d.TaskId AS taskId FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM @Due d;
 DECLARE @RuleTask BIGINT,@RuleProject BIGINT,@RuleCase BIGINT,@RuleRecipient BIGINT;
 DECLARE ruleDue CURSOR LOCAL FAST_FORWARD FOR SELECT TaskId,ProjectId,CaseId,Recipient FROM @Due;
 OPEN ruleDue;FETCH NEXT FROM ruleDue INTO @RuleTask,@RuleProject,@RuleCase,@RuleRecipient;
 WHILE @@FETCH_STATUS=0
 BEGIN
  EXEC notify.usp_QueueConfiguredEvent 'SLA_BREACHED',@RuleProject,@RuleCase,@TaskId=@RuleTask,@RecipientUserId=@RuleRecipient;
  FETCH NEXT FROM ruleDue INTO @RuleTask,@RuleProject,@RuleCase,@RuleRecipient;
 END;
 CLOSE ruleDue;DEALLOCATE ruleDue;
 DECLARE @TaskId BIGINT,@ProjectId BIGINT,@CaseId BIGINT,@Recipient BIGINT,@Address NVARCHAR(320),@Ref NVARCHAR(55),@NotificationId BIGINT;
 DECLARE dueTasks CURSOR LOCAL FAST_FORWARD FOR SELECT TaskId,ProjectId,CaseId,Recipient,Address,ReferenceNo FROM @Due WHERE NULLIF(Address,'') IS NOT NULL;
 OPEN dueTasks;FETCH NEXT FROM dueTasks INTO @TaskId,@ProjectId,@CaseId,@Recipient,@Address,@Ref;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @NotificationId=NEXT VALUE FOR notify.Seq_Outbox;
  INSERT notify.Outbox(NotificationId,ProjectId,CaseId,TaskId,Channel,RecipientUserId,RecipientAddress,PayloadJson,IdempotencyKey)
   VALUES(@NotificationId,@ProjectId,@CaseId,@TaskId,'Email',@Recipient,@Address,
   (SELECT CONCAT(N'SLA overdue: ',@Ref) AS subject,
    CONCAT(N'The assigned task for case ',@Ref,N' is overdue. Please take action.') AS body FOR JSON PATH,WITHOUT_ARRAY_WRAPPER),
    CONCAT('sla:',CONVERT(VARCHAR(36),@TaskId)));
  UPDATE work.SlaEscalations SET NotificationId=@NotificationId WHERE TaskId=@TaskId;
  FETCH NEXT FROM dueTasks INTO @TaskId,@ProjectId,@CaseId,@Recipient,@Address,@Ref;
 END;
 CLOSE dueTasks;DEALLOCATE dueTasks;
 COMMIT;
 SELECT (SELECT COUNT(*) FROM @Due) AS EscalatedCount;
END;
GO
/* A dedicated queue claim procedure avoids granting table UPDATE to the API login. */
CREATE OR ALTER PROCEDURE integration.usp_ClaimWorkflowExecutions @BatchSize INT=8
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @BatchSize NOT BETWEEN 1 AND 30 THROW 50320,'Invalid workflow integration batch size.',1;
 BEGIN TRAN;
 ;WITH nextBatch AS (
  SELECT TOP(@BatchSize) * FROM integration.Executions WITH(UPDLOCK,READPAST,ROWLOCK)
  WHERE NodeId IS NOT NULL AND CaseId IS NOT NULL AND AttemptCount<5
    AND (Status='Pending' OR Status='Running' AND StartedAt<DATEADD(MINUTE,-3,SYSUTCDATETIME())
    OR Status='Failed' AND FinishedAt<DATEADD(SECOND,-60,SYSUTCDATETIME()))
  ORDER BY ExecutionId
 )
 UPDATE nextBatch SET Status='Running',StartedAt=SYSUTCDATETIME(),
  AttemptCount=AttemptCount+CASE WHEN Status='Running' THEN 1 ELSE 0 END
 OUTPUT inserted.ExecutionId,inserted.CaseId,inserted.NodeId,inserted.OperationId,inserted.IdempotencyKey;
 COMMIT;
END;
GO
/* No direct table UPDATE privileges are needed by the attachment scanning background service. */
CREATE OR ALTER PROCEDURE files.usp_RecordScanResult @DocumentId BIGINT,@Clean BIT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 BEGIN TRAN;
 DECLARE @CaseId BIGINT;
 SELECT @CaseId=CaseId FROM files.Documents WITH(UPDLOCK,HOLDLOCK)
  WHERE DocumentId=@DocumentId AND ScanStatus='Pending' AND IsDeleted=0;
 IF @CaseId IS NULL AND NOT EXISTS(SELECT 1 FROM files.Documents WHERE DocumentId=@DocumentId AND ScanStatus='Pending' AND IsDeleted=0)
 BEGIN ROLLBACK; THROW 50321,'Attachment has already been scanned, deleted or does not exist.',1; END;
 UPDATE files.Documents SET ScanStatus=CASE WHEN @Clean=1 THEN 'Clean' ELSE 'Rejected' END
  WHERE DocumentId=@DocumentId AND ScanStatus='Pending' AND IsDeleted=0;
 IF @CaseId IS NOT NULL INSERT work.CaseEvents(CaseId,EventType,Message)
 VALUES(@CaseId,'DocumentScanned',CASE WHEN @Clean=1 THEN N'Attachment security scan passed' ELSE N'Attachment rejected by malware scanner' END);
 COMMIT;
END;
GO
/* Integration service records test/run results with redacted payloads, never API keys. */
CREATE OR ALTER PROCEDURE integration.usp_RecordResult
 @ExecutionId BIGINT,@Succeeded BIT,@ResponseRedactedJson NVARCHAR(MAX)=NULL,
 @MappedFieldsJson NVARCHAR(MAX)=NULL,@Error NVARCHAR(1000)=NULL
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @ResponseRedactedJson IS NOT NULL AND ISJSON(@ResponseRedactedJson)<>1 THROW 50213,'Response must be JSON.',1;
 IF @MappedFieldsJson IS NOT NULL AND (ISJSON(@MappedFieldsJson)<>1 OR LEFT(LTRIM(@MappedFieldsJson),1)<>'{') THROW 50214,'Mapped response must be a JSON object.',1;
 DECLARE @CaseId BIGINT,@ProjectId BIGINT,@NodeId BIGINT,@CurrentJson NVARCHAR(MAX);
 BEGIN TRAN;
 SELECT @CaseId=CaseId,@ProjectId=ProjectId,@NodeId=NodeId FROM integration.Executions WITH(UPDLOCK,HOLDLOCK)
 WHERE ExecutionId=@ExecutionId AND Status IN('Running','Pending','Failed');
 IF @ProjectId IS NULL BEGIN ROLLBACK; THROW 50215,'Execution does not exist or is already completed.',1; END;
 UPDATE integration.Executions SET Status=CASE WHEN @Succeeded=1 THEN 'Succeeded' ELSE 'Failed' END,
 FinishedAt=SYSUTCDATETIME(),LastError=@Error,ResponseRedactedJson=@ResponseRedactedJson,
 MappedFieldsJson=@MappedFieldsJson,AttemptCount=AttemptCount+1 WHERE ExecutionId=@ExecutionId;
 IF @CaseId IS NOT NULL
 BEGIN
  IF @Succeeded=1 AND @MappedFieldsJson IS NOT NULL
  BEGIN
   SELECT @CurrentJson=CurrentValuesJson FROM work.Cases WITH(UPDLOCK,HOLDLOCK) WHERE CaseId=@CaseId;
   DECLARE @Key NVARCHAR(200),@Val NVARCHAR(MAX),@JsonType INT,@Path NVARCHAR(240);
   DECLARE mapped CURSOR LOCAL FAST_FORWARD FOR SELECT [key],[value],[type] FROM OPENJSON(@MappedFieldsJson);
   OPEN mapped;FETCH NEXT FROM mapped INTO @Key,@Val,@JsonType;
   WHILE @@FETCH_STATUS=0
   BEGIN
    /* Keep mapping names simple and predictable; do not execute arbitrary JSON-path expressions. */
    IF LEN(@Key)>100 OR @Key LIKE '%[^A-Za-z0-9_]%' COLLATE Latin1_General_BIN2
    BEGIN CLOSE mapped;DEALLOCATE mapped;ROLLBACK; THROW 50216,'Mapped field keys may contain only letters, numbers and underscore.',1; END;
    SET @Path=CONCAT('$.',@Key);
    IF @JsonType IN(4,5) SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,JSON_QUERY(@MappedFieldsJson,@Path));
    ELSE SET @CurrentJson=JSON_MODIFY(@CurrentJson,@Path,@Val);
    FETCH NEXT FROM mapped INTO @Key,@Val,@JsonType;
   END;
   CLOSE mapped;DEALLOCATE mapped;
   UPDATE work.Cases SET CurrentValuesJson=@CurrentJson,UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
   EXEC work.usp_ReindexCaseFields @CaseId;
  END;
  IF @Succeeded=0 UPDATE work.Cases SET Status='Integration failed',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
  INSERT work.CaseEvents(CaseId,EventType,Message) VALUES(@CaseId,CASE WHEN @Succeeded=1 THEN 'IntegrationSucceeded' ELSE 'IntegrationFailed' END,
  CASE WHEN @Succeeded=1 THEN N'External integration completed' ELSE N'External integration failed; retry required' END);
 END;
 COMMIT;
END;
GO
/* Workflow backend calls this after a successful provider result or when a verified timer is due. */
CREATE OR ALTER PROCEDURE work.usp_ResumeSystemNode
 @InstanceId BIGINT,@NodeId BIGINT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 DECLARE @CaseId BIGINT,@VersionId BIGINT,@NextNodeId BIGINT,@Kind VARCHAR(30);
 BEGIN TRAN;
 SELECT @CaseId=CaseId,@VersionId=WorkflowVersionId FROM work.Instances WITH(UPDLOCK,HOLDLOCK)
 WHERE InstanceId=@InstanceId AND Status IN('Running','Waiting');
 SELECT @Kind=NodeType FROM flow.Nodes WHERE NodeId=@NodeId AND WorkflowVersionId=@VersionId;
 IF @CaseId IS NULL OR @Kind NOT IN('dataSource','wait','notify') BEGIN ROLLBACK; THROW 50217,'Invalid instance/system node.',1; END;
 IF @Kind='dataSource'
 BEGIN
  /* Only one continuation may consume each successfully executed node. Transactional
     marker survives crashes and concurrent workers, and the rollback restores it. */
  UPDATE integration.Executions SET ResumedAt=SYSUTCDATETIME()
   WHERE ExecutionId=(SELECT TOP(1) ExecutionId FROM integration.Executions WITH(UPDLOCK,HOLDLOCK)
    WHERE CaseId=@CaseId AND NodeId=@NodeId AND Status='Succeeded' AND ResumedAt IS NULL
    ORDER BY ExecutionId);
  IF @@ROWCOUNT=0 BEGIN ROLLBACK; THROW 50218,'Cannot resume an uncompleted or previously resumed integration.',1; END;
 END;
 IF @Kind='wait'
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM work.PendingTimers WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Pending' AND WakeAtUtc<=SYSUTCDATETIME())
  BEGIN ROLLBACK; THROW 50219,'Timer is not due.',1; END;
  UPDATE work.PendingTimers SET Status='Resumed' WHERE InstanceId=@InstanceId AND NodeId=@NodeId AND Status='Pending';
 END;
 IF @Kind='notify'
 BEGIN
  UPDATE sn SET ResumedAt=SYSUTCDATETIME() FROM work.SystemNotifications sn WITH(UPDLOCK,HOLDLOCK)
  JOIN notify.Outbox o ON o.NotificationId=sn.NotificationId AND o.State IN('Accepted','Delivered')
  WHERE sn.InstanceId=@InstanceId AND sn.NodeId=@NodeId AND sn.ResumedAt IS NULL;
  IF @@ROWCOUNT=0 BEGIN ROLLBACK; THROW 50220,'Notification has not been accepted or was previously resumed.',1; END;
 END;
 SELECT TOP(1) @NextNodeId=TargetNodeId FROM flow.Edges
 WHERE WorkflowVersionId=@VersionId AND SourceNodeId=@NodeId ORDER BY SortOrder;
 IF @NextNodeId IS NULL BEGIN ROLLBACK; THROW 50221,'System node has no outgoing connection.',1; END;
 UPDATE work.Cases SET Status='In progress',UpdatedAt=SYSUTCDATETIME() WHERE CaseId=@CaseId;
 UPDATE work.Instances SET Status='Running' WHERE InstanceId=@InstanceId;
 EXEC work.usp_ActivateNode @InstanceId,@NextNodeId,@SourceNodeId=@NodeId;
 COMMIT;
END;
GO
/* 21: Project-scoped read endpoints for cases, My Tasks, case audit and reports. */
CREATE OR ALTER PROCEDURE work.usp_GetMyTasks @ActorUserId BIGINT,@ProjectId BIGINT,@IncludeCompleted BIT=0
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'cases.view')<>1 THROW 50222,'No access to project tasks.',1;
 SELECT t.TaskId,c.CaseId,c.ReferenceNo,c.Title,c.Status AS CaseStatus,
 t.Status AS TaskStatus,t.Priority,t.RoutingStage,t.CreatedAt,t.DueAt,t.CompletedAt,t.ActionCode,
 n.Label AS StepName,tm.Name AS TeamName,t.TeamId
 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
 JOIN work.Cases c ON c.CaseId=i.CaseId JOIN flow.Nodes n ON n.NodeId=t.NodeId
 LEFT JOIN teams.Teams tm ON tm.TeamId=t.TeamId
 WHERE c.ProjectId=@ProjectId AND (t.AssignedTo=@ActorUserId OR t.CompletedBy=@ActorUserId)
 AND (@IncludeCompleted=1 OR t.Status='Open')
 ORDER BY CASE t.Priority WHEN 'Urgent' THEN 0 WHEN 'High' THEN 1 ELSE 2 END,
 t.DueAt,t.CreatedAt DESC;
END;
GO
CREATE OR ALTER PROCEDURE work.usp_GetCaseDetails @ActorUserId BIGINT,@ProjectId BIGINT,@CaseId BIGINT
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @Allowed BIT=0;
 IF NOT EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND ProjectId=@ProjectId) THROW 50223,'Case not found in project.',1;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)=1 OR EXISTS(SELECT 1 FROM work.Cases WHERE CaseId=@CaseId AND CreatedBy=@ActorUserId)
  OR EXISTS(SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
    LEFT JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@ActorUserId AND m.IsActive=1
    WHERE i.CaseId=@CaseId AND (t.AssignedTo=@ActorUserId OR m.UserId IS NOT NULL)) SET @Allowed=1;
 IF @Allowed<>1 THROW 50224,'User is not authorized to view this case.',1;
 SELECT * FROM work.Cases WHERE CaseId=@CaseId;
 SELECT t.* FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId WHERE i.CaseId=@CaseId ORDER BY t.CreatedAt;
 SELECT EventId,EventType,Message,ActorUserId,DetailsJson,OccurredAt FROM work.CaseEvents WHERE CaseId=@CaseId ORDER BY EventId;
 SELECT AnswerId,FormVersionId,TaskId,AnswersJson,SubmittedBy,SubmittedAt FROM work.CaseFormAnswers WHERE CaseId=@CaseId ORDER BY SubmittedAt;
 SELECT DocumentId,TaskId,FieldKey,OriginalFileName,MimeType,FileSizeBytes,ScanStatus,UploadedAt FROM files.Documents WHERE CaseId=@CaseId AND IsDeleted=0 ORDER BY UploadedAt;
END;
GO
CREATE OR ALTER PROCEDURE reports.usp_CaseSummary
 @ActorUserId BIGINT,@ProjectId BIGINT,@FromUtc DATETIME2(3)=NULL,@ToUtc DATETIME2(3)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_HasPermission(@ActorUserId,@ProjectId,'reports.view')<>1 THROW 50225,'Reports permission required.',1;
 DECLARE @FullProject BIT=auth.fn_IsAdmin(@ActorUserId,@ProjectId);
 IF EXISTS(SELECT 1 FROM auth.RoleAssignments a JOIN auth.Roles r ON r.RoleId=a.RoleId
 JOIN auth.RolePermissions rp ON rp.RoleId=r.RoleId AND rp.PermissionCode='reports.view'
 WHERE a.UserId=@ActorUserId AND a.ProjectId=@ProjectId AND a.TeamId IS NULL AND a.IsActive=1 AND r.Scope='Project')
 SET @FullProject=1;
 CREATE TABLE #VisibleCases(CaseId BIGINT PRIMARY KEY);
 INSERT #VisibleCases(CaseId)
 SELECT c.CaseId FROM work.Cases c WHERE c.ProjectId=@ProjectId
 AND (@FromUtc IS NULL OR c.CreatedAt>=@FromUtc) AND (@ToUtc IS NULL OR c.CreatedAt<@ToUtc)
 AND (@FullProject=1 OR c.CreatedBy=@ActorUserId OR EXISTS(
  SELECT 1 FROM work.Tasks t JOIN work.Instances i ON i.InstanceId=t.InstanceId
  LEFT JOIN teams.Members m ON m.TeamId=t.TeamId AND m.UserId=@ActorUserId AND m.IsActive=1
  WHERE i.CaseId=c.CaseId AND (t.AssignedTo=@ActorUserId OR m.UserId IS NOT NULL)));
 SELECT c.Status,COUNT_BIG(*) AS Total,COUNT_BIG(CASE WHEN c.ClosedAt IS NULL THEN 1 END) AS OpenCount,
 COUNT_BIG(CASE WHEN c.DueAt<SYSUTCDATETIME() AND c.ClosedAt IS NULL THEN 1 END) AS OverdueCount
 FROM work.Cases c JOIN #VisibleCases v ON v.CaseId=c.CaseId
 GROUP BY c.Status ORDER BY c.Status;
 SELECT ct.Name AS CaseType,COUNT_BIG(*) AS Total
 FROM work.Cases c JOIN #VisibleCases vis ON vis.CaseId=c.CaseId
 JOIN core.CaseTypeVersions ctv ON ctv.CaseTypeVersionId=c.CaseTypeVersionId
 JOIN core.CaseTypes ct ON ct.CaseTypeId=ctv.CaseTypeId
 GROUP BY ct.Name ORDER BY Total DESC;
END;
GO
/* Read-only platform health checks, useful after SSMS F5 and before .NET integration. */
CREATE OR ALTER PROCEDURE core.usp_DatabaseHealth
AS
BEGIN
 SET NOCOUNT ON;
 SELECT DB_NAME() AS DatabaseName,SERVERPROPERTY('ProductVersion') AS SqlServerVersion,
 (SELECT COUNT(*) FROM core.Projects) AS ProjectCount,
 (SELECT COUNT_BIG(*) FROM work.Cases) AS CaseCount,
 (SELECT COUNT(*) FROM auth.Roles) AS RoleCount,
 (SELECT COUNT(*) FROM auth.Permissions) AS PermissionCount,
 SYSUTCDATETIME() AS UtcNow;
END;
GO
/* Project RCA Setup screen: admins can customize fields without altering global RCA templates. */
CREATE OR ALTER PROCEDURE core.usp_SetProjectRcaFields
 @ActorUserId BIGINT,@ProjectId BIGINT,@FieldsJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50346,'Project Admin required.',1;
 IF ISJSON(@FieldsJson)<>1 OR LEFT(LTRIM(@FieldsJson),1)<>'[' THROW 50347,'RCA field definitions must be a JSON array.',1;
 IF NOT EXISTS(SELECT 1 FROM core.Projects WHERE ProjectId=@ProjectId AND RcaRequired=1)
 THROW 50348,'This project does not require RCA.',1;
 IF EXISTS(SELECT JSON_VALUE(value,'$.key') FROM OPENJSON(@FieldsJson)
 GROUP BY JSON_VALUE(value,'$.key') HAVING COUNT(*)>1) THROW 50349,'Duplicate RCA field keys.',1;
 BEGIN TRAN;
 DELETE FROM core.ProjectRcaFields WHERE ProjectId=@ProjectId;
 INSERT core.ProjectRcaFields(ProjectId,FieldKey,ConfigJson,SortOrder)
 SELECT @ProjectId,JSON_VALUE(j.value,'$.key'),j.value,CONVERT(INT,j.[key])
 FROM OPENJSON(@FieldsJson) j;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,
  @EntityType='ProjectRCA',@EntityId=@ProjectId,@ActionCode='UpdateFields';
 COMMIT;
END;
GO
/* 22: Configuration API procedures (catalog maintenance, no seed/demo project assumptions). */
CREATE OR ALTER PROCEDURE auth.usp_SaveCustomRole
 @ActorUserId BIGINT,@Name NVARCHAR(150),@Code VARCHAR(65)=NULL,
 @Scope VARCHAR(16)='Project',@PermissionsJson NVARCHAR(MAX),@RoleId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'roles.assign')<>1 THROW 50300,'Platform Admin required to manage role definitions.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50301,'Invalid role code.',1;
 IF @Scope NOT IN('Project','Team') THROW 50302,'Custom roles may only have project or team scope.',1;
 IF ISJSON(@PermissionsJson)<>1 OR LEFT(LTRIM(@PermissionsJson),1)<>'[' THROW 50303,'Permissions must be a JSON array.',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@PermissionsJson) j WHERE NOT EXISTS(
 SELECT 1 FROM auth.Permissions p WHERE p.PermissionCode=j.value)) THROW 50304,'Unknown permission code.',1;
 BEGIN TRAN;
 IF @RoleId IS NULL
 BEGIN
  IF EXISTS(SELECT 1 FROM auth.Roles WHERE Code=@Code) BEGIN ROLLBACK; THROW 50305,'Role code already exists.',1; END;
  SET @RoleId=NEXT VALUE FOR auth.Seq_Roles;
  INSERT auth.Roles(RoleId,Code,Name,Scope,IsSystem) VALUES(@RoleId,@Code,@Name,@Scope,0);
 END ELSE
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM auth.Roles WHERE RoleId=@RoleId AND IsSystem=0) BEGIN ROLLBACK; THROW 50306,'Cannot edit a system role here.',1; END;
  UPDATE auth.Roles SET Name=@Name,Code=@Code,Scope=@Scope WHERE RoleId=@RoleId;
 END;
 DELETE FROM auth.RolePermissions WHERE RoleId=@RoleId;
 INSERT auth.RolePermissions(RoleId,PermissionCode) SELECT DISTINCT @RoleId,j.value FROM OPENJSON(@PermissionsJson) j;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='Role',@EntityId=@RoleId,@ActionCode='SaveRoleRights';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE forms.usp_SaveLibraryField
 @ActorUserId BIGINT,@ProjectId BIGINT=NULL,@Name NVARCHAR(200),
 @Code VARCHAR(90)=NULL,@FieldType VARCHAR(25),@DefaultConfigJson NVARCHAR(MAX)=N'{}',
 @LibraryFieldId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @ProjectId IS NULL AND auth.fn_HasPermission(@ActorUserId,NULL,'forms.manage')<>1
 OR @ProjectId IS NOT NULL AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1
 THROW 50307,'Forms configuration permission required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50308,'Invalid field code.',1;
 IF @FieldType NOT IN('text','textarea','number','date','select','checkbox','email','attachment') THROW 50309,'Invalid field type.',1;
 IF ISJSON(@DefaultConfigJson)<>1 THROW 50310,'Field settings must be JSON.',1;
 BEGIN TRAN;
 IF @LibraryFieldId IS NULL
 BEGIN
  SET @LibraryFieldId=NEXT VALUE FOR forms.Seq_FieldLibrary;
  INSERT forms.FieldLibrary(LibraryFieldId,ProjectId,Code,Label,FieldType,DefaultConfigJson)
  VALUES(@LibraryFieldId,@ProjectId,@Code,@Name,@FieldType,@DefaultConfigJson);
 END ELSE
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM forms.FieldLibrary WHERE LibraryFieldId=@LibraryFieldId AND
  (ProjectId=@ProjectId OR ProjectId IS NULL AND @ProjectId IS NULL)) BEGIN ROLLBACK; THROW 50311,'Field not found in requested scope.',1; END;
  UPDATE forms.FieldLibrary SET Label=@Name,FieldType=@FieldType,DefaultConfigJson=@DefaultConfigJson
  WHERE LibraryFieldId=@LibraryFieldId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='FieldLibrary',@EntityId=@LibraryFieldId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE core.usp_SaveRcaTemplate
 @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,
 @FieldsJson NVARCHAR(MAX),@RcaTemplateId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50312,'Platform Admin required.',1;
 IF ISJSON(@FieldsJson)<>1 OR LEFT(LTRIM(@FieldsJson),1)<>'[' THROW 50313,'RCA fields must be an array.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50314,'Invalid RCA code.',1;
 BEGIN TRAN;
 IF @RcaTemplateId IS NULL BEGIN
  SET @RcaTemplateId=NEXT VALUE FOR core.Seq_RcaTemplates;
  INSERT core.RcaTemplates(RcaTemplateId,Code,Name) VALUES(@RcaTemplateId,@Code,@Name);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM core.RcaTemplates WHERE RcaTemplateId=@RcaTemplateId) BEGIN ROLLBACK; THROW 50315,'RCA template not found.',1; END;
  UPDATE core.RcaTemplates SET Name=@Name,Version=Version+1 WHERE RcaTemplateId=@RcaTemplateId;
 END;
 /* Existing cases must retain their own RCA version snapshot in the backend at case creation. */
 DELETE FROM core.RcaTemplateFields WHERE RcaTemplateId=@RcaTemplateId;
 INSERT core.RcaTemplateFields(RcaTemplateId,FieldKey,Label,FieldType,Required,ParentFieldKey,ParentValue,OptionsJson,SortOrder)
 SELECT @RcaTemplateId,
 JSON_VALUE(j.value,'$.key'),JSON_VALUE(j.value,'$.label'),JSON_VALUE(j.value,'$.type'),
 CASE JSON_VALUE(j.value,'$.required') WHEN 'true' THEN 1 ELSE 0 END,
 JSON_VALUE(j.value,'$.parentKey'),JSON_VALUE(j.value,'$.parentValue'),JSON_QUERY(j.value,'$.options'),TRY_CONVERT(INT,j.[key])
 FROM OPENJSON(@FieldsJson) j;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='RcaTemplate',@EntityId=@RcaTemplateId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_SaveDataSource
 @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,@Kind VARCHAR(20)='REST',
 @BaseUrl NVARCHAR(1000)=NULL,@CredentialSecretRef NVARCHAR(400)=NULL,@Description NVARCHAR(700)=NULL,
 @DataSourceId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50316,'Platform Admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50317,'Invalid data source code.',1;
 IF @Kind NOT IN('REST','SOAP','DATABASE','CUSTOM') THROW 50318,'Invalid data source type.',1;
 /* URL hosts/SSRF protection must be validated and allowlisted by the backend, not SQL. */
 BEGIN TRAN;
 IF @DataSourceId IS NULL BEGIN
  SET @DataSourceId=NEXT VALUE FOR integration.Seq_DataSources;
  INSERT integration.DataSources(DataSourceId,Code,Name,Kind,BaseUrl,CredentialSecretRef,Description)
  VALUES(@DataSourceId,@Code,@Name,@Kind,@BaseUrl,NULLIF(@CredentialSecretRef,'__CLEAR__'),@Description);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM integration.DataSources WHERE DataSourceId=@DataSourceId) BEGIN ROLLBACK; THROW 50319,'Data source not found.',1; END;
  UPDATE integration.DataSources SET Name=@Name,Kind=@Kind,BaseUrl=@BaseUrl,
  CredentialSecretRef=CASE WHEN @CredentialSecretRef='__CLEAR__' THEN NULL ELSE COALESCE(@CredentialSecretRef,CredentialSecretRef) END,Description=@Description
  WHERE DataSourceId=@DataSourceId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DataSource',@EntityId=@DataSourceId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_SaveOperation
 @ActorUserId BIGINT,@DataSourceId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75)=NULL,
 @HttpMethod VARCHAR(12),@UrlPath NVARCHAR(1000),@RequestTemplateJson NVARCHAR(MAX)=NULL,
 @ResponseMapJson NVARCHAR(MAX)=NULL,@HeaderTemplateJson NVARCHAR(MAX)=NULL,
 @RequestParamsJson NVARCHAR(MAX)=NULL,@OperationId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1 THROW 50320,'Platform Admin required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50321,'Invalid operation code.',1;
 IF NOT EXISTS(SELECT 1 FROM integration.DataSources WHERE DataSourceId=@DataSourceId AND IsActive=1) THROW 50322,'Data source missing or inactive.',1;
 IF @HttpMethod NOT IN('GET','POST','PUT','PATCH','DELETE') THROW 50323,'Invalid HTTP method.',1;
 IF @RequestTemplateJson IS NOT NULL AND ISJSON(@RequestTemplateJson)<>1 THROW 50324,'Invalid request JSON.',1;
 IF @ResponseMapJson IS NOT NULL AND ISJSON(@ResponseMapJson)<>1 THROW 50325,'Invalid response mapping JSON.',1;
 IF @HeaderTemplateJson IS NOT NULL AND ISJSON(@HeaderTemplateJson)<>1 THROW 50326,'Invalid header template JSON.',1;
 IF @RequestParamsJson IS NOT NULL AND (ISJSON(@RequestParamsJson)<>1 OR LEFT(LTRIM(@RequestParamsJson),1)<>'[') THROW 50328,'Invalid request parameter definitions.',1;
 BEGIN TRAN;
 IF @OperationId IS NULL BEGIN
  SET @OperationId=NEXT VALUE FOR integration.Seq_Operations;
  INSERT integration.Operations(OperationId,DataSourceId,Code,Name,HttpMethod,UrlPath,RequestTemplateJson,ResponseMapJson,HeaderTemplateJson,RequestParamsJson)
  VALUES(@OperationId,@DataSourceId,@Code,@Name,@HttpMethod,@UrlPath,@RequestTemplateJson,@ResponseMapJson,@HeaderTemplateJson,@RequestParamsJson);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM integration.Operations WHERE OperationId=@OperationId AND DataSourceId=@DataSourceId)
  BEGIN ROLLBACK; THROW 50327,'Operation not found under data source.',1; END;
  UPDATE integration.Operations SET Name=@Name,HttpMethod=@HttpMethod,UrlPath=@UrlPath,
  RequestTemplateJson=@RequestTemplateJson,ResponseMapJson=@ResponseMapJson,HeaderTemplateJson=@HeaderTemplateJson,RequestParamsJson=@RequestParamsJson
  WHERE OperationId=@OperationId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@EntityType='DataSourceOperation',@EntityId=@OperationId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE integration.usp_QueueTest
 @ActorUserId BIGINT,@ProjectId BIGINT,@OperationId BIGINT,
 @ExecutionId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50328,'Project admin required.',1;
 IF NOT EXISTS(SELECT 1 FROM integration.Operations o JOIN integration.ProjectDataSources p ON p.DataSourceId=o.DataSourceId
 WHERE o.OperationId=@OperationId AND p.ProjectId=@ProjectId AND o.IsActive=1) THROW 50329,'Operation is not approved for this project.',1;
 SET @ExecutionId=NEXT VALUE FOR integration.Seq_Executions;
 INSERT integration.Executions(ExecutionId,ProjectId,OperationId,Status) VALUES(@ExecutionId,@ProjectId,@OperationId,'Pending');
END;
GO
CREATE OR ALTER PROCEDURE notify.usp_SaveTemplate
 @ActorUserId BIGINT,@ProjectId BIGINT=NULL,@Name NVARCHAR(180),
 @Code VARCHAR(85)=NULL,@Channel VARCHAR(15)='Email',@LanguageCode VARCHAR(5)='en',
 @Subject NVARCHAR(300)=NULL,@Body NVARCHAR(MAX),@TemplateId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;SET XACT_ABORT ON;
 IF @ProjectId IS NULL AND auth.fn_HasPermission(@ActorUserId,NULL,'notifications.manage')<>1
 OR @ProjectId IS NOT NULL AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50330,'Notifications configuration permission required.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50331,'Invalid notification code.',1;
 IF @Channel NOT IN('Email','SMS','InApp') OR @LanguageCode NOT IN('en','ur') THROW 50332,'Invalid channel/language.',1;
 BEGIN TRAN;
 IF @TemplateId IS NULL BEGIN
  SET @TemplateId=NEXT VALUE FOR notify.Seq_Templates;
  INSERT notify.Templates(TemplateId,ProjectId,Code,Name,Channel,LanguageCode,SubjectTemplate,BodyTemplate)
  VALUES(@TemplateId,@ProjectId,@Code,@Name,@Channel,@LanguageCode,@Subject,@Body);
 END ELSE BEGIN
  IF NOT EXISTS(SELECT 1 FROM notify.Templates WHERE TemplateId=@TemplateId AND (ProjectId=@ProjectId OR ProjectId IS NULL AND @ProjectId IS NULL))
   BEGIN ROLLBACK; THROW 50333,'Template not found in scope.',1; END;
  UPDATE notify.Templates SET Name=@Name,Channel=@Channel,LanguageCode=@LanguageCode,SubjectTemplate=@Subject,BodyTemplate=@Body
  WHERE TemplateId=@TemplateId;
 END;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='NotificationTemplate',@EntityId=@TemplateId,@ActionCode='Save';
 COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE notify.usp_SaveRule
 @ActorUserId BIGINT,@ProjectId BIGINT,@EventCode VARCHAR(65),
 @TemplateId BIGINT,@RecipientRuleJson NVARCHAR(MAX)=N'{}',@RuleId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50334,'Project Admin required.',1;
 IF ISJSON(@RecipientRuleJson)<>1 THROW 50335,'Invalid recipient rule JSON.',1;
 IF NOT EXISTS(SELECT 1 FROM notify.Templates WHERE TemplateId=@TemplateId AND IsActive=1
 AND (ProjectId=@ProjectId OR ProjectId IS NULL)) THROW 50336,'Notification template not available.',1;
 IF @RuleId IS NULL BEGIN
  SET @RuleId=NEXT VALUE FOR notify.Seq_Rules;
  INSERT notify.Rules(RuleId,ProjectId,EventCode,TemplateId,RecipientRuleJson)
  VALUES(@RuleId,@ProjectId,@EventCode,@TemplateId,@RecipientRuleJson);
 END ELSE UPDATE notify.Rules SET EventCode=@EventCode,TemplateId=@TemplateId,RecipientRuleJson=@RecipientRuleJson
 WHERE RuleId=@RuleId AND ProjectId=@ProjectId;
END;
GO
CREATE OR ALTER PROCEDURE reports.usp_SaveDefinition
 @ActorUserId BIGINT,@ProjectId BIGINT,@Name NVARCHAR(200),@Code VARCHAR(80)=NULL,
 @ConfigJson NVARCHAR(MAX),@ReportId BIGINT OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50337,'Project Admin required to build reports.',1;
 IF ISJSON(@ConfigJson)<>1 THROW 50338,'Report definition must be valid JSON.',1;
 IF @Code IS NULL OR LTRIM(RTRIM(@Code))='' SET @Code=core.fn_CodeFromName(@Name);
 IF core.fn_IsCode(@Code)<>1 THROW 50339,'Invalid report code.',1;
 IF @ReportId IS NULL BEGIN
  SET @ReportId=NEXT VALUE FOR reports.Seq_Definitions;
  INSERT reports.Definitions(ReportId,ProjectId,Code,Name,ConfigJson) VALUES(@ReportId,@ProjectId,@Code,@Name,@ConfigJson);
 END ELSE UPDATE reports.Definitions SET Name=@Name,ConfigJson=@ConfigJson WHERE ReportId=@ReportId AND ProjectId=@ProjectId;
END;
GO
CREATE OR ALTER PROCEDURE core.usp_SetProjectCalendar
 @ActorUserId BIGINT,@ProjectId BIGINT,@CalendarId BIGINT,@SlaMinutes INT
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50340,'Project Admin required.',1;
 IF NOT EXISTS(SELECT 1 FROM calendar.Calendars WHERE CalendarId=@CalendarId AND IsActive=1) THROW 50341,'Calendar inactive.',1;
 IF @SlaMinutes<0 THROW 50342,'Invalid SLA.',1;
 UPDATE core.Projects SET CalendarId=@CalendarId,DefaultSlaMinutes=@SlaMinutes,UpdatedAt=SYSUTCDATETIME()
 WHERE ProjectId=@ProjectId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='Project',@EntityId=@ProjectId,@ActionCode='UpdateSlaCalendar';
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_UpdateItem
 @ActorUserId BIGINT,@ItemId BIGINT,@Label NVARCHAR(240),@SortOrder INT,@IsActive BIT,
 @ParentItemId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @ListId BIGINT,@ParentListId BIGINT,@ProjectId BIGINT,@Scope VARCHAR(10);
 SELECT @ListId=i.ListId,@ParentListId=l.ParentListId,@ProjectId=l.ProjectId,@Scope=l.Scope
 FROM lookup.Items i JOIN lookup.Lists l ON l.ListId=i.ListId WHERE i.ItemId=@ItemId;
 IF @ListId IS NULL THROW 50343,'Lookup item does not exist.',1;
 IF @Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1 OR
 @Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 50344,'Lookup admin required.',1;
 IF @ParentItemId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lookup.Items WHERE ItemId=@ParentItemId AND ListId=@ParentListId)
 THROW 50345,'Parent item must belong to the parent list.',1;
 UPDATE lookup.Items SET Label=@Label,SortOrder=@SortOrder,IsActive=@IsActive,ParentItemId=@ParentItemId WHERE ItemId=@ItemId;
END;
GO

/* Verify required procedures exist before reporting successful compilation. */
IF OBJECT_ID(N'audit.usp_Write',N'P') IS NULL THROW 50980,N'Missing expected procedure: audit.usp_Write',1;
IF OBJECT_ID(N'auth.usp_UpsertDirectoryUser',N'P') IS NULL THROW 50980,N'Missing expected procedure: auth.usp_UpsertDirectoryUser',1;
IF OBJECT_ID(N'auth.usp_BootstrapPlatformAdmin',N'P') IS NULL THROW 50980,N'Missing expected procedure: auth.usp_BootstrapPlatformAdmin',1;
IF OBJECT_ID(N'auth.usp_AssignRole',N'P') IS NULL THROW 50980,N'Missing expected procedure: auth.usp_AssignRole',1;
IF OBJECT_ID(N'core.usp_OnboardProject',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_OnboardProject',1;
IF OBJECT_ID(N'core.usp_SetTerminology',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_SetTerminology',1;
IF OBJECT_ID(N'calendar.usp_CreateCalendar',N'P') IS NULL THROW 50980,N'Missing expected procedure: calendar.usp_CreateCalendar',1;
IF OBJECT_ID(N'calendar.usp_SetWorkingInterval',N'P') IS NULL THROW 50980,N'Missing expected procedure: calendar.usp_SetWorkingInterval',1;
IF OBJECT_ID(N'calendar.usp_AddHolidayRange',N'P') IS NULL THROW 50980,N'Missing expected procedure: calendar.usp_AddHolidayRange',1;
IF OBJECT_ID(N'calendar.usp_RemoveHolidayDate',N'P') IS NULL THROW 50980,N'Missing expected procedure: calendar.usp_RemoveHolidayDate',1;
IF OBJECT_ID(N'calendar.usp_CalculateBusinessDueAt',N'P') IS NULL THROW 50980,N'Missing expected procedure: calendar.usp_CalculateBusinessDueAt',1;
IF OBJECT_ID(N'teams.usp_CreateTeam',N'P') IS NULL THROW 50980,N'Missing expected procedure: teams.usp_CreateTeam',1;
IF OBJECT_ID(N'teams.usp_SetMember',N'P') IS NULL THROW 50980,N'Missing expected procedure: teams.usp_SetMember',1;
IF OBJECT_ID(N'teams.usp_SetLeaveBackup',N'P') IS NULL THROW 50980,N'Missing expected procedure: teams.usp_SetLeaveBackup',1;
IF OBJECT_ID(N'teams.usp_ApplyResignedUser',N'P') IS NULL THROW 50980,N'Missing expected procedure: teams.usp_ApplyResignedUser',1;
IF OBJECT_ID(N'core.usp_AllowProjectDataSource',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_AllowProjectDataSource',1;
IF OBJECT_ID(N'core.usp_AllowProjectLookup',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_AllowProjectLookup',1;
IF OBJECT_ID(N'lookup.usp_CreateList',N'P') IS NULL THROW 50980,N'Missing expected procedure: lookup.usp_CreateList',1;
IF OBJECT_ID(N'lookup.usp_SetParentList',N'P') IS NULL THROW 50980,N'Missing expected procedure: lookup.usp_SetParentList',1;
IF OBJECT_ID(N'lookup.usp_BulkAddItems',N'P') IS NULL THROW 50980,N'Missing expected procedure: lookup.usp_BulkAddItems',1;
IF OBJECT_ID(N'lookup.usp_GetOptions',N'P') IS NULL THROW 50980,N'Missing expected procedure: lookup.usp_GetOptions',1;
IF OBJECT_ID(N'forms.usp_CreateDefinition',N'P') IS NULL THROW 50980,N'Missing expected procedure: forms.usp_CreateDefinition',1;
IF OBJECT_ID(N'forms.usp_SaveDraft',N'P') IS NULL THROW 50980,N'Missing expected procedure: forms.usp_SaveDraft',1;
IF OBJECT_ID(N'forms.usp_Publish',N'P') IS NULL THROW 50980,N'Missing expected procedure: forms.usp_Publish',1;
IF OBJECT_ID(N'flow.usp_CreateDefinition',N'P') IS NULL THROW 50980,N'Missing expected procedure: flow.usp_CreateDefinition',1;
IF OBJECT_ID(N'flow.usp_SaveDraft',N'P') IS NULL THROW 50980,N'Missing expected procedure: flow.usp_SaveDraft',1;
IF OBJECT_ID(N'flow.usp_Publish',N'P') IS NULL THROW 50980,N'Missing expected procedure: flow.usp_Publish',1;
IF OBJECT_ID(N'core.usp_CreateCaseType',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_CreateCaseType',1;
IF OBJECT_ID(N'core.usp_PublishCaseType',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_PublishCaseType',1;
IF OBJECT_ID(N'work.usp_ReindexCaseFields',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_ReindexCaseFields',1;
IF OBJECT_ID(N'work.usp_ActivateNode',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_ActivateNode',1;
IF NOT EXISTS (SELECT 1 FROM sys.sql_modules WHERE object_id=OBJECT_ID(N'work.usp_ActivateNode',N'P') AND definition LIKE N'%DECLARE @DecisionNextDepth INT = @Depth + 1%')
 THROW 50981,N'Workflow activation procedure was not updated. Review earlier compilation errors before continuing.',1;
IF OBJECT_ID(N'work.usp_CreateCase',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_CreateCase',1;
IF OBJECT_ID(N'work.usp_ForwardTask',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_ForwardTask',1;
IF OBJECT_ID(N'work.usp_CompleteTask',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_CompleteTask',1;
IF OBJECT_ID(N'work.usp_ForceIntimation',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_ForceIntimation',1;
IF OBJECT_ID(N'work.usp_SubmitRca',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_SubmitRca',1;
IF OBJECT_ID(N'work.usp_AssignUnassignedTask',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_AssignUnassignedTask',1;
IF OBJECT_ID(N'files.usp_RegisterDocument',N'P') IS NULL THROW 50980,N'Missing expected procedure: files.usp_RegisterDocument',1;
IF OBJECT_ID(N'notify.usp_ClaimOutbox',N'P') IS NULL THROW 50980,N'Missing expected procedure: notify.usp_ClaimOutbox',1;
IF OBJECT_ID(N'notify.usp_RecordDelivery',N'P') IS NULL THROW 50980,N'Missing expected procedure: notify.usp_RecordDelivery',1;
IF OBJECT_ID(N'integration.usp_RecordResult',N'P') IS NULL THROW 50980,N'Missing expected procedure: integration.usp_RecordResult',1;
IF OBJECT_ID(N'work.usp_ResumeSystemNode',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_ResumeSystemNode',1;
IF OBJECT_ID(N'work.usp_GetMyTasks',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_GetMyTasks',1;
IF OBJECT_ID(N'work.usp_GetCaseDetails',N'P') IS NULL THROW 50980,N'Missing expected procedure: work.usp_GetCaseDetails',1;
IF OBJECT_ID(N'reports.usp_CaseSummary',N'P') IS NULL THROW 50980,N'Missing expected procedure: reports.usp_CaseSummary',1;
IF OBJECT_ID(N'core.usp_DatabaseHealth',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_DatabaseHealth',1;
IF OBJECT_ID(N'core.usp_SetProjectRcaFields',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_SetProjectRcaFields',1;
IF OBJECT_ID(N'auth.usp_SaveCustomRole',N'P') IS NULL THROW 50980,N'Missing expected procedure: auth.usp_SaveCustomRole',1;
IF OBJECT_ID(N'forms.usp_SaveLibraryField',N'P') IS NULL THROW 50980,N'Missing expected procedure: forms.usp_SaveLibraryField',1;
IF OBJECT_ID(N'core.usp_SaveRcaTemplate',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_SaveRcaTemplate',1;
IF OBJECT_ID(N'integration.usp_SaveDataSource',N'P') IS NULL THROW 50980,N'Missing expected procedure: integration.usp_SaveDataSource',1;
IF OBJECT_ID(N'integration.usp_SaveOperation',N'P') IS NULL THROW 50980,N'Missing expected procedure: integration.usp_SaveOperation',1;
IF OBJECT_ID(N'integration.usp_QueueTest',N'P') IS NULL THROW 50980,N'Missing expected procedure: integration.usp_QueueTest',1;
IF OBJECT_ID(N'notify.usp_SaveTemplate',N'P') IS NULL THROW 50980,N'Missing expected procedure: notify.usp_SaveTemplate',1;
IF OBJECT_ID(N'notify.usp_SaveRule',N'P') IS NULL THROW 50980,N'Missing expected procedure: notify.usp_SaveRule',1;
IF OBJECT_ID(N'reports.usp_SaveDefinition',N'P') IS NULL THROW 50980,N'Missing expected procedure: reports.usp_SaveDefinition',1;
IF OBJECT_ID(N'core.usp_SetProjectCalendar',N'P') IS NULL THROW 50980,N'Missing expected procedure: core.usp_SetProjectCalendar',1;
IF OBJECT_ID(N'lookup.usp_UpdateItem',N'P') IS NULL THROW 50980,N'Missing expected procedure: lookup.usp_UpdateItem',1;
EXEC core.usp_DatabaseHealth;
PRINT N'WorkflowPlatformV2 installation completed: all expected stored procedures exist.';
GO
