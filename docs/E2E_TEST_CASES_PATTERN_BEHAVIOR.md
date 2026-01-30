# BehaviorIQ Pattern Behavior Feature - End-to-End Test Cases

## Overview

This document provides comprehensive end-to-end test cases for the BehaviorIQ Pattern Behavior detection and remediation feature. Test cases are organized by:
- **License Tier** (FREE vs PREMIUM)
- **Permission Set Security** (Admin vs User vs Unprivileged)
- **Bulk Stress Testing**
- **Security Bypass Attempts**

---

## Prerequisites - New Customer Setup Flow

Before running these tests, follow the complete new customer experience:

### Step 1: Deploy Metadata to Scratch Org
```bash
sf project deploy start --target-org <your-scratch-org>
```

### Step 2: Create Test Users (3 Required)

**Admin User** - Full BehaviorIQ access:
```bash
sf org assign permset -n BehaviorIQ_Admin -o <your-scratch-org> -u <admin-user>
```

**Standard User** - Tracking marker only (no operational permissions):
```bash
sf org assign permset -n BehaviorIQ_User -o <your-scratch-org> -u <standard-user>
```

**Unprivileged User** - No BehaviorIQ permission sets assigned

### Step 3: Complete Setup Wizard (as Admin)
1. Open BehaviorIQ app in Lightning
2. Navigate to BehaviorIQ tab
3. Complete the Setup Wizard:
   - Configure monitored objects
   - Set thresholds
   - Review pattern rules
4. Verify Setup Wizard completion

### Step 4: Run Test Data Script
```bash
sf apex run --file scripts/apex/e2e_security_test_data.apex --target-org <your-scratch-org>
```

### Step 5: Run Pattern Analysis
```apex
Database.executeBatch(new PatternAnalysisBatch(), 200);
```

---

## License Configuration

### Set License to FREE (Default)
```apex
BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
license.Status__c = 'Free';
upsert license;
System.debug('License set to: ' + license.Status__c);
```

### Set License to PREMIUM
```apex
BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
license.Status__c = 'Premium';
upsert license;
System.debug('License set to: ' + license.Status__c);
```

---

## Pattern Reference - Actual Deployed Patterns (24 Total)

### FREE Tier Patterns (4 Patterns)

| Pattern | Object | Immediately Testable | Fix Type | Cost |
|---------|--------|---------------------|----------|------|
| Contact_Data_Gap | Contact | **Yes** | Task_Creation | $50 |
| Stale_Case_14 | Case | No (14-day aging) | Task_Creation | $500 |
| Stale_Case_30 | Case | No (30-day aging) | Task_Creation | $500 |
| Weekend_Case_Spike | Case | Only on weekends | No_Action | $50 |

### PREMIUM Tier Patterns (20 Patterns)

| Pattern | Object | Immediately Testable | Fix Type | Cost |
|---------|--------|---------------------|----------|------|
| High_Value_Ghosting | Opportunity | **Yes** | Task_Creation | $2,500 |
| Stale_Opp_90 | Opportunity | No (90-day aging) | Task_Creation | $1,000 |
| Unassigned_Lead_48 | Lead | No (48-hour aging) | Owner_Assignment | $200 |
| Lead_Hoarding | Lead | No (5-day aging) | Owner_Assignment | $150 |
| Duplicate_Leads | Lead | **Yes** | Task_Creation | $100 |
| Duplicate_Contacts | Contact | **Yes** | Task_Creation | $100 |
| Duplicate_Accounts | Account | **Yes** | Task_Creation | $100 |
| Orphan_Contact | Contact | **Yes** | Task_Creation | $25 |
| Orphan_Opportunity | Opportunity | **Yes** | Task_Creation | $25 |
| Orphan_Case | Case | **Yes** | Task_Creation | $25 |
| Frequent_Flyer_Churn | Case | Conditional | Task_Creation | $500 |
| Premature_Escalation | Case | Conditional | Escalation_Revert | $200 |
| Contract_Expiry_Red_Zone | Contract | Conditional | Opportunity_Creation | $1,000 |
| Inactive_Owner_Account | Account | Conditional | Task_Creation | $100 |
| Inactive_Owner_Contact | Contact | Conditional | Task_Creation | $100 |
| Inactive_Owner_Lead | Lead | Conditional | Task_Creation | $100 |
| Inactive_Owner_Opportunity | Opportunity | Conditional | Task_Creation | $100 |
| Inactive_Owner_Case | Case | Conditional | Task_Creation | $100 |
| Missing_Attachment_Closed_Won | Opportunity | Conditional | Task_Creation | $250 |
| Missing_Attachment_Closed_Case | Case | Conditional | Task_Creation | $150 |

---

# PART 1: FREE TIER TESTING

These tests can be run with `Status__c = 'Free'`. Only 4 patterns are available on the free tier.

## Free Tier Test Suite

### FT-1.1: Contact Data Gap Detection - Verified

**Objective:** Verify contacts missing email or phone are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 10 contacts with null Email
- 5 contacts with null Phone
- 15 total contacts matching pattern

**Steps:**
1. Set license to FREE
2. Run: `Database.executeBatch(new PatternAnalysisBatch(), 200);`
3. Query for Contact_Data_Gap pain point

