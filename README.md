# Aperture Foundation Services

This repository contains the **platform control-plane services** for the Aperture platform. These are the remote foundation services that the Platform SDK thin clients call at runtime.

> This is not the SDK. The SDK (NuGet packages) lives in `aperture-foundation-sdk`. This repo contains the actual services that the SDK talks to over HTTP.

---

## How this repo fits in the platform

The Aperture Platform SDK (`Aperture.Platform.*`) runs embedded inside every domain macroservice. Most SDK capabilities — tenant resolution, persistence, caching, messaging, audit writes, correlation — run entirely in-process or directly against infrastructure (PostgreSQL, Redis, SQS). They never make a network call to a foundation service.

Only three capabilities are genuinely remote and require a foundation service:

| Capability | What calls it | This repo |
|---|---|---|
| Entitlement / PDP (Authorize) | SDK PEP middleware at runtime | Separate repo (Ragupathi) |
| Patient Identity / EMPI (Resolve) | SDK EMPI thin client | `aperture-patient-identity` repo |
| Rules version lookup (effective definition) | SDK Rules thin client (cached) | `Aperture.PlatformServices.RulesRegistry` (this repo) |

Config / feature flags is **not** a remote REST service. It reads from AWS AppConfig / SSM directly via the SDK library. `Aperture.PlatformServices.Config` in this repo is a placeholder for the future authoring/admin surface only.

---

## Repository structure

```
aperture-foundation/
├── Directory.Build.props                   # shared build settings (net10.0, nullable, warnings-as-errors)
├── Directory.Packages.props                # central NuGet version pinning
├── ApertureFoundation.sln
├── Aperture.PlatformServices.RulesRegistry/   # Rules Registry REST service (M0)
└── Aperture.PlatformServices.Config/          # Config authoring surface (deferred, stub only)
```

---

## Services

### 1. Aperture.PlatformServices.RulesRegistry

The Rules Registry is the system of record for versioned, effective-dated rule definitions. It is the only service in this repo that is active in M0.

**What it does:**
- Stores immutable rule set versions registered by the CI/CD pipeline after PR approval in Bitbucket
- Enforces no-overlap constraint — at most one approved version per rule set per effective date range per scope
- Serves effective-dated version lookups to the SDK rules thin client
- Binds every rule decision to its exact version and Git commit SHA for audit and compliance (21 CFR Part 11)

**Why a dedicated service and not just Git/S3:**
Git captures deploy-time lineage. A copay audit needs effective-time — "which rule was in force on the service date, prove it." Deploy time is not effective time. S3 holds only the current version. Nothing in Git/S3 durably binds a stored decision to its rule version. The Rules Registry is the system of record; Git is the front door.

**REST API surface:**

| Method | Path | Caller | Purpose |
|---|---|---|---|
| POST | /rules/versions | CI/CD pipeline (after PR approval) | Register an immutable approved rule set version |
| GET | /rules/versions | SDK rules thin client | List versions for a rule set key |
| GET | /rules/versions/{id} | SDK rules thin client | Fetch a specific version by ID |

> Rule execution itself is NOT done here. The SDK fetches the definition (and caches it), then executes it in-process using Microsoft RulesEngine. There is no remote rule-execution endpoint.

**Effective-dated version selection (what the SDK thin client queries):**

```sql
SELECT *
FROM rule_set_version
WHERE rule_set_key   = @key
  AND COALESCE(scope_manufacturer, @mfr) = @mfr
  AND (scope_drug = @drug OR scope_drug IS NULL)
  AND status         = 'approved'
  AND effective_from <= @asOf
  AND (effective_to IS NULL OR @asOf < effective_to)
ORDER BY (scope_drug IS NULL) ASC, version DESC
LIMIT 1;
```

`asOf` is the date of service, so historical re-evaluation reproduces the exact version that was in force at the time. Zero rows means no approved version found — the SDK fails closed.

**Governance flow:**

```
Author edits rule JSON in Bitbucket
  -> PR + reviewers + branch protection (approval, diff, blame)
  -> PR manifest carries effective_from / effective_to + applicability
  -> merge
CI/CD (Bitbucket Pipelines):
  -> validate schema; dry-run against MS RulesEngine
  -> POST /rules/versions  (registers immutable rule_set_version)
  -> (optional) upload definition to S3 as execution cache
Runtime:
  domain -> IRulesEvaluator.Evaluate(key, scope, asOf=serviceDate, input)
         -> SDK thin client fetches effective version (cached)
         -> MS RulesEngine executes in-process
         -> decision bound to version_id + commit_sha in rule_evaluation_audit
```

Rollback is forward-correcting — register a corrective version or close the bad one with `effective_to`. History is never rewritten.

---

### 2. Aperture.PlatformServices.Config

Stub only in M0. Not a runtime REST service.

Config and feature flags are consumed by the SDK via AWS AppConfig and AWS Systems Manager (SSM) directly. The SDK `Aperture.Platform.Configuration.Client` package reads config in-process with a local cache. No network call to a foundation service is made on the request path.

This project is reserved for a future config authoring and management UI. It must not consume its own SDK client (circular dependency).

---

## How the SDK consumes the Rules Registry

In a macroservice, the SDK is registered once:

```csharp
builder.Services.AddAperturePlatform(o =>
{
    o.Tenancy.Mode = TenancyMode.SingleOperator;
    o.Persistence.EnableRowLevelSecurity = true;
    o.Messaging.UseOutbox = true;
    o.Security.RequireEntitlement = true;
    o.Audit.Immutable = true;
});
```

At rule evaluation time the domain calls:

```csharp
var result = await rulesEvaluator.Evaluate(
    key:   "copay.benefit_caps",
    scope: new RuleScope(manufacturerId, drugId),
    asOf:  serviceDate,
    input: evaluationInput,
    ct:    cancellationToken);
```

The SDK thin client fetches the effective version from this service (with short-TTL cache), then Microsoft RulesEngine executes the definition in-process inside the domain. The decision is written to `rule_evaluation_audit` along with `rule_set_version_id` and `git_commit_sha`.

---

## Related repositories

| Repository | Purpose |
|---|---|
| `aperture-foundation-sdk` | Platform SDK NuGet packages (`Aperture.Platform.*`) — embedded in every macroservice |
| `aperture-patient-identity` | Patient Identity (EMPI) service — `POST /patients/resolve`, `GET /patients/{id}` |
| `aperture-patient-support` | Patient Support macroservice (Copay, Benefits Investigation, Prior Authorization) |

---

## Local development setup

### Prerequisites

- .NET 10 SDK
- PostgreSQL (for the Rules Registry database)
- AWS CLI (for AppConfig / SSM in Config, when implemented)

### Build

```powershell
dotnet build ApertureFoundation.sln
```

### SDK reference

During local development, the SDK is referenced as a project reference via `SdkRoot` in `Directory.Build.props`. Once SDK packages are published to AWS CodeArtifact, switch to `PackageReference` and remove the local path override.

The current `SdkRoot` default points to:
```
C:\Users\vishalkumar\aperture-foundation\aperture-foundation-sdk
```

Override it per machine without committing by setting the `SdkRoot` environment variable or adding a local `Directory.Build.props` that is git-ignored.

---

## API conventions

All REST endpoints in this repo follow the same conventions as the domain APIs:

- Auth: JWT bearer token
- Correlation: `X-Correlation-Id` header (propagated by SDK middleware)
- Idempotency: `Idempotency-Key` header on mutations
- Errors: RFC 7807 `application/problem+json`
- Pagination: cursor-based

The full OpenAPI contract will be published as `aperture-foundation-openapi.yaml`.
