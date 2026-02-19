// Check batch job status
List<AsyncApexJob> jobs = [
    SELECT Status, NumberOfErrors, ExtendedStatus, TotalJobItems, JobItemsProcessed, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'PatternAnalysisService'
    ORDER BY CreatedDate DESC
    LIMIT 3
];
System.debug('=== BATCH JOB STATUS ===');
for (AsyncApexJob job : jobs) {
    System.debug('Status: ' + job.Status + ' | Errors: ' + job.NumberOfErrors +
                 ' | Items: ' + job.JobItemsProcessed + '/' + job.TotalJobItems +
                 ' | Created: ' + job.CreatedDate);
}

// Check for the 4 missing pain points
System.debug('');
System.debug('=== CHECKING FOR MISSING PATTERNS ===');
List<Identified_Pain_Point__c> painPoints = [
    SELECT Unique_Key__c, Occurrences__c, Last_Detected__c, Status__c
    FROM Identified_Pain_Point__c
    WHERE Unique_Key__c IN (
        'Missing_Attachment_Closed_Case',
        'Missing_Attachment_Closed_Won',
        'Stale_Opp_90',
        'Unassigned_Lead_48'
    )
];

if (painPoints.isEmpty()) {
    System.debug('None of the 4 patterns detected yet');
} else {
    for (Identified_Pain_Point__c pp : painPoints) {
        System.debug(pp.Unique_Key__c + ': ' + pp.Occurrences__c + ' occurrences | Last: ' + pp.Last_Detected__c);
    }
}

// Total pain point count
Integer totalPP = [SELECT COUNT() FROM Identified_Pain_Point__c];
System.debug('');
System.debug('Total Pain Points in system: ' + totalPP);
