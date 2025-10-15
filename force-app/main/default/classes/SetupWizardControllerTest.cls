/**
 * @description Test class for SetupWizardController.
 * @version 2.4 - Uses test hook simulation for deterministic duplicate-job validation.
 */
@isTest
private class SetupWizardControllerTest {

    @isTest
    static void testGetTrackableObjects_ReturnsObjects() {
        Test.startTest();
        List<SetupWizardController.TrackableObject> results = SetupWizardController.getTrackableObjects();
        Test.stopTest();

        System.assertNotEquals(0, results.size(), 'Should return a list of trackable objects.');
    }

    @isTest
    static void testScheduleAnalysisJob_Success() {
        Test.startTest();
        String jobId = SetupWizardController.scheduleAnalysisJob();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'A job ID should be returned.');
        List<CronTrigger> scheduledJobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, scheduledJobs.size(), 'One job should be scheduled.');
    }

    @isTest
    static void testScheduleAnalysisJob_PreventsDuplicates() {
        // Simulate duplicate scenario using the test hook
        SetupWizardController.testHook_simulateDuplicateJob = true;
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            SetupWizardController.scheduleAnalysisJob();
        } catch (AuraHandledException e) {
            // SUCCESS: The correct exception type was caught.
            // This confirms the duplicate prevention logic was triggered.
            exceptionThrown = true;
        }
        Test.stopTest();

        // Assert that the expected exception was thrown and caught.
        System.assert(exceptionThrown, 'An AuraHandledException should have been thrown to prevent a duplicate job.');
    }

    @isTest
    static void testSaveMonitoringSettings_Success() {
        List<String> objectsToMonitor = new List<String>{'Account', 'Opportunity'};

        Test.startTest();
        SetupWizardController.saveMonitoringSettings(objectsToMonitor);
        Test.stopTest();

        OrgPulse_Configuration__c settings = OrgPulse_Configuration__c.getOrgDefaults();
        System.assertNotEquals(null, settings, 'Settings record should exist.');
        System.assertEquals('Account,Opportunity', settings.Monitored_Objects__c);
    }
}