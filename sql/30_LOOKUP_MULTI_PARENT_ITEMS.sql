/* Migration 30: allow one lookup item to belong to multiple parent-list options.
   Idempotent and non-destructive; preserves lookup.Items.ParentItemId for older clients.
   Run after 28 / 29. Requires SQL Server 2017+ for STRING_AGG. */
USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF OBJECT_ID(N'lookup.ItemParents',N'U') IS NULL
BEGIN
  CREATE TABLE lookup.ItemParents (
    ItemId BIGINT NOT NULL REFERENCES lookup.Items(ItemId),
    ParentItemId BIGINT NOT NULL REFERENCES lookup.Items(ItemId),
    CONSTRAINT PK_LookupItemParents PRIMARY KEY (ItemId, ParentItemId)
  );
END;
GO
/* Safely backfill previously configured one-to-one links. */
INSERT INTO lookup.ItemParents(ItemId,ParentItemId)
SELECT i.ItemId,i.ParentItemId
FROM lookup.Items i
JOIN lookup.Lists l ON l.ListId=i.ListId
JOIN lookup.Items parent ON parent.ItemId=i.ParentItemId AND parent.ListId=l.ParentListId
WHERE i.ParentItemId IS NOT NULL
AND NOT EXISTS(SELECT 1 FROM lookup.ItemParents ip WHERE ip.ItemId=i.ItemId AND ip.ParentItemId=i.ParentItemId);
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'IX_LookupItemParents_Parent' AND object_id=OBJECT_ID(N'lookup.ItemParents'))
  CREATE INDEX IX_LookupItemParents_Parent ON lookup.ItemParents(ParentItemId,ItemId);
GO
/* Administrators can replace a set of parent links for one or more children atomically.
   Input example: [{"code":"KARACHI","parentCodes":["SINDH","SOUTH"]}] */
CREATE OR ALTER PROCEDURE lookup.usp_SetItemParentLinks
  @ActorUserId BIGINT, @ListId BIGINT, @LinksJson NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  IF ISJSON(@LinksJson)<>1 OR LEFT(LTRIM(@LinksJson),1)<>N'['
    THROW 51030,'LinksJson must be a JSON array.',1;

  DECLARE @ProjectId BIGINT,@Scope VARCHAR(10),@ParentListId BIGINT;
  SELECT @ProjectId=l.ProjectId,@Scope=l.Scope,@ParentListId=l.ParentListId
  FROM lookup.Lists l WHERE l.ListId=@ListId AND l.IsActive=1;
  IF @Scope IS NULL THROW 51031,'Lookup list is not active or does not exist.',1;
  IF (@Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1)
    OR (@Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1)
    THROW 51032,'Lookup admin required.',1;

  DECLARE @Input TABLE (Code VARCHAR(100) NOT NULL PRIMARY KEY, ParentCodesJson NVARCHAR(MAX) NOT NULL);
  INSERT INTO @Input(Code,ParentCodesJson)
  SELECT j.Code,ISNULL(j.ParentCodesJson,N'[]')
  FROM OPENJSON(@LinksJson) WITH (
    Code VARCHAR(100) '$.code',
    ParentCodesJson NVARCHAR(MAX) '$.parentCodes' AS JSON
  ) AS j;
  IF (SELECT COUNT(*) FROM @Input)>200 THROW 51033,'At most 200 child items per request.',1;
  IF EXISTS(SELECT 1 FROM @Input WHERE NULLIF(LTRIM(RTRIM(Code)),'') IS NULL OR ISJSON(ParentCodesJson)<>1 OR LEFT(LTRIM(ParentCodesJson),1)<>N'[')
    THROW 51034,'Every item requires a code and a parentCodes array.',1;
  IF EXISTS(SELECT 1 FROM @Input input WHERE NOT EXISTS (
    SELECT 1 FROM lookup.Items i WHERE i.ListId=@ListId AND i.Code=input.Code))
    THROW 51035,'One or more child codes do not exist in the selected list.',1;

  DECLARE @Pairs TABLE(ChildCode VARCHAR(100) NOT NULL, ParentCode VARCHAR(100) NOT NULL,
    PRIMARY KEY (ChildCode,ParentCode));
  IF EXISTS(SELECT 1 FROM @Input i CROSS APPLY OPENJSON(i.ParentCodesJson) AS p WHERE p.[type]<>1 OR NULLIF(LTRIM(RTRIM(p.[value])),N'') IS NULL)
    THROW 51036,'Parent codes must be non-empty strings.',1;
  INSERT INTO @Pairs(ChildCode,ParentCode)
  SELECT DISTINCT i.Code,CONVERT(VARCHAR(100),p.[value])
  FROM @Input i CROSS APPLY OPENJSON(i.ParentCodesJson) AS p;

  IF @ParentListId IS NULL AND EXISTS(SELECT 1 FROM @Pairs)
    THROW 51037,'Standalone lookup lists cannot have parent item links.',1;
  IF EXISTS(SELECT 1 FROM @Pairs links WHERE NOT EXISTS(
    SELECT 1 FROM lookup.Items parent WHERE parent.ListId=@ParentListId
      AND parent.Code=links.ParentCode AND parent.IsActive=1))
    THROW 51038,'Parent item code does not belong to the active parent list.',1;

  BEGIN TRANSACTION;
    DELETE links FROM lookup.ItemParents links
    JOIN lookup.Items item ON item.ItemId=links.ItemId
    JOIN @Input input ON input.Code=item.Code
    WHERE item.ListId=@ListId;
    INSERT INTO lookup.ItemParents(ItemId,ParentItemId)
    SELECT child.ItemId,parent.ItemId
    FROM @Pairs links
    JOIN lookup.Items child ON child.ListId=@ListId AND child.Code=links.ChildCode
    JOIN lookup.Items parent ON parent.ListId=@ParentListId AND parent.Code=links.ParentCode;
    UPDATE child SET ParentItemId=(
      SELECT TOP(1) links.ParentItemId FROM lookup.ItemParents links
      WHERE links.ItemId=child.ItemId ORDER BY links.ParentItemId
    )
    FROM lookup.Items child JOIN @Input input ON input.Code=child.Code
    WHERE child.ListId=@ListId;
    EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,
      @EntityType='LookupList',@EntityId=@ListId,@ActionCode='SetItemParentLinks';
  COMMIT TRANSACTION;
