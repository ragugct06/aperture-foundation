# Aperture Entitlements API

This solution implements the Entitlements API with trusted identity propagation from an already-authenticated Domain API, PostgreSQL persistence, and Redis user-context caching. Authentication and action-level authorization are owned by the calling Domain API.

The BFF implementation has been removed. Browser login, session-cookie handling, token storage, proxying, PKCE, and CSRF behavior are outside this solution.

## Updated model

### User

The former `Subject` model is now `User`. Its business fields are:

- `FirstName`
- `LastName`
- `Email`
- `Status`: `active`, `suspended`, or `deprovisioned`

`UserId` is the database identifier and `ContextVersion` is internal cache/concurrency metadata. Email is normalized to lowercase and is unique.

### Role

The former `Persona` model is now `Role`. A role contains:

- `RoleId`
- `RoleKey`
- `Description`
- `Status`: `active` or `retired`

There is no separate persona-to-role bridge. The Domain API receives the effective `RoleKey` values and performs its own authorization.

### Role assignment

A role assignment connects one user to one role and remains effective-dated:

```text
User → RoleAssignment → Role
```

Tenant/program scopes and `scopedRoles` have been removed. The user context returns a flat `roles` collection.

## Projects

| Project | Responsibility |
|---|---|
| `Aperture.Entitlements.Contracts` | User, role, and assignment API contracts |
| `Aperture.Entitlements.Domain` | User, role, assignment, and outbox entities |
| `Aperture.Entitlements.Infrastructure` | PostgreSQL, Redis, and application services |
| `Aperture.Entitlements.Api` | User context and role-administration endpoints |
| `Aperture.Entitlements.Tests` | Domain, user resolution, and authenticated-user boundary tests |

## Endpoints

### Internal user context

These endpoints require a verified authenticated user propagated by the trusted Domain API. The Entitlements API does not evaluate roles, scopes, or action permissions.

| Method | Path | Purpose |
|---|---|---|
| POST | `/entitlement/v1/users:resolve` | Resolve or create a user by normalized email |
| GET | `/entitlement/v1/users/{userId}/context` | Return the user and flat effective role list |

Resolve request:

```json
{
  "firstName": "Example",
  "lastName": "User",
  "email": "user@example.com",
  "status": "active"
}
```

Context response:

```json
{
  "userId": "11111111-1111-1111-1111-111111111111",
  "firstName": "Example",
  "lastName": "User",
  "email": "user@example.com",
  "status": "active",
  "roles": ["ClaimsSpecialist"],
  "version": 2,
  "eTag": "..."
}
```

### Role administration

These endpoints require only a verified authenticated user. The calling Domain API is responsible for authorizing role-administration actions before forwarding the request.

```text
GET    /entitlement/v1/roles
POST   /entitlement/v1/roles
GET    /entitlement/v1/roles/{roleId}
PUT    /entitlement/v1/roles/{roleId}
DELETE /entitlement/v1/roles/{roleId}

GET    /entitlement/v1/users/{userId}/role-assignments
POST   /entitlement/v1/users/{userId}/role-assignments
DELETE /entitlement/v1/users/{userId}/role-assignments/{assignmentId}
```

### User administration and lookup

The following endpoints are available under both `/api/users` and `/users`:

| Service operation | Endpoint |
|---|---|
| `FindByEmailAsync` | `GET /api/users?email={email}` |
| `FindByIdAsync` | `GET /api/users/{id}` |
| `FindByIdsAsync` | `GET /api/users?ids={id1,id2}` |
| `SearchIdsAsync` | `GET /api/users/search?q={text}` |
| `AddAsync` | `POST /api/users` |
| `UpdateAsync` | `PATCH /api/users` or `PATCH /api/users/{id}` |

These endpoints require only a verified authenticated user. `SearchIdsAsync` returns at most 100 user IDs and requires at least two search characters.

The following compatibility endpoint creates a role assignment through the same audited assignment service:

```text
POST /api/authorization/administration/role-assignments
```

Request:

```json
{
  "userId": "11111111-1111-1111-1111-111111111111",
  "roleId": "22222222-2222-2222-2222-222222222222",
  "effectiveFrom": "2026-09-18",
  "effectiveTo": null
}
```

`DELETE` retires or revokes; it does not physically delete compliance history.

## Authentication boundary and identity propagation

The Entitlements API no longer validates JWTs and does not register an ASP.NET authentication handler. The calling Domain API must validate the token first and then replace any inbound identity headers with trusted values:

| Header | Value |
|---|---|
| `X-Aperture-Identity-Verified` | `true` after successful Domain API authentication |
| `X-Aperture-User-Email` | Validated caller email |

`TrustedDomainIdentityMiddleware` converts the verified marker and email into an authenticated `ClaimsPrincipal`. `AuthenticatedUserMiddleware` rejects API requests with `401` unless that principal is authenticated. The Entitlements API does not validate a bearer token and does not evaluate roles, scopes, or resource/action policies.

This arrangement is safe only when the Entitlements API is private and the network boundary guarantees that callers cannot forge the headers. API Gateway/ingress must remove client-supplied copies, the Domain API must set fresh values after authentication, and east-west traffic should use mTLS and network policies.

## PostgreSQL

Create the database and apply scripts in order:

```powershell
$env:PGPASSWORD = "your-local-password"
psql -h localhost -U postgres -c "CREATE DATABASE aperture_foundation;"
psql -h localhost -U postgres -d aperture_foundation -f deploy/postgres/001_entitlement_schema.sql
psql -h localhost -U postgres -d aperture_foundation -f deploy/postgres/002_database_roles.sql
psql -h localhost -U postgres -d aperture_foundation -f deploy/postgres/003_seed_roles.sql
```

The schema uses these tables:

