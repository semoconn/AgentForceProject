# BehaviorIQ Pattern Behavior Feature - End-to-End Test Cases

## Overview

This document provides comprehensive end-to-end test cases for the BehaviorIQ Pattern Behavior detection and remediation feature. Test cases are organized by **license tier** (FREE vs PREMIUM) to facilitate targeted testing.

---

## Prerequisites

Before running these tests:

1. Deploy all metadata to scratch org:
   ```bash
   sf project deploy start --target-org <your-scratch-org>
   ```

2. Assign permission sets:
   ```bash
   sf org assign permset -n BehaviorIQ_Admin -n BehaviorIQ_User
   ```

3. Run the mock data setup script:
   ```bash
   sf apex run --file scripts/apex/release_candidate_mock_data.apex --target-org <your-scratch-org>
   ```

4. Run the pattern analysis batch job:
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

# PART 1: FREE TIER TESTING

These tests can be run with `Status__c = 'Free'`. Only 6 patterns are available on the free tier.

## Free Tier Pattern Reference

| Pattern | Object | Immediately Testable | Mock Data | Notes |
|---------|--------|---------------------|-----------|-------|
| Contact_Data_Gap | Contact | **Yes** | 7 contacts | Missing Email/Phone |
| Stale_Case_14 | Case | No | N/A | Requires 14+ days aging |
| Stale_Case_30 | Case | No | N/A | Requires 30+ days aging |
| Test_Status_New | Case | **Yes** | 3 cases | **TEST ONLY** - Status = 'New' with COVERAGE_TEST prefix |
| Weekend_Case_Spike | Case | Conditional | N/A | Only on weekends |
| Sample_Plugin_Pattern | Account | **Yes** | 3 accounts | **TEST ONLY** - Demo plugin pattern (Rating = Cold) |

> **Note:** `Test_Status_New` and `Sample_Plugin_Pattern` are **TEST ONLY** patterns for E2E/coverage testing. Do not include in production deployments.

---

## Free Tier Test Suite 

### FT-1.1: Contact Data Gap Detection - Verified

**Objective:** Verify contacts missing email or phone are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 3 orphan contacts (no AccountId, no Phone)
- 2 contacts with Account but missing Phone
- 2 contacts with Account but missing Email

**Steps:**
1. Set license to FREE
2. Run: `Database.executeBatch(new PatternAnalysisBatch(), 200);`
3. Query for Contact_Data_Gap pain point

**Expected Results:**
- [ ] Identified_Pain_Point__c record created with Unique_Key__c = 'Contact_Data_Gap'
- [ ] Occurrences__c = 7 (or matches count of contacts missing data)
- [ ] Object_API_Name__c = 'Contact'
- [ ] Cost_Per_Incident__c = $50

**Verification Query:**
```sql
SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c = 'Contact_Data_Gap'
```

---

### FT-1.2: Test Status New Detection (TEST ONLY) - Verified

**Objective:** Verify cases with Status = 'New' and COVERAGE_TEST subject prefix are detected.

**Immediately Testable:** Yes

> **WARNING:** This is a TEST ONLY pattern. Do not deploy to production.

**Mock Data Created:**
- 3 cases with Subject starting with 'COVERAGE_TEST'

**Steps:**
1. Set license to FREE
2. Run pattern analysis batch
3. Check for Test_Status_New pain point

**Expected Results:**
- [ ] Pain point created for Test_Status_New
- [ ] Occurrences__c = 3
- [ ] Object_API_Name__c = 'Case'

---

### FT-1.3: Sample Plugin Pattern Detection (TEST ONLY) -Verified

**Objective:** Verify accounts with Rating = 'Cold' are detected by the Apex plugin.

**Immediately Testable:** Yes

> **WARNING:** This is a TEST ONLY pattern. Do not deploy to production.

**Mock Data Created:**
- 3 accounts with Rating = 'Cold'

**Steps:**
1. Set license to FREE
2. Run pattern analysis batch
3. Check for Sample_Plugin_Pattern pain point

**Expected Results:**
- [ ] Pain point created for Sample_Plugin_Pattern
- [ ] Occurrences__c = 3
- [ ] Object_API_Name__c = 'Account'

---

### FT-1.4: Stale Case Detection (14 Days) - Need to age data

**Objective:** Verify cases untouched for 14+ days are detected.

**Immediately Testable:** No (requires 14-day aging)

**Pattern Query:**
```
Status != 'Closed' AND LastModifiedDate < LAST_N_DAYS:14
```

