USE [WorkflowPlatformV2];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Set this to the ID of the affected UAT project. NULL intentionally makes no changes.
DECLARE @ProjectId BIGINT=NULL;
IF @ProjectId IS NULL
BEGIN
 SELECT p.ProjectId,p.Name,p.TemplateCode,p.Status FROM core.Projects p
 WHERE p.Status='UAT' AND p.TemplateCode IN ('step1','step2','step3')
 AND NOT EXISTS(SELECT 1 FROM flow.Definitions w WHERE w.ProjectId=p.ProjectId);
 PRINT 'Preview only. Set @ProjectId to repair one affected project.';
 RETURN;
END;
BEGIN TRY
 BEGIN TRAN;
 DECLARE @TemplateCode VARCHAR(50);
 SELECT @TemplateCode=TemplateCode FROM core.Projects WITH(UPDLOCK,HOLDLOCK) WHERE ProjectId=@ProjectId AND Status='UAT';
 IF @TemplateCode IS NULL OR @TemplateCode NOT IN ('step1','step2','step3') THROW 50926,'Project must be UAT with a selected step template.',1;
 IF EXISTS(SELECT 1 FROM flow.Definitions WITH(UPDLOCK,HOLDLOCK) WHERE ProjectId=@ProjectId) THROW 50927,'Project already has workflow definitions; no repair applied.',1;
 IF @TemplateCode='step1' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'1-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-end","source":"step1","target":"end","type":"smoothstep"}]}');
 IF @TemplateCode='step2' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'2-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"step2","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"Step 2","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":820,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-step2","source":"step1","target":"step2","type":"smoothstep"},{"id":"e-step2-end","source":"step2","target":"end","type":"smoothstep"}]}');
 IF @TemplateCode='step3' INSERT flow.Definitions(ProjectId,Code,Name,DraftGraphJson) VALUES(@ProjectId,'INITIAL_WORKFLOW',N'3-step workflow',N'{"nodes":[{"id":"start","type":"flowNode","position":{"x":40,"y":180},"data":{"label":"Start","kind":"start"}},{"id":"step1","type":"flowNode","position":{"x":300,"y":180},"data":{"label":"Step 1","kind":"task","formIds":[],"teamId":null}},{"id":"step2","type":"flowNode","position":{"x":560,"y":180},"data":{"label":"Step 2","kind":"task","formIds":[],"teamId":null}},{"id":"step3","type":"flowNode","position":{"x":820,"y":180},"data":{"label":"Step 3","kind":"task","formIds":[],"teamId":null}},{"id":"end","type":"flowNode","position":{"x":1080,"y":180},"data":{"label":"End","kind":"end"}}],"edges":[{"id":"e-start-step1","source":"start","target":"step1","type":"smoothstep"},{"id":"e-step1-step2","source":"step1","target":"step2","type":"smoothstep"},{"id":"e-step2-step3","source":"step2","target":"step3","type":"smoothstep"},{"id":"e-step3-end","source":"step3","target":"end","type":"smoothstep"}]}');
 COMMIT;
 SELECT WorkflowId,ProjectId,Name,LiveVersionId,DraftGraphJson FROM flow.Definitions WHERE ProjectId=@ProjectId AND Code='INITIAL_WORKFLOW';
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
END CATCH;
GO
