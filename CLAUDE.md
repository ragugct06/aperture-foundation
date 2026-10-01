# Repository guide: aperture-foundation

## Current scope and source of truth

This checkout implements the Aperture Entitlements API: users, roles, effective-dated
role assignments, user-context lookup, PostgreSQL persistence, and Redis caching.
The calling Domain API owns authentication and action-level authorization. The
Entitlements API consumes verified identity headers and requires an authenticated
user for business endpoints.

Use the current controllers, contracts, project files, and tests as the source of
truth. Read `README.md` for the model and delivery setup. Some older README command
examples use `src/` and `Aperture.Entitlements.sln`; use the actual paths below.

The previous platform-wide blueprint is not the implemented scope. This checkout
has no Patient Identity/EMPI, rules version store, audit-read service, tenant control
plane, or `aperture-foundation-v0-openapi.yaml`. Do not add those services or generate
contracts from an assumed specification as part of routine maintenance.

## Repository layout

| Path | Purpose |
| --- | --- |
| `ApertureFoundation.sln` | Solution, including the application test project |
| `Aperture.Entitlements.Api/` | ASP.NET Core host, controllers, identity/error/correlation middleware |
| `Aperture.Entitlements.Contracts/` | API request and response contracts |
| `Aperture.Entitlements.Domain/` | User, role, assignment, and outbox entities |
| `Aperture.Entitlements.Infrastructure/` | Application services, EF Core persistence/migrations, Redis cache |
| `tests/Aperture.Entitlements.Tests/` | xUnit application tests |
| `ci/common/` | Tool setup, restore/build/test, publish, Docker build, vulnerability scan |
| `ci/ecr/` | DEV image publication and image metadata |
| `ci/gitops/` | Read/update environment values and complete deployment PRs |
| `ci/release/` | QA promotion and beta release tagging |
| `ci/tests/` | Offline Python regression tests for CI scripts |
| `scripts/` | Database schema, role, and seed SQL |
| `DockerFile` | Runtime image consuming `app/publish/`; filename is case-sensitive |

## Stack and implementation conventions

- .NET 10, C# 14, nullable reference types, and warnings as errors are configured
  in `Directory.Build.props`.
- Package versions are centrally managed in `Directory.Packages.props`; avoid
  adding independent versions to project files.
- Persistence uses EF Core/Npgsql with PostgreSQL; user-context caching uses Redis.
- Keep controllers thin, application behavior in infrastructure services, domain
  invariants in domain types, and shared DTOs in the contracts project.
- Identity propagation uses `X-Aperture-Identity-Verified` and
  `X-Aperture-User-Email`, configurable through `TrustedDomainIdentity`.
  Inspect `Program.cs` and the middleware before changing authentication behavior;
  do not assume a JWT bearer pipeline is configured.
- Preserve normalized email handling, effective role dates, context versioning,
  cache invalidation, and outbox behavior when changing users or assignments.
- Keep credentials out of source, generated documentation, and logs. Use existing
  environment/configuration mechanisms and user-secrets for local credentials.

## Local commands

Run from the repository root with the .NET 10 SDK and configured package sources:

```sh
dotnet restore ApertureFoundation.sln
dotnet build ApertureFoundation.sln --configuration Release --no-restore
dotnet test tests/Aperture.Entitlements.Tests/Aperture.Entitlements.Tests.csproj \
  --configuration Release --no-build --no-restore \
  --logger 'trx;LogFileName=foundation-tests.trx' --results-directory TestResults
dotnet run --project Aperture.Entitlements.Api/Aperture.Entitlements.Api.csproj
```

`nuget.config` contains both CodeArtifact and a Windows-specific local SDK feed.
Check enabled sources before diagnosing restore failures on another OS. CI configures
CodeArtifact through `ci/common/setup-codeartifact.sh`; do not commit tokens written
into NuGet configuration during setup.

Offline CI regression tests require Python 3, Bash, Git, and jq:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s ci/tests -v
```

For script edits, also run `bash -n` on each changed script and `git diff --check`.
Use the existing regression suite for deployment behavior changes. Tests use mocked
Bitbucket responses and temporary local Git repositories, not live deployments.

## CI and delivery flow

- All PRs and `main` pushes run offline script checks in a lightweight step.
  GitOps/release scripts, CI tests, docs, and pipeline YAML alone do not trigger
  application builds or delivery. The includePaths list in the pipeline selects
  application/build inputs; extend it for new application directories.
- PRs targeting `main` with matching changes: solution restore/build, application
  tests, local publish, Docker build, and Trivy scan.
  Validation has no deployment environment; AWS/CodeArtifact variables and OIDC
  trust must permit repository-level, non-deployment steps.
- `main` with matching changes: the same validation, followed by ECR publication/reuse and a DEV GitOps
  update. Tests must pass. Scans temporarily report fixable HIGH/CRITICAL findings
  without blocking (`IMAGE_SCAN_EXIT_CODE=0`); set it to `1` to enforce the gate.
  Scanner execution errors fail in either mode. Keep this switch explicit rather
  than commenting out an argument inside a continued shell command.
- Manual `promote-to-qa`: read DEV's GitOps image repository/digest and source commit,
  create/reuse an application beta tag, and update QA with that same image digest.
  It does not rebuild or copy the image. Full application history supports the
  current tag ancestry check; image deployment itself does not need that history.
- Manual `validate-build` forces full validation without delivery;
  `build-and-deploy-dev` forces full delivery. `deploy-existing-dev-image` uses
  IMAGE_COMMIT to resolve an existing ECR digest and retry DEV GitOps without
  rebuilding. Run from the revision containing the CI fix, using the original
  image's application commit as IMAGE_COMMIT.
- Native changeset conditions inspect all PR commits but only the last commit
  on `main`. Prefer merge/squash commits; use manual delivery for multi-commit
  pushes ending in unrelated changes or recovery after a failed delivery.
- `install-tools.sh gitops` prepares curl, jq, and Git; `scripts` also prepares
  Python for offline tests; `aws` adds unzip/AWS CLI without .NET checks.
  Default `build` mode prepares unzip/AWS CLI and checks .NET.
- `update-environment.sh` edits GitOps values, preserves an identical deployment
  branch on retries, and calls `complete-pull-request.sh` to reuse/create, approve,
  and merge the PR. Distinguish the application SOURCE_COMMIT from DEPLOY_COMMIT,
  which identifies the GitOps configuration commit.
- PR handling checks the expected source, waits for Bitbucket's configured merge
  checks, handles asynchronous merges, and requires the PR to report `MERGED`.
  Polling defaults to 10 seconds with a 600-second deadline; see the script header
  and README for overrides and credential requirements.
- Keep force-with-lease protection and preserve PR recovery on retries. Do not add
  `[skip ci]` to GitOps deployment commits, since GitOps validation may be required.
- A successful GitOps update does not verify cluster reconciliation or app health.

See the usage guides and numbered comments in `update-environment.sh`,
`complete-pull-request.sh`, and `create-next-tag.sh` before modifying release logic.
These scripts push branches/tags and approve/merge real PRs when run with credentials;
use the offline tests when validating changes locally.

## Generated files

Treat `bin/`, `obj/`, `app/publish/`, `TestResults/`, `reports/`, and Python caches as
outputs rather than source. `reports/*.env` files carry generated image/release
metadata and are sourced by CI; preserve their variable contracts when changing
producer or consumer scripts. Keep migrations, test source, CI scripts, project
files, and checked-in configuration available for review.
