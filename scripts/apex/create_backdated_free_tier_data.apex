/**
 * Create Backdated Test Data for FREE Tier Pattern Testing
 * =========================================================
 *
 * PREREQUISITES:
 * 1. Enable "Set Audit Fields upon Record Creation" in Setup > User Interface
 * 2. Assign "Set Audit Fields upon Record Creation" permission to your user
 *
 * This script creates:
 * - Cases with LastModifiedDate > 14 days ago (for Stale_Case_14)
 * - Cases with LastModifiedDate > 30 days ago (for Stale_Case_30)
 * - Cases created on last weekend (for Weekend_Case_Spike)
 */

System.debug('=== Creating Backdated FREE Tier Test Data ===');

// Get an existing account to link cases to
List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 1];
if (accounts.isEmpty()) {
    System.debug('ERROR: No accounts found. Please run the main test data script first.');
} else {
    Account testAccount = accounts[0];
    System.debug('Using account: ' + testAccount.Name);

    List<Case> casesToInsert = new List<Case>();

    // Calculate dates
    DateTime now = DateTime.now();
    Date today = Date.today();

    // For Stale_Case_14: Need LastModifiedDate > 14 days ago
    // Create cases with CreatedDate 15-20 days ago
    System.debug('');
    System.debug('--- Creating Stale Cases (14+ days) ---');
    for (Integer i = 1; i <= 5; i++) {
        casesToInsert.add(new Case(
            Subject = 'Stale Case 14-Day Test ' + i,
            Status = 'New',
            Priority = 'Medium',
            Origin = 'Web',
            AccountId = testAccount.Id,
            Description = 'Test case for Stale_Case_14 pattern - should be detected as stale (14+ days)'
        ));
    }

    // For Stale_Case_30: Need LastModifiedDate > 30 days ago
    // Create cases with CreatedDate 31-45 days ago
    System.debug('--- Creating Stale Cases (30+ days) ---');
    for (Integer i = 1; i <= 5; i++) {
        casesToInsert.add(new Case(
            Subject = 'Stale Case 30-Day Test ' + i,
            Status = 'New',
            Priority = 'Low',
            Origin = 'Email',
            AccountId = testAccount.Id,
            Description = 'Test case for Stale_Case_30 pattern - should be detected as very stale (30+ days)'
        ));
    }

    // For Weekend_Case_Spike: Need CreatedDate = LAST_WEEK AND weekend day
    // Calculate last Saturday and Sunday
    Integer dayOfWeek = Math.mod(Date.today().toStartOfWeek().daysBetween(Date.today()), 7);
    Date lastSunday = today.addDays(-dayOfWeek - 7);  // Last week's Sunday
    Date lastSaturday = lastSunday.addDays(-1);       // Last week's Saturday

    System.debug('--- Creating Weekend Cases ---');
    System.debug('Last Saturday: ' + lastSaturday);
    System.debug('Last Sunday: ' + lastSunday);

    for (Integer i = 1; i <= 3; i++) {
        casesToInsert.add(new Case(
            Subject = 'Weekend Case Saturday Test ' + i,
            Status = 'New',
            Priority = 'High',
            Origin = 'Phone',
            AccountId = testAccount.Id,
            Description = 'Test case for Weekend_Case_Spike pattern - created on Saturday'
        ));
    }

    for (Integer i = 1; i <= 3; i++) {
        casesToInsert.add(new Case(
            Subject = 'Weekend Case Sunday Test ' + i,
            Status = 'New',
            Priority = 'High',
            Origin = 'Phone',
            AccountId = testAccount.Id,
            Description = 'Test case for Weekend_Case_Spike pattern - created on Sunday'
        ));
    }

    // Insert all cases first (without audit fields - this is the baseline)
    insert casesToInsert;
    System.debug('Inserted ' + casesToInsert.size() + ' test cases');

    // Now attempt to update with backdated timestamps using Database.setSavePoint and special handling
    // Note: Direct LastModifiedDate setting is NOT possible even with audit fields
    // The workaround is to use external tools (Data Loader, API) with audit field headers

    System.debug('');
    System.debug('=== IMPORTANT: Manual Steps Required ===');
    System.debug('Cases created, but LastModifiedDate cannot be set via Apex.');
    System.debug('');
    System.debug('To complete the test data setup:');
    System.debug('1. Export the case IDs below');
    System.debug('2. Use Data Loader or Workbench to update LastModifiedDate');
    System.debug('3. Or use the Salesforce CLI data import with --external-id');
    System.debug('');

    // Output case IDs for manual update
    System.debug('=== Case IDs for Manual Backdating ===');
    Integer index = 0;
    for (Case c : casesToInsert) {
        String dateNote = '';
        if (index < 5) {
            dateNote = ' -> Set LastModifiedDate to ' + (today.addDays(-15-index)) + ' (for Stale_Case_14)';
        } else if (index < 10) {
            dateNote = ' -> Set LastModifiedDate to ' + (today.addDays(-31-(index-5))) + ' (for Stale_Case_30)';
        } else if (index < 13) {
            dateNote = ' -> Set CreatedDate to ' + lastSaturday + ' (for Weekend_Case_Spike)';
        } else {
            dateNote = ' -> Set CreatedDate to ' + lastSunday + ' (for Weekend_Case_Spike)';
        }
        System.debug(c.Id + ': ' + c.Subject + dateNote);
        index++;
    }

    System.debug('');
    System.debug('Total cases created: ' + casesToInsert.size());
}
