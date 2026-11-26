/* Read-only verification of migration 30; no account data modified. */
USE [WorkflowPlatformV2];
GO
SELECT 'lookup.ItemParents' AS ObjectName,
 CASE WHEN OBJECT_ID(N'lookup.ItemParents',N'U') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END AS Result
UNION ALL SELECT 'lookup.usp_SetItemParentLinks',
 CASE WHEN OBJECT_ID(N'lookup.usp_SetItemParentLinks',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'lookup.usp_CreateListWithItems',
 CASE WHEN OBJECT_ID(N'lookup.usp_CreateListWithItems',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END
UNION ALL SELECT 'lookup.usp_GetOptions',
 CASE WHEN OBJECT_ID(N'lookup.usp_GetOptions',N'P') IS NOT NULL THEN 'PASS' ELSE 'MISSING' END;
GO
IF OBJECT_ID(N'lookup.ItemParents',N'U') IS NOT NULL
  EXEC sys.sp_executesql N'SELECT COUNT(*) AS TotalParentItemLinks FROM lookup.ItemParents;';
GO