END;
GO
/* Case Type modal saves list, options and all parent links in one transaction. */
CREATE OR ALTER PROCEDURE lookup.usp_CreateListWithItems
  @ActorUserId BIGINT,@Name NVARCHAR(160),@Code VARCHAR(75),@Scope VARCHAR(10),
  @ProjectId BIGINT=NULL,@ParentListId BIGINT=NULL,
  @ItemsJson NVARCHAR(MAX),@LinksJson NVARCHAR(MAX),@ListId BIGINT OUTPUT
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  BEGIN TRANSACTION;
    EXEC lookup.usp_CreateList @ActorUserId=@ActorUserId,@Name=@Name,@Code=@Code,
      @Scope=@Scope,@ProjectId=@ProjectId,@ParentListId=@ParentListId,@ListId=@ListId OUTPUT;
    EXEC lookup.usp_BulkAddItems @ActorUserId=@ActorUserId,@ListId=@ListId,@ItemsJson=@ItemsJson;
    IF @ParentListId IS NOT NULL
      EXEC lookup.usp_SetItemParentLinks @ActorUserId=@ActorUserId,@ListId=@ListId,@LinksJson=@LinksJson;
  COMMIT TRANSACTION;
END;
GO
/* When switching a list's parent, clear old relationships; do not clear on a no-op save. */
CREATE OR ALTER PROCEDURE lookup.usp_SetParentList
 @ActorUserId BIGINT,@ListId BIGINT,@ParentListId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 DECLARE @ProjectId BIGINT,@Scope VARCHAR(10),@PreviousParentListId BIGINT;
 SELECT @ProjectId=ProjectId,@Scope=Scope,@PreviousParentListId=ParentListId FROM lookup.Lists WHERE ListId=@ListId;
 IF @Scope IS NULL THROW 50075,'Lookup list not found.',1;
 IF (@Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1)
 OR (@Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1)
 THROW 50076,'Lookup admin required.',1;
 IF @ParentListId=@ListId THROW 50077,'List cannot parent itself.',1;
 IF @ParentListId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lookup.Lists WHERE ListId=@ParentListId AND IsActive=1
   AND (Scope='Global' OR ProjectId=@ProjectId))
   THROW 50078,'Parent is not available in this project.',1;
 DECLARE @Walk BIGINT=@ParentListId,@Next BIGINT,@Depth INT=0;
 WHILE @Walk IS NOT NULL
 BEGIN
  IF @Walk=@ListId THROW 50079,'Cyclic lookup relationships are not allowed.',1;
  SET @Depth+=1;IF @Depth>50 THROW 50080,'Lookup nesting is too deep.',1;
  SET @Next=(SELECT ParentListId FROM lookup.Lists WHERE ListId=@Walk);
  SET @Walk=@Next;
 END;
 IF ISNULL(@PreviousParentListId,-1)=ISNULL(@ParentListId,-1) RETURN;
 BEGIN TRANSACTION;
 UPDATE lookup.Lists SET ParentListId=@ParentListId,UpdatedAt=SYSUTCDATETIME() WHERE ListId=@ListId;
 DELETE links FROM lookup.ItemParents links JOIN lookup.Items child ON child.ItemId=links.ItemId WHERE child.ListId=@ListId;
 UPDATE lookup.Items SET ParentItemId=NULL WHERE ListId=@ListId;
 EXEC audit.usp_Write @ActorUserId=@ActorUserId,@ProjectId=@ProjectId,@EntityType='LookupList',@EntityId=@ListId,@ActionCode='ChangeParent';
 COMMIT TRANSACTION;
