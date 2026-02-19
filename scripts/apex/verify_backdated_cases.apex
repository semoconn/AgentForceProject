// Verify the backdated cases have correct dates
System.debug('=== Verifying Backdated Cases ===');

// Check 14-day stale cases
List<Case> stale14Cases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate, Status
    FROM Case
    WHERE Subject LIKE 'Stale Case 14-Day%'
    ORDER BY CreatedDate ASC
];

System.debug('');
System.debug('--- 14-Day Stale Cases ---');
for (Case c : stale14Cases) {
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' | LastMod: ' + c.LastModifiedDate);
}

// Check 30-day stale cases
List<Case> stale30Cases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate, Status
    FROM Case
    WHERE Subject LIKE 'Stale Case 30-Day%'
    ORDER BY CreatedDate ASC
];

System.debug('');
System.debug('--- 30-Day Stale Cases ---');
for (Case c : stale30Cases) {
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' | LastMod: ' + c.LastModifiedDate);
}

// Check weekend cases
List<Case> weekendCases = [
    SELECT Id, Subject, CreatedDate, LastModifiedDate, Status
    FROM Case
    WHERE Subject LIKE 'Weekend Case%'
    ORDER BY CreatedDate ASC
];

System.debug('');
System.debug('--- Weekend Cases ---');
for (Case c : weekendCases) {
    Integer dayOfWeek = Math.mod((Date.newInstance(1900, 1, 7)).daysBetween(c.CreatedDate.date()), 7);
    String dayName = (dayOfWeek == 0) ? 'Saturday' : (dayOfWeek == 1) ? 'Sunday' : 'Weekday(' + dayOfWeek + ')';
    System.debug(c.Subject + ' | Created: ' + c.CreatedDate + ' | Day: ' + dayName);
}

System.debug('');
System.debug('=== Date Thresholds ===');
System.debug('Today: ' + Date.today());
System.debug('14 days ago: ' + Date.today().addDays(-14));
System.debug('30 days ago: ' + Date.today().addDays(-30));
