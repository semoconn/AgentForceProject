// Verify freshly imported data has correct dates
System.debug('=== Verifying Fresh Test Data ===');

// Check contacts with missing data
System.debug('');
System.debug('--- Contacts Missing Data (for Contact_Data_Gap) ---');
List<Contact> contactsNoData = [
    SELECT Id, FirstName, LastName, Email, Phone
    FROM Contact
    WHERE Email = null OR Phone = null
];
System.debug('Contacts with missing email or phone: ' + contactsNoData.size());
for (Contact c : contactsNoData) {
    String missing = '';
    if (c.Email == null) missing += 'Email ';
    if (c.Phone == null) missing += 'Phone';
    System.debug(c.FirstName + ' ' + c.LastName + ' - Missing: ' + missing.trim());
}

// Check 14-day stale cases
System.debug('');
System.debug('--- Stale Cases 14+ Days (for Stale_Case_14) ---');
System.debug('Condition: Status != Closed AND LastModifiedDate < LAST_N_DAYS:14');
List<Case> stale14Cases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate, Status
    FROM Case
    WHERE Subject LIKE 'Stale Case 14-Day%'
    ORDER BY CreatedDate
];
for (Case c : stale14Cases) {
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' | LastMod: ' + c.LastModifiedDate + ' | Status: ' + c.Status);
}

// Test the actual pattern query for Stale_Case_14
Integer stale14Match = [SELECT COUNT() FROM Case WHERE Status != 'Closed' AND LastModifiedDate < LAST_N_DAYS:14];
System.debug('Cases matching Stale_Case_14 pattern: ' + stale14Match);

// Check 30-day stale cases
System.debug('');
System.debug('--- Stale Cases 30+ Days (for Stale_Case_30) ---');
List<Case> stale30Cases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate, Status
    FROM Case
    WHERE Subject LIKE 'Stale Case 30-Day%'
    ORDER BY CreatedDate
];
for (Case c : stale30Cases) {
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' | LastMod: ' + c.LastModifiedDate + ' | Status: ' + c.Status);
}

// Test the actual pattern query for Stale_Case_30
Integer stale30Match = [SELECT COUNT() FROM Case WHERE Status != 'Closed' AND LastModifiedDate < LAST_N_DAYS:30];
System.debug('Cases matching Stale_Case_30 pattern: ' + stale30Match);

// Check weekend cases
System.debug('');
System.debug('--- Weekend Cases (for Weekend_Case_Spike) ---');
List<Case> weekendCases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate
    FROM Case
    WHERE Subject LIKE 'Weekend Case%'
    ORDER BY CreatedDate
];
for (Case c : weekendCases) {
    Datetime dt = Datetime.newInstance(c.CreatedDate.date().year(), c.CreatedDate.date().month(), c.CreatedDate.date().day());
    String dayName = dt.format('EEEE');
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' (' + dayName + ') | LastMod: ' + c.LastModifiedDate);
}

// Test the actual pattern query for Weekend_Case_Spike
Integer weekendMatch = [SELECT COUNT() FROM Case WHERE CreatedDate = LAST_WEEK AND DAY_IN_WEEK(CreatedDate) IN (1, 7)];
System.debug('Cases matching Weekend_Case_Spike pattern: ' + weekendMatch);

System.debug('');
System.debug('=== Summary ===');
System.debug('Contact_Data_Gap matches: ' + contactsNoData.size());
System.debug('Stale_Case_14 matches: ' + stale14Match);
System.debug('Stale_Case_30 matches: ' + stale30Match);
System.debug('Weekend_Case_Spike matches: ' + weekendMatch);
