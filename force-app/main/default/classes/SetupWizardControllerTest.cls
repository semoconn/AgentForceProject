/**
 * @description       : Test class for the SetupWizardController.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-13-2025
 * @last modified by  : Gemini
**/
@isTest
private class SetupWizardControllerTest {

    @isTest
    static void testGetTrackableObjects_ReturnsObjects() {
        // Arrange
        Test.startTest();
        // Act
        List<SetupWizardController.TrackableObject> results = SetupWizardController.getTrackableObjects();
        Test.stopTest();

        // Assert
        System.assertNotEquals(0, results.size(), 'Should return a list of trackable objects.');
        
        Boolean foundAccount = false;
        for (SetupWizardController.TrackableObject obj : results) {
            if (obj.apiName == 'Account') {
                foundAccount = true;
                System.assertEquals('Account', obj.label, 'The label for Account should be "Account".');
            }
        }
        System.assert(foundAccount, 'The list should include the Account object.');
    }

    @isTest
    static void testScheduleAnalysisJob_Success() {
        // Arrange
        Test.startTest();
        // Act
        String jobId = SetupWizardController.scheduleAnalysisJob();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, jobId, 'A job ID should be returned upon successful scheduling.');

        List<CronTrigger> scheduledJobs = [SELECT Id FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, scheduledJobs.size(), 'One job should be scheduled.');
    }

    @isTest
    static void testScheduleAnalysisJob_PreventsDuplicates() {
        // Arrange: Schedule the job once
        System.schedule('OrgPulse Nightly Analysis', '0 0 2 * * ?', new PatternAnalysisService());

        String exceptionMessage = '';
        Test.startTest();
        try {
            // Act: Attempt to schedule it again
            SetupWizardController.scheduleAnalysisJob();
        } catch (AuraHandledException e) {
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        // Assert
        System.assert(exceptionMessage.contains('already scheduled'), 'Should throw an exception if the job is already scheduled.');
    }
    
    @isTest
    static void testSaveMonitoringSettings_Success() {
        // Arrange
        List<String> objectsToMonitor = new List<String>{'Account', 'Opportunity'};

        Test.startTest();
        // Act
        SetupWizardController.saveMonitoringSettings(objectsToMonitor);
        Test.stopTest();

        // Assert
        OrgPulse_Configuration__c settings = OrgPulse_Configuration__c.getOrgDefaults();
        System.assertNotEquals(null, settings, 'Custom setting record should be created.');
        System.assertEquals('Account,Opportunity', settings.Monitored_Objects__c, 'The monitored objects should be saved correctly.');
    }
}

