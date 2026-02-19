/**
 * BehaviorIQ E2E Bulk Stress Test Data Setup
 * ============================================
 *
 * WARNING: This script creates HIGH-VOLUME test data for stress testing.
 * Run this in a DEDICATED scratch org to avoid hitting org limits.
 *
 * DATA CREATED:
 * - 10,000 Contacts (for bulk pattern detection)
 * - 5,000 Leads (for duplicate detection stress)
 * - 2,000 Opportunities (for high-value ghosting at scale)
 *
 * ESTIMATED RUNTIME: 5-10 minutes depending on org performance
 *
 * RECOMMENDED:
 * - Use a fresh scratch org
 * - Run during off-peak hours
 * - Monitor governor limits
 */

System.debug('=== BehaviorIQ BULK STRESS TEST Data Setup ===');
System.debug('WARNING: This creates high-volume data. Estimated runtime: 5-10 minutes.');
System.debug('');

// ============================================================================
// CONFIGURATION
// ============================================================================
Integer CONTACT_COUNT = 10000;
Integer LEAD_COUNT = 5000;
Integer OPPORTUNITY_COUNT = 2000;
Integer BATCH_SIZE = 200; // Salesforce DML limit

// ============================================================================
// PART 1: CREATE BASE ACCOUNTS
// ============================================================================
System.debug('--- Creating base accounts for relationships ---');

List<Account> accounts = new List<Account>();
for (Integer i = 1; i <= 100; i++) {
    accounts.add(new Account(
        Name = 'Bulk Test Account ' + i,
        Rating = Math.mod(i, 3) == 0 ? 'Hot' : (Math.mod(i, 3) == 1 ? 'Warm' : 'Cold'),
        Industry = 'Technology',
        Type = 'Customer - Direct'
    ));
}
insert accounts;
System.debug('Created ' + accounts.size() + ' base accounts.');

// ============================================================================
// PART 2: BULK CONTACTS (10,000)
// ============================================================================
System.debug('');
System.debug('--- Creating ' + CONTACT_COUNT + ' contacts (bulk stress) ---');

Integer contactsCreated = 0;
Integer contactBatch = 0;

while (contactsCreated < CONTACT_COUNT) {
    List<Contact> contactBatchList = new List<Contact>();
    Integer batchEnd = Math.min(contactsCreated + BATCH_SIZE, CONTACT_COUNT);

    for (Integer i = contactsCreated; i < batchEnd; i++) {
        Integer idx = i + 1;

        // 30% of contacts have missing Email (for Contact_Data_Gap)
        Boolean missingEmail = Math.mod(idx, 10) < 3;

        // 5% are orphan contacts (for Orphan_Contact)
        Boolean isOrphan = Math.mod(idx, 20) == 0;

        // 10% have duplicate emails (for Duplicate_Contacts)
        String email;
        if (missingEmail) {
            email = null;
        } else if (Math.mod(idx, 10) == 0) {
            // Duplicate email - use a repeated pattern
            email = 'bulk.dup.contact' + Math.mod(idx, 500) + '@stress.test';
        } else {
            email = 'bulk.contact' + idx + '@stress.test';
        }

        contactBatchList.add(new Contact(
            AccountId = isOrphan ? null : accounts[Math.mod(idx, accounts.size())].Id,
            FirstName = 'Bulk',
            LastName = 'Contact ' + idx,
            Email = email,
            Phone = missingEmail ? '555-' + String.valueOf(idx).leftPad(7, '0') : null,
            Title = 'Test Contact'
        ));
    }

    insert contactBatchList;
    contactsCreated = batchEnd;
    contactBatch++;

    if (Math.mod(contactBatch, 10) == 0) {
        System.debug('  Progress: ' + contactsCreated + ' / ' + CONTACT_COUNT + ' contacts created');
    }
}

System.debug('Created ' + contactsCreated + ' contacts.');
System.debug('  - ~3,000 with missing Email (Contact_Data_Gap)');
System.debug('  - ~500 orphan contacts (Orphan_Contact)');
System.debug('  - ~1,000 with duplicate emails (Duplicate_Contacts)');

// ============================================================================
// PART 3: BULK LEADS (5,000)
// ============================================================================
System.debug('');
System.debug('--- Creating ' + LEAD_COUNT + ' leads (bulk stress) ---');

Integer leadsCreated = 0;
Integer leadBatch = 0;

