// Debug Weekend_Case_Spike pattern detection
System.debug('=== Debugging Weekend_Case_Spike Pattern ===');

// Check the weekend cases we created
List<Case> weekendCases = [
    SELECT Id, Subject, CreatedDate, Status
    FROM Case
    WHERE Subject LIKE 'Weekend Case%'
];

System.debug('');
System.debug('--- Weekend Cases in Org ---');
for (Case c : weekendCases) {
    System.debug('Case: ' + c.Subject + ' | CreatedDate: ' + c.CreatedDate);
}

// Now run the EXACT query from the Weekend_Case_Spike pattern
System.debug('');
System.debug('--- Running Weekend_Case_Spike Query ---');
System.debug('Query: CreatedDate = LAST_WEEK AND DAY_IN_WEEK(CreatedDate) IN (1, 7)');

List<Case> matchingCases = [
    SELECT Id, Subject, CreatedDate
    FROM Case
    WHERE CreatedDate = LAST_WEEK AND DAY_IN_WEEK(CreatedDate) IN (1, 7)
];

System.debug('Matching cases: ' + matchingCases.size());
for (Case c : matchingCases) {
    System.debug('MATCH: ' + c.Subject + ' | CreatedDate: ' + c.CreatedDate);
}

// Check what LAST_WEEK evaluates to
System.debug('');
System.debug('--- Date Reference ---');
System.debug('Today: ' + Date.today());
System.debug('Note: LAST_WEEK = The previous calendar week (Sunday-Saturday)');

// Also check all pain points
System.debug('');
System.debug('--- All Pain Points ---');
List<Identified_Pain_Point__c> pps = [SELECT Id, Unique_Key__c, Object_API_Name__c, Occurrences__c, Status__c FROM Identified_Pain_Point__c];
for (Identified_Pain_Point__c pp : pps) {
    System.debug(pp.Unique_Key__c + ' | Object: ' + pp.Object_API_Name__c + ' | Occurrences: ' + pp.Occurrences__c + ' | Status: ' + pp.Status__c);
}
