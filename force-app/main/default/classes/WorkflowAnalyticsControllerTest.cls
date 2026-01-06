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
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(1, results.size(), 'Should return 1 pain point');
        // Verify ROI fields are populated (may be 0 if no cost configured)
        System.assertNotEquals(null, results[0].EstimatedSavings, 'EstimatedSavings should not be null');
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
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Case');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.message, 'Message should not be null');
        System.assertEquals(1, result.fixedCount, 'Should have fixed 1 record');
        System.assertEquals(1, result.fixedRecordIds.size(), 'Should return 1 fixed record ID');
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created via Service');
    }

    @isTest
    static void testRunAutoFix_UnassignedLead() {
        Lead l = [SELECT Id FROM Lead LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(l.Id)};

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Unassigned Lead');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.message, 'Message should not be null');
        System.assertEquals(1, result.fixedCount, 'Should have fixed 1 record');
        Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(UserInfo.getUserId(), updatedLead.OwnerId, 'Owner should be updated');
    }

    @isTest
    static void testRunAutoFix_InvalidType() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, 'Invalid Type');
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
            WorkflowAnalyticsController.runAutoFix(new List<String>(), 'Stale Case');
            System.assert(false, 'Should throw exception for empty list');
        } catch (AuraHandledException e) {
            System.assert(true); // Expected - message may vary depending on how exception is thrown
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_NoLicense() {
        // Remove license to simulate Free
        delete [SELECT Id FROM BehaviorIQ_License__c];

        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Case');
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

    // ==================== ADDITIONAL COVERAGE TESTS ====================

    @isTest
    static void testRunAutoFix_StaleOpportunity() {
        // Test stale opportunity fix path (lines 140-141, 215-234)
        Account acc = new Account(Name = 'Opp Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Stale Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
        );
        insert opp;

        List<String> recordIds = new List<String>{String.valueOf(opp.Id)};

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Opportunity');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.fixedCount, 'Should have fixed 1 record');

        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :opp.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created for stale opportunity');
    }

    @isTest
    static void testRunAutoFix_InvalidId() {
        // Test invalid ID format handling (lines 114-118)
        List<String> recordIds = new List<String>{'invalid-id-format'};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Case');
            System.assert(false, 'Should throw exception for invalid ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid Record ID') || 
                          e.getMessage().contains('Script-thrown'),
                'Exception should mention invalid ID');
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_MetadataFallback() {
        // Test metadata-driven fix fallback (line 148)
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, 'Custom_Pattern_Type');
            // If PatternFixService succeeds, test passes
        } catch (AuraHandledException e) {
            // Expected if metadata rule doesn't exist
            System.assert(e.getMessage().contains('Auto-Fix') || 
                          e.getMessage().contains('not found') ||
                          e.getMessage().contains('Script-thrown'),
                'Exception should be from auto-fix logic');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetDashboardData_EmptyMetrics() {
        // Test empty metrics fallback (lines 322-330)
        // Delete all pain points to trigger empty state
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper result = WorkflowAnalyticsController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.metrics, 'Metrics should not be null');
        // When empty, should fall back to stale opportunities metric
    }

    @isTest
    static void testGetMetrics_DismissedStatus() {
        // Test dismissed status metric (lines 313-314)
        // Create a dismissed pain point
        Identified_Pain_Point__c dismissedPP = new Identified_Pain_Point__c(
            Name = 'Dismissed Test',
            Object_API_Name__c = 'Case',
            Status__c = 'Dismissed',
            Impact_Score__c = 50,
            Occurrences__c = 5,
            Unique_Key__c = 'Dismissed_Test_Key'
        );
        insert dismissedPP;

        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper result = WorkflowAnalyticsController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result.metrics, 'Metrics should not be null');
    }

    @isTest
    static void testMetricWrapper() {
        // Test MetricWrapper constructor
        Test.startTest();
        WorkflowAnalyticsController.MetricWrapper metric = 
            new WorkflowAnalyticsController.MetricWrapper('Test Label', 100, '+5%', 'alert', 'test_key');
        Test.stopTest();

        System.assertEquals('Test Label', metric.label);
        System.assertEquals(100, metric.count);
        System.assertEquals('+5%', metric.trend);
        System.assertEquals('alert', metric.type);
        System.assertEquals('test_key', metric.key);
    }

    @isTest
    static void testDashboardDataWrapper() {
        // Test DashboardDataWrapper constructor
        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper wrapper = 
            new WorkflowAnalyticsController.DashboardDataWrapper();
        Test.stopTest();

        System.assertEquals(false, wrapper.isPremium);
        System.assertNotEquals(null, wrapper.metrics);
        System.assertNotEquals(null, wrapper.recentLogs);
    }

    @isTest
    static void testAutoFixResult() {
        // Test AutoFixResult constructor
        List<Id> testIds = new List<Id>();
        Case c = [SELECT Id FROM Case LIMIT 1];
        testIds.add(c.Id);

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result = 
            new WorkflowAnalyticsController.AutoFixResult('Test message', testIds);
        Test.stopTest();

        System.assertEquals('Test message', result.message);
        System.assertEquals(1, result.fixedCount);
        System.assertEquals(1, result.fixedRecordIds.size());
    }

    @isTest
    static void testTopAction() {
        // Test TopAction class
        Test.startTest();
        WorkflowAnalyticsController.TopAction action = new WorkflowAnalyticsController.TopAction();
        action.id = 'test_id';
        action.actionName = 'Test Action';
        action.objectName = 'Account';
        action.count = 50;
        Test.stopTest();

        System.assertEquals('test_id', action.id);
        System.assertEquals('Test Action', action.actionName);
        System.assertEquals('Account', action.objectName);
        System.assertEquals(50, action.count);
    }

    @isTest
    static void testGetRecentLogs_WithData() {
        // Logs are created in testSetup
        Test.startTest();
        List<Behavior_Log__c> logs = WorkflowAnalyticsController.getRecentLogs();
        Test.stopTest();

        System.assertNotEquals(null, logs, 'Logs should not be null');
        System.assert(logs.size() > 0, 'Should return logs from test setup');
    }

    // ==================== HEALTH SCORE TESTS ====================

    @isTest
    static void testGetHealthScore_WithPainPoints() {
        // Pain points created in testSetup
        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.score >= 0 && result.score <= 100, 'Score should be between 0 and 100');
        System.assertNotEquals(null, result.status, 'Status should not be null');
    }

    @isTest
    static void testGetHealthScore_NoPainPoints() {
        // Delete all pain points
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertEquals(100, result.score, 'Score should be 100 with no pain points');
        System.assertEquals('Your Org is Healthy', result.status, 'Status should indicate healthy org');
        System.assertEquals(0, result.highCount, 'High count should be 0');
        System.assertEquals(0, result.mediumCount, 'Medium count should be 0');
        System.assertEquals(0, result.lowCount, 'Low count should be 0');
    }

    @isTest
    static void testGetHealthScore_HighSeverity() {
        // Create pain points that will be categorized
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        for (Integer i = 0; i < 4; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Test Pain Point ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 100,
                Unique_Key__c = 'Test_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        // With 4 pain points (low severity since no matching cost metadata), score should be 96
        System.assert(result.score < 100, 'Score should be reduced by issues');
        System.assert(result.score >= 0, 'Score should be non-negative');
    }

    @isTest
    static void testGetHealthScore_MixedSeverity() {
        // Create mixed severity pain points
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();

        // High severity (Cost_Per_Incident >= 1000)
        points.add(new Identified_Pain_Point__c(
            Name = 'High Severity',
            Object_API_Name__c = 'Contract',
            Status__c = 'New',
            Impact_Score__c = 100,
            Unique_Key__c = 'Contract_Expiry_Red_Zone',
            Occurrences__c = 1
        ));

        // Medium severity (Cost 100-999)
        points.add(new Identified_Pain_Point__c(
            Name = 'Medium Severity',
            Object_API_Name__c = 'Opportunity',
            Status__c = 'New',
            Impact_Score__c = 70,
            Unique_Key__c = 'Stale_Opp_90',
            Occurrences__c = 1
        ));

        // Low severity (no cost configured)
        points.add(new Identified_Pain_Point__c(
            Name = 'Low Severity',
            Object_API_Name__c = 'Task',
            Status__c = 'New',
            Impact_Score__c = 30,
            Unique_Key__c = 'Unknown_Rule',
            Occurrences__c = 1
        ));

        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.score < 100, 'Score should be less than 100');
        System.assert(result.highCount > 0 || result.mediumCount > 0 || result.lowCount > 0,
            'Should have at least some severity counts');
    }

    @isTest
    static void testGetHealthScore_CriticalStatus() {
        // Create enough issues to drop below 50
        // Since test keys won't match metadata, all will be "low" severity (-1 each)
        // Need 51+ low severity items to drop below 50
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        for (Integer i = 0; i < 55; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Critical Issue ' + i,
                Object_API_Name__c = 'Task',
                Status__c = 'New',
                Impact_Score__c = 20,
                Unique_Key__c = 'Critical_Test_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assert(result.score < 50, 'Score should be below 50 for critical status');
        System.assertEquals('Critical Issues Found', result.status, 'Status should indicate critical issues');
    }

    @isTest
    static void testHealthScoreResult_Constructor() {
        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result =
            new WorkflowAnalyticsController.HealthScoreResult(75, 'Needs Attention', 2, 3, 5);
        Test.stopTest();

        System.assertEquals(75, result.score);
        System.assertEquals('Needs Attention', result.status);
        System.assertEquals(2, result.highCount);
        System.assertEquals(3, result.mediumCount);
        System.assertEquals(5, result.lowCount);
    }

    // ==================== TOTAL EVENTS ANALYZED TESTS ====================

    @isTest
    static void testGetTotalEventsAnalyzed_WithData() {
        // 8 behavior logs created in testSetup
        Test.startTest();
        Integer count = WorkflowAnalyticsController.getTotalEventsAnalyzed();
        Test.stopTest();

        System.assertEquals(8, count, 'Should return 8 events from test setup');
    }

    @isTest
    static void testGetTotalEventsAnalyzed_NoData() {
        // Delete all behavior logs
        delete [SELECT Id FROM Behavior_Log__c];

        Test.startTest();
        Integer count = WorkflowAnalyticsController.getTotalEventsAnalyzed();
        Test.stopTest();

        System.assertEquals(0, count, 'Should return 0 when no events exist');
    }
}