END;
GO
/* Preserve compatibility for API clients updating a single parent through the original endpoint. */
CREATE OR ALTER PROCEDURE lookup.usp_UpdateItem
 @ActorUserId BIGINT,@ItemId BIGINT,@Label NVARCHAR(240),@SortOrder INT,@IsActive BIT,
 @ParentItemId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 DECLARE @ListId BIGINT,@ParentListId BIGINT,@ProjectId BIGINT,@Scope VARCHAR(10),@PreviousParentItemId BIGINT;
 SELECT @ListId=i.ListId,@PreviousParentItemId=i.ParentItemId,
  @ParentListId=l.ParentListId,@ProjectId=l.ProjectId,@Scope=l.Scope
 FROM lookup.Items i JOIN lookup.Lists l ON l.ListId=i.ListId WHERE i.ItemId=@ItemId;
 IF @ListId IS NULL THROW 50343,'Lookup item does not exist.',1;
 IF (@Scope='Global' AND auth.fn_HasPermission(@ActorUserId,NULL,'lookups.manage')<>1)
   OR (@Scope='Project' AND auth.fn_IsAdmin(@ActorUserId,@ProjectId)<>1)
   THROW 50344,'Lookup admin required.',1;
 IF @ParentItemId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lookup.Items
     WHERE ItemId=@ParentItemId AND ListId=@ParentListId AND IsActive=1)
   THROW 50345,'Parent item must belong to the active parent list.',1;
 BEGIN TRANSACTION;
 UPDATE lookup.Items SET Label=@Label,SortOrder=@SortOrder,IsActive=@IsActive,ParentItemId=@ParentItemId WHERE ItemId=@ItemId;
 IF ISNULL(@PreviousParentItemId,-1)<>ISNULL(@ParentItemId,-1)
 BEGIN
   DELETE FROM lookup.ItemParents WHERE ItemId=@ItemId;
   IF @ParentItemId IS NOT NULL INSERT INTO lookup.ItemParents(ItemId,ParentItemId) VALUES(@ItemId,@ParentItemId);
 END;
 COMMIT TRANSACTION;
END;
GO
CREATE OR ALTER PROCEDURE lookup.usp_GetOptions
 @ProjectId BIGINT,@ListId BIGINT,@ParentItemId BIGINT=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM lookup.Lists l WHERE l.ListId=@ListId AND l.IsActive=1
  AND (l.ProjectId=@ProjectId OR (l.Scope='Global' AND EXISTS(
    SELECT 1 FROM lookup.ProjectLists pl WHERE pl.ProjectId=@ProjectId AND pl.ListId=l.ListId))))
 THROW 50090,'Lookup is not allowed for this project.',1;
 SELECT i.ItemId,i.Code,i.Label,i.ParentItemId,i.SortOrder
 FROM lookup.Items i
 WHERE i.ListId=@ListId AND i.IsActive=1 AND (
    (@ParentItemId IS NULL AND NOT EXISTS(SELECT 1 FROM lookup.ItemParents rel WHERE rel.ItemId=i.ItemId))
    OR (@ParentItemId IS NOT NULL AND EXISTS(SELECT 1 FROM lookup.ItemParents rel
          WHERE rel.ItemId=i.ItemId AND rel.ParentItemId=@ParentItemId))
 )
 ORDER BY i.SortOrder,i.Label;
END;
GO
IF OBJECT_ID(N'lookup.ItemParents',N'U') IS NULL
 OR OBJECT_ID(N'lookup.usp_SetItemParentLinks',N'P') IS NULL
 OR OBJECT_ID(N'lookup.usp_CreateListWithItems',N'P') IS NULL
 OR OBJECT_ID(N'lookup.usp_GetOptions',N'P') IS NULL
 THROW 51039,'Migration 30 verification failed.',1;
PRINT 'PASS: migration 30 lookup multi-parent item links installed.';
GO
