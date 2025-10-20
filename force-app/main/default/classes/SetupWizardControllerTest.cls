/**
 * @description Test class for SetupWizardController.
 * @version 3.0 - Added cleanup for scheduled jobs to ensure test isolation.
 */
@isTest
private class SetupWizardControllerTest {

    @isTest
    static void testGetTrackableObjects_ReturnsObjects() {
        // ... test remains the same ...
        Test.startTest();
        List<SetupWizardController.TrackableObject> results = SetupWizardController.getTrackableObjects();
        Test.stopTest();
        System.assertNotEquals(0, results.size(), 'Should return a list of trackable objects.');
    }

    @isTest
    static void testScheduleAnalysisJob_Success() {
        // --- NEW: Clean up any existing jobs from other tests ---
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'OrgPulse Nightly Analysis']) {
            System.abortJob(ct.Id);
        }

        Test.startTest();
        String jobId = SetupWizardController.scheduleAnalysisJob();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'A job ID should be returned.');
        List<CronTrigger> scheduledJobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, scheduledJobs.size(), 'One job should be scheduled.');
    }

    @isTest
    static void testScheduleAnalysisJob_PreventsDuplicates() {
        // ... test remains the same ...
        SetupWizardController.testHook_simulateDuplicateJob = true;
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            SetupWizardController.scheduleAnalysisJob();
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'An AuraHandledException should have been thrown to prevent a duplicate job.');
    }

    @isTest
    static void testSaveMonitoringSettings_Success() {
        // ... test remains the same ...
        List<String> objectsToMonitor = new List<String>{'Account', 'Opportunity'};
        Test.startTest();
        SetupWizardController.saveMonitoringSettings(objectsToMonitor);
        Test.stopTest();
        OrgPulse_Configuration__c settings = OrgPulse_Configuration__c.getOrgDefaults();
        System.assertNotEquals(null, settings, 'Settings record should exist.');
        System.assertEquals('Account,Opportunity', settings.Monitored_Objects__c);
    }
}
