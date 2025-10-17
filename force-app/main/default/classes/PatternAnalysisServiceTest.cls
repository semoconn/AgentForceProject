/**
 * @description Test class for PatternAnalysisService. Ensures accurate detection, cleanup, and health logging behavior.
 * @version 4.0 - Production-ready test suite.
 */
@isTest
private class PatternAnalysisServiceTest {

    @TestSetup
    static void setupData() {
        // No setup data needed here to ensure tests are isolated
    }

    @isTest
    static void testSequentialPatternDetection_And_HealthLogging() {
        // ARRANGE: Create test data that fits the pattern
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 6; i++) {
            contacts.add(new Contact(LastName = 'Contact' + i));
        }
        insert contacts;

        List<Task> tasks = new List<Task>();
        for (Contact c : contacts) {
            tasks.add(new Task(Subject = 'Follow Up', WhoId = c.Id));
        }
        insert tasks;

        // Create Behavior Logs that mimic the user action
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 6; i++) {
            // Simulate Contact creation log
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created', Object_API_Name__c = 'Contact',
                Record_ID__c = contacts[i].Id, User__c = UserInfo.getUserId()
            ));
            // Simulate immediate Task creation log
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created', Object_API_Name__c = 'Task',
                Record_ID__c = tasks[i].Id, User__c = UserInfo.getUserId()
            ));
        }
        insert logs;
        
        // Use Test.setCreatedDate to ensure logs are within the 5-minute detection window
        for (Integer i = 0; i < logs.size(); i += 2) {
            Datetime contactTime = Datetime.now().addMinutes(i * -10); // set in the past to ensure they are found
            Test.setCreatedDate(logs[i].Id, contactTime);
            Test.setCreatedDate(logs[i+1].Id, contactTime.addSeconds(30));
        }

        // ACT
        Test.startTest();
            Database.executeBatch(new PatternAnalysisService());
        Test.stopTest();

        // ASSERT: Verify Pain Point was created correctly
        List<Identified_Pain_Point__c> pps = [SELECT Id, Occurrences__c, Impact_Score__c FROM Identified_Pain_Point__c];
        System.assertEquals(1, pps.size(), 'One pain point record should have been created.');
        System.assertEquals(6, pps[0].Occurrences__c, 'Should detect 6 sequential actions.');
        System.assertEquals(60, pps[0].Impact_Score__c, 'Impact score should match occurrences * 10.');

        // ASSERT: Verify a health log was created
        List<System_Health_Log__c> healthLogs = [SELECT Id FROM System_Health_Log__c];
        System.assertEquals(1, healthLogs.size(), 'A health log should be created for the job.');
    }

    @isTest
    static void testDataRetention_DeletesOldLogs() {
        // ARRANGE: Create old logs that should be deleted
        List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            oldLogs.add(new Behavior_Log__c(Action_Name__c = 'Old_Action'));
        }
        insert oldLogs;

        // Set their created date to be older than the 90-day retention period
        for(Behavior_Log__c log : oldLogs){
            Test.setCreatedDate(log.Id, Date.today().addDays(-100));
        }

        // ACT
        Test.startTest();
            Database.executeBatch(new PatternAnalysisService());
        Test.stopTest();

        // ASSERT: Verify the old logs were deleted
        Integer remainingLogs = [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'Old_Action'];
        System.assertEquals(0, remainingLogs, 'Old logs should have been deleted by the finish method.');
    }
}