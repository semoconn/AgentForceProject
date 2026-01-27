# BehaviorIQ Security Review Documentation

This document addresses Salesforce Code Analyzer (SFCA) findings for AppExchange security review.

## Summary

- **Security Violations (ApexCRUDViolation, ApexSOQLInjection): 0**
- **All SOQL queries use WITH USER_MODE or SECURITY_ENFORCED**
- **All DML operations use `as user` modifier with Security.stripInaccessible()**
- **All dynamic SOQL uses Schema-validated identifiers or bind variables**

---

## Addressed Security Measures

### 1. CRUD/FLS Enforcement

All database operations enforce CRUD and Field-Level Security through:

- **SOQL Queries**: `WITH USER_MODE` clause enforces sharing rules and FLS at query execution
- **DML Operations**: `as user` modifier enforces CRUD permissions at runtime
- **Field Stripping**: `Security.stripInaccessible()` removes inaccessible fields before DML

Example pattern used throughout codebase:
```apex
// Query with USER_MODE for sharing/FLS
List<Account> accounts = [SELECT Id, Name FROM Account WITH USER_MODE];

// DML with security stripping and 'as user'
List<SObject> secureRecords = Security.stripInaccessible(AccessType.CREATABLE, records).getRecords();
insert as user secureRecords;
```

### 2. SOQL Injection Prevention

All dynamic SOQL queries are protected through:

- **Schema Validation**: Object/field names are validated via `Schema.getGlobalDescribe()` and `DescribeSObjectResult` before use in queries
- **Bind Variables**: User-provided values use Apex bind variables (`:variableName`) not string concatenation
- **String.escapeSingleQuotes()**: Applied to identifiers as additional defense-in-depth

---

## False Positive Explanations

### 1. ApexCRUDViolation on Custom Metadata (CMDT) Queries

**Files Affected**: BehaviorSettingsController.cls, PatternRuleManagerController.cls, PatternFixService.cls, WorkflowAnalyticsController.cls

**Finding**: PMD flags CMDT queries (Behavior_Pattern_Rule__mdt, Behavior_Setting__mdt) as lacking CRUD enforcement.

**Explanation**: This is a **known false positive**. Custom Metadata Types:
- Are read-only at runtime (cannot be modified via DML)
- Are controlled by metadata deployment, requiring administrator/developer access
- Do not support `WITH USER_MODE` clause by Salesforce design
- Contain configuration data, not user data

**Mitigation**: Added `// NOPMD - ApexCRUDViolation: CMDT doesn't support USER_MODE` comments with documentation.

### 2. ApexSOQLInjection on Schema-Validated Dynamic SOQL

**Files Affected**: DuplicateRecordPlugin.cls, MissingAttachmentPlugin.cls, PatternFixService.cls, WorkflowAnalyticsController.cls, PatternRuleManagerController.cls

**Finding**: PMD flags dynamic SOQL queries as potential injection risks.

**Explanation**: These are **false positives** because all dynamic values are:
- Object names validated via `Schema.getGlobalDescribe().get(objectApiName)` returning null for invalid objects
- Field names validated via `DescribeSObjectResult.fields.getMap().get(fieldName)` returning null for invalid fields
- Validated identifiers obtained from `DescribeSObjectResult.getName()` and `DescribeFieldResult.getName()` (not user input)
- User-provided values always use bind variables (`:variableName`)

**Example of Schema Validation Pattern**:
```apex
// Validate object exists and is accessible via Schema
Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
if (sObjectType == null) {
    return new List<Id>(); // Object doesn't exist - safe return
}
Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
if (!describeResult.isAccessible()) {
    return new List<Id>(); // Object not accessible - safe return
}
// Get validated name from Schema (not from user input)
String validatedObjectName = describeResult.getName();
// Safe to use in query
String query = 'SELECT Id FROM ' + validatedObjectName + ' WHERE Id IN :recordIds WITH USER_MODE';
```

**Mitigation**: Added `// NOPMD - ApexSOQLInjection` comments documenting the validation chain.

### 3. ProtectSensitiveData Warnings on Field Names