**Expected Results:**
- [ ] Identified_Pain_Point__c record created with Unique_Key__c = 'Contact_Data_Gap'
- [ ] Occurrences__c = 15 (or matches count of contacts missing data)
- [ ] Object_API_Name__c = 'Contact'
- [ ] Cost_Per_Incident__c = $50

**Verification Query:**
```sql
SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c = 'Contact_Data_Gap'
```

---

### FT-1.2: Stale Case Detection (14 Days) - Verified

**Objective:** Verify cases untouched for 14+ days are detected.

**Immediately Testable:** No (requires 14-day aging)

**Pattern Query:**
```
Status != 'Closed' AND LastModifiedDate < LAST_N_DAYS:14
```

> **Note:** This pattern uses the real `LastModifiedDate` system field. Records must actually be 14+ days old without modification.

**Workaround for Testing:**
- Wait 14 days after creating test data, OR
- Use Data Loader with "Set Audit Fields" permission to backdate `LastModifiedDate`

**Expected Results (when data aged):**
- [ ] Stale_Case_14 pain point created
- [ ] Object_API_Name__c = 'Case'

---

### FT-1.3: Stale Case Detection (30 Days) - Verified

**Objective:** Verify cases untouched for 30+ days are detected.

**Immediately Testable:** No (requires 30-day aging)

**Same notes as FT-1.2 - requires real data aging.**

---

### FT-1.4: Weekend Case Spike Detection - Verified

**Objective:** Verify cases created on weekends are flagged.

**Immediately Testable:** Only on weekends

**Pattern Query:**
```
CreatedDate = LAST_WEEK AND DAY_IN_WEEK(CreatedDate) IN (1, 7)
```

**Steps:**
1. Create cases on a Saturday or Sunday
2. Run pattern analysis
3. Check for Weekend_Case_Spike pain point

**Expected Results:**
- [ ] Weekend_Case_Spike pain point created (if weekend cases exist)
- [ ] Fix_Type = No_Action (detection only)

---

### FT-1.5: Premium Pattern Gating - Verified

**Objective:** Verify premium patterns are NOT detected on free tier.

**Immediately Testable:** Yes

**Steps:**
1. Ensure license is set to FREE
2. Run pattern analysis batch
3. Query for premium patterns

**Expected Results:**
- [ ] NO pain points created for premium patterns
- [ ] Only free patterns detected (Contact_Data_Gap, Stale_Case_14, Stale_Case_30, Weekend_Case_Spike)
- [ ] No errors thrown

**Verification Query:**
```sql
SELECT Unique_Key__c, Occurrences__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c IN ('High_Value_Ghosting', 'Stale_Opp_90', 'Orphan_Contact', 'Duplicate_Leads')
```
Should return 0 records.

---

### FT-2.1: Auto-Fix Premium Gating - Verified

**Objective:** Verify Auto-Fix is blocked on Free tier (Premium feature only).

**Steps:**
1. Set license to FREE
2. Navigate to BehaviorIQ Dashboard
3. Click on Contact_Data_Gap pain point
4. Click "View Affected Records"
5. Select contacts and click "Fix" button

**Expected Results:**
- [ ] Error message displayed: "This is a Premium feature. Please upgrade BehaviorIQ to enable Auto-Fix."
- [ ] No tasks created
- [ ] No changes made to records

> **Note:** Auto-Fix is a Premium-only feature for ALL patterns. Free tier users can VIEW affected records but cannot execute fixes.

---

### FT-3.1: Dashboard on Free Tier - Verified

**Objective:** Verify dashboard displays correctly on free tier.

**Steps:**
1. Navigate to BehaviorIQ Dashboard
2. Review health score and pain points

**Expected Results:**
- [ ] Health score displays (0-100)
- [ ] Only free-tier pain points shown in list
- [ ] Premium patterns show upgrade CTA or are hidden
- [ ] "Upgrade to Premium" messaging visible

---

# PART 2: PREMIUM TIER TESTING

Set license to PREMIUM before running these tests.

## Premium Tier Test Suite

### PT-1.1: High Value Ghosting Detection

**Objective:** Verify opportunities >$50K with no activity are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 10 opportunities >$50K with no Tasks/Events (LastActivityDate = null)
  - Enterprise Deal Alpha: $75,000
  - Enterprise Deal Beta: $125,000
  - Global Expansion: $250,000
  - Healthcare Project: $175,000
  - Mega Deal: $500,000
  - (5 more at varying amounts)

**Pattern Query:**
```
Amount > 50000 AND (LastActivityDate < LAST_N_DAYS:14 OR LastActivityDate = null) AND IsClosed = false
```

**Steps:**
1. Set license to PREMIUM
2. Run: `Database.executeBatch(new PatternAnalysisBatch(), 200);`
3. Query for High_Value_Ghosting pain point

**Expected Results:**
- [ ] Identified_Pain_Point__c created with Unique_Key__c = 'High_Value_Ghosting'
- [ ] Occurrences__c = 10
- [ ] Impact_Score__c = sum of Opportunity.Amount values

**Verification Query:**
```sql
SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c = 'High_Value_Ghosting'
```

---

### PT-1.2: Duplicate Leads Detection

