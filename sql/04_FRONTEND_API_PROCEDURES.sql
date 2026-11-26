/* WorkflowPlatformV2: additive, repeatable migration for Chunk 6 API integration.
   Execute as a database admin ONCE before switching the frontend to API mode.
   Existing tables and data remain untouched; permissions remain SELECT/EXECUTE only.
   Requires the original 00_CREATE_ALL plus the previously supplied procedure repair. */
USE [WorkflowPlatformV2];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE core.usp_SaveCaseTypeDraft
 @ActorUserId BIGINT,@CaseTypeId BIGINT,
 @Name NVARCHAR(200),@DraftJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL THROW 51001,'Case type name is required.',1;
 IF ISJSON(@DraftJson)<>1 OR LEFT(LTRIM(@DraftJson),1)<>N'{' THROW 51002,'A JSON object is required.',1;
 DECLARE @ProjectId BIGINT=(SELECT ProjectId FROM core.CaseTypes WHERE CaseTypeId=@CaseTypeId);
 IF @ProjectId IS NULL THROW 51003,'Case type not found.',1;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 51004,'Project admin required.',1;
 UPDATE core.CaseTypes SET Name=@Name,DraftJson=@DraftJson,UpdatedAt=SYSUTCDATETIME()
 WHERE CaseTypeId=@CaseTypeId AND ProjectId=@ProjectId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,
  @EntityType='CaseType',@EntityId=@CaseTypeId,@ActionCode='SaveDraft';
END;
GO
CREATE OR ALTER PROCEDURE teams.usp_UpdateTeamDetails
 @ActorUserId BIGINT,@ProjectId BIGINT,@TeamId BIGINT,
 @Name NVARCHAR(160),@Description NVARCHAR(500)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1 THROW 51010,'Project admin required.',1;
 IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL THROW 51011,'Team name is required.',1;
 UPDATE teams.Teams SET Name=@Name,Description=@Description
 WHERE TeamId=@TeamId AND ProjectId=@ProjectId AND IsActive=1;
 IF @@ROWCOUNT<>1 THROW 51012,'Team not found.',1;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,
  @EntityType='Team',@EntityId=@TeamId,@ActionCode='UpdateDetails';
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_UpdateCalendarDetails
 @ActorUserId BIGINT,@CalendarId BIGINT,
 @Name NVARCHAR(160),@TimeZoneId SYSNAME
AS
BEGIN
 SET NOCOUNT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1
  THROW 51020,'Platform settings permission required.',1;
 IF NULLIF(LTRIM(RTRIM(@Name)),N'') IS NULL THROW 51021,'Calendar name is required.',1;
 IF NOT EXISTS(SELECT 1 FROM sys.time_zone_info WHERE name=@TimeZoneId)
  THROW 51022,'Invalid SQL Server Windows time zone.',1;
 UPDATE calendar.Calendars SET Name=@Name,TimeZoneId=@TimeZoneId
 WHERE CalendarId=@CalendarId AND IsActive=1;
 IF @@ROWCOUNT<>1 THROW 51023,'Calendar not found.',1;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,
  @EntityType='Calendar',@EntityId=@CalendarId,@ActionCode='UpdateDetails';
END;
GO
CREATE OR ALTER PROCEDURE calendar.usp_ReplaceSchedule
 @ActorUserId BIGINT,@CalendarId BIGINT,@ScheduleJson NVARCHAR(MAX)
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF auth.fn_HasPermission(@ActorUserId,NULL,'settings.manage')<>1
  THROW 51030,'Platform settings permission required.',1;
 IF NOT EXISTS(SELECT 1 FROM calendar.Calendars WHERE CalendarId=@CalendarId AND IsActive=1)
  THROW 51031,'Calendar not found.',1;
 IF ISJSON(@ScheduleJson)<>1 OR LEFT(LTRIM(@ScheduleJson),1)<>N'['
  THROW 51032,'Schedule must be a JSON array.',1;
 DECLARE @Intervals TABLE(DayOfWeek TINYINT,StartMinute SMALLINT,EndMinute SMALLINT);
 INSERT @Intervals(DayOfWeek,StartMinute,EndMinute)
 SELECT TRY_CONVERT(TINYINT,JSON_VALUE(j.value,'$.dayOfWeek')),
  TRY_CONVERT(SMALLINT,JSON_VALUE(j.value,'$.startMinute')),
  TRY_CONVERT(SMALLINT,JSON_VALUE(j.value,'$.endMinute'))
 FROM OPENJSON(@ScheduleJson) j;
 IF EXISTS(SELECT 1 FROM @Intervals WHERE DayOfWeek IS NULL OR DayOfWeek NOT BETWEEN 1 AND 7
  OR StartMinute IS NULL OR EndMinute IS NULL OR StartMinute NOT BETWEEN 0 AND 1439
  OR EndMinute NOT BETWEEN 1 AND 1440 OR StartMinute>=EndMinute)
  THROW 51033,'Schedule contains invalid days or time ranges.',1;
 IF EXISTS(SELECT 1 FROM @Intervals a JOIN @Intervals b ON a.DayOfWeek=b.DayOfWeek
  AND a.StartMinute<b.EndMinute AND b.StartMinute<a.EndMinute
  GROUP BY a.DayOfWeek,a.StartMinute,a.EndMinute HAVING COUNT(*)>1)
  THROW 51034,'Overlapping or duplicate working intervals are not permitted.',1;
 BEGIN TRANSACTION;
 DELETE calendar.WorkingIntervals WHERE CalendarId=@CalendarId;
 INSERT calendar.WorkingIntervals(CalendarId,DayOfWeek,StartMinute,EndMinute)
 SELECT @CalendarId,DayOfWeek,StartMinute,EndMinute FROM @Intervals;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,
  @EntityType='Calendar',@EntityId=@CalendarId,@ActionCode='ReplaceSchedule';
 COMMIT TRANSACTION;
END;
GO
-- Validate the expected 4 procedures (zero missing is success):
SELECT n.ProcedureName, CASE WHEN OBJECT_ID(n.ProcedureName,N'P') IS NULL THEN 'MISSING' ELSE 'PRESENT' END AS Status
FROM (VALUES (N'core.usp_SaveCaseTypeDraft'),(N'teams.usp_UpdateTeamDetails'),
 (N'calendar.usp_UpdateCalendarDetails'),(N'calendar.usp_ReplaceSchedule'))n(ProcedureName);
GO
