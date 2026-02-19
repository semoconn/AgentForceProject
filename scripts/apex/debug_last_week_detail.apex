// Find exactly which cases match LAST_WEEK
System.debug('=== Cases Matching LAST_WEEK ===');

List<Case> lastWeekCases = [
    SELECT Id, Subject, CreatedDate
    FROM Case
    WHERE CreatedDate = LAST_WEEK
    ORDER BY CreatedDate
];

for (Case c : lastWeekCases) {
    // Calculate day of week (Salesforce: 1=Sunday, 7=Saturday)
    Date d = c.CreatedDate.date();
    Datetime dt = Datetime.newInstance(d.year(), d.month(), d.day());
    String dayName = dt.format('EEEE');
    System.debug(c.CreatedDate + ' (' + dayName + '): ' + c.Subject);
}

System.debug('');
System.debug('=== All Weekend Cases (Jan 19 & 25) with Day Names ===');
for (Case c : [SELECT Subject, CreatedDate FROM Case WHERE Subject LIKE 'Weekend Case%' ORDER BY CreatedDate]) {
    Date d = c.CreatedDate.date();
    Datetime dt = Datetime.newInstance(d.year(), d.month(), d.day());
    String dayName = dt.format('EEEE');
    System.debug(c.CreatedDate + ' (' + dayName + '): ' + c.Subject);
}

System.debug('');
System.debug('=== Test Weekend Pattern Query ===');
List<Case> weekendMatches = [
    SELECT Id, Subject, CreatedDate
    FROM Case
    WHERE CreatedDate = LAST_WEEK
    AND DAY_IN_WEEK(CreatedDate) IN (1, 7)
];
System.debug('Matches with BOTH conditions: ' + weekendMatches.size());
for (Case c : weekendMatches) {
    System.debug(c.Subject);
}