**Objective:** Verify leads with duplicate email addresses are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 6 pairs of leads with same email (12 total duplicates)
  - duplicate1@test.com (2 leads)
  - duplicate2@test.com (2 leads)
  - duplicate3@test.com (2 leads)
  - duplicate4@test.com (2 leads)
  - duplicate5@test.com (2 leads)
  - duplicate6@test.com (2 leads)

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Duplicate_Leads pain point

**Expected Results:**
- [ ] Duplicate_Leads pain point created
- [ ] Occurrences__c = 12 (all duplicates counted)
- [ ] Example_Records__c contains lead IDs with duplicates
- [ ] Object_API_Name__c = 'Lead'

---

### PT-1.3: Duplicate Contacts Detection

**Objective:** Verify contacts with duplicate email addresses are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 5 pairs of contacts with same email (10 total duplicates)

**Expected Results:**
- [ ] Duplicate_Contacts pain point created
- [ ] Occurrences__c = 10
- [ ] Object_API_Name__c = 'Contact'

---

### PT-1.4: Duplicate Accounts Detection

**Objective:** Verify accounts with duplicate names are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 4 pairs of accounts with same name (8 total duplicates)
  - "Duplicate Company Alpha" (2 accounts)
  - "Duplicate Company Beta" (2 accounts)
  - "Duplicate Company Gamma" (2 accounts)
  - "Duplicate Company Delta" (2 accounts)

**Expected Results:**
- [ ] Duplicate_Accounts pain point created
- [ ] Occurrences__c = 8
- [ ] Object_API_Name__c = 'Account'

---

### PT-1.5: Orphan Contact Detection

**Objective:** Verify contacts without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 10 orphan contacts (AccountId = null)

**Expected Results:**
- [ ] Orphan_Contact pain point created
- [ ] Occurrences__c = 10
- [ ] Object_API_Name__c = 'Contact'

---

### PT-1.6: Orphan Opportunity Detection

**Objective:** Verify opportunities without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 6 orphan opportunities (AccountId = null)

**Expected Results:**
- [ ] Orphan_Opportunity pain point created
- [ ] Occurrences__c = 6

---

### PT-1.7: Orphan Case Detection

**Objective:** Verify cases without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 8 orphan cases (AccountId = null, ContactId = null)

**Expected Results:**
- [ ] Orphan_Case pain point created
- [ ] Occurrences__c = 8

---

### PT-1.8: Frequent Flyer Churn Detection

**Objective:** Verify Hot accounts with excessive cases are detected.

**Immediately Testable:** Conditional (requires Hot accounts with many cases)

**Mock Data Created:**
- 5 Hot-rated accounts with 10+ cases each

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Frequent_Flyer_Churn pain point

**Expected Results:**
- [ ] Frequent_Flyer_Churn pain point created (if qualifying accounts exist)
- [ ] Object_API_Name__c = 'Case'

---

### PT-1.9: Premature Escalation Detection

**Objective:** Verify escalated cases without High priority are detected.

**Immediately Testable:** Conditional

**Mock Data Created:**
- 5 cases with IsEscalated = true but Priority != 'High'

**Expected Results:**
- [ ] Premature_Escalation pain point created
- [ ] Fix_Type = Escalation_Revert

---

### PT-1.10: Contract Expiry Red Zone Detection

**Objective:** Verify contracts expiring within 30 days are detected.

**Immediately Testable:** Conditional

**Mock Data Created:**
- 8 contracts with end date within 30 days

**Expected Results:**
- [ ] Contract_Expiry_Red_Zone pain point created
- [ ] Fix_Type = Opportunity_Creation

---

### PT-1.11: Stale Opportunity 90-Day Detection

**Objective:** Verify opportunities with no stage change in 90+ days are detected.

**Immediately Testable:** No (requires 90-day aging)

**Pattern Query:**
```
IsClosed = false AND LastStageChangeDate < LAST_N_DAYS:90
```

> **Note:** This pattern uses the real `LastStageChangeDate` system field.

---

### PT-2.1: Task Creation Fix (Premium)

**Objective:** Verify Task_Creation fix works on premium patterns.

**Pattern:** High_Value_Ghosting

**Steps:**
1. View High_Value_Ghosting pain point
2. Select affected opportunities
3. Execute fix

**Expected Results:**
- [ ] Tasks created for each selected opportunity
- [ ] Task Subject: "URGENT: High-Value Opportunity Needs Attention"
- [ ] Task assigned to opportunity owner
- [ ] Remediation_Log__c records created with Status__c = 'Success'

---

### PT-2.2: Owner Assignment Fix

**Objective:** Verify Owner_Assignment fix reassigns records.

**Pattern:** Unassigned_Lead_48 (requires 48-hour aging)

**Expected Results (when testable):**
- [ ] Leads reassigned to queue or user
- [ ] Remediation_Log__c with Original_Value__c (old owner) and New_Value__c (new owner)

---

### PT-2.3: Escalation Revert Fix

**Objective:** Verify Escalation_Revert fix removes improper escalations.

**Pattern:** Premature_Escalation

**Expected Results:**
- [ ] IsEscalated set to false
- [ ] Remediation_Log__c records created

---

### PT-3.1: Pattern Rule Manager (Premium Features)

**Objective:** Verify Pattern Rule Manager shows premium features.

**Steps:**
1. Set license to PREMIUM
2. Navigate to Pattern Rule Manager

