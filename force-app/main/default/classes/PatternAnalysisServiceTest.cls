/**
 * @description Test class for PatternAnalysisService.
 * @version 5.0 - Hardened tests to account for dismissal logic and explicit finish method call.
 */
@isTest
private class PatternAnalysisServiceTest {

    @TestSetup
    static void setupData() {
        // Create a dedicated user for this test to avoid conflicts with dismissals
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User testUser = new User(
            Alias = 'testpas', Email='testpas@testorg.com', EmailEncodingKey='UTF-8',
            LastName='Testing', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
            ProfileId = p.Id, TimeZoneSidKey='America/Los_Angeles', UserName='testpas@testorg.com'
        );
        insert testUser;
    }

    @isTest
    static void testSequentialPatternDetection_And_HealthLogging() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas'];
        
        // ARRANGE: Run test as the dedicated test user
        System.runAs(testUser) {
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

            List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 6; i++) {
                logs.add(new Behavior_Log__c(
                    Action_Name__c = 'Record_Created', Object_API_Name__c = 'Contact',
                    Record_ID__c = contacts[i].Id, User__c = testUser.Id
                ));
                logs.add(new Behavior_Log__c(
                    Action_Name__c = 'Record_Created', Object_API_Name__c = 'Task',
                    Record_ID__c = tasks[i].Id, User__c = testUser.Id
                ));
            }
            insert logs;
            
            for (Integer i = 0; i < logs.size(); i += 2) {
                Datetime contactTime = Datetime.now().addMinutes(i * -10);
                Test.setCreatedDate(logs[i].Id, contactTime);
                Test.setCreatedDate(logs[i+1].Id, contactTime.addSeconds(30));
            }

            // ACT
            Test.startTest();
                PatternAnalysisService service = new PatternAnalysisService();
                Database.executeBatch(service);
            Test.stopTest(); // Batch execute runs, finish method is called automatically

            // ASSERT: Verify Pain Point
            List<Identified_Pain_Point__c> pps = [SELECT Id, Occurrences__c FROM Identified_Pain_Point__c];
            System.assertEquals(1, pps.size(), 'One pain point record should have been created.');
            System.assertEquals(6, pps[0].Occurrences__c, 'Should detect 6 sequential actions.');

            // ASSERT: Verify Health Log
            List<System_Health_Log__c> healthLogs = [SELECT Id FROM System_Health_Log__c];
            System.assertEquals(1, healthLogs.size(), 'A health log should be created by the finish method.');
        }
    }

    @isTest
    static void testDataRetention_DeletesOldLogs() {
        // ARRANGE
        List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            oldLogs.add(new Behavior_Log__c(Action_Name__c = 'Old_Action'));
        }
        insert oldLogs;

        for(Behavior_Log__c log : oldLogs){
            Test.setCreatedDate(log.Id, Date.today().addDays(-100));
        }

        // ACT
        Test.startTest();
            PatternAnalysisService service = new PatternAnalysisService();
            // We need a dummy BatchableContext to call the finish method
            String jobId = Database.executeBatch(service);
            // Get the BatchableContext from the job ID.
            // This is a bit of a workaround to simulate the context.
            // In a real scenario, the platform provides this context.
            // For testing the `finish` method in isolation, this is a standard approach.
            // However, since Test.stopTest() already invokes `finish`, we can rely on that.
        Test.stopTest();

        // ASSERT
        Integer remainingLogs = [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'Old_Action'];
        System.assertEquals(0, remainingLogs, 'Old logs should have been deleted by the finish method.');
    }
}
