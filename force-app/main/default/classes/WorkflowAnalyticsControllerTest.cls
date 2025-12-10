@isTest
private class WorkflowAnalyticsControllerTest {

    @testSetup
    static void setup() {
        // 1. Setup License (Premium)
        // FIX: Used SetupOwnerId for correct Org-level default and Status 'Premium' to ensure isPremium() returns true
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Premium'
        );
        insert license;

        // 2. Setup Pain Points
        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        points.add(new Identified_Pain_Point__c(
            Name = 'Stale Opportunities',
            Object_API_Name__c = 'Opportunity',
            Status__c = 'New', 
            Impact_Score__c = 80,
            Description__c = 'Test Description',
            Unique_Key__c = 'Test_Opp_Key',
            Occurrences__c = 1
        ));
        insert points;

        // 3. Setup Behavior Logs
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Created',
                Object_API_Name__c = 'Contact',
                User__c = UserInfo.getUserId(),
                Timestamp__c = System.now()
            ));
        }
        for (Integer i = 0; i < 3; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Record_Updated',
                Object_API_Name__c = 'Account',
                User__c = UserInfo.getUserId(),
                Timestamp__c = System.now()
            ));
        }
        insert logs;

        // 4. Create System_Health_Log__c
        insert new System_Health_Log__c(Job_Name__c = 'Test Job', Status__c = 'Success');

        // 5. Setup Records for Auto-Fix
        Case c = new Case(Subject = 'Fix Me', Status = 'New');
        insert c;

        Lead l = new Lead(LastName = 'Fix Me Lead', Company = 'Fix Me Co', Status = 'Open');
        insert l;
    }

    // --- EXISTING AUTO-FIX TESTS ---

    @isTest
    static void testGetPainPoints() {
        // We do NOT update status to 'Active' here anymore, as 'New' is the valid schema value.
        // The Controller has been updated to query for 'New'.
        
        Test.startTest();
        List<Identified_Pain_Point__c> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return 1 pain point');
    }

    @isTest
    static void testDismissSuggestion() {
        Identified_Pain_Point__c point = [SELECT Id FROM Identified_Pain_Point__c LIMIT 1];

        Test.startTest();
        String result = WorkflowAnalyticsController.dismissSuggestion(point.Id);
        Test.stopTest();

        System.assertEquals('Suggestion dismissed successfully.', result);
        
        Identified_Pain_Point__c updatedPoint = [SELECT Status__c FROM Identified_Pain_Point__c WHERE Id = :point.Id];
        System.assertEquals('Dismissed', updatedPoint.Status__c);
    }

    @isTest
    static void testRunAutoFix_StaleCase() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<Id> recordIds = new List<Id>{c.Id};

        Test.startTest();
        String result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Case');
        Test.stopTest();

        System.assert(result.contains('Success'), 'Should return success message');
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created via Service');
    }

    @isTest
    static void testRunAutoFix_UnassignedLead() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        List<Id> recordIds = new List<Id>{l.Id};

        Test.startTest();
        String result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Unassigned Lead');
        Test.stopTest();

        System.assert(result.contains('Success'), 'Should return success message');
        Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(UserInfo.getUserId(), updatedLead.OwnerId, 'Owner should be updated');
    }

    @isTest
    static void testRunAutoFix_InvalidType() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(new List<Id>{c.Id}, 'Invalid Type');
            System.assert(false, 'Should throw exception for unknown type');
        } catch (AuraHandledException e) {
            System.assert(true); // Expected
        } catch (Exception e) {
             System.assert(true); // Generic exception also acceptable if wrapped
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_EmptyList() {
        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(new List<Id>(), 'Stale Case');
            System.assert(false, 'Should throw exception for empty list');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage()); 
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_NoLicense() {
        // Remove license to simulate Free
        delete [SELECT Id FROM BehaviorIQ_License__c];

        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(new List<Id>{c.Id}, 'Stale Case');
            System.assert(false, 'Should throw exception for missing license');
        } catch (AuraHandledException e) {
            System.assert(true); // Expected
        }
        Test.stopTest();
    }

    // --- NEW ANALYTICS & DASHBOARD TESTS ---

    @isTest
    static void testGetWorkflowStats() {
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
        List<WorkflowAnalyticsController.TopAction> topActions = WorkflowAnalyticsController.getTopActions();
        Test.stopTest();

        // Check for the main action
        WorkflowAnalyticsController.TopAction contactAction;
        for(WorkflowAnalyticsController.TopAction ta : topActions) {
            if(ta.actionName == 'Record_Created') contactAction = ta;
        }
        
        System.assertNotEquals(null, contactAction, 'Record_Created action should exist');
        System.assertEquals(5, contactAction.count, 'The count for the top action should be 5.');
    }

    @isTest
    static void testGetSystemHealth_ReturnsLog() {
        Test.startTest();
        System_Health_Log__c healthLog = WorkflowAnalyticsController.getSystemHealth();
        Test.stopTest();

        System.assertNotEquals(null, healthLog, 'Should return a health log.');
        System.assertEquals('Success', healthLog.Status__c);
    }

    @isTest
    static void testGetDashboardData_Free() {
        // Remove license to test Free state logic in Dashboard wrapper
        delete [SELECT Id FROM BehaviorIQ_License__c];

        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper result = WorkflowAnalyticsController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.isPremium, 'Should default to Free without license');
        
        // Verify data flows
        System.assert(result.recentLogs.size() > 0, 'Recent logs should be returned');
        System.assertNotEquals(null, result.metrics, 'Metrics list should be initialized');
    }

    @isTest
    static void testGetDashboardData_Premium() {
        // License already exists from @testSetup
        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper result = WorkflowAnalyticsController.getDashboardData();
        Test.stopTest();

        System.assertEquals(true, result.isPremium, 'Should identify Premium user');
        System.assert(result.metrics.size() > 0, 'Should return metrics including Active anomalies');
    }
}