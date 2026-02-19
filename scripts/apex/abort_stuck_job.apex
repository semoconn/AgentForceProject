// Abort stuck PatternAnalysisService job
String stuckJobId = '707KY000043MZiUYAW';

try {
    System.abortJob(stuckJobId);
    System.debug('SUCCESS: Aborted stuck job ' + stuckJobId);
} catch (Exception e) {
    System.debug('ERROR aborting job: ' + e.getMessage());
}

// Verify the job was aborted
AsyncApexJob job = [
    SELECT Id, Status, ApexClass.Name
    FROM AsyncApexJob
    WHERE Id = :stuckJobId
    LIMIT 1
];
System.debug('Job status after abort: ' + job.Status);

// Check if any other jobs are still blocking
List<AsyncApexJob> remainingJobs = [
    SELECT Id, ApexClass.Name, Status, CreatedDate
    FROM AsyncApexJob
    WHERE Status IN ('Queued', 'Preparing', 'Processing', 'Holding')
    AND ApexClass.Name LIKE '%Pattern%'
];

if (remainingJobs.isEmpty()) {
    System.debug('No more blocking Pattern jobs. You can now run a fresh analysis.');
} else {
    System.debug('WARNING: Still have ' + remainingJobs.size() + ' blocking jobs:');
    for (AsyncApexJob j : remainingJobs) {
        System.debug('  ' + j.Id + ' - ' + j.ApexClass.Name + ' - ' + j.Status);
    }
}
