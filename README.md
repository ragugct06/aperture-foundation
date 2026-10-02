# Aperture Entitlements API

This solution implements the Entitlements API with trusted identity propagation from an already-authenticated Domain API, PostgreSQL persistence, and in-memory user-context caching. Authentication and action-level authorization are owned by the calling Domain API.

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
| `Aperture.Entitlements.Infrastructure` | PostgreSQL, in-memory caching, and application services |
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

Liquibase manages the schema in `database/changelog.yaml`. DEV and QA start
with empty databases: run the normal update; no baseline sync is needed.
See [the migration guide](database/README.md) for provisioning, deployment variables,
local commands, and adding changesets. Do not apply the legacy `scripts/` schema
files or EF migrations alongside Liquibase.

The initial changelog creates `entitlement.app_user`, `app_role`,
`role_assignment`, `entitlement_outbox`, and `user_credential`, and seeds the
four reference roles. It does not create database logins or user credentials.

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
4. Effective, non-revoked roles are loaded from PostgreSQL or the local in-memory cache when user context is requested.
5. The Domain API uses that context for its own authorization decisions.
6. Role changes increment user context version, remove the cached entry, and append `EntitlementRevised` to the outbox.

There is no authorization decision cache, Cerbos dependency, or scoped-role model in this service.

## Bitbucket delivery pipeline

Pipeline implementation is maintained in `anovorx/aperture-pipeline-templates`,
pinned to `v1.0.0` by both `bitbucket-pipelines.yml` and `ci/template-version`.
`ci/bootstrap.sh` fetches the tagged scripts into ignored `.pipeline-tools/`.
`ci/service.env` supplies Foundation's project paths, service name, and database hook.

PR validation, main/DEV delivery, and custom workflows without inputs use shared
imports. Manual workflows accepting `RELEASE_TAG`, `SOURCE_REF`, or `IMAGE_COMMIT`
keep thin local wrappers because Bitbucket documents a shared-import limitation
with UI-entered custom variables. Their implementation still lives in the template.

All PRs and `main` pushes run service configuration and shell syntax validation
without AWS authentication or Docker. Shared script regression tests run in the
template repository. Changes only to the pipeline YAML, bootstrap/version pin,
documentation, or database files do not build or deploy the application. Database,
persistence, domain, service configuration, and pipeline YAML changes run the
isolated PostgreSQL migration test. Foundation's schema assertions remain in
`database/test-migrations.sh` and run through the shared database harness.

Application changes and `ci/service.env` changes trigger full validation for PRs
targeting `main`, and full validation plus ECR publication/DEV deployment on `main`.
The change filters are maintained in the exported template YAML.
Other PR targets run
configuration validation and, when relevant, the database check. Image scanning temporarily
reports fixable HIGH/CRITICAL vulnerabilities without failing on findings
(`IMAGE_SCAN_EXIT_CODE=0`, the default). Set `IMAGE_SCAN_EXIT_CODE=1` in Bitbucket
variables to restore blocking on findings. Scanner execution errors still fail
in either mode. The JSON scan report and TRX test results are published as
artifacts. NuGet packages and the Trivy database are cached.

Promotions use existing release tags from trunk: `1.0.0-beta.1` for QE,
`1.0.0-rc.1` for UAT, and `1.0.0` for production. An optional `v` prefix is
accepted for existing tags. The pipeline fetches the selected tag, resolves it
(including annotated tags) to a commit on `origin/main`, verifies the changelog
exists, and resolves that commit's existing ECR image before any migration.
It then applies that commit's migrations and updates GitOps with the same image
digest. A missing image or failed migration stops promotion. No image is rebuilt
and no release tag is created or moved by promotion.

QE retains the existing Bitbucket deployment name `QA` and GitOps path
`environments/qa/aperture-foundation/values.yaml`. UAT and production use `UAT` /
`uat` and `PROD` / `prod`. Create those Bitbucket environments and GitOps values
files before using their pipelines. Configure environment-specific secrets, roles,
network access, and GitOps permissions. Restrict production deployment access in
Bitbucket. GitOps PRs are automatically approved/merged after configured merge
checks; pipeline success does not verify cluster reconciliation or application health.