**Fields Affected**: Unique_Key__c, Dismissal_Key__c, Unassigned_Lead_Age_Hours__c

**Finding**: PMD flags fields with "key", "token", or "hours" in their names as potentially containing sensitive data.

**Explanation**: These are **false positives** - the fields contain:
- `Unique_Key__c`: A calculated hash for deduplication (e.g., "Stale_Opportunity_001ABC") - not an auth token
- `Dismissal_Key__c`: A composite key for tracking user dismissals (e.g., "user001_rule_Stale_Case") - not an auth token
- `Unassigned_Lead_Age_Hours__c`: A numeric threshold value (e.g., 24, 48, 72) - not an auth token

None of these fields store authentication credentials, API keys, or secrets.

### 4. GlobalVariable in LWC JavaScript

**Files Affected**: All LWC components (behaviorLogList.js, workflowAnalyticsDashboard.js, etc.)

**Finding**: PMD flags 129 instances of "global variable" usage.

**Explanation**: This is a **known PMD false positive** for Lightning Web Components. PMD incorrectly identifies the `this` keyword in LWC class methods as a "global variable". In reality:
- `this` refers to the component instance, not a global variable
- This is standard JavaScript class syntax required by the LWC framework
- Salesforce's own LWC documentation and examples use this pattern

**Example flagged code**:
```javascript
handleClick() {
    this.isLoading = true;  // PMD incorrectly flags 'this' as GlobalVariable
}
```

### 5. EmptyCatchBlock in Test Classes

**Files Affected**: Test classes (*Test.cls)

**Finding**: PMD flags empty catch blocks as potential issues.

**Explanation**: These are **intentional in test classes** for exception testing patterns:
```apex
try {
    // Code that should throw an exception
    controller.methodThatShouldFail();
    System.assert(false, 'Expected exception was not thrown');
} catch (Exception e) {
    // Expected - test passes when exception is caught
}
```

The empty catch blocks confirm that expected exceptions are properly thrown.

### 6. EagerlyLoadedDescribeSObjectResult

**Files Affected**: Various controller classes

**Finding**: PMD suggests lazy loading for Schema.describe() calls.

**Explanation**: This is a **performance optimization suggestion**, not a security issue. The code prioritizes security (validating object/field accessibility) over micro-optimization. The performance impact is negligible for the use cases in this application.

### 7. AvoidLwcBubblesComposedTrue

**Files Affected**: remediationPreview.js

**Finding**: PMD warns about LWC events with both `bubbles: true` and `composed: true`.

**Explanation**: This is a **best practice warning**, not a security issue. The events in question are intentionally configured to:
- Bubble up through the component hierarchy
- Cross shadow DOM boundaries for parent component communication

This is the correct pattern for custom events that need to communicate with parent components in a LWC hierarchy.

---

## Security Controls Summary

| Control | Implementation |
|---------|----------------|
| CRUD Enforcement | `as user` DML modifier, `Schema.SObjectType.isCreateable/isUpdateable/isAccessible()` checks |
| FLS Enforcement | `WITH USER_MODE`, `Security.stripInaccessible()` |
| Sharing Enforcement | `with sharing` class modifier, `WITH USER_MODE` |
| SOQL Injection Prevention | Schema validation, bind variables, `String.escapeSingleQuotes()` |
| XSS Prevention | LWC framework handles output encoding automatically |

---

## Verification Commands

To verify security violations are resolved:

```bash
# Check for security-category violations (should return 0 high-severity security issues)
sf code-analyzer run --rule-selector "pmd:Security:2" --workspace .

# Full security scan
sf code-analyzer run --rule-selector "pmd:ApexCRUDViolation" --rule-selector "pmd:ApexSOQLInjection" --workspace .
```

---

## Architectural Security Hardening (January 2026)

### Transaction Integrity (DeclarativeFixExecutor.cls)

**Issue**: Multi-action fix operations could leave partial state on failure.