**Expected Results:**
- [ ] Premium patterns can be viewed and edited
- [ ] Create/Edit/Clone buttons functional
- [ ] No upgrade CTAs for premium features

---

# PART 3: PERMISSION SET SECURITY TESTING

This section tests the security boundaries between BehaviorIQ_Admin, BehaviorIQ_User, and unprivileged users.

## Permission Set Reference

| Category | BehaviorIQ_Admin | BehaviorIQ_User | No Permission Set |
|----------|-----------------|-----------------|-------------------|
| Purpose | Full admin control | Tracking marker only | No access |
| Object CRUD | 9 objects (full) | 0 objects | 0 objects |
| Field Permissions | 50+ fields | 0 fields | 0 fields |
| Apex Classes | 9 classes | 0 classes | 0 classes |
| Tabs | 9 tabs | 0 tabs | 0 tabs |

## PS-1: Admin Permission Set Tests

### PS-1.1: Admin Can View Pain Points

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Log in as Admin user
2. Navigate to Identified Pain Points tab
3. Query pain points via SOQL

**Expected Results:**
- [ ] Full access to Identified_Pain_Point__c records
- [ ] All fields visible
- [ ] Create/Edit/Delete buttons available

**Verification Query (run as Admin):**
```sql
SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c, Status__c
FROM Identified_Pain_Point__c
```

---

### PS-1.2: Admin Can Execute Auto-Fix

**User:** Admin (BehaviorIQ_Admin assigned, PREMIUM license)

**Steps:**
1. Navigate to a pain point (e.g., High_Value_Ghosting)
2. Select affected records
3. Click Fix button

**Expected Results:**
- [ ] Fix executes successfully
- [ ] Tasks created
- [ ] Remediation_Log__c records created

---

### PS-1.3: Admin Can Access Pattern Rule Manager

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to Pattern Rule Manager component
2. View existing rules
3. Attempt to create/edit a rule

**Expected Results:**
- [ ] All pattern rules visible
- [ ] Can view rule details
- [ ] Can create new rules (with proper permissions)
- [ ] Can edit existing rules
- [ ] Can clone rules

---

### PS-1.4: Admin Can View Remediation Logs

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to Remediation Logs tab
2. Query remediation logs

**Expected Results:**
- [ ] Full access to Remediation_Log__c records
- [ ] Can see all fields including Original_Value__c, New_Value__c, Snapshot_JSON__c
- [ ] Can filter and sort

**Verification Query:**
```sql
SELECT Id, Affected_Record_ID__c, Rule_Developer_Name__c, Action_Taken__c,
       Original_Value__c, New_Value__c, Status__c, Error_Message__c
FROM Remediation_Log__c
ORDER BY CreatedDate DESC
LIMIT 50
```

---

### PS-1.5: Admin Can Modify BehaviorIQ Configuration

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to BehaviorIQ Configuration tab
2. Modify Stale_Case_Threshold__c
3. Save changes

**Expected Results:**
- [ ] Can read configuration records
- [ ] Can edit thresholds
- [ ] Changes saved successfully

---

### PS-1.6: Admin Can View Behavior Logs

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to Behavior Logs tab
2. Query behavior logs

**Expected Results:**
- [ ] Full access to Behavior_Log__c records
- [ ] All fields visible including Behavior_Data__c JSON

---

### PS-1.7: Admin Can Dismiss Suggestions

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to a pain point
2. Click "Dismiss" button

**Expected Results:**
- [ ] Suggestion_Dismissal__c record created
- [ ] Pain point status updated

---

### PS-1.8: Admin Can View System Health Logs

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to System Health Logs tab
2. View batch job status

**Expected Results:**
- [ ] Full access to System_Health_Log__c records
- [ ] Can see job status and error details

---

### PS-1.9: Admin Can View Behavior Snapshots

**User:** Admin (BehaviorIQ_Admin assigned)

**Steps:**
1. Navigate to Behavior Snapshots tab
2. Query snapshots

**Expected Results:**
- [ ] Full access to Behavior_Snapshot__c records
- [ ] Historical data accessible

---

## PS-2: User Permission Set Tests (BehaviorIQ_User - No Access Expected)

> **Note:** BehaviorIQ_User is intentionally empty. It serves only as a tracking marker to identify which users should be monitored by BehaviorIQ.

### PS-2.1: User Cannot View Pain Points

**User:** Standard user (BehaviorIQ_User only)

**Steps:**
1. Log in as Standard user
2. Attempt to navigate to Identified Pain Points tab
3. Attempt SOQL query

**Expected Results:**
- [ ] Tab not visible (no tab visibility)
- [ ] SOQL query returns empty or throws error
- [ ] No object-level access

**Verification Query (run as User):**
```sql
SELECT Id FROM Identified_Pain_Point__c LIMIT 1
```
Should return error: "sObject type 'Identified_Pain_Point__c' is not supported"

---

### PS-2.2: User Cannot Execute Auto-Fix

**User:** Standard user (BehaviorIQ_User only)

**Steps:**
1. Attempt to call PatternFixService directly
2. Attempt to call PainPointController.dismissPainPoint()

**Expected Results:**
- [ ] No Apex class access
- [ ] AuraHandledException if attempted via LWC

---

### PS-2.3: User Cannot Access Pattern Rule Manager