Create immutable release tags through your release process before promotion.
When advancing the same tested artifact from beta to RC to final, point all three
tags at the same commit. Changed code needs a new tested candidate. Keep ECR
commit tags immutable and retain candidate images for later promotions.
Promotion requires an existing commit-tagged image; database-only releases can
use the migration-only pipelines without an image.

Create tags with the manual `create-beta-tag`, `create-rc-tag`, and
`create-prod-tag` pipelines. Start them from protected `main` with these inputs:

| Pipeline | `RELEASE_TAG` | `SOURCE_REF` |
| --- | --- | --- |
| `create-beta-tag` | `1.0.0-beta.1` | Full 40-character tested main commit SHA |
| `create-rc-tag` | `1.0.0-rc.1` | Approved beta tag, such as `1.0.0-beta.1` |
| `create-prod-tag` | `1.0.0` | Approved RC tag, such as `1.0.0-rc.1` |

RC and final tags must use the same major.minor.patch version as their source.
Each run verifies main ancestry, the changelog, and the existing ECR image before
creating an annotated tag. Existing remote tags on the same commit are reused;
conflicting tags are rejected without force-pushing. No migration or application
deployment is performed. After creation, run the corresponding `promote-to-*`
pipeline with the new tag. Source-tag approval is an operational release decision;
the script does not check test sign-offs or prior deployment status.

Configure secured `APP_REPO_ACCESS_TOKEN` in QA, UAT, and PROD with permission to
push tags to this application repository. Tag creation also uses that environment's
AWS OIDC role and ECR settings. The pipeline-provided `BITBUCKET_GIT_HTTP_ORIGIN`
is the push destination; the credential is supplied through a Git credential
helper, not stored in the remote URL. Restrict these pipelines using each target
environment's deployment permissions. They declare QA/UAT/PROD for permissions
and variable scoping, so Bitbucket may record the tag-creation step as a deployment
even though it only creates a Git tag. Promotion itself requires no tag-push token.

Manual pipelines provide explicit validation and recovery:

| Pipeline | Purpose |
| --- | --- |
| `validate-build` | Run full application/image validation regardless of changed paths; no ECR push or deployment. Use for pipeline YAML/orchestration edits that need a full exercise. |
| `migrate-dev-db` | Validate on disposable PostgreSQL, then migrate DEV using the selected pipeline commit; no application deployment. |
| `migrate-qe-db`, `migrate-uat-db`, `migrate-prod-db` | Supply `RELEASE_TAG`; apply that tag's changelog to the target database without image lookup or GitOps changes. |
| `promote-to-qe`, `promote-to-uat`, `promote-to-prod` | Supply `RELEASE_TAG`; resolve the existing image, migrate the database, then update GitOps. |
| `build-and-deploy-dev` | Force a full build and DEV delivery regardless of changed paths. |
| `deploy-existing-dev-image` | Supply `IMAGE_COMMIT`, the original full application commit SHA used as an ECR tag. Resolve its existing digest, apply its migrations, and update DEV GitOps; no application build or ECR push. |

For a GitOps fix, run `deploy-existing-dev-image` from a revision selecting the
fixed template release and select the original image's commit. This can resume its open
deployment PR. Selecting an older image intentionally redeploys that image;
it does not roll back the database. Images whose commit predates `database/`
cannot use this migration-enabled deployment flow.

