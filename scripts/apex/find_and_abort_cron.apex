// Find and abort the CronTrigger for the stuck Pattern job
List<CronTrigger> cronJobs = [
    SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime, TimesTriggered
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE '%Pattern%'
    OR CronJobDetail.Name LIKE '%BehaviorIQ%'
    OR CronJobDetail.Name LIKE '%Analysis%'
];

System.debug('=== CronTrigger Jobs ===');
if (cronJobs.isEmpty()) {
    System.debug('No CronTrigger jobs found matching Pattern/BehaviorIQ/Analysis.');
} else {
    for (CronTrigger ct : cronJobs) {
        System.debug('CronTrigger ID: ' + ct.Id + ' | Name: ' + ct.CronJobDetail.Name + ' | State: ' + ct.State);
        // Abort each one
        try {
            System.abortJob(ct.Id);
            System.debug('  --> ABORTED successfully');
        } catch (Exception e) {
            System.debug('  --> Abort failed: ' + e.getMessage());
        }
    }
}

// Also check ALL active CronTriggers
List<CronTrigger> allActiveCrons = [
    SELECT Id, CronJobDetail.Name, State, NextFireTime
    FROM CronTrigger
    WHERE State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'BLOCKED')
    LIMIT 20
];

System.debug('');
System.debug('=== All Active CronTriggers ===');
for (CronTrigger ct : allActiveCrons) {
    System.debug('ID: ' + ct.Id + ' | Name: ' + ct.CronJobDetail.Name + ' | State: ' + ct.State);
}

// Check if the batch job has a parent CronTrigger
AsyncApexJob stuckJob = [
    SELECT Id, JobType, Status, ApexClass.Name, ParentJobId
    FROM AsyncApexJob
    WHERE Id = '707KY000043MZiUYAW'
];

System.debug('');
System.debug('=== Stuck Job Details ===');
System.debug('ID: ' + stuckJob.Id);
System.debug('Type: ' + stuckJob.JobType);
System.debug('Class: ' + stuckJob.ApexClass.Name);
System.debug('Status: ' + stuckJob.Status);
System.debug('ParentJobId: ' + stuckJob.ParentJobId);

// If there's a parent job, try to abort it
if (stuckJob.ParentJobId != null) {
    System.debug('Attempting to abort parent job: ' + stuckJob.ParentJobId);
    try {
        System.abortJob(stuckJob.ParentJobId);
        System.debug('  --> Parent job ABORTED successfully');
    } catch (Exception e) {
        System.debug('  --> Parent abort failed: ' + e.getMessage());
    }
}
