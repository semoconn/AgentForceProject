// Check configuration
System.debug('=== Configuration Check ===');
List<BehaviorIQ_Configuration__c> configs = [SELECT Id, Monitored_Objects__c FROM BehaviorIQ_Configuration__c LIMIT 5];
for (BehaviorIQ_Configuration__c config : configs) {
    System.debug('Config ID: ' + config.Id);
    System.debug('Monitored Objects: ' + config.Monitored_Objects__c);
}

// Check the existing pain points
System.debug('');
System.debug('=== Existing Pain Points ===');
List<Identified_Pain_Point__c> painPoints = [SELECT Id, Unique_Key__c, Description__c, Status__c, Object_API_Name__c, Occurrences__c FROM Identified_Pain_Point__c LIMIT 10];
for (Identified_Pain_Point__c pp : painPoints) {
    System.debug('Key: ' + pp.Unique_Key__c + ' | Object: ' + pp.Object_API_Name__c + ' | Status: ' + pp.Status__c + ' | Occurrences: ' + pp.Occurrences__c);
    System.debug('Description: ' + pp.Description__c);
}

// Abort stuck queued job
System.debug('');
System.debug('=== Aborting Stuck Jobs ===');
List<AsyncApexJob> queuedJobs = [
    SELECT Id, Status, ApexClass.Name
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'PatternAnalysisService'
    AND Status = 'Queued'
];

for (AsyncApexJob job : queuedJobs) {
    try {
        System.abortJob(job.Id);
        System.debug('Aborted job: ' + job.Id);
    } catch (Exception e) {
        System.debug('Error aborting job: ' + e.getMessage());
    }
}