Bitbucket's native changeset conditions consider all commits in a PR, but only
the last commit for branch pipelines. Use merge/squash commits into `main` so the
merge changeset includes the application changes. A multi-commit direct or
fast-forward push ending in a CI-only commit can skip delivery; run
`build-and-deploy-dev` to deliver it. These conditions do not track the last
successful deployment. See [Bitbucket step conditions](https://support.atlassian.com/bitbucket-cloud/docs/step-options/).

Configure these Bitbucket variables before running the pipeline:

| Scope | Variables and permissions |
| --- | --- |
| Repository (all steps) | Secured `PIPELINE_TEMPLATE_ACCESS_TOKEN`: access token for `anovorx/aperture-pipeline-templates` with Repository Read only. YAML import access does not grant Git clone access. |
| Repository (PR validation) | `AWS_ROLE_ARN`, `AWS_REGION`, `CODEARTIFACT_DOMAIN`, `CODEARTIFACT_DOMAIN_OWNER`, `CODEARTIFACT_REPOSITORY`. The role needs CodeArtifact read access and an OIDC trust policy permitting this repository's non-deployment steps. |
| DEV deployment | Override `AWS_ROLE_ARN` with the publishing role; configure `AWS_ACCOUNT_ID`, `ECR_REPOSITORY`, and the AWS region. This role also needs CodeArtifact read and ECR publishing access. |
| DEV, QA (QE), UAT, and PROD deployments | `GITOPS_ACCESS_TOKEN`: repository access token for `anovorx/aperture-gitops` with repository read/write and pull request read/write permissions. |
| DEV, QA (QE), UAT, and PROD deployments | `GITOPS_APPROVER_EMAIL`, `GITOPS_APPROVER_TOKEN`: a separate account's Atlassian email and API token with `read:pullrequest:bitbucket` and `write:pullrequest:bitbucket` scopes, repository access, and permission to merge into GitOps `main`. |
| DEV, QA (QE), UAT, and PROD deployments | `DB_SECRET_ID` (environment-specific AWS Secrets Manager name/ARN), `AWS_REGION`, and `AWS_ROLE_ARN` for OIDC. The runner fetches database credentials at runtime; see `database/README.md` for JSON key mappings and TLS settings. Docker containers on the runner must reach that database. |
| QA (QE), UAT, and PROD deployments | `AWS_ACCOUNT_ID` and `ECR_REPOSITORY` identify the shared image repository; `AWS_REGION` must locate that repository and the environment secret. The OIDC role needs `ecr:DescribeImages` on the repository plus secret/KMS access. Supply `RELEASE_TAG` when starting promotion; no application tag-push token is needed. |

Keep tokens secured and scoped to deployment environments. PR validation no
longer declares a DEV deployment and cannot read DEV deployment variables.
Configure required builds/approvals as enforced merge checks in the GitOps
repository. GitOps commits no longer contain `[skip ci]`, so its validation can
run. Start promotion pipelines from `main` selecting the intended template release,
and restrict them through Bitbucket deployment permissions. `RELEASE_TAG` selects
the artifact and migrations independently of the pipeline checkout commit.

An unchanged deployment retry preserves its branch commit and reuses the open
PR. Pending merge checks and asynchronous merge tasks are polled every 10
seconds for up to 600 seconds. Override these limits using
`GITOPS_POLL_INTERVAL_SECONDS` and `GITOPS_MERGE_TIMEOUT_SECONDS`. Failed
approvals, denied API requests, changed PR source commits, and failed merge
tasks stop the deployment; resolve the reported issue and rerun the step.

### Runner capacity

The defaults target a dedicated `t3.large` host with 8 GB RAM: `size: 1x`
(4 GB total step budget), including `docker.memory: 2048` (2 GB for Docker,
leaving 2 GB for the build container when Docker is enabled). Allow only one
active step across all runner registrations on that host, leaving capacity for
the OS, Docker daemon, and runner processes. Enforce this in the runner setup;
pipeline YAML does not enforce host-wide concurrency. Verify application builds
and PostgreSQL/Liquibase tests under these limits before increasing concurrency.

### Template cutover and local validation

Publish and test the template repository, then create its immutable `v1.0.0` tag
and configure `PIPELINE_TEMPLATE_ACCESS_TOKEN` **before pushing this application's
migration branch**. Bitbucket must resolve the template tag to load the pipeline.
Run `validate-build`, verify DEV delivery, and exercise manual workflows in a
nonproduction environment before the next production release.

For a template upgrade, update the import and `ci/template-version` together in a
reviewed change. Never move published template tags. A version-only edit does not
automatically deploy DEV; use `validate-build` for verification. See the template
repository README for release, onboarding, and rollback instructions.

From this checkout, with Python 3/PyYAML, Bash, Git, jq, and curl installed:

```sh
bash ../aperture-pipeline-templates/ci/run.sh validate-config
# Requires a running Docker daemon; exercises Foundation's database hook.
bash ../aperture-pipeline-templates/ci/run.sh test-database
# Shared offline regression suite; install its ci/requirements-test.txt first.
bash ../aperture-pipeline-templates/ci/common/validate-scripts.sh
```

To fetch the published template instead, export the secured read-only token locally,
run `bash ci/bootstrap.sh`, and use `.pipeline-tools/ci/run.sh` for those commands.