**User:** Standard user (BehaviorIQ_User only)

**Steps:**
1. Attempt to navigate to Pattern Rule Manager

**Expected Results:**
- [ ] Component not accessible
- [ ] No PatternRuleManagerController access

---

### PS-2.4: User Cannot View Remediation Logs

**User:** Standard user (BehaviorIQ_User only)

**Steps:**
1. Attempt to query Remediation_Log__c

**Expected Results:**
- [ ] No object access
- [ ] Query returns empty or error

---

### PS-2.5: User Cannot Modify Configuration

**User:** Standard user (BehaviorIQ_User only)

**Steps:**
1. Attempt to modify BehaviorIQ_Configuration__c

**Expected Results:**
- [ ] No create/edit access
- [ ] DML operation blocked

---

## PS-3: No Permission Set Tests

### PS-3.1: Unprivileged User Dashboard Access

**User:** Unprivileged (no BehaviorIQ permission sets)

**Steps:**
1. Log in as unprivileged user
2. Attempt to access BehaviorIQ app

**Expected Results:**
- [ ] BehaviorIQ app not visible
- [ ] No tabs accessible
- [ ] No object access

---

### PS-3.2: Unprivileged User API Access

**User:** Unprivileged (no BehaviorIQ permission sets)

**Steps:**
1. Attempt to call BehaviorIQ controllers via Apex anonymous

**Expected Results:**
- [ ] AuraHandledException or insufficient access error
- [ ] No data returned
- [ ] Security enforced

---

## PS-4: Apex Class Access Tests

| Apex Class | Test Admin | Test User | Test Unprivileged |
|------------|-----------|-----------|-------------------|
| BehaviorLogService | [ ] Access | [ ] Blocked | [ ] Blocked |
| GenericBehaviorTriggerHandler | [ ] Access | [ ] Blocked | [ ] Blocked |
| PainPointController | [ ] Access | [ ] Blocked | [ ] Blocked |
| PatternAnalysisService | [ ] Access | [ ] Blocked | [ ] Blocked |
| PatternFixService | [ ] Access | [ ] Blocked | [ ] Blocked |
| UserLeaderboardController | [ ] Access | [ ] Blocked | [ ] Blocked |
| LicenseService | [ ] Access | [ ] Blocked | [ ] Blocked |
| SetupWizardController | [ ] Access | [ ] Blocked | [ ] Blocked |
| BehaviorSettingsController | [ ] Access | [ ] Blocked | [ ] Blocked |

---

# PART 4: BULK STRESS TESTING

This section tests BehaviorIQ performance under high data volumes.

## Bulk Test Prerequisites

Use `scripts/apex/e2e_bulk_stress_data.apex` to create high-volume test data.

**Recommended:** Run bulk tests in a dedicated scratch org to avoid governor limit issues in your primary test org.

---

### BK-1.1: Pattern Analysis 10K Records

**Objective:** Verify batch job completes with 10,000 records.

**Setup:**
- Create 10,000 contacts with missing data

**Steps:**
1. Run bulk data setup script
2. Execute pattern analysis batch
3. Monitor job completion

**Expected Results:**
- [ ] Batch job completes without errors
- [ ] Pain point correctly reflects 10,000 occurrences
- [ ] No governor limit errors

**Verification:**
```apex
AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
System.assertEquals('Completed', job.Status);
System.assertEquals(0, job.NumberOfErrors);
```

---

### BK-1.2: Pattern Analysis 50K Records

**Objective:** Verify batch job handles 50,000 records.

**Setup:**
- Create 50,000 contacts across multiple patterns

**Expected Results:**
- [ ] Batch processes in multiple chunks
- [ ] All patterns correctly detected
- [ ] Job completes within reasonable time

---

### BK-1.3: Auto-Fix 200 Records

**Objective:** Verify Auto-Fix can process 200 records at once.

**Setup:**
- Pain point with 200 affected records

**Steps:**
1. Select all 200 records
2. Execute fix

**Expected Results:**
- [ ] All 200 tasks created
- [ ] 200 Remediation_Log__c records created
- [ ] No partial failures

---

### BK-1.4: Auto-Fix 500 Records

**Objective:** Verify Auto-Fix handles 500 records with batching.

**Expected Results:**
- [ ] Records processed in batches (DML limit = 200)
- [ ] All records processed successfully
- [ ] No governor limit errors

---

### BK-1.5: Duplicate Detection 5K Leads

**Objective:** Verify duplicate detection performance with 5,000 leads.

**Setup:**
- 5,000 leads with various duplicate email patterns

**Expected Results:**
- [ ] All duplicates correctly identified
- [ ] Duplicate plugin executes within CPU limits
- [ ] Occurrences count accurate

---

### BK-1.6: Duplicate Detection 5K Contacts

**Objective:** Verify duplicate detection for contacts at scale.

**Expected Results:**
- [ ] Same as BK-1.5 for contacts

---

### BK-2.1: Dashboard Load 100 Pain Points

**Objective:** Verify dashboard renders with 100 pain points.

**Setup:**
- Create data that triggers 100+ different pain points

**Steps:**
1. Navigate to BehaviorIQ dashboard
2. Measure load time

**Expected Results:**
- [ ] Dashboard loads within 3 seconds
- [ ] All pain points visible
- [ ] Health gauge calculates correctly
- [ ] No timeout errors