> **Note:** This pattern uses the real `LastModifiedDate` system field. Records must actually be 14+ days old without modification. Freshly created mock data will NOT trigger this pattern.

**Workaround for Testing:**
- Wait 14 days after creating test data, OR
- Use Data Loader with "Set Audit Fields" permission to backdate `LastModifiedDate`

**Expected Results (when data aged):**
- [ ] Stale_Case_14 pain point created
- [ ] Object_API_Name__c = 'Case'

---

### FT-1.5: Stale Case Detection (30 Days) - Need to age data

**Objective:** Verify cases untouched for 30+ days are detected.

**Immediately Testable:** No (requires 30-day aging)

**Same notes as FT-1.4 - requires real data aging.**

---

### FT-1.6: Weekend Case Spike Detection -  Need to age data

**Objective:** Verify cases created on weekends are flagged.

**Immediately Testable:** Only on weekends

**Pattern:** Weekend_Case_Spike (Apex Plugin)

**Steps:**
1. Create cases on a Saturday or Sunday
2. Run pattern analysis
3. Check for Weekend_Case_Spike pain point

---

### FT-1.7: Premium Pattern Gating - Verified

**Objective:** Verify premium patterns are NOT detected on free tier.

**Immediately Testable:** Yes

**Steps:**
1. Ensure license is set to FREE
2. Run pattern analysis batch
3. Query for premium patterns

**Expected Results:**
- [ ] NO pain points created for premium patterns (High_Value_Ghosting, Stale_Opp_90, Orphan_*, Duplicate_*, etc.)
- [ ] Only free patterns detected (Contact_Data_Gap, Stale_Case_*, Test_Status_New, Weekend_Case_Spike, Sample_Plugin_Pattern)
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
- [x] Error message displayed: "This is a Premium feature. Please upgrade BehaviorIQ to enable Auto-Fix."
- [x] No tasks created
- [x] No changes made to records

> **Note:** Auto-Fix is a Premium-only feature for ALL patterns. Free tier users can VIEW affected records but cannot execute fixes. This encourages upgrades to Premium.

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

