List<AsyncApexJob> jobs = [SELECT Id, Status, JobType, ApexClass.Name, NumberOfErrors, JobItemsProcessed, TotalJobItems FROM AsyncApexJob WHERE JobType = 'BatchApex' ORDER BY CreatedDate DESC LIMIT 3];
for(AsyncApexJob j : jobs) { System.debug('Job: ' + j.ApexClass.Name + ' | Status: ' + j.Status + ' | Items: ' + j.JobItemsProcessed + '/' + j.TotalJobItems); }
