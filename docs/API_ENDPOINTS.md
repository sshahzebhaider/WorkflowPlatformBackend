# REST API endpoints (all `/api` endpoints require authenticated identity)

**Security**: `X-Dev-User` is loopback-only and Development-only. In production use `Authorization: Bearer <JWT>`; the backend obtains the real actor from the SQL directory. Scoped reads enforce project access. Stored procedures enforce permissions and data integrity for writes.

**Read endpoints**

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/me` | User, memberships and roles |
| GET | `/api/users?projectId=` | User directory scoped to administrator |
| GET | `/api/roles` | Global roles and permission assignments |
| GET | `/api/projects/{projectId}/available-roles` | Assignable project/team roles |
| GET | `/api/permissions` | Permission catalog |
| GET | `/api/projects` | All accessible projects |
| GET | `/api/projects/{projectId}` | Project and terminology |
| GET | `/api/projects/{projectId}/permissions` | Signed-in user's effective permissions |
| GET | `/api/projects/{projectId}/terminology` | Project labels |
| GET | `/api/projects/{projectId}/role-assignments` | Project user-role mappings |
| GET | `/api/projects/{projectId}/rca-fields` | RCA field configuration |
| GET | `/api/audit` | Platform audit entries |
| GET | `/api/projects/{projectId}/audit` | Project audit entries |
| GET | `/api/calendars` | Platform calendars |
| GET | `/api/calendars/{calendarId}` | Calendar, working intervals and holidays |
| GET | `/api/rca-templates` | RCA templates |
| GET | `/api/rca-templates/{id}/fields` | RCA fields |
| GET | `/api/projects/{projectId}/teams` | Teams, members and leave backups |
| GET | `/api/lookups` | Platform lookup definitions |
| GET | `/api/lookups/{listId}/items` | Lookup item editor |
| GET | `/api/projects/{projectId}/lookups` | Project-approved lookups |
| GET | `/api/projects/{projectId}/lookups/{listId}/options?parentItemId=` | Cascading dropdown options |
| GET | `/api/projects/{projectId}/field-library` | Reusable fields |
| GET | `/api/projects/{projectId}/forms` | Form definitions |
| GET | `/api/projects/{projectId}/forms/{formId}` | Form drafts and published versions |
| GET | `/api/projects/{projectId}/workflows` | Workflow definitions |
| GET | `/api/projects/{projectId}/workflows/{workflowId}` | Workflow drafts and versions |
| GET | `/api/projects/{projectId}/case-types` | Case types and live versions |
| GET | `/api/projects/{projectId}/case-types/{caseTypeId}/intake` | Published intake form + initial lookups |
| GET | `/api/projects/{projectId}/cases?skip=&take=` | Project-access-filtered cases, paginated |
| GET | `/api/projects/{projectId}/cases/{caseId}` | Full case, tasks, answers, audit, attachments |
| GET | `/api/projects/{projectId}/tasks/mine?includeCompleted=` | My Tasks |
| GET | `/api/projects/{projectId}/teams/{teamId}/tasks` | Unit Head / Team Lead's team tasks |
| GET | `/api/projects/{projectId}/reports/definitions` | Report definitions |
| GET | `/api/projects/{projectId}/reports/summary` | Real case counts and SLA status |
| GET | `/api/data-sources` | Platform data source definitions |
| GET | `/api/data-sources/{sourceId}/operations` | Source operations |
| GET | `/api/projects/{projectId}/data-sources` | Approved project sources |
| GET | `/api/projects/{projectId}/integrations/executions` | Integration test executions |
| GET | `/api/projects/{projectId}/notifications` | Email/SMS queue and outcomes |
| GET | `/api/projects/{projectId}/notification-rules` | Notification rules |
| GET | `/api/notification-templates?projectId=` | Bilingual templates |
| GET | `/api/projects/{projectId}/cases/{caseId}/attachments/{documentId}` | Download only after malware clearance |

**Write endpoints — POST** (request body is a JSON object; `*Json` fields accept JSON objects/arrays)

| Endpoint | Stored procedure / function |
|---|---|
| `/api/projects/onboard` | `core.usp_OnboardProject` |
| `/api/projects/{projectId}/terminology` | `core.usp_SetTerminology` |
| `/api/projects/{projectId}/calendar` | `core.usp_SetProjectCalendar` |
| `/api/projects/{projectId}/rca-fields` | `core.usp_SetProjectRcaFields` |
| `/api/projects/{projectId}/allow-data-source` | `core.usp_AllowProjectDataSource` |
| `/api/projects/{projectId}/allow-lookup` | `core.usp_AllowProjectLookup` |
| `/api/calendars` | `calendar.usp_CreateCalendar` |
| `/api/calendars/{calendarId}/intervals` | `calendar.usp_SetWorkingInterval` |
| `/api/calendars/{calendarId}/holidays` | `calendar.usp_AddHolidayRange` |
| `/api/calendars/holidays/{holidayId}/remove` | `calendar.usp_RemoveHolidayDate` |
| `/api/roles` | `auth.usp_SaveCustomRole` |
| `/api/roles/assign` | `auth.usp_AssignRole` |
| `/api/directory/upsert` | `auth.usp_UpsertDirectoryUser` — trusted admin only |
| `/api/directory/resigned` | `teams.usp_ApplyResignedUser` |
| `/api/rca-templates` | `core.usp_SaveRcaTemplate` |
| `/api/projects/{projectId}/teams` | `teams.usp_CreateTeam` |
| `/api/projects/{projectId}/teams/{teamId}/members` | `teams.usp_SetMember` |
| `/api/projects/{projectId}/teams/{teamId}/absence` | `teams.usp_SetLeaveBackup` |
| `/api/lookups` | `lookup.usp_CreateList` |
| `/api/lookups/{listId}/parent` | `lookup.usp_SetParentList` |
| `/api/lookups/{listId}/items/bulk` | `lookup.usp_BulkAddItems` |
| `/api/lookups/items/{itemId}` | `lookup.usp_UpdateItem` |
| `/api/field-library` | `forms.usp_SaveLibraryField` |
| `/api/projects/{projectId}/forms` | `forms.usp_CreateDefinition` |
| `/api/forms/{formId}/draft` | `forms.usp_SaveDraft` |
| `/api/forms/{formId}/publish` | `forms.usp_Publish` |
| `/api/projects/{projectId}/workflows` | `flow.usp_CreateDefinition` |
| `/api/workflows/{workflowId}/draft` | `flow.usp_SaveDraft` |
| `/api/workflows/{workflowId}/publish` | `flow.usp_Publish` |
| `/api/projects/{projectId}/case-types` | `core.usp_CreateCaseType` |
| `/api/case-types/{caseTypeId}/publish` | `core.usp_PublishCaseType` |
| `/api/projects/{projectId}/cases` | API validation + `work.usp_CreateCase` |
| `/api/tasks/{taskId}/complete` | API validation + `work.usp_CompleteTask` |
| `/api/tasks/{taskId}/forward` | `work.usp_ForwardTask` |
| `/api/tasks/{taskId}/assign` | `work.usp_AssignUnassignedTask` |
| `/api/tasks/{taskId}/force-intimation` | `work.usp_ForceIntimation` |
| `/api/cases/{caseId}/rca` | `work.usp_SubmitRca` |
| `/api/data-sources` | `integration.usp_SaveDataSource` |
| `/api/data-sources/{dataSourceId}/operations` | `integration.usp_SaveOperation` |
| `/api/projects/{projectId}/data-sources/operations/{operationId}/test` | `integration.usp_QueueTest` + safe REST tester + `usp_RecordResult` |
| `/api/notifications/templates` | `notify.usp_SaveTemplate` |
| `/api/projects/{projectId}/notifications/rules` | `notify.usp_SaveRule` |
| `/api/projects/{projectId}/reports/definitions` | `reports.usp_SaveDefinition` |
| `/api/projects/{projectId}/cases/{caseId}/attachments` | multipart file storage + `files.usp_RegisterDocument` |
| `/api/directory/sync` | `501` until real AD/Entra connector configured |

**Important formats**:

- `definitionJson`: `{ "fields": [{ "key":"cnic", "label":"CNIC", "type":"text", "required":true, "regex":"^[0-9]{13}$" }] }`
- `graphJson`: `{ "nodes": [...], "edges": [...] }` matching the SQL `flow.usp_Publish` contract, **not** arbitrary React Flow data.
- `configJson`: `{"formId":12,"workflowId":8,"lookupListIds":[4],"requiredLookupIds":[4],"subjectField":"cnic","slaHours":24}`
- `intakeJson`: `{ "cnic":"1234567890123" }`, `classificationJson`: `{ "classification_category":"ITEM_INTEGER_ID" }`.
- `answersByFormJson`: `{ "FORM_VERSION_INTEGER_ID": { "comments": "Approved" } }`.

### Boundaries and gaps

- The old JSX localStorage store is still active until explicitly connected to these APIs.
- Role permissions are dynamically checked in the database; dev headers are never trusted in production.
- `integration` test does real HTTPS only for allowlisted hosts; there is no background workflow integration worker yet.
- Notification worker is **preview only**. Live email/SMS provider must be configured separately.
- File uploads require a case ID first. Pre-case file staging + malware scanning integration is not implemented.
- Advanced workflow graph execution requires a runtime worker for system nodes/parallel joins/timers.
- API creation and persistence endpoints have not been validated against a running SQL Server or compiled with .NET in the authoring environment.