---

### BK-2.2: Remediation Log Query 10K Records

**Objective:** Verify remediation log pagination with 10K records.

**Steps:**
1. Navigate to Remediation Logs
2. Scroll through records

**Expected Results:**
- [ ] Pagination works correctly
- [ ] No performance degradation
- [ ] Records load incrementally

---

### BK-3.1: Platform Event Burst 1000 Events

**Objective:** Verify platform event handling under load.

**Setup:**
- Trigger 1000 behavior events rapidly

**Expected Results:**
- [ ] All events captured
- [ ] Behavior_Log__c records created
- [ ] No event loss

---

# PART 5: SECURITY BYPASS TESTING

This section attempts to bypass BehaviorIQ security controls.

> **Note:** All tests should FAIL to bypass security. Success = security is working.

---

### SEC-1.1: Direct Apex API Call Bypass

**Attack Vector:** Call controller method without permission set

**Method:**
```apex
// Run as unprivileged user
List<Identified_Pain_Point__c> points = PainPointController.getOpenPainPoints();
```

**Expected Defense:**
- [ ] AuraHandledException thrown
- [ ] Empty list returned
- [ ] CRUD check enforced

---

### SEC-1.2: SOQL Injection via Pattern Rule

**Attack Vector:** Malicious Query_Condition__c in pattern rule

**Method:** (Admin creates rule with injection attempt)
```
1=1 OR Name LIKE '%'
```

**Expected Defense:**
- [ ] Query validation rejects malformed condition
- [ ] String.escapeSingleQuotes() applied
- [ ] WITH USER_MODE enforced on dynamic queries

---

### SEC-1.3: License Bypass via Custom Setting

**Attack Vector:** Directly modify BehaviorIQ_License__c

**Method:**
```apex
// Run as standard user
BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
license.Status__c = 'Premium';
upsert license;
```

**Expected Defense:**
- [ ] Protected visibility prevents unauthorized modification
- [ ] DML blocked for non-admins
- [ ] License status unchanged

---

### SEC-1.4: FLS Bypass on Sensitive Fields

**Attack Vector:** Query fields user shouldn't access

**Method:**
```apex
// Run as user without field access
SELECT Snapshot_JSON__c FROM Remediation_Log__c
```

**Expected Defense:**
- [ ] stripInaccessible removes sensitive fields
- [ ] WITH SECURITY_ENFORCED blocks query
- [ ] Field not returned in results

---

### SEC-1.5: Sharing Bypass Attempt

**Attack Vector:** Query across sharing boundaries

**Method:**
```apex
// Run as user without ViewAllRecords
SELECT Id FROM Identified_Pain_Point__c
```

**Expected Defense:**
- [ ] WITH USER_MODE enforces sharing
- [ ] Only owned/shared records returned
- [ ] ViewAllRecords required for full access

---

### SEC-2.1: Plugin Injection Attempt

**Attack Vector:** Fake Apex_Handler_Class__c in pattern rule

**Method:** Create rule with non-existent or malicious class name
```
Apex_Handler_Class__c = 'MaliciousPlugin'
```

**Expected Defense:**
- [ ] Type.forName() returns null for non-existent class
- [ ] Interface validation rejects non-PatternPlugin classes
- [ ] PluginException thrown with clear message

---

### SEC-2.2: Cross-User Data Access

**Attack Vector:** View other users' remediation logs

**Method:**
```apex
// Run as User A, try to view User B's logs
SELECT Id, Executed_By__c FROM Remediation_Log__c WHERE Executed_By__c != :UserInfo.getUserId()
```

**Expected Defense:**
- [ ] Sharing rules enforce record visibility
- [ ] Only ViewAllRecords users can see all logs
- [ ] Standard sharing applied

---

### SEC-3.1: Metadata Deployment Bypass

**Attack Vector:** Deploy pattern rule without proper permissions

**Method:** Use Metadata API without "Modify All Data" or "Deploy Metadata"

**Expected Defense:**
- [ ] Metadata deployment requires specific permissions
- [ ] Deployment blocked for unprivileged users
- [ ] Audit trail records attempt

---

### SEC-3.2: Premium Feature Escalation

**Attack Vector:** Free tier user triggers Premium fix

**Method:**
```apex
// Run as Free tier user
PatternFixService.executeFixForRecords('High_Value_Ghosting', recordIds);
```

**Expected Defense:**
- [ ] LicenseService.isPremium() returns false
- [ ] AuraHandledException: "This is a Premium feature..."
- [ ] Fix not executed
- [ ] No remediation logs created

---

# PART 6: OBJECT CRUD VALIDATION

This section validates CRUD operations on all BehaviorIQ custom objects.

## Object CRUD Matrix

Test each operation for each user type.

### Identified_Pain_Point__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### Remediation_Log__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### BehaviorIQ_Configuration__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### Behavior_Log__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### Suggestion_Dismissal__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### System_Health_Log__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### BehaviorIQ_License__c (Custom Setting)

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] Limited | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### Behavior_Snapshot__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

### Workflow_Log__c

| Operation | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| Create | [ ] Yes | [ ] No | [ ] No |
| Read | [ ] Yes | [ ] No | [ ] No |
| Update | [ ] Yes | [ ] No | [ ] No |
| Delete | [ ] Yes | [ ] No | [ ] No |

