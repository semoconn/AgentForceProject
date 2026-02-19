# BehaviorIQ - CLAUDE.md

## Project Overview

BehaviorIQ is a Salesforce managed package that detects CRM data quality issues ("pain points"), scores their business impact, and offers one-click auto-fix remediation. It ships as an AppExchange-ready 2GP package.

- **Package name:** AgentForce SMB
- **Namespace:** `biq`
- **API version:** 63.0
- **Source directory:** `force-app/`

## Tech Stack

- **Backend:** Apex (classes, triggers, batch jobs, platform events)
- **Frontend:** Lightning Web Components (LWC)
- **Metadata:** Custom Metadata Types for pattern rules and settings
- **Testing:** Apex tests + LWC Jest tests
- **Tooling:** Salesforce CLI (`sf`), ESLint, Prettier, Husky pre-commit hooks

## Key Commands

```bash
# Deploy to scratch org
sf project deploy start --target-org <org-alias>

# Run all Apex tests
sf apex run test --target-org <org-alias> --code-coverage --result-format human --wait 10

# Run a specific Apex test class
sf apex run test --target-org <org-alias> --tests PatternAnalysisServiceTest --wait 10

# Run LWC Jest tests
npm run test:unit

# Run Anonymous Apex script
sf apex run --file scripts/apex/<script-name>.apex --target-org <org-alias>

# Lint
npm run lint

# Format
npm run prettier
```

## Architecture

### Core Flow
1. **Triggers** (Account, Case, Contact, Lead, Opportunity, Task, Contract) fire `GenericBehaviorTriggerHandler`
2. Handler publishes `Behavior_Event__e` platform events
3. `BehaviorEventTrigger` calls `BehaviorLogService.createLogsFromEvents()` which dual-writes:
   - Raw `Behavior_Log__c` records (detailed audit trail)
   - `Behavior_Log_Summary__c` counters (daily aggregates for analytics, upserted via `Composite_Key__c`)
4. `PatternAnalysisBatch` runs scheduled/on-demand, executing each `Behavior_Pattern_Rule__mdt` rule
5. Detected issues create/update `Identified_Pain_Point__c` records
6. `PatternFixService` + `DeclarativeFixExecutor` handle auto-fix remediation
7. `CircuitBreakerService` tracks per-rule health in `Rule_Execution_Health__c` (opens after 3 consecutive failures)

### Permission Model
- **`BehaviorIQ_Admin`** — Full CRUD on all 9 custom objects, 50+ field permissions, 9 Apex classes, 9 tabs

### License Tiers
- **Free:** 4 patterns (Contact_Data_Gap, Stale_Case_14, Stale_Case_30, Weekend_Case_Spike). No auto-fix.
- **Premium:** All 24 patterns + auto-fix. Controlled by `BehaviorIQ_License__c` hierarchy custom setting.

### Custom Objects
| Object | Purpose |
|--------|---------|
| `Identified_Pain_Point__c` | Core detection output — one record per pattern |
| `Behavior_Log__c` | Raw user activity tracking (DML events) |
| `Behavior_Log_Summary__c` | Daily aggregate counters (upsert via Composite_Key__c) |
| `Behavior_Snapshot__c` | Trend data snapshots |
| `Remediation_Log__c` | Auto-fix audit trail |
| `Suggestion_Dismissal__c` | Dismissal audit log |
| `System_Health_Log__c` | Batch job health + telemetry |
| `Workflow_Log__c` | Workflow audit trail |
| `BehaviorIQ_Configuration__c` | Admin config (thresholds) |
| `Rule_Execution_Health__c` | Circuit breaker state per rule |
| `Behavior_Pattern_Rule__mdt` | Detection rules (custom metadata) |
| `Behavior_Setting__mdt` | System settings (custom metadata) |
| `Behavior_Event__e` | Platform event for DML tracking |
| `Workflow_Behavior_Event__e` | Platform event for workflow tracking |
| `BehaviorIQ_License__c` | Hierarchy custom setting (Free/Premium) |

