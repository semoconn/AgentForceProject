@isTest
private class WorkflowSuggestionControllerTest {

    @TestSetup
    static void makeData() {
        // Just create the test account - Custom Metadata is already available!
        Account testAccount = new Account(Name='Test Account');
        insert testAccount;
    }

    @isTest
    static void testLogWorkflowEvent() {
        // ARRANGE
        delete [SELECT Id FROM Workflow_Log__c];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        String actionName = 'Test_Action';

        // ACT
        Test.startTest();
            WorkflowSuggestionController.logWorkflowEvent(acc.Id, 'Account', actionName, '{"test":true}');
            WorkflowSuggestionController.commitLogs();
        Test.stopTest();

        // ASSERT
        List<Workflow_Log__c> logs = [SELECT Id, Action_Name__c FROM Workflow_Log__c WHERE Record_ID__c = :acc.Id];
        System.assertEquals(1, logs.size(), 'A single log record should have been created.');
        System.assertEquals(actionName, logs[0].Action_Name__c, 'The Action_Name__c should match.');
    }

    @isTest
    static void testCheckForPatterns() {
        // ARRANGE
        delete [SELECT Id FROM Workflow_Log__c];
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        String actionName = 'Frequent_Action';
        
        WorkflowSuggestionController.logWorkflowEvent(acc.Id, 'Account', actionName, '{"num":1}');
        WorkflowSuggestionController.logWorkflowEvent(acc.Id, 'Account', actionName, '{"num":2}');
        WorkflowSuggestionController.logWorkflowEvent(acc.Id, 'Account', actionName, '{"num":3}');

        // ACT
        Test.startTest();
            WorkflowSuggestionController.commitLogs();
        Test.stopTest();

        // ASSERT
        List<Workflow_Log__c> insightLogs = [
            SELECT Id, Action_Name__c 
            FROM Workflow_Log__c 
            WHERE Action_Name__c = 'INSIGHT_GENERATED'
        ];
        System.assertEquals(1, insightLogs.size(), 'An insight log should be generated.');
    }

    @isTest
    static void testShouldShowSuggestion_True() {
        // ARRANGE
        delete [SELECT Id FROM Workflow_Log__c];
        
        String actionName = 'Record_Created'; 
        for (Integer i = 0; i < 5; i++) {
             WorkflowSuggestionController.logWorkflowEvent(null, 'Account', actionName, '{}');
        }
        WorkflowSuggestionController.commitLogs();

        // ACT
        Test.startTest();
            Boolean shouldShow = WorkflowSuggestionController.shouldShowSuggestion(null, 'Account');
        Test.stopTest();

        // ASSERT
        System.assertEquals(true, shouldShow, 'Should return true for 5 or more logs.');
    }

    @isTest
    static void testShouldShowSuggestion_False() {
        // ARRANGE
        delete [SELECT Id FROM Workflow_Log__c];

        String actionName = 'Record_Created'; 
        for (Integer i = 0; i < 4; i++) {
             WorkflowSuggestionController.logWorkflowEvent(null, 'Account', actionName, '{}');
        }
        WorkflowSuggestionController.commitLogs();

        // ACT
        Test.startTest();
            Boolean shouldShow = WorkflowSuggestionController.shouldShowSuggestion(null, 'Account');
        Test.stopTest();

        // ASSERT
        System.assertEquals(false, shouldShow, 'Should return false for fewer than 5 logs.');
    }
    
    @isTest
    static void testDismissSuggestion() {
        // ACT
        Test.startTest();
            WorkflowSuggestionController.dismissSuggestion('Account', 'Record_Created');
        Test.stopTest();
        
        // ASSERT
        List<Suggestion_Dismissal__c> dismissals = [SELECT Id FROM Suggestion_Dismissal__c];
        System.assertEquals(1, dismissals.size(), 'A dismissal record should be created.');
    }
}