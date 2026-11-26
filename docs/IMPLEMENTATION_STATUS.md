> Updated release notes: see `../../HARDENING_CHANGES_AND_RELEASE_GATES.md` for the current implementation, tests, and remaining deployment blockers. This original status document predates hardening.

# Implementation status (source-generated, not locally compiled)

**Implemented in C# source:**
- ASP.NET Core 10 Web API application; SQL Server ADO.NET data layer with parameterized queries and explicit stored procedure calls.
- Development-only loopback identity headers and production OIDC/JWT authentication configuration, with active SQL directory-user resolution.
- RBAC project/team scope on reads and SQL procedure authorization on writes.
- Platform projects, owners, role management, calendar and holiday ranges, lookups and cascading items, reusable form-field library, forms and workflows with draft/publish/versioning, request/case types, RCA setup, teams/leave backups, audit, reports, notifications configuration, integration configuration.
- Readable indexed case list, complete case detail/audit, My Tasks/My Team tasks, server-side required/regex form validation, case creation/idempotency, human assignment and task completion, Force Intimation.
- Restricted REST operation testing for configured HTTPS public domains, with private-IP blocking, response limits and redirects disabled.
- File-upload storage for an existing case + SQL file metadata; download only after malware scanner marks clean.
- Development notification-preview background worker, which **does not send email/SMS**.

**Not implemented (requires further services/integration):**
- Actual AD/Entra ID import and recurring synchronization. Only trusted admin manual upsert is implemented; `/api/directory/sync` returns 501.
- Live email/SMS provider integrations, delivery receipts and webhook verification. Force Intimation queues an email, and preview mode records that it was *not sent*.
- Durable engine worker for advanced workflow nodes (system API nodes, timer wake-ups, parallel joins, external data-source execution from workflow). Existing SQL human-task transitions work as implemented in stored procedures.
- Malware scanning provider, file staging before case creation, and production object storage. Uploaded files remain `Pending` until scanned by a separately integrated security service.
- Direct frontend integration: the final Chunk 6 JSX frontend currently uses localStorage. The provided fetch client is a starting adapter, not an automatically installed frontend patch.
- Production-ready comprehensive integration, browser, load, threat-model, E2E and deployment tests.

**Verification performed here:** JSON parses; source delimiter checks; SQL stored-procedure name/argument matching for all 40 procedure-backed mutation routes; all direct C# SQL procedure calls resolve to the SQL script. No .NET SDK, SQL Server or network package restore was available for an actual compiler run. See `tests/` and `samples/requests.http`.