```text
entitlement.app_user
entitlement.app_role
entitlement.role_assignment
entitlement.entitlement_outbox
```

If upgrading an existing database containing the previous `subject`/`persona` schema, create and review a data migration instead of running this initial script over the existing database.

The optional first `Admin` assignment can be created as deployment seed data so the Domain API has an initial administrative role to consume:

```sql
INSERT INTO entitlement.role_assignment
    (user_id, role_id, effective_from, assigned_by)
SELECT
    :'user_id'::uuid,
    role_id,
    current_date,
    :'deployment_identity'
FROM entitlement.app_role
WHERE role_key = 'Admin' AND status = 'active';
```

After bootstrapping, manage assignments through the administration endpoints. The Domain API must authorize those calls.

## Configuration

Use user-secrets locally and AWS Secrets Manager in deployed environments:

```powershell
dotnet user-secrets set "ConnectionStrings:EntitlementsDatabase" "Host=localhost;Port=5432;Database=aperture_foundation;Username=postgres;Password=..." --project src/Aperture.Entitlements.Api
dotnet user-secrets set "ConnectionStrings:Redis" "localhost:6379,abortConnect=false" --project src/Aperture.Entitlements.Api
```

## Build and run

```powershell
dotnet restore Aperture.Entitlements.sln
dotnet build Aperture.Entitlements.sln
dotnet test Aperture.Entitlements.sln
dotnet run --project src/Aperture.Entitlements.Api
```

Swagger is available in Development at `https://localhost:7102/swagger`. Its **Authorize** dialog accepts the same two propagated identity headers used by the API:

```text
VerifiedIdentity: true
UserEmail: authenticated.user@example.test
```

These development inputs simulate a trusted Domain API; they are not bearer-token validation. Swagger UI and `/health` remain reachable without identity so that users can enter the headers and orchestrators can run health probes, but calls to business endpoints require both values.

Use `Aperture.Entitlements.http` for example requests.

## Identity and entitlement-context flow

1. The Domain API validates authentication and replaces the trusted identity headers.
2. The Entitlements API constructs a principal from the verified marker and email.
3. Requests without an authenticated principal receive `401`; no role/scope authorization is performed here.
4. Effective, non-revoked roles are loaded from PostgreSQL or Redis when user context is requested.
5. The Domain API uses that context for its own authorization decisions.
6. Role changes increment user context version, remove the Redis entry, and append `EntitlementRevised` to the outbox.

There is no authorization decision cache, Cerbos dependency, or scoped-role model in this service.

## Bitbucket delivery pipeline

PRs targeting `main` run the CI script regression tests, restore/build the solution
including its test project, run application tests, build the runtime image, and
scan it. PRs targeting other branches are skipped. Image scanning temporarily
reports fixable HIGH/CRITICAL vulnerabilities without failing on findings
(`IMAGE_SCAN_EXIT_CODE=0`, the default). Set `IMAGE_SCAN_EXIT_CODE=1` in Bitbucket
variables to restore blocking on findings. Scanner execution errors still fail
in either mode. The JSON scan report and TRX test results are published as
artifacts. NuGet packages and the Trivy database are cached.

Changes on `main` also publish the image to ECR and update DEV through a GitOps
PR. The manual `promote-to-qa` pipeline reads DEV's GitOps image digest, creates
or reuses a beta release tag, and promotes that digest to QA without rebuilding.
Both environments automatically approve and merge their GitOps PR after the
configured repository merge checks allow it. Success means the GitOps PR has
merged; it does not verify cluster reconciliation or application health.

Configure these Bitbucket variables before running the pipeline:

| Scope | Variables and permissions |
| --- | --- |
| Repository (PR validation) | `AWS_ROLE_ARN`, `AWS_REGION`, `CODEARTIFACT_DOMAIN`, `CODEARTIFACT_DOMAIN_OWNER`, `CODEARTIFACT_REPOSITORY`. The role needs CodeArtifact read access and an OIDC trust policy permitting this repository's non-deployment steps. |
| DEV deployment | Override `AWS_ROLE_ARN` with the publishing role; configure `AWS_ACCOUNT_ID`, `ECR_REPOSITORY`, and the AWS region. This role also needs CodeArtifact read and ECR publishing access. |
| DEV and QA deployments | `GITOPS_ACCESS_TOKEN`: repository access token for `anovorx/aperture-gitops` with repository read/write and pull request read/write permissions. |
| DEV and QA deployments | `GITOPS_APPROVER_EMAIL`, `GITOPS_APPROVER_TOKEN`: a separate account's Atlassian email and API token with `read:pullrequest:bitbucket` and `write:pullrequest:bitbucket` scopes, repository access, and permission to merge into GitOps `main`. |
| QA deployment | `APP_REPO_ACCESS_TOKEN`: repository access token permitting release tag pushes to this application repository. `RELEASE_VERSION` is supplied when starting promotion, for example `1.2.0`. |

Keep tokens secured and scoped to deployment environments. PR validation no
longer declares a DEV deployment and cannot read DEV deployment variables.
Configure required builds/approvals as enforced merge checks in the GitOps
repository. GitOps commits no longer contain `[skip ci]`, so its validation can
run. A custom QA pipeline should be started from `main` and restricted through
Bitbucket deployment permissions.

An unchanged deployment retry preserves its branch commit and reuses the open
PR. Pending merge checks and asynchronous merge tasks are polled every 10
seconds for up to 600 seconds. Override these limits using
`GITOPS_POLL_INTERVAL_SECONDS` and `GITOPS_MERGE_TIMEOUT_SECONDS`. Failed
approvals, denied API requests, changed PR source commits, and failed merge
tasks stop the deployment; resolve the reported issue and rerun the step.

Run the offline CI regression tests locally with Python 3, Bash, Git, and jq:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ci/tests -v
```