---

# PART 7: SETUP WIZARD TESTING

This section tests the new customer onboarding experience.

### SW-1.1: Setup Wizard Initial Load

**Objective:** Verify Setup Wizard loads for new Admin user.

**Steps:**
1. Log in as Admin (first time)
2. Navigate to BehaviorIQ app

**Expected Results:**
- [ ] Setup Wizard automatically displayed
- [ ] Step 1 (Welcome) visible
- [ ] Progress indicator shows current step

---

### SW-1.2: Setup Wizard Object Selection

**Objective:** Verify object selection works correctly.

**Steps:**
1. In Setup Wizard, select monitored objects
2. Select: Account, Contact, Lead, Opportunity, Case

**Expected Results:**
- [ ] Checkboxes functional
- [ ] Selection saved to BehaviorIQ_Configuration__c
- [ ] Can proceed to next step

---

### SW-1.3: Setup Wizard Threshold Configuration

**Objective:** Verify threshold configuration.

**Steps:**
1. Set Stale Case Threshold to 21 days
2. Set Stale Opportunity Threshold to 45 days
3. Save configuration

**Expected Results:**
- [ ] Values validated (1-999 range)
- [ ] Configuration saved
- [ ] Confirmation displayed

---

### SW-1.4: Setup Wizard Completion

**Objective:** Verify Setup Wizard completion flow.

**Steps:**
1. Complete all wizard steps
2. Click "Finish" or "Complete Setup"

**Expected Results:**
- [ ] Wizard marked as complete
- [ ] Redirected to main dashboard
- [ ] Pattern analysis can now run

---

### SW-1.5: Setup Wizard Skip for Returning Users

**Objective:** Verify returning users don't see wizard.

**Steps:**
1. Complete Setup Wizard
2. Log out and log back in
3. Navigate to BehaviorIQ app

**Expected Results:**
- [ ] Setup Wizard NOT displayed
- [ ] Direct to dashboard
- [ ] Configuration preserved

---

# Mock Data Summary

The `e2e_security_test_data.apex` script creates the following data:

| Object | Total Records | Pattern-Specific Data |
|--------|--------------|----------------------|
| Account | 50 | 8 duplicates (4 pairs), 5 Hot (churn test) |
| Contact | 100 | 15 missing data, 10 orphans, 10 duplicates |
| Lead | 75 | 12 duplicates (6 pairs), various statuses |
| Opportunity | 60 | 10 high-value ghosted, 6 orphans |
| Case | 80 | 8 orphans, 5 premature escalation, 50+ for churn test |
| Contract | 20 | 8 expiring in 30 days |

---

# Test Execution Checklist

## Free Tier Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| FT-1.1 Contact_Data_Gap | [ ] | 15 contacts expected |
| FT-1.2 Stale_Case_14 | [ ] | Requires 14-day aging |
| FT-1.3 Stale_Case_30 | [ ] | Requires 30-day aging |
| FT-1.4 Weekend_Case_Spike | [ ] | Only on weekends |
| FT-1.5 Premium Gating | [ ] | Verify premium patterns blocked |
| FT-2.1 Auto-Fix Premium Gating | [ ] | Verify fix blocked on Free tier |
| FT-3.1 Dashboard (Free) | [ ] | Health gauge calculation |

## Premium Tier Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| PT-1.1 High_Value_Ghosting | [ ] | 10 opportunities expected |
| PT-1.2 Duplicate_Leads | [ ] | 12 leads expected |
| PT-1.3 Duplicate_Contacts | [ ] | 10 contacts expected |
| PT-1.4 Duplicate_Accounts | [ ] | 8 accounts expected |
| PT-1.5 Orphan_Contact | [ ] | 10 contacts expected |
| PT-1.6 Orphan_Opportunity | [ ] | 6 opportunities expected |
| PT-1.7 Orphan_Case | [ ] | 8 cases expected |
| PT-1.8 Frequent_Flyer_Churn | [ ] | 5 Hot accounts |
| PT-1.9 Premature_Escalation | [ ] | 5 cases expected |
| PT-1.10 Contract_Expiry_Red_Zone | [ ] | 8 contracts expected |
| PT-1.11 Stale_Opp_90 | [ ] | Requires 90-day aging |
| PT-2.1 Task Fix (Premium) | [ ] | |
| PT-2.2 Owner_Assignment | [ ] | Requires 48-hour aging |
| PT-2.3 Escalation_Revert | [ ] | |
| PT-3.1 Pattern Rule Manager | [ ] | |

## Permission Set Tests

| Test Case | Admin | User | Unprivileged |
|-----------|-------|------|--------------|
| PS-1.1 View Pain Points | [ ] | N/A | N/A |
| PS-1.2 Execute Auto-Fix | [ ] | N/A | N/A |
| PS-1.3 Pattern Rule Manager | [ ] | N/A | N/A |
| PS-1.4 Remediation Logs | [ ] | N/A | N/A |
| PS-1.5 Configuration | [ ] | N/A | N/A |
| PS-2.1 User Blocked | N/A | [ ] | N/A |
| PS-2.2 User Fix Blocked | N/A | [ ] | N/A |
| PS-3.1 Unprivileged Blocked | N/A | N/A | [ ] |
| PS-3.2 API Access Blocked | N/A | N/A | [ ] |

