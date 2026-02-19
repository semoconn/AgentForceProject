# Data Import Instructions for Missing Pattern Test Data

This guide walks you through importing test data for the 4 missing patterns:

| Pattern | Data File | Method |
|---------|-----------|--------|
| Missing_Attachment_Closed_Case | Apex Script | Run immediately |
| Missing_Attachment_Closed_Won | Apex Script | Run immediately |
| Stale_Opp_90 | CSV (Data Loader) | Requires audit fields |
| Unassigned_Lead_48 | CSV (Data Loader) | Requires audit fields + Queue ID |

---

## STEP 1: Run Apex Script for Missing Attachment Patterns

These patterns are **immediately testable** - run the Apex script first.

```bash
sf apex run --file scripts/apex/create_missing_attachment_data.apex --target-org <your-org>
```

**What it creates:**
- 8 Closed Cases WITHOUT file attachments
- 8 Closed Won Opportunities WITHOUT file attachments

**Expected pain points:** `Missing_Attachment_Closed_Case` and `Missing_Attachment_Closed_Won` should appear after running PatternAnalysisBatch.

---

## STEP 2: Import Stale_Opp_90 Data via Data Loader

### 2a. Verify "Set Audit Fields" is Enabled

You mentioned this is already done, but verify:
- Setup → User Interface → ✅ "Set Audit Fields upon Record Creation"
- Your user has the permission (via Permission Set or Profile)

### 2b. Import the CSV

**File:** `scripts/data/stale_opp_90_import.csv`

**Using Salesforce Data Loader:**
1. Open Data Loader
2. Select **Insert**
3. Choose object: **Opportunity**
4. Select the CSV file: `stale_opp_90_import.csv`
5. **IMPORTANT:** In Settings, ensure "Insert Null Values" is UNCHECKED
6. Map the fields:
   - Name → Name
   - StageName → StageName
   - CloseDate → CloseDate
   - Amount → Amount
   - LastStageChangeDate → LastStageChangeDate ← **Critical field!**
   - Description → Description
7. Click **Finish** to import

**Using SFDX CLI (alternative):**
```bash
sf data import tree --files scripts/data/stale_opp_90_import.csv --target-org <your-org>
```

---

## STEP 3: Import Unassigned_Lead_48 Data via Data Loader

### 3a. Find Your Lead Queue ID

Run this Apex script to find existing Lead queues:

```bash
sf apex run --file scripts/apex/find_lead_queues.apex --target-org <your-org>
```

Copy the Queue ID from the output (looks like `00G...`).

**If no Lead queues exist:**
1. Setup → Queues → New
2. Label: "Lead Queue" (or any name)
3. Supported Objects: Add **Lead**
4. Queue Members: Add yourself
5. Save, then re-run the script to get the ID

### 3b. Update the CSV with Queue ID

1. Open `scripts/data/unassigned_lead_48_import.csv`
2. Find & Replace: `REPLACE_WITH_QUEUE_ID` → `<your-queue-id>`
3. Save the file

### 3c. Import the CSV

**Using Salesforce Data Loader:**
1. Open Data Loader
2. Select **Insert**
3. Choose object: **Lead**
4. Select the CSV file: `unassigned_lead_48_import.csv`
5. Map the fields:
   - LastName → LastName
   - FirstName → FirstName
   - Company → Company
   - Status → Status
   - OwnerId → OwnerId ← **Must be Queue ID**
   - CreatedDate → CreatedDate ← **Critical field!**
   - LeadSource → LeadSource
   - Description → Description
6. Click **Finish** to import

---

## STEP 4: Run Pattern Analysis Batch

After all data is imported, run the pattern analysis:

```apex
Database.executeBatch(new PatternAnalysisBatch(), 200);
```

Or via CLI:
```bash
echo "Database.executeBatch(new PatternAnalysisBatch(), 200);" | sf apex run --target-org <your-org>
```

---

## STEP 5: Verify Pain Points

### Expected Pain Points After Import:

| Pattern | Expected Count | When Visible |
|---------|---------------|--------------|
| Missing_Attachment_Closed_Case | 8 | Immediately after batch |
| Missing_Attachment_Closed_Won | 8 | Immediately after batch |
| Stale_Opp_90 | 8 | Immediately after batch |
| Unassigned_Lead_48 | 8 | Immediately after batch |

### Verification Query:
```sql
SELECT Unique_Key__c, Occurrences__c, Last_Detected__c
FROM Identified_Pain_Point__c
WHERE Unique_Key__c IN (
    'Missing_Attachment_Closed_Case',
    'Missing_Attachment_Closed_Won',
    'Stale_Opp_90',
    'Unassigned_Lead_48'
)
```

---

## Troubleshooting

### "LastStageChangeDate cannot be set"
- Verify "Set Audit Fields upon Record Creation" is enabled in Setup
- Verify your user has the permission assigned

### "Invalid OwnerId" for Leads
- The OwnerId must be a valid Queue ID (starts with `00G`)
- Verify the queue supports the Lead object

### Pattern not detecting records
1. Check that the pattern rule `Is_Active__c = true`
2. Verify license is set to Premium (these are all Premium patterns)
3. Check the batch job completed without errors:
   ```sql
   SELECT Status, NumberOfErrors, ExtendedStatus
   FROM AsyncApexJob
   WHERE ApexClass.Name = 'PatternAnalysisBatch'
   ORDER BY CreatedDate DESC
   LIMIT 1
   ```

### Missing Attachment patterns not detecting
- Verify the MissingAttachmentPlugin class is deployed
- Check that records truly have NO ContentDocumentLink records
- The plugin queries for files/attachments separately from the main query

---

## Timeline Summary

| Step | Action | Pain Point Visible |
|------|--------|-------------------|
| 1 | Run `create_missing_attachment_data.apex` | After batch |
| 2 | Import `stale_opp_90_import.csv` | After batch |
| 3 | Import `unassigned_lead_48_import.csv` | After batch |
| 4 | Run `PatternAnalysisBatch` | — |
| 5 | All 4 pain points visible | ✅ Immediately |

**Total new pain points:** 4 (bringing you from 20 to 24!)
