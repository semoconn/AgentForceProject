// Debug LAST_WEEK date literal behavior
System.debug('=== Debugging LAST_WEEK Date Literal ===');

// Get org timezone
System.debug('Org Timezone: ' + UserInfo.getTimeZone().getDisplayName());
System.debug('Org Timezone ID: ' + UserInfo.getTimeZone().getID());

// Today's date
Date today = Date.today();
DateTime nowDT = DateTime.now();
System.debug('Date.today(): ' + today);
System.debug('DateTime.now(): ' + nowDT);

// Try different date range queries to find what LAST_WEEK means
System.debug('');
System.debug('--- Testing Different Date Ranges ---');

// Query cases with LAST_WEEK
Integer lastWeekCount = [SELECT COUNT() FROM Case WHERE CreatedDate = LAST_WEEK];
System.debug('Cases in LAST_WEEK: ' + lastWeekCount);

// Query cases with THIS_WEEK
Integer thisWeekCount = [SELECT COUNT() FROM Case WHERE CreatedDate = THIS_WEEK];
System.debug('Cases in THIS_WEEK: ' + thisWeekCount);

// Query cases in specific date range (Jan 19-25)
Date jan19 = Date.newInstance(2026, 1, 19);
Date jan25 = Date.newInstance(2026, 1, 25);
Integer specificRangeCount = [SELECT COUNT() FROM Case WHERE CreatedDate >= :jan19 AND CreatedDate <= :jan25.addDays(1)];
System.debug('Cases in Jan 19-25: ' + specificRangeCount);

// Show all cases with their CreatedDate to find the pattern
System.debug('');
System.debug('--- All Cases by CreatedDate ---');
for (Case c : [SELECT Subject, CreatedDate FROM Case ORDER BY CreatedDate ASC LIMIT 20]) {
    Date cDate = c.CreatedDate.date();
    String dayName = '';
    if (Math.mod((Date.newInstance(1900, 1, 7)).daysBetween(cDate), 7) == 0) dayName = 'Sat';
    else if (Math.mod((Date.newInstance(1900, 1, 7)).daysBetween(cDate), 7) == 1) dayName = 'Sun';
    else dayName = 'Weekday';
    System.debug(c.CreatedDate + ' (' + dayName + '): ' + c.Subject);
}
