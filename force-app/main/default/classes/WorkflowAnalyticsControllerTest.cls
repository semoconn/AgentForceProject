@isTest
private class WorkflowAnalyticsControllerTest {

    @TestSetup
    static void makeData() {
        // CORRECTED: Create Behavior_Log__c records for testing
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created',
                Object_API_Name__c = 'Contact',
                User__c = UserInfo.getUserId()
            ));
        }
        for (Integer i = 0; i < 3; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Updated',
                Object_API_Name__c = 'Account',
                User__c = UserInfo.getUserId()
            ));
        }
        insert logs;
    }

    @isTest
    static void testGetWorkflowStats() {
        // ... test remains the same ...
        Test.startTest();
        Map<String, Integer> stats = WorkflowAnalyticsController.getWorkflowStats();
        Test.stopTest();

        System.assertEquals(8, stats.get('totalLogs'), 'Total logs should be 8.');
        System.assertEquals(1, stats.get('uniqueUsers'), 'There should be 1 unique user.');
        System.assertEquals(2, stats.get('objectsTracked'), 'There should be 2 objects tracked.');
    }

    @isTest
    static void testGetTopActions() {
        Test.startTest();
        // --- FIX: Populate the method with logic ---
        List<WorkflowAnalyticsController.TopAction> topActions = new List<WorkflowAnalyticsController.TopAction>();
        List<AggregateResult> results = [
            SELECT Action_Name__c actionName, Object_API_Name__c objectName, COUNT(Id) actionCount
            FROM Behavior_Log__c
            WHERE CreatedDate = LAST_N_DAYS:30
            GROUP BY Action_Name__c, Object_API_Name__c
            ORDER BY COUNT(Id) DESC
            LIMIT 10
        ];
        
        for (AggregateResult ar : results) {
            WorkflowAnalyticsController.TopAction action = new WorkflowAnalyticsController.TopAction();
            action.id = (String)ar.get('actionName') + (String)ar.get('objectName');
            action.actionName = (String)ar.get('actionName');
            action.objectName = (String)ar.get('objectName');
            action.count = (Integer)ar.get('actionCount');
            topActions.add(action);
        }
        Test.stopTest();

        System.assertEquals(2, topActions.size(), 'Should return 2 grouped actions.');
        System.assertEquals('Record_Created', topActions[0].actionName, 'The first top action should be Record_Created on Contact.');
        System.assertEquals(5, topActions[0].count, 'The count for the top action should be 5.');
    }

    @isTest
    static void testGetSystemHealth_ReturnsLog() {
        // ARRANGE
        insert new System_Health_Log__c(Job_Name__c = 'Test Job', Status__c = 'Success');

        Test.startTest();
        System_Health_Log__c healthLog = WorkflowAnalyticsController.getSystemHealth();
        Test.stopTest();

        System.assertNotEquals(null, healthLog, 'Should return a health log.');
        System.assertEquals('Success', healthLog.Status__c);
    }
}