while (leadsCreated < LEAD_COUNT) {
    List<Lead> leadBatchList = new List<Lead>();
    Integer batchEnd = Math.min(leadsCreated + BATCH_SIZE, LEAD_COUNT);

    for (Integer i = leadsCreated; i < batchEnd; i++) {
        Integer idx = i + 1;

        // 20% have duplicate emails (for Duplicate_Leads stress test)
        String email;
        if (Math.mod(idx, 5) == 0) {
            // Duplicate email - use a repeated pattern (creates groups of duplicates)
            email = 'bulk.dup.lead' + Math.mod(idx, 250) + '@stress.test';
        } else {
            email = 'bulk.lead' + idx + '@stress.test';
        }

        leadBatchList.add(new Lead(
            FirstName = 'Bulk',
            LastName = 'Lead ' + idx,
            Company = 'Bulk Lead Company ' + idx,
            Email = email,
            Status = 'Open - Not Contacted',
            LeadSource = 'Web',
            Industry = 'Technology'
        ));
    }

    insert leadBatchList;
    leadsCreated = batchEnd;
    leadBatch++;

    if (Math.mod(leadBatch, 10) == 0) {
        System.debug('  Progress: ' + leadsCreated + ' / ' + LEAD_COUNT + ' leads created');
    }
}

System.debug('Created ' + leadsCreated + ' leads.');
System.debug('  - ~1,000 with duplicate emails (Duplicate_Leads)');

// ============================================================================
// PART 4: BULK OPPORTUNITIES (2,000)
// ============================================================================
System.debug('');
System.debug('--- Creating ' + OPPORTUNITY_COUNT + ' opportunities (bulk stress) ---');

List<String> stages = new List<String>{'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition', 'Proposal/Price Quote', 'Negotiation/Review'};

Integer oppsCreated = 0;
Integer oppBatch = 0;

while (oppsCreated < OPPORTUNITY_COUNT) {
    List<Opportunity> oppBatchList = new List<Opportunity>();
    Integer batchEnd = Math.min(oppsCreated + BATCH_SIZE, OPPORTUNITY_COUNT);

    for (Integer i = oppsCreated; i < batchEnd; i++) {
        Integer idx = i + 1;

        // 25% are high-value ($50K+) with no activity (for High_Value_Ghosting)
        Boolean isHighValue = Math.mod(idx, 4) == 0;
        Decimal amount = isHighValue ? (50000 + (idx * 100)) : (5000 + (idx * 50));

        // 5% are orphan opportunities (for Orphan_Opportunity)
        Boolean isOrphan = Math.mod(idx, 20) == 0;

        oppBatchList.add(new Opportunity(
            Name = 'Bulk Deal ' + idx,
            AccountId = isOrphan ? null : accounts[Math.mod(idx, accounts.size())].Id,
            Amount = amount,
            StageName = stages[Math.mod(idx, 6)],
            CloseDate = Date.today().addDays(30 + Math.mod(idx, 90)),
            Probability = 30 + Math.mod(idx * 5, 50),
            Description = isHighValue ? 'High-value ghosted opportunity' : 'Standard opportunity'
        ));
    }

    insert oppBatchList;
    oppsCreated = batchEnd;
    oppBatch++;

    if (Math.mod(oppBatch, 5) == 0) {
        System.debug('  Progress: ' + oppsCreated + ' / ' + OPPORTUNITY_COUNT + ' opportunities created');
    }
}

System.debug('Created ' + oppsCreated + ' opportunities.');
System.debug('  - ~500 high-value ($50K+) with no activity (High_Value_Ghosting)');
System.debug('  - ~100 orphan opportunities (Orphan_Opportunity)');

// ============================================================================
// SUMMARY
// ============================================================================
System.debug('');
System.debug('=== BULK STRESS TEST DATA SETUP COMPLETE ===');
System.debug('');
System.debug('Total Records Created:');
System.debug('  Accounts:      100');
System.debug('  Contacts:      ' + CONTACT_COUNT);
System.debug('  Leads:         ' + LEAD_COUNT);
System.debug('  Opportunities: ' + OPPORTUNITY_COUNT);
System.debug('');
System.debug('BULK PATTERN COVERAGE:');
System.debug('  Contact_Data_Gap:     ~3,000 contacts');
System.debug('  Orphan_Contact:       ~500 contacts');
System.debug('  Duplicate_Contacts:   ~1,000 contacts');
System.debug('  Duplicate_Leads:      ~1,000 leads');
System.debug('  High_Value_Ghosting:  ~500 opportunities');
System.debug('  Orphan_Opportunity:   ~100 opportunities');
System.debug('');
System.debug('NEXT STEPS:');
System.debug('1. Run: Database.executeBatch(new PatternAnalysisBatch(), 200);');
System.debug('2. Monitor batch job completion');
System.debug('3. Verify pain point occurrences match expected counts');
System.debug('4. Test Auto-Fix with bulk record selection (200+)');
System.debug('');
System.debug('STRESS TEST SCENARIOS:');
System.debug('- BK-1.1: Pattern Analysis 10K records');
System.debug('- BK-1.3: Auto-Fix 200 records');
System.debug('- BK-1.4: Auto-Fix 500 records');
System.debug('- BK-1.5: Duplicate detection 5K leads');
System.debug('- BK-1.6: Duplicate detection 5K contacts (subset)');
System.debug('');
