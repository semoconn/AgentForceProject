# BehaviorIQ Application Component Reference

This document provides a comprehensive reference for every component in the BehaviorIQ managed package, organized by metadata type.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Custom Objects](#custom-objects)
- [Custom Metadata Types](#custom-metadata-types)
- [Platform Events](#platform-events)
- [Apex Classes](#apex-classes)
- [Triggers](#triggers)
- [Lightning Web Components](#lightning-web-components)
- [FlexiPages](#flexipages)
- [Tabs](#tabs)
- [Permission Sets](#permission-sets)
- [Custom Permissions](#custom-permissions)
- [Custom Metadata Records](#custom-metadata-records)
- [Page Layouts](#page-layouts)

---

## Architecture Overview

BehaviorIQ is a Salesforce AppExchange application that detects CRM behavioral anti-patterns (stale records, duplicates, missing attachments, orphaned records) and provides automated remediation. The application follows a **detect-analyze-remediate** pipeline:

1. **Triggers** publish `Behavior_Event__e` platform events on standard object DML operations
2. **BehaviorLogService** subscribes to events and persists `Behavior_Log__c` records
3. **PatternAnalysisService** runs as a scheduled batch job, evaluating `Behavior_Pattern_Rule__mdt` rules against org data to identify `Identified_Pain_Point__c` records
4. **PatternFixService** executes remediation actions (task creation, field updates, email notifications, escalation reverts) on detected pain points
5. **LWC Dashboard** surfaces insights, leaderboards, and one-click fix actions to end users

The app uses a **freemium model** gated by `LicenseService`: Free users get detection and read-only insights; Premium users unlock auto-fix, remediation preview, and advanced analytics.

---

## Custom Objects

### Behavior_Log__c
Stores individual user behavior events captured by triggers. Each record represents a single DML action (create, update, delete, undelete) on a monitored standard object. Used for behavioral analytics and the user activity leaderboard.

**Key Fields:** `Action_Name__c`, `Object_API_Name__c`, `Record_ID__c`, `User__c`, `Behavior_Data__c`, `Timestamp__c`

### Behavior_Snapshot__c
Point-in-time snapshots of pattern analysis metrics. Created by the `PatternAnalysisService` batch job to track trend data over time (e.g., how many stale cases existed on each analysis run). Powers the trend chart visualizations on the dashboard.

**Key Fields:** `Metric_Name__c`, `Record_Count__c`, `Impact_Score__c`, `Snapshot_Date__c`, `Related_Pain_Point__c`

### BehaviorIQ_Configuration__c
Stores org-level configuration settings for the application, including which objects to monitor, threshold values, and global exclusion filters. Managed through the Setup Wizard and Settings UI.

**Key Fields:** `Monitored_Objects__c`, `Stale_Case_Threshold__c`, `Stale_Opportunity_Threshold__c`, `Cost_Override__c`, `Global_Exclusion_Filter__c`

### BehaviorIQ_License__c
Protected Hierarchy Custom Setting that controls the freemium licensing model. Determines whether the current user/org has Free or Premium access. Checked by `LicenseService.isPremium()` at the entry point of all Premium features.

**Key Fields:** `Status__c` (values: "Free", "Premium")

### Identified_Pain_Point__c
Core entity representing a detected CRM anti-pattern (e.g., "14 Stale Cases over 30 days"). Created and updated by the `PatternAnalysisService` batch job. Displayed on the BehaviorIQ dashboard and used as the trigger for remediation actions.

**Key Fields:** `Description__c`, `Impact_Score__c`, `Status__c`, `Occurrences__c`, `Last_Detected__c`, `Object_API_Name__c`, `Example_Records__c`, `Fixed_Record_Ids__c`, `Cost_Per_Incident__c`, `Unique_Key__c`

### Remediation_Log__c
Audit trail for all fix actions executed by the system. Each record documents what action was taken, on which record, by whom, and whether it succeeded or failed. Provides full traceability for compliance and rollback scenarios.

**Key Fields:** `Action_Taken__c`, `Affected_Record_ID__c`, `Record_Name__c`, `Object_API_Name__c`, `Original_Value__c`, `New_Value__c`, `Executed_By__c`, `Status__c`, `Error_Message__c`, `Rule_Developer_Name__c`, `Snapshot_JSON__c`

### Suggestion_Dismissal__c
Tracks when users dismiss specific pain point suggestions from the dashboard. Prevents dismissed items from resurfacing. Uses a composite `Dismissal_Key__c` (user + rule combination) for deduplication.

**Key Fields:** `Action_Name__c`, `Object_API_Name__c`, `User__c`, `Dismissal_Key__c`

### System_Health_Log__c
Operational health records for batch jobs and system processes. Tracks job execution status, error counts, and error details. Used by the System Health gauge on the dashboard.

**Key Fields:** `Job_Name__c`, `Job_ID__c`, `Status__c`, `Error_Count__c`, `Error_Details__c`

### Workflow_Log__c
Extended logging for workflow-level behavioral tracking. Captures richer context than `Behavior_Log__c`, including IP address and session data. Used by the Workflow Log Viewer component.

**Key Fields:** `Action_Name__c`, `Object_API_Name__c`, `Record_ID__c`, `User__c`, `Behavior_Data__c`, `Timestamp__c`, `IP_Address__c`, `Session_ID__c`

---

## Custom Metadata Types

### Behavior_Pattern_Rule__mdt
Defines pattern detection rules that drive the `PatternAnalysisService` batch engine. Each record specifies a target object, query condition, detection logic type (SOQL or Apex plugin), fix type, and fix configuration. Administrators create and modify these rules to define what anti-patterns to detect and how to remediate them.

**Key Fields:** `Object_API_Name__c`, `Query_Condition__c`, `Logic_Type__c`, `Apex_Handler_Class__c`, `Fix_Type__c`, `Fix_Config__c`, `Threshold_Default__c`, `Cost_Per_Incident__c`, `Is_Active__c`, `Is_Premium__c`, `Description__c`

### Behavior_Setting__mdt
Global application settings stored as custom metadata. Contains default threshold values for pattern detection (stale case days, stale opportunity days, unassigned lead hours, sequential action threshold). Managed through the BehaviorIQ Settings UI.

**Key Fields:** `Stale_Case_Days__c`, `Stale_Opportunity_Days__c`, `Unassigned_Lead_Age_Hours__c`, `Sequential_Action_Threshold__c`

---

## Platform Events

### Behavior_Event__e
Published by triggers on standard objects (Account, Case, Contact, Lead, Opportunity, Task) whenever DML occurs. Consumed by `BehaviorLogService` to create `Behavior_Log__c` records asynchronously. Decouples trigger execution from log persistence.

**Fields:** `Action_Name__c`, `Object_API_Name__c`, `Record_ID__c`, `User_ID__c`, `Behavior_Data__c`

### Workflow_Behavior_Event__e
Platform event for workflow-level behavioral tracking. Similar to `Behavior_Event__e` but carries additional workflow context fields.

**Fields:** `Action__c`, `Object_Type__c`, `Record_ID__c`, `User_ID__c`, `Behavior_Data__c`

---

## Apex Classes

### Core Services

#### BehaviorLogService
Subscribes to `Behavior_Event__e` platform events and creates `Behavior_Log__c` records. Applies `Security.stripInaccessible()` before DML to enforce field-level security. Entry point for the behavior event pipeline.

#### PatternAnalysisService
The primary batch engine of BehaviorIQ. Implements `Database.Batchable` and `Schedulable`. Iterates through active `Behavior_Pattern_Rule__mdt` records, executes dynamic SOQL or Apex plugin analysis, and upserts `Identified_Pain_Point__c` records. Includes governor limit protection with a snapshot flush threshold (500 records) and automatic retention cleanup of old snapshots.

#### PatternFixService
Service class for Premium "Auto-Fix" features. Reads fix configuration from `Behavior_Pattern_Rule__mdt`, determines the appropriate remediation action (task creation, owner assignment, field update, email notification, escalation revert), executes the fix, and creates `Remediation_Log__c` audit records. Supports both Apex plugin-based and declarative JSON-based fix execution.

#### DeclarativeFixExecutor
Executes JSON-based fix actions defined in `Fix_Config__c` without requiring custom Apex code. Supports action types: `UpdateField`, `UpdateFieldFromRecord`, `CreateTask`, `SendEmail`, and `PostChatter`. Uses `Database.setSavepoint()` / `Database.rollback()` for transactional integrity across multi-action configurations. All operations enforce `USER_MODE` and `stripInaccessible`.

#### LicenseService
Centralized freemium licensing gate. Reads `BehaviorIQ_License__c` hierarchy custom setting to determine Free vs. Premium status. Provides `isPremium()` check and `enforcePremiumGate()` method that throws `AuraHandledException` for unauthorized Premium access attempts.

#### DeleteRecordsBatch
Generic batch class for deleting records returned by a SOQL query. Used for data retention cleanup (e.g., purging old snapshots and logs). Automatically appends `WITH SECURITY_ENFORCED` to queries and verifies delete permissions before DML.

### Plugin System

#### PatternPlugin (Interface)
Global interface that enables administrators to write custom Apex pattern detection and remediation logic. Defines two methods: `analyze(PatternPluginContext)` returns matching record IDs, and `fix(List<Id>, Map<String, Object>)` returns a `PatternPluginResult`. Implementations are invoked by name from `Behavior_Pattern_Rule__mdt.Apex_Handler_Class__c`.

#### PatternPluginContext
Context object passed to `PatternPlugin.analyze()`. Encapsulates the target object API name, SOQL query condition, custom configuration map, and rule developer name. Using a context object allows the interface to evolve without breaking existing implementations.

#### PatternPluginResult
Result object returned from `PatternPlugin.fix()`. Contains success/failure counts, error messages, and `Remediation_Log__c` records for audit persistence.

#### PluginInvoker
Safely instantiates and invokes `PatternPlugin` implementations via `Type.forName()`. Validates class existence and interface compliance before instantiation. Includes CPU time monitoring that logs warnings when plugins exceed a 5-second threshold.

#### DuplicateRecordPlugin
Detects duplicate records based on a configurable field (e.g., Email, Phone, Name). Uses `GROUP BY` with `HAVING COUNT(Id) > 1` to find records sharing the same field value. Supports Lead, Contact, Account, and custom objects. Fix action creates follow-up tasks for record owners to merge duplicates.

#### LeadDataQualityPlugin
Detects Leads with missing or invalid email addresses. Queries unconverted Leads where Email is null. Fix action creates tasks for Lead owners to update contact information.

#### MissingAttachmentPlugin
Detects records that should have file attachments but don't. Queries records matching a filter condition (e.g., Closed Won Opportunities), then cross-references `ContentDocumentLink` to identify records with zero attachments. Fix action creates reminder tasks.

#### MockPatternPlugin
Test-only mock implementation of `PatternPlugin` with configurable behavior. Allows tests to set expected return values, simulate exceptions, and verify call counts without deploying real plugin logic.

### UI Controllers

#### PainPointController
Dashboard controller for the insight layer. Fetches active `Identified_Pain_Point__c` records, retrieves pattern-matched record details, and provides record counts. Uses `stripInaccessible` for graceful FLS handling. Supports record dismissal and fix initiation.

#### WorkflowAnalyticsController
Primary dashboard data controller. Provides `getDashboardData()` which returns metrics, recent logs, and Premium status in a single wire call. Handles auto-fix execution, sharing-aware aggregate queries for analytics, and pattern match retrieval. Uses query-then-aggregate pattern to respect sharing rules on aggregate data.

#### UserLeaderboardController
Powers the user activity leaderboard. Aggregates `Behavior_Log__c` records by user using a sharing-aware pattern (query with `USER_MODE` then aggregate in Apex). Enriches results with user profile photos. Includes a "nudge" feature that creates follow-up tasks for inactive users (Premium only).

#### BehaviorSettingsController
Manages reading and writing of `Behavior_Setting__mdt` custom metadata and `BehaviorIQ_Configuration__c` settings. Handles metadata deployment via `Metadata.DeployContainer` for CMDT updates.

#### SetupWizardController
Supports the initial setup wizard flow. Lists trackable objects from the org schema, saves monitored object selections to `BehaviorIQ_Configuration__c`, and schedules the `PatternAnalysisService` batch job. Handles duplicate job detection.

#### ExclusionBuilderController
Provides schema metadata for building visual exclusion rules. Returns monitored objects and their filterable fields, and saves exclusion filter JSON to `BehaviorIQ_Configuration__c.Global_Exclusion_Filter__c`.

#### PatternRuleManagerController
CRUD operations for `Behavior_Pattern_Rule__mdt` records. Provides rule listing with computed display fields, schema introspection for visual query building, and metadata deployment for creating/updating rules.

#### SolutionGuideController
Returns solution guide content (titles and step-by-step instructions) for specific pain point types. Provides actionable Salesforce admin guidance for resolving detected anti-patterns (e.g., "How to create a Quick Action on Contacts").

### Trigger Handler

#### GenericBehaviorTriggerHandler
Generic handler used by all behavior triggers. Accepts an object API name at construction and handles `AFTER_INSERT`, `AFTER_UPDATE`, `AFTER_DELETE`, and `AFTER_UNDELETE` events. Publishes `Behavior_Event__e` platform events with field change detection. Includes a recursion guard (`processedRecordIds`) to prevent duplicate processing.

---

## Triggers

All triggers delegate to `GenericBehaviorTriggerHandler` and fire on after-DML events (insert, update, delete, undelete).

| Trigger | Object | Purpose |
|---------|--------|---------|
| `AccountBehaviorTrigger` | Account | Tracks Account record changes |
| `CaseBehaviorTrigger` | Case | Tracks Case record changes |
| `ContactBehaviorTrigger` | Contact | Tracks Contact record changes |
| `LeadBehaviorTrigger` | Lead | Tracks Lead record changes |
| `OpportunityBehaviorTrigger` | Opportunity | Tracks Opportunity record changes |
| `TaskBehaviorTrigger` | Task | Tracks Task record changes |
| `BehaviorEventTrigger` | Behavior_Event__e | Subscribes to platform events, calls `BehaviorLogService` to persist logs |

---

## Lightning Web Components

### Dashboard & Visualization

#### behaviorIQContainer
Top-level container component that hosts the entire BehaviorIQ application UI. Manages navigation between the dashboard, settings, setup wizard, and rule manager views.

#### behaviorIQDashboard
Main dashboard view displaying active pain points, metrics cards, recent activity, and quick-action buttons. Wires to `WorkflowAnalyticsController.getDashboardData()` for data. Conditionally renders Premium features based on license status.

#### behaviorIQHealthGauge
Visual gauge component displaying the overall CRM health score. Renders a circular progress indicator with color-coded severity (green/yellow/red) based on the aggregate impact score of active pain points.

#### behaviorIQSystemHealth
Displays system operational health metrics from `System_Health_Log__c`. Shows batch job status, error counts, and last-run timestamps. Helps administrators monitor the pattern analysis engine.

#### behaviorIQTrendChart
Line/area chart component showing pain point trends over time. Visualizes `Behavior_Snapshot__c` data to show whether detected issues are increasing or decreasing across analysis runs.

#### behaviorIQUpgradeCta
Call-to-action component displayed to Free-tier users when they attempt to access Premium features. Provides upgrade messaging and links.

#### userLeaderboard
Displays a ranked leaderboard of users by behavioral activity. Shows user photos, names, and impact scores. Premium users can "nudge" inactive team members (creates a follow-up task).

### Configuration & Management

#### setupWizard
Multi-step wizard for initial BehaviorIQ configuration. Guides administrators through selecting monitored objects, configuring thresholds, and scheduling the analysis batch job.

#### behaviorSettings
Settings panel for adjusting application thresholds (stale case days, stale opportunity days, unassigned lead hours, sequential action threshold). Reads from and writes to `Behavior_Setting__mdt` and `BehaviorIQ_Configuration__c`.

#### exclusionBuilder
Visual builder for creating global exclusion rules. Allows administrators to define conditions (object + field + operator + value) that exclude specific records from pattern analysis.

#### patternRuleManager
Management interface for `Behavior_Pattern_Rule__mdt` records. Provides a list/detail view for creating, editing, activating/deactivating, and deleting pattern detection rules.

#### patternRuleEditor
Detail editor for a single pattern rule. Provides form fields for all rule properties including object selection, query condition, fix type, fix configuration JSON, and premium gating.

#### patternRuleList
List view sub-component of `patternRuleManager`. Displays all pattern rules in a sortable, filterable table with status indicators and quick-action buttons.

#### queryConditionBuilder
Visual SOQL condition builder. Lets administrators construct WHERE clause conditions by selecting fields, operators, and values from picklists rather than writing raw SOQL.

#### fixConfigEditor
JSON configuration editor for declarative fix actions. Provides a structured form for defining fix action sequences (UpdateField, CreateTask, SendEmail, etc.) that are serialized to `Fix_Config__c`.

### Logging & Remediation

#### workflowLogViewer
Tabular viewer for `Workflow_Log__c` records. Displays recent workflow activity with filtering, sorting, and pagination. Used by administrators to audit system behavior.

#### remediationPreview
Preview component shown before executing a fix action. Displays which records will be affected, what changes will be made, and estimated impact. Allows users to confirm or cancel before proceeding. Fires bubbling/composed events to communicate with parent components.

---

## FlexiPages

| FlexiPage | Type | Purpose |
|-----------|------|---------|
| `BehaviorIQ_Dashboard` | App Page | Main application page hosting the dashboard container |
| `Behavior_Tracking_Record_Page` | Record Page | Generic behavior tracking embedded on record detail pages |
| `Case_Behavior_Tracking_Record_Page` | Record Page | Case-specific behavior tracking record page |
| `Contact_Behavior_Tracking_Record_Page` | Record Page | Contact-specific behavior tracking record page |
| `Lead_Behavior_Tracking_Record_Page` | Record Page | Lead-specific behavior tracking record page |
| `Opportunity_Behavior_Tracking_Record_Page` | Record Page | Opportunity-specific behavior tracking record page |
| `Admin_View_for_Workflow_Log` | Record Page | Admin-oriented workflow log record page |
| `Workflow_Log_Record_Page` | Record Page | Standard workflow log record detail page |

---

## Tabs

| Tab | Target |
|-----|--------|
| `BehaviorIQ` | FlexiPage (BehaviorIQ_Dashboard) |
| `Behavior_Log__c` | Behavior_Log__c object |
| `Behavior_Snapshot__c` | Behavior_Snapshot__c object |
| `BehaviorIQ_Configuration__c` | BehaviorIQ_Configuration__c object |
| `Identified_Pain_Point__c` | Identified_Pain_Point__c object |
| `Remediation_Log__c` | Remediation_Log__c object |
| `Suggestion_Dismissal__c` | Suggestion_Dismissal__c object |
| `System_Health_Log__c` | System_Health_Log__c object |
| `Workflow_Log__c` | Workflow_Log__c object |

---

## Permission Sets

### BehaviorIQ_Admin
Full administrative access to all BehaviorIQ objects, fields, Apex classes, custom metadata types, and tabs. Grants create/read/update/delete/viewAll/modifyAll on all custom objects. Intended for Salesforce administrators managing the BehaviorIQ application.

### BehaviorIQ_User
Standard user-level access to BehaviorIQ. Provides read access to pain points, behavior logs, and dashboard data. Does not grant configuration or remediation permissions.

---

## Custom Permissions

### Workflow_Log
Controls access to `Workflow_Log__c` records and the Workflow Log Viewer component. Assigned through permission sets to users who need visibility into workflow-level behavioral data.

---

## Custom Metadata Records

### Behavior_Pattern_Rule__mdt Records (24 pre-configured rules)

| Developer Name | Object | Description |
|---------------|--------|-------------|
| `Contact_Data_Gap` | Contact | Identifies contacts with incomplete information |
| `Contract_Expiry_Red_Zone` | Contract | Detects contracts nearing expiration |
| `Duplicate_Accounts` | Account | Finds duplicate account records by name |
| `Duplicate_Contacts` | Contact | Finds duplicate contact records by email |
| `Duplicate_Leads` | Lead | Finds duplicate lead records by email |
| `Frequent_Flyer_Churn` | Account | Identifies high-activity accounts at churn risk |
| `High_Value_Ghosting` | Opportunity | Detects inactive high-value opportunities |
| `Inactive_Owner_Account` | Account | Finds accounts assigned to inactive users |
| `Inactive_Owner_Case` | Case | Finds cases assigned to inactive users |
| `Inactive_Owner_Contact` | Contact | Finds contacts owned by inactive users |
| `Inactive_Owner_Lead` | Lead | Finds leads assigned to inactive users |
| `Inactive_Owner_Opportunity` | Opportunity | Finds opportunities owned by inactive users |
| `Lead_Hoarding` | Lead | Detects users hoarding excessive leads |
| `Missing_Attachment_Closed_Case` | Case | Finds closed cases without file attachments |
| `Missing_Attachment_Closed_Won` | Opportunity | Finds closed-won opportunities without attachments |
| `Orphan_Case` | Case | Finds cases without account relationships |
| `Orphan_Contact` | Contact | Finds contacts without account associations |
| `Orphan_Opportunity` | Opportunity | Finds opportunities without account links |
| `Premature_Escalation` | Case | Detects cases escalated without proper workflow |
| `Stale_Case_14` | Case | Finds cases untouched for 14+ days |
| `Stale_Case_30` | Case | Finds cases untouched for 30+ days |
| `Stale_Opp_90` | Opportunity | Finds opportunities stagnant for 90+ days |
| `Unassigned_Lead_48` | Lead | Finds unassigned leads older than 48 hours |
| `Weekend_Case_Spike` | Case | Detects unusual weekend case creation patterns |

### Behavior_Setting__mdt Records

| Developer Name | Purpose |
|---------------|---------|
| `Default` | Default threshold configuration for pattern analysis |

---

## Page Layouts

| Layout | Object |
|--------|--------|
| `Behavior Log Layout` | Behavior_Log__c |
| `Identified Pain Point Layout` | Identified_Pain_Point__c |
| `Remediation Log Layout` | Remediation_Log__c |
| `Suggestion Dismissal Layout` | Suggestion_Dismissal__c |
| `System Health Log Layout` | System_Health_Log__c |
| `Workflow Log Layout` | Workflow_Log__c |

---

*Document generated: January 27, 2026*
*BehaviorIQ Version: AppExchange Submission*