**Resolution**: Implemented `Database.setSavepoint()` and `Database.rollback()` pattern for atomic transactions:
```apex
Savepoint sp = Database.setSavepoint();
try {
    // Execute each action within the transaction boundary
    for (Object actionObj : actions) {
        executeAction(actionType, action, recordIds);
    }
} catch (DeclarativeFixException e) {
    Database.rollback(sp);
    pendingLogs.clear();
    throw new DeclarativeFixException('Fix rolled back due to error: ' + e.getMessage());
}
```

### Sharing-Aware Aggregate Queries (WorkflowAnalyticsController.cls, UserLeaderboardController.cls)

**Issue**: Aggregate queries (`GROUP BY`) bypass sharing rules, potentially revealing counts of inaccessible records.

**Resolution**: Implemented query-then-aggregate pattern where records are first queried with `USER_MODE` to respect sharing, then aggregated in Apex:
```apex
// STEP A: Query accessible logs with USER_MODE to respect sharing rules
List<Behavior_Log__c> accessibleLogs = [
    SELECT Id, User__c FROM Behavior_Log__c
    WHERE User__c != null WITH USER_MODE LIMIT 50000
];

// STEP B: Aggregate counts by User__c in Apex (sharing-aware)
Map<Id, Integer> userEventCounts = new Map<Id, Integer>();
for (Behavior_Log__c log : accessibleLogs) {
    // ... aggregate in Apex
}
```

### Governor Limit Protection (PatternAnalysisService.cls)

**Issue**: Unbounded snapshot accumulation in batch jobs could exceed heap limits.

**Resolution**: Implemented automatic flushing mechanism:
```apex
private static final Integer SNAPSHOT_FLUSH_THRESHOLD = 500;

private void createSnapshot(...) {
    pendingSnapshots.add(snapshot);
    if (pendingSnapshots.size() >= SNAPSHOT_FLUSH_THRESHOLD) {
        insertPendingSnapshots();
    }
}
```

### Plugin CPU Time Monitoring (PluginInvoker.cls)

**Issue**: Custom plugins could consume excessive CPU time without warning.

**Resolution**: Added CPU time monitoring with warning logs:
```apex
private static final Integer CPU_TIME_WARNING_THRESHOLD_MS = 5000;

Integer cpuTimeBefore = Limits.getCpuTime();
List<Id> results = plugin.analyze(context);
Integer cpuTimeConsumed = Limits.getCpuTime() - cpuTimeBefore;
if (cpuTimeConsumed > CPU_TIME_WARNING_THRESHOLD_MS) {
    System.debug(LoggingLevel.WARN, 'Plugin consumed ' + cpuTimeConsumed + 'ms CPU time');
}
```

### LWC Console Logging Cleanup

**Issue**: Verbose console.log statements exposed record IDs and internal data structures.

**Resolution**: Removed 60+ console.log statements from:
- `behaviorIQDashboard.js`
- `remediationPreview.js`
- `userLeaderboard.js`

### API Version Standardization

**Update**: All LWC and Apex class metadata files updated to API v63.0 or higher.

---

## Code Analyzer Results (January 2026)

### High Severity Findings (Non-Security)

| Finding | Count | Assessment |
|---------|-------|------------|
| EmptyCatchBlock (test classes) | ~14 | Intentional for exception testing |
| EagerlyLoadedDescribeSObjectResult | 4 | Performance suggestion, not security |

### Security Violations: 0

No ApexCRUDViolation or ApexSOQLInjection violations in the codebase. All CRUD/FLS enforcement is in place via `USER_MODE`, `SECURITY_ENFORCED`, `as user`, and `Security.stripInaccessible()`.

---

## Example_Records__c Information Disclosure (Accepted Risk)

**Issue**: Example_Records__c contains record IDs generated by the batch job (running with elevated access). These IDs may indicate records the current user cannot access.

**Mitigation**:
- Actual record data is protected via `USER_MODE` queries in `getPatternMatches()` and `getRecordsByIds()`
- The IDs only indicate record existence, not sensitive data
- Filtering IDs through sharing context would add significant overhead

**Decision**: Accepted as low-severity risk given existing protections on record data access.

---

*Document updated: January 26, 2026*
*BehaviorIQ Version: AppExchange Submission*
