// Abort ALL scheduled Apex jobs to unblock deployment
List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, State FROM CronTrigger WHERE CronJobDetail.JobType = '7'];
System.debug('Found ' + jobs.size() + ' scheduled jobs');
for (CronTrigger ct : jobs) {
    System.debug('Aborting: ' + ct.CronJobDetail.Name + ' (' + ct.Id + ') - State: ' + ct.State);
    System.abortJob(ct.Id);
}

// Also abort any running async/batch jobs
List<AsyncApexJob> asyncJobs = [SELECT Id, JobType, Status, ApexClass.Name FROM AsyncApexJob WHERE Status IN ('Holding', 'Queued', 'Preparing', 'Processing')];
System.debug('Found ' + asyncJobs.size() + ' async jobs');
for (AsyncApexJob aj : asyncJobs) {
    System.debug('Aborting async: ' + aj.ApexClass.Name + ' (' + aj.Id + ') - ' + aj.Status);
    System.abortJob(aj.Id);
}
