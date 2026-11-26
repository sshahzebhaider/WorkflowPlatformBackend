USE [WorkflowPlatformV2];
GO
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
