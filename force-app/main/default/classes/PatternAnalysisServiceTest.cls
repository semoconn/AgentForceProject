/**
 * @description Test class for PatternAnalysisService.
 * Ensures accurate detection, cleanup, and health logging behavior.
 * @version 3.0 - Enterprise test coverage including cleanup & job logging.
 */
@isTest
private class PatternAnalysisServiceTest {

    @TestSetup
    static void setupData() {
        insert new Account(Name = 'Test Account');
    }

    @isTest
    static void testSequentialPatternDetection() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Create related Contacts and Tasks
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 6; i++) {
            contacts.add(new Contact(LastName = 'Contact' + i, AccountId = acc.Id));
        }
        insert contacts;

        List<Task> tasks = new List<Task>();
        for (Contact c : contacts) {
            tasks.add(new Task(Subject = 'Follow Up', WhoId = c.Id));
        }
        insert tasks;

        // Create Behavior Logs
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 6; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created',
                Object_API_Name__c = 'Contact',
                Record_ID__c = contacts[i].Id,
                User__c = UserInfo.getUserId()
            ));
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created',
                Object_API_Name__c = 'Task',
                Record_ID__c = tasks[i].Id,
                User__c = UserInfo.getUserId()
            ));
        }
        insert logs;

        // Set timestamps for detection window
        for (Integer i = 0; i < logs.size(); i += 2) {
            Datetime contactTime = Datetime.now().addMinutes(i * 10);
            Test.setCreatedDate(logs[i].Id, contactTime);
            Test.setCreatedDate(logs[i + 1].Id, contactTime.addSeconds(30));
        }

        Test.startTest();
            Database.executeBatch(new PatternAnalysisService());
        Test.stopTest();

        Identified_Pain_Point__c pp = [
            SELECT Id, Occurrences__c, Impact_Score__c
            FROM Identified_Pain_Point__c
            WHERE Unique_Key__c = 'Sequential_Action_Contact_Task'
            LIMIT 1
        ];

        System.assertEquals(6, pp.Occurrences__c, 'Should detect 6 sequential actions.');
        System.assertEquals(60, pp.Impact_Score__c, 'Impact score should match occurrences * 10.');
    }

    @isTest
    static void testDataRetentionAndHealthLogging() {
        // Create old logs that are outside the batch query's 1-day scope
        List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            oldLogs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created',
                Object_API_Name__c = 'Contact',
                User__c = UserInfo.getUserId()
            ));
        }
        insert oldLogs;
        
        // Manually set CreatedDate to be old
        for(Behavior_Log__c log : oldLogs){
            Test.setCreatedDate(log.Id, System.now().addDays(-100));
        }

        Test.startTest();
            Database.executeBatch(new PatternAnalysisService());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE CreatedDate < :Date.today().addDays(-90)],
            'Old logs should be deleted.');
        System.assertEquals(1, [SELECT COUNT() FROM System_Health_Log__c WHERE Job_Name__c = 'Pattern Analysis Service'],
            'Health log should be created.');
    }
}