> **Note:** The Health Gauge score reflects ALL detected issues (including premium patterns the user can't see). This is intentional - it shows free users there's additional risk they could address by upgrading.

---

# PART 2: PREMIUM TIER TESTING

Set license to PREMIUM before running these tests.

## Premium Tier Pattern Reference

| Pattern | Object | Immediately Testable | Mock Data | Notes |
|---------|--------|---------------------|-----------|-------|
| High_Value_Ghosting | Opportunity | **Yes** | 4 opps | >$50K with no activity |
| Stale_Opp_90 | Opportunity | No | N/A | Requires 90-day aging |
| Unassigned_Lead_48 | Lead | No | N/A | Requires 48-hour aging |
| Lead_Hoarding | Lead | No | N/A | Requires 5-day aging |
| Zombie_Projects | Project__c | No | N/A | Requires 60-day aging |
| Duplicate_Leads | Lead | **Yes** | 4 leads | Same Email detection |
| Duplicate_Contacts | Contact | **Yes** | 4 contacts | Same Email detection |
| Duplicate_Accounts | Account | **Yes** | 4 accounts | Same Name detection |
| Orphan_Contact | Contact | **Yes** | 3 contacts | No AccountId |
| Orphan_Opportunity | Opportunity | **Yes** | 2 opps | No AccountId |
| Orphan_Case | Case | **Yes** | 2 cases | No AccountId or ContactId |
| Expired_Quote_Requests | Quote_Request__c | **Yes** | 3 quotes | Expiration_Date__c < TODAY |
| Frequent_Flyer_Churn | Case | Conditional | N/A | Hot accounts with High cases |
| Premature_Escalation | Case | Conditional | N/A | IsEscalated without High priority |
| Inactive_Owner_* | Various | Conditional | N/A | Requires inactive users |
| Contract_Expiry_Red_Zone | Contract | Conditional | N/A | Expiring in 30 days |
| Missing_Attachment_* | Opp/Case | Conditional | N/A | Closed without attachments |

---

## Premium Tier Test Suite

### PT-1.1: High Value Ghosting Detection - Verified

**Objective:** Verify opportunities >$50K with no activity are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 4 opportunities >$50K with no Tasks/Events (LastActivityDate = null)
  - Ghosted Enterprise Deal: $150,000
  - Ghosted Global Expansion: $250,000
  - Ghosted Healthcare Project: $175,000
  - Ghosted Mega Deal: $500,000

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
- [ ] Occurrences__c = 4
- [ ] Impact_Score__c = sum of Opportunity.Amount values ($1,075,000)

**Verification Query:**
```sql
SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c = 'High_Value_Ghosting'
```

---

### PT-1.2: Duplicate Leads Detection - Verified

**Objective:** Verify leads with duplicate email addresses are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 2 leads with email: duplicate@test.com
- 2 leads with email: another.dup@test.com

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Duplicate_Leads pain point

**Expected Results:**
- [ ] Duplicate_Leads pain point created
- [ ] Occurrences__c = 4 (all duplicates counted)
- [ ] Example_Records__c contains lead IDs with duplicates
- [ ] Object_API_Name__c = 'Lead'

---

### PT-1.3: Duplicate Contacts Detection -Verified

**Objective:** Verify contacts with duplicate email addresses are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 2 contacts with email: duplicate.contact@example.com
- 2 contacts with email: another.duplicate@example.com

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Duplicate_Contacts pain point

**Expected Results:**
- [ ] Duplicate_Contacts pain point created
- [ ] Occurrences__c = 4
- [ ] Object_API_Name__c = 'Contact'

---

### PT-1.4: Duplicate Accounts Detection - Verified

**Objective:** Verify accounts with duplicate names are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 2 accounts named: "Duplicate Company Inc"
- 2 accounts named: "Another Duplicate Corp"

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Duplicate_Accounts pain point

**Expected Results:**
- [ ] Duplicate_Accounts pain point created
- [ ] Occurrences__c = 4
- [ ] Object_API_Name__c = 'Account'

---

### PT-1.5: Orphan Contact Detection - Verified

**Objective:** Verify contacts without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 3 orphan contacts (AccountId = null)

**Steps:**
1. Set license to PREMIUM
2. Run pattern analysis
3. Check for Orphan_Contact pain point

**Expected Results:**
- [ ] Orphan_Contact pain point created
- [ ] Occurrences__c = 3
- [ ] Object_API_Name__c = 'Contact'

---

### PT-1.6: Orphan Opportunity Detection - Verified

**Objective:** Verify opportunities without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 2 orphan opportunities (AccountId = null)

**Expected Results:**
- [ ] Orphan_Opportunity pain point created
- [ ] Occurrences__c = 2

---

### PT-1.7: Orphan Case Detection - Verified

**Objective:** Verify cases without accounts are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 2 orphan cases (AccountId = null, ContactId = null)

**Expected Results:**
- [ ] Orphan_Case pain point created
- [ ] Occurrences__c = 2

---

### PT-1.8: Expired Quote Requests Detection - Verified

**Objective:** Verify expired quote requests are detected.

**Immediately Testable:** Yes

**Mock Data Created:**
- 3 quote requests with Expiration_Date__c in the past and Status = 'Draft' or 'Pending Review'

**Pattern Query:**
```
Status__c IN ('Draft', 'Pending Review') AND Expiration_Date__c < TODAY
```

**Expected Results:**
- [ ] Expired_Quote_Requests pain point created
- [ ] Occurrences__c = 3

---

### PT-1.9: Stale Opportunity 90-Day Detection - Need to age data


**Objective:** Verify opportunities with no stage change in 90+ days are detected.

**Immediately Testable:** No (requires 90-day aging)

**Pattern Query:**
```
IsClosed = false AND LastStageChangeDate < LAST_N_DAYS:90
```

> **Note:** This pattern uses the real `LastStageChangeDate` system field. Freshly created opportunities will NOT trigger this pattern.

**Workaround:** Wait 90 days or use Data Loader with audit field permissions.

---

### PT-2.1: Task Creation Fix (Premium) - Verified

**Objective:** Verify Task_Creation fix works on premium patterns.

**Pattern:** High_Value_Ghosting

**Steps:**
1. View High_Value_Ghosting pain point
2. Select affected opportunities
3. Execute fix

**Expected Results:**
- [ ] Tasks created for each selected opportunity
- [ ] Task Subject follows fix configuration
- [ ] Task assigned to opportunity owner
- [ ] Remediation_Log__c records created

---

### PT-2.2: Owner Assignment Fix - Aging Required


**Objective:** Verify Owner_Assignment fix reassigns records.

**Pattern:** Unassigned_Lead_48 (requires 48-hour aging)

**Immediately Testable:** No

> **Note:** The Unassigned_Lead_48 pattern requires leads to be 48+ hours old in a queue. This test requires data aging.

**Expected Results (when testable):**
- [ ] Leads reassigned to queue or user
- [ ] Remediation_Log__c with Original_Value__c (old owner) and New_Value__c (new owner)

---

### PT-3.1: Pattern Rule Manager (Premium Features) - Verified

**Objective:** Verify Pattern Rule Manager shows premium features.

**Steps:**
1. Set license to PREMIUM
2. Navigate to Pattern Rule Manager

**Expected Results:**
- [ ] Premium patterns can be viewed and edited
- [ ] Create/Edit/Clone buttons functional
- [ ] No upgrade CTAs for premium features

---

## Mock Data Summary

The `release_candidate_mock_data.apex` script creates the following data:

| Object | Total Records | Pattern-Specific Data |
|--------|--------------|----------------------|
| Account | 17 | 3 with Rating='Cold', 4 duplicates (2 pairs) |
| Contact | 31 | 3 orphans, 4 missing data, 4 duplicates (2 pairs) |
| Lead | 9 | 4 duplicates (2 pairs) |
| Opportunity | 9 | 4 high-value ghosted, 2 orphans |
| Case | 11 | 3 COVERAGE_TEST, 2 orphans |
| Project__c | 5 | Standard data |
| Quote_Request__c | 7 | 3 expired |

---

## Quick Reference: Pattern Testability Matrix

### Immediately Testable (No Data Aging Required)

| Pattern | Tier | Fix Type | Mock Data Count |
|---------|------|----------|-----------------|
| Contact_Data_Gap | FREE | Task_Creation | 7 contacts |
| Test_Status_New | FREE | Task_Creation | 3 cases (**TEST ONLY**) |
| Sample_Plugin_Pattern | FREE | Task_Creation | 3 accounts (**TEST ONLY**) |
| High_Value_Ghosting | PREMIUM | Task_Creation | 4 opportunities |
| Duplicate_Leads | PREMIUM | Task_Creation | 4 leads |
| Duplicate_Contacts | PREMIUM | Task_Creation | 4 contacts |
| Duplicate_Accounts | PREMIUM | Task_Creation | 4 accounts |
| Orphan_Contact | PREMIUM | Task_Creation | 3 contacts |
| Orphan_Opportunity | PREMIUM | Task_Creation | 2 opportunities |
| Orphan_Case | PREMIUM | Task_Creation | 2 cases |
| Expired_Quote_Requests | PREMIUM | No_Action | 3 quotes |

### Requires Data Aging

| Pattern | Tier | Wait Time | System Field Used |
|---------|------|-----------|-------------------|
| Stale_Case_14 | FREE | 14 days | LastModifiedDate |
| Stale_Case_30 | FREE | 30 days | LastModifiedDate |
| Stale_Opp_90 | PREMIUM | 90 days | LastStageChangeDate |
| Unassigned_Lead_48 | PREMIUM | 48 hours | CreatedDate |
| Lead_Hoarding | PREMIUM | 5 days | CreatedDate |
| Zombie_Projects | PREMIUM | 60 days | LastModifiedDate |

---

## Fix Types Coverage Matrix

> **IMPORTANT:** Auto-Fix is a **Premium-only feature**. The table below shows which fix types are configured for each pattern, but executing ANY fix requires a Premium license.

| Fix Type | Free Patterns | Premium Patterns | Immediately Testable |
|----------|--------------|------------------|---------------------|
| Task_Creation | Contact_Data_Gap, Stale_Case_*, Test_Status_New | High_Value_Ghosting, Orphan_*, Frequent_Flyer_Churn, Duplicates | Premium only |
| Owner_Assignment | None | Unassigned_Lead_48, Lead_Hoarding | Premium only |
| Field_Update | None | Zombie_Projects | Premium only |
| Escalation_Revert | None | Premature_Escalation | Premium only |
| Opportunity_Creation | None | Contract_Expiry_Red_Zone | Premium only |
| No_Action | Weekend_Case_Spike, Sample_Plugin_Pattern | Expired_Quote_Requests | N/A (detection only) |

---

## Test Execution Checklist

### Free Tier Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| FT-1.1 Contact_Data_Gap | ⬜ | 7 contacts expected |
| FT-1.2 Test_Status_New | ⬜ | TEST ONLY - 3 cases |
| FT-1.3 Sample_Plugin_Pattern | ⬜ | TEST ONLY - 3 accounts |
| FT-1.4 Stale_Case_14 | ⬜ | Requires 14-day aging |
| FT-1.5 Stale_Case_30 | ⬜ | Requires 30-day aging |
| FT-1.6 Weekend_Case_Spike | ⬜ | Only on weekends |
| FT-1.7 Premium Gating | ⬜ | Verify premium patterns blocked |
| FT-2.1 Auto-Fix Premium Gating | ⬜ | Verify fix blocked on Free tier |
| FT-3.1 Dashboard (Free) | ⬜ | Health gauge includes all patterns |

### Premium Tier Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| PT-1.1 High_Value_Ghosting | ⬜ | 4 opportunities expected |
| PT-1.2 Duplicate_Leads | ⬜ | 4 leads expected |
| PT-1.3 Duplicate_Contacts | ⬜ | 4 contacts expected |
| PT-1.4 Duplicate_Accounts | ⬜ | 4 accounts expected |
| PT-1.5 Orphan_Contact | ⬜ | 3 contacts expected |
| PT-1.6 Orphan_Opportunity | ⬜ | 2 opportunities expected |
| PT-1.7 Orphan_Case | ⬜ | 2 cases expected |
| PT-1.8 Expired_Quote_Requests | ⬜ | 3 quotes expected |
| PT-1.9 Stale_Opp_90 | ⬜ | Requires 90-day aging |
| PT-2.1 Task Fix (Premium) | ⬜ | |
| PT-2.2 Owner_Assignment | ⬜ | Requires 48-hour aging |
| PT-3.1 Pattern Rule Manager | ⬜ | |

---

## Troubleshooting

### Pattern Not Detecting Expected Records

1. **Check license tier** - Premium patterns require Premium license
2. **Verify data aging** - Stale patterns need real LastModifiedDate/CreatedDate aging
3. **Check Is_Active__c** - Pattern rule must be active
4. **Verify Query_Condition__c** - Ensure SOQL syntax is valid
5. **Check FLS** - User must have access to queried fields

### Stale Patterns Not Working

The stale patterns (Stale_Case_14, Stale_Case_30, Stale_Opp_90) use **real system fields**:
- `LastModifiedDate` - Updated automatically on any DML
- `LastStageChangeDate` - Updated when Opportunity stage changes

These fields CANNOT be set manually. Records must genuinely age to trigger these patterns.

**Options:**
1. Wait the required time (14/30/90 days)
2. Use Data Loader with "Set Audit Fields" permission (requires admin setup)
3. Test in a sandbox that has aged data

### Fix Not Executing

1. Check user has edit permissions on target object
2. Verify Fix_Config__c JSON is valid
3. Check for validation rules blocking updates
4. Review Remediation_Log__c for error messages

---

## SOQL Verification Queries

### Check All Pain Points
```sql
SELECT Id, Name, Unique_Key__c, Object_API_Name__c, Occurrences__c,
       Impact_Score__c, Status__c, Last_Detected__c
FROM Identified_Pain_Point__c
ORDER BY Last_Detected__c DESC
```

### Check Remediation Logs
```sql
SELECT Id, Affected_Record_ID__c, Rule_Developer_Name__c, Action_Taken__c,
       Original_Value__c, New_Value__c, Status__c, CreatedDate
FROM Remediation_Log__c
ORDER BY CreatedDate DESC
LIMIT 50
```

### Check License Status
```sql
SELECT Id, Status__c FROM BehaviorIQ_License__c
```

### Verify Mock Data Counts
```sql
-- Contacts missing data (Contact_Data_Gap)
SELECT COUNT() FROM Contact WHERE Email = null OR Phone = null

-- Orphan contacts
SELECT COUNT() FROM Contact WHERE AccountId = null

-- Cases with COVERAGE_TEST (Test_Status_New)
SELECT COUNT() FROM Case WHERE Subject LIKE 'COVERAGE_TEST%' AND Status = 'New'

-- Cold accounts (Sample_Plugin_Pattern)
SELECT COUNT() FROM Account WHERE Rating = 'Cold'

-- High-value opportunities without activity (High_Value_Ghosting)
SELECT COUNT() FROM Opportunity WHERE Amount > 50000 AND IsClosed = false AND LastActivityDate = null

-- Duplicate leads
SELECT Email, COUNT(Id) FROM Lead WHERE Email != null GROUP BY Email HAVING COUNT(Id) > 1

-- Expired quote requests
SELECT COUNT() FROM Quote_Request__c WHERE Status__c IN ('Draft', 'Pending Review') AND Expiration_Date__c < TODAY
```

---

## Production Deployment Notes

> **IMPORTANT:** Before deploying to production, ensure the following TEST ONLY patterns are either:
> - Removed from the deployment package, OR
> - Set to `Is_Active__c = false`
>
> **TEST ONLY Patterns (do not deploy active to production):**
> - `Test_Status_New` - Coverage test pattern
> - `Sample_Plugin_Pattern` - Demo plugin pattern

---

Last Updated: January 2026