## Bulk Stress Tests

| Test Case | Status | Volume | Notes |
|-----------|--------|--------|-------|
| BK-1.1 10K Records | [ ] | 10,000 | |
| BK-1.2 50K Records | [ ] | 50,000 | |
| BK-1.3 200 Record Fix | [ ] | 200 | |
| BK-1.4 500 Record Fix | [ ] | 500 | |
| BK-1.5 5K Lead Duplicates | [ ] | 5,000 | |
| BK-1.6 5K Contact Duplicates | [ ] | 5,000 | |
| BK-2.1 Dashboard Load | [ ] | 100 PP | |
| BK-2.2 10K Logs | [ ] | 10,000 | |
| BK-3.1 1K Events | [ ] | 1,000 | |

## Security Bypass Tests

| Test Case | Attack Attempted | Defense Verified |
|-----------|-----------------|------------------|
| SEC-1.1 Apex Bypass | [ ] | [ ] |
| SEC-1.2 SOQL Injection | [ ] | [ ] |
| SEC-1.3 License Bypass | [ ] | [ ] |
| SEC-1.4 FLS Bypass | [ ] | [ ] |
| SEC-1.5 Sharing Bypass | [ ] | [ ] |
| SEC-2.1 Plugin Injection | [ ] | [ ] |
| SEC-2.2 Cross-User Access | [ ] | [ ] |
| SEC-3.1 Metadata Bypass | [ ] | [ ] |
| SEC-3.2 Premium Escalation | [ ] | [ ] |

## Setup Wizard Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| SW-1.1 Initial Load | [ ] | |
| SW-1.2 Object Selection | [ ] | |
| SW-1.3 Threshold Config | [ ] | |
| SW-1.4 Completion | [ ] | |
| SW-1.5 Skip Returning | [ ] | |

---

# Troubleshooting

## Pattern Not Detecting Expected Records

1. **Check license tier** - Premium patterns require Premium license
2. **Verify data aging** - Stale patterns need real LastModifiedDate/CreatedDate aging
3. **Check Is_Active__c** - Pattern rule must be active
4. **Verify Query_Condition__c** - Ensure SOQL syntax is valid
5. **Check FLS** - User must have access to queried fields

## Permission Set Issues

1. **Verify assignment** - Run `sf org display user` to check permission sets
2. **Clear cache** - Log out/in after permission set changes
3. **Check profile** - Some permissions may conflict with profile settings

## Bulk Test Failures

1. **Governor limits** - Check debug logs for limit warnings
2. **Batch size** - Reduce batch size if hitting limits
3. **CPU time** - Complex plugins may need optimization

## Security Test Considerations

1. **Admin vs System Admin** - Some tests require System Admin profile
2. **Custom setting visibility** - Protected settings have special rules
3. **Metadata API** - Requires specific permissions beyond object CRUD

---

# SOQL Verification Queries

## Check All Pain Points
```sql
SELECT Id, Name, Unique_Key__c, Object_API_Name__c, Occurrences__c,
       Impact_Score__c, Status__c, Last_Detected__c
FROM Identified_Pain_Point__c
ORDER BY Last_Detected__c DESC
```

## Check Remediation Logs
```sql
SELECT Id, Affected_Record_ID__c, Rule_Developer_Name__c, Action_Taken__c,
       Original_Value__c, New_Value__c, Status__c, CreatedDate
FROM Remediation_Log__c
ORDER BY CreatedDate DESC
LIMIT 50
```

## Check License Status
```sql
SELECT Id, Status__c FROM BehaviorIQ_License__c
```

## Verify Mock Data Counts
```sql
-- Contacts missing data (Contact_Data_Gap)
SELECT COUNT() FROM Contact WHERE Email = null OR Phone = null

-- Orphan contacts
SELECT COUNT() FROM Contact WHERE AccountId = null

-- High-value opportunities without activity (High_Value_Ghosting)
SELECT COUNT() FROM Opportunity WHERE Amount > 50000 AND IsClosed = false AND LastActivityDate = null

-- Duplicate leads
SELECT Email, COUNT(Id) FROM Lead WHERE Email != null GROUP BY Email HAVING COUNT(Id) > 1

-- Duplicate contacts
SELECT Email, COUNT(Id) FROM Contact WHERE Email != null GROUP BY Email HAVING COUNT(Id) > 1

-- Duplicate accounts
SELECT Name, COUNT(Id) FROM Account WHERE Name != null GROUP BY Name HAVING COUNT(Id) > 1

-- Orphan opportunities
SELECT COUNT() FROM Opportunity WHERE AccountId = null

-- Orphan cases
SELECT COUNT() FROM Case WHERE AccountId = null AND ContactId = null

-- Expiring contracts
SELECT COUNT() FROM Contract WHERE EndDate <= :Date.today().addDays(30) AND EndDate > :Date.today()

-- Hot accounts with many cases (Frequent Flyer)
SELECT Account.Name, COUNT(Id) caseCount FROM Case WHERE Account.Rating = 'Hot' GROUP BY Account.Name HAVING COUNT(Id) >= 10

-- Premature escalations
SELECT COUNT() FROM Case WHERE IsEscalated = true AND Priority != 'High'
```

---

Last Updated: January 2026