### Plugin System
Pattern rules with `Fix_Type__c = 'Plugin'` use the `PatternPlugin` interface:
- `DuplicateRecordPlugin` — deduplication for Leads, Contacts, Accounts
- `LeadDataQualityPlugin` — lead data quality scoring
- `MissingAttachmentPlugin` — closed won/closed case attachment checks
- `PluginInvoker` — safe invocation with interface validation

## LWC Components
| Component | Purpose |
|-----------|---------|
| `behaviorIQContainer` | Main app container |
| `behaviorIQDashboard` | Health score + pain point list |
| `behaviorIQHealthGauge` | Visual health gauge |
| `behaviorIQTrendChart` | Trend visualization |
| `behaviorIQSystemHealth` | System health monitoring |
| `behaviorIQUpgradeCta` | Premium upgrade call-to-action |
| `behaviorSettings` | Admin settings panel |
| `patternRuleManager` | Rule CRUD container |
| `patternRuleList` | Rule listing |
| `patternRuleEditor` | Rule create/edit form |
| `queryConditionBuilder` | Visual SOQL condition builder |
| `fixConfigEditor` | Fix configuration editor |
| `exclusionBuilder` | Record exclusion rules |
| `remediationPreview` | Pre-fix preview |
| `setupWizard` | New customer onboarding |
| `userLeaderboard` | User activity leaderboard |

## Critical Rules When Modifying Code

### Permission Sets
- `BehaviorIQ_Admin` uses `viewAllFields=false` — every field needs an explicit `fieldPermissions` entry
- **NEVER add `fieldPermissions` for required fields** (`<required>true</required>`) — Salesforce errors: "You cannot deploy to a required field"
- **NEVER add `tabSettings` for objects without a matching tab** in `force-app/main/default/tabs/`
- When adding fields to page layouts, ALWAYS verify a matching field permission exists

### Apex Conventions
- All classes use `with sharing` (sharing model enforced)
- CRUD/FLS checks via `Schema.sObjectType.X.isCreateable()` + `Security.stripInaccessible()`
- Dynamic SOQL uses `WITH SECURITY_ENFORCED` or `WITH USER_MODE`
- License gating via `LicenseService.isPremium()`
- No hardcoded IDs — use describe calls and dynamic references

### Testing
- Every Apex class has a corresponding `*Test.cls` file
- Test methods use `@TestSetup` for shared data where possible
- Pattern rules are tested via `PatternAnalysisServiceTest`
- Fix logic tested via `PatternFixServiceTest`
- LWC tests live alongside components as `__tests__/*.test.js`

### Layouts
- Located in `force-app/main/default/layouts/`
- Follow pattern: Information section -> optional Detail sections -> System Information -> Custom Links

## File Organization

```
force-app/main/default/
  classes/          # Apex classes + test classes
  triggers/         # SObject behavior triggers
  lwc/              # Lightning Web Components
  objects/          # Custom object definitions + fields
  layouts/          # Page layouts
  permissionsets/   # BehaviorIQ_Admin
  customMetadata/   # Pattern rules + settings records
  tabs/             # Custom tabs
  applications/     # App definition
  flexipages/       # Lightning pages
```

## Common Workflows

### Adding a New Pattern Rule
1. Create `Behavior_Pattern_Rule__mdt` record in `customMetadata/`
2. If plugin-based: implement `PatternPlugin` interface in a new class
3. Add test coverage in `PatternAnalysisServiceTest`
4. If new fix type: update `PatternFixService` + `DeclarativeFixExecutor`

### Adding a New Field to an Object
1. Create field XML in `objects/<ObjectName>/fields/`
2. Add `fieldPermissions` entry in `BehaviorIQ_Admin.permissionset-meta.xml` (unless field is required)
3. Add field to the object's layout XML
4. Update any Apex classes that should read/write the field

### Adding a New Custom Object
1. Create object folder + definition in `objects/`
2. Add `objectPermissions` in `BehaviorIQ_Admin.permissionset-meta.xml`
3. Create a tab in `tabs/` (required before adding `tabSettings`)
4. Add `tabSettings` in the permission set
5. Create a layout in `layouts/`
