// Check for any running or queued batch jobs
List<AsyncApexJob> jobs = [
    SELECT Id, JobType, ApexClass.Name, Status, NumberOfErrors,
           JobItemsProcessed, TotalJobItems, CreatedDate, CompletedDate
    FROM AsyncApexJob
    WHERE Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
    OR (Status = 'Completed' AND CreatedDate = TODAY)
    ORDER BY CreatedDate DESC
    LIMIT 20
];

System.debug('=== Async Apex Jobs ===');
if (jobs.isEmpty()) {
    System.debug('No active or recent jobs found.');
} else {
    for (AsyncApexJob job : jobs) {
        System.debug('Job: ' + job.ApexClass.Name + ' | Status: ' + job.Status +
                     ' | Created: ' + job.CreatedDate + ' | Items: ' + job.JobItemsProcessed + '/' + job.TotalJobItems);
    }
}

// Check for Pattern Analysis specific jobs
List<AsyncApexJob> patternJobs = [
    SELECT Id, JobType, ApexClass.Name, Status, NumberOfErrors, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name LIKE '%Pattern%'
    ORDER BY CreatedDate DESC
    LIMIT 10
];

System.debug('');
System.debug('=== Pattern Analysis Jobs ===');
for (AsyncApexJob job : patternJobs) {
    System.debug('Job ID: ' + job.Id + ' | Class: ' + job.ApexClass.Name + ' | Status: ' + job.Status + ' | Created: ' + job.CreatedDate);
}

// Check System Health Logs for any errors
List<System_Health_Log__c> healthLogs = [
    SELECT Id, Name, Job_ID__c, Status__c, Error_Count__c, Error_Details__c, CreatedDate
    FROM System_Health_Log__c
    ORDER BY CreatedDate DESC
    LIMIT 5
];

System.debug('');
System.debug('=== System Health Logs ===');
for (System_Health_Log__c log : healthLogs) {
    System.debug('Log: ' + log.Name + ' | Job: ' + log.Job_ID__c + ' | Status: ' + log.Status__c + ' | Errors: ' + log.Error_Count__c);
    if (log.Error_Details__c != null) {
        System.debug('  Error Details: ' + log.Error_Details__c.left(200));
    }
}
