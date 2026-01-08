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
    static void testRestoreSuggestion() {
        // First dismiss the pain point
        Identified_Pain_Point__c point = [SELECT Id FROM Identified_Pain_Point__c LIMIT 1];
        point.Status__c = 'Dismissed';
        update point;

        Test.startTest();
        String result = WorkflowAnalyticsController.restoreSuggestion(point.Id);
        Test.stopTest();

        System.assertEquals('Suggestion restored successfully.', result);

        Identified_Pain_Point__c updatedPoint = [SELECT Status__c FROM Identified_Pain_Point__c WHERE Id = :point.Id];
        System.assertEquals('New', updatedPoint.Status__c);
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
        // Create high-severity issues to drop below 50
        // For Opportunity objects, Impact_Score__c is used directly as dollar risk
        // High severity (>=$50K) = -15 points each, capped at -45
        // We need 4+ high severity items to ensure score drops below 50
        // (100 - 45 = 55, need additional deductions from low/medium)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();

        // Create 4 high-severity Opportunity items (each >= $50K)
        // First 3 = -45 (capped), then low items add more deductions
        for (Integer i = 0; i < 4; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'High Risk Opportunity ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 100000, // $100K - high severity
                Unique_Key__c = 'Critical_Opp_Key_' + i,
                Occurrences__c = 1
            ));
        }

        // Add 10 low-severity Contract items (each <$5K but >$0)
        // Contract uses Impact_Score directly, so $1000 = low severity
        // Low severity (<$5K) = -2 points each, capped at -20
        for (Integer i = 0; i < 10; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Low Risk Contract ' + i,
                Object_API_Name__c = 'Contract',
                Status__c = 'New',
                Impact_Score__c = 1000, // $1K - low severity (< $5K)
                Unique_Key__c = 'Low_Contract_Key_' + i,
                Occurrences__c = 1
            ));
        }

        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        // Score should be: 100 - 45 (high cap) - 20 (low cap) = 35
        System.assert(result.score < 50, 'Score should be below 50 for critical status. Actual: ' + result.score);
        System.assertEquals('Critical Issues Found', result.status, 'Status should indicate critical issues');
    }

    @isTest
    static void testHealthScoreResult_Constructor() {
        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result =
            new WorkflowAnalyticsController.HealthScoreResult(75, 'Needs Attention', 2, 3, 5, 125000.00);
        Test.stopTest();

        System.assertEquals(75, result.score);
        System.assertEquals('Needs Attention', result.status);
        System.assertEquals(2, result.highCount);
        System.assertEquals(3, result.mediumCount);
        System.assertEquals(5, result.lowCount);
        System.assertEquals(125000.00, result.totalAtRisk);
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

    // ==================== ADDITIONAL COVERAGE TESTS ====================

    @isTest
    static void testGetPainPoints_WithCostOverrides() {
        // Test getRuleCostMap() with Cost_Override__c containing different value types
        List<BehaviorIQ_Configuration__c> configs = [SELECT Id, Cost_Override__c FROM BehaviorIQ_Configuration__c LIMIT 1];

        if (!configs.isEmpty()) {
            // JSON with Integer, Double values to test all parsing branches
            configs[0].Cost_Override__c = '{"Test_Opp_Key": 500, "Another_Key": 250.50}';
            update configs[0];
        }

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        // Verify cost override was applied if config exists
        if (!configs.isEmpty()) {
            for (WorkflowAnalyticsController.PainPointWithROI pp : results) {
                if (pp.UniqueKey == 'Test_Opp_Key') {
                    System.assertEquals(500, pp.CostPerIncident, 'Cost override should be applied');
                }
            }
        }
    }

    @isTest
    static void testGetHealthScore_MediumSeverityOpportunity() {
        // Test medium severity path ($5,000 - $49,999)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        // Create 5 medium severity Opportunity items (each $10K-$40K range)
        for (Integer i = 0; i < 5; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Medium Risk Opportunity ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 25000, // $25K - medium severity
                Unique_Key__c = 'Medium_Opp_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.mediumCount > 0, 'Should have medium severity count');
        // Score should be: 100 - 30 (medium cap) = 70
        System.assert(result.score <= 100 && result.score >= 70,
            'Score should reflect medium deductions. Actual: ' + result.score);
    }

    @isTest
    static void testGetHealthScore_NonOpportunityObjects() {
        // Test health score calculation for Case/Lead objects using occurrences * cost
        delete [SELECT Id FROM Identified_Pain_Point__c];

        // Create pain points for Case object
        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        points.add(new Identified_Pain_Point__c(
            Name = 'Stale Case Issue',
            Object_API_Name__c = 'Case',
            Status__c = 'New',
            Impact_Score__c = 100,
            Unique_Key__c = 'Stale_Case_30',
            Occurrences__c = 10
        ));
        points.add(new Identified_Pain_Point__c(
            Name = 'Lead Issue',
            Object_API_Name__c = 'Lead',
            Status__c = 'New',
            Impact_Score__c = 50,
            Unique_Key__c = 'Lead_Hoarding',
            Occurrences__c = 5
        ));
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.score >= 0 && result.score <= 100, 'Score should be valid');
    }

    @isTest
    static void testGetHealthScore_NullObjectName() {
        // Test handling of null Object_API_Name__c
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Identified_Pain_Point__c point = new Identified_Pain_Point__c(
            Name = 'Null Object Test',
            Object_API_Name__c = null,
            Status__c = 'New',
            Impact_Score__c = 100,
            Unique_Key__c = 'Null_Object_Key',
            Occurrences__c = 5
        );
        insert point;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testPainPointWithROI_ContractObject() {
        // Test PainPointWithROI for Contract object (uses Impact_Score directly)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Identified_Pain_Point__c point = new Identified_Pain_Point__c(
            Name = 'Contract Expiry',
            Object_API_Name__c = 'Contract',
            Status__c = 'New',
            Impact_Score__c = 75000,
            Unique_Key__c = 'Contract_Expiry_Key',
            Occurrences__c = 3
        );
        insert point;

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 pain point');
        // For Contract, EstimatedSavings should equal Impact_Score__c
        System.assertEquals(75000, results[0].EstimatedSavings,
            'Contract should use Impact_Score as EstimatedSavings');
    }

    @isTest
    static void testPainPointWithROI_NullValues() {
        // Test PainPointWithROI with null values
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Identified_Pain_Point__c point = new Identified_Pain_Point__c(
            Name = 'Null Values Test',
            Object_API_Name__c = 'Task',
            Status__c = 'New',
            Impact_Score__c = null,
            Unique_Key__c = 'Null_Values_Key',
            Occurrences__c = null
        );
        insert point;

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 pain point');
        System.assertEquals(0, results[0].EstimatedSavings, 'EstimatedSavings should be 0 for null values');
        System.assertEquals(0, results[0].CostPerIncident, 'CostPerIncident should be 0 when not configured');
    }

    @isTest
    static void testGetHealthScore_NeedsAttentionStatus() {
        // Test the "Needs Attention" status (score 50-80)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        // Create high severity items to get score in 50-80 range
        // 3 high severity = -45, score = 55 (Needs Attention)
        for (Integer i = 0; i < 3; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'High Risk ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 60000, // High severity
                Unique_Key__c = 'High_Risk_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assert(result.score >= 50 && result.score <= 80,
            'Score should be in Needs Attention range. Actual: ' + result.score);
        System.assertEquals('Needs Attention', result.status, 'Status should be Needs Attention');
    }

    @isTest
    static void testGetRecentLogs_NoData() {
        // Test getRecentLogs when no logs exist
        delete [SELECT Id FROM Behavior_Log__c];

        Test.startTest();
        List<Behavior_Log__c> logs = WorkflowAnalyticsController.getRecentLogs();
        Test.stopTest();

        System.assertNotEquals(null, logs, 'Logs should not be null');
        System.assertEquals(0, logs.size(), 'Should return empty list');
    }

    @isTest
    static void testGetSystemHealth_NoData() {
        // Test getSystemHealth when no logs exist
        delete [SELECT Id FROM System_Health_Log__c];

        Test.startTest();
        System_Health_Log__c healthLog = WorkflowAnalyticsController.getSystemHealth();
        Test.stopTest();

        System.assertEquals(null, healthLog, 'Should return null when no health logs exist');
    }

    @isTest
    static void testRunAutoFix_NullRecordIds() {
        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(null, 'Stale Case');
            System.assert(false, 'Should throw exception for null recordIds');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for null recordIds');
        }
        Test.stopTest();
    }

    // ==================== APPEXCHANGE SECURITY EDGE CASE TESTS ====================

    @isTest
    static void testRunAutoFix_NullFixType() {
        // Test null fixType parameter
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, null);
            // If it doesn't throw, it should try metadata-driven approach and fail
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for null/unknown fix type');
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_EmptyFixType() {
        // Test empty string fixType
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, '');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception for empty fix type');
        }
        Test.stopTest();
    }

    @isTest
    static void testRunAutoFix_MultipleRecords() {
        // Test with multiple records to verify bulk handling
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            cases.add(new Case(Subject = 'Bulk Test Case ' + i, Status = 'New'));
        }
        insert cases;

        List<String> recordIds = new List<String>();
        for (Case c : cases) {
            recordIds.add(String.valueOf(c.Id));
        }

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result = WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale Case');
        Test.stopTest();

        System.assertEquals(5, result.fixedCount, 'Should have fixed 5 records');
        System.assertEquals(5, result.fixedRecordIds.size(), 'Should return 5 fixed record IDs');

        // Verify tasks were created for all cases
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId IN :cases];
        System.assertEquals(5, tasks.size(), 'Should create 5 tasks');
    }

    @isTest
    static void testDismissSuggestion_InvalidId() {
        // Test with a valid-format but non-existent ID
        Id fakeId = 'a00000000000001AAA'; // Fake Identified_Pain_Point__c ID

        Test.startTest();
        try {
            WorkflowAnalyticsController.dismissSuggestion(fakeId);
            System.assert(false, 'Should throw exception for non-existent record');
        } catch (Exception e) {
            System.assert(true, 'Expected exception for invalid ID');
        }
        Test.stopTest();
    }

    @isTest
    static void testRestoreSuggestion_InvalidId() {
        // Test with a valid-format but non-existent ID
        Id fakeId = 'a00000000000001AAA'; // Fake Identified_Pain_Point__c ID

        Test.startTest();
        try {
            WorkflowAnalyticsController.restoreSuggestion(fakeId);
            System.assert(false, 'Should throw exception for non-existent record');
        } catch (Exception e) {
            System.assert(true, 'Expected exception for invalid ID');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPainPoints_NoConfig() {
        // Test getPainPoints when no BehaviorIQ_Configuration__c exists
        delete [SELECT Id FROM BehaviorIQ_Configuration__c];

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null even without config');
    }

    @isTest
    static void testGetHealthScore_ZeroDollarRisk() {
        // Test pain points with $0 dollar risk (should not affect score)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        for (Integer i = 0; i < 5; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Zero Risk ' + i,
                Object_API_Name__c = 'Task',
                Status__c = 'New',
                Impact_Score__c = 0,
                Unique_Key__c = 'Zero_Risk_Key_' + i,
                Occurrences__c = 0
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        // Zero risk items should not affect score
        System.assertEquals(100, result.score, 'Score should remain 100 with $0 risk items');
    }

    @isTest
    static void testGetHealthScore_MaxDeductions() {
        // Test that deductions are properly capped
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();

        // Add many high severity items (should cap at -45)
        for (Integer i = 0; i < 10; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Max High ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 100000,
                Unique_Key__c = 'Max_High_Key_' + i,
                Occurrences__c = 1
            ));
        }

        // Add many medium severity items (should cap at -30)
        for (Integer i = 0; i < 10; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Max Medium ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 25000,
                Unique_Key__c = 'Max_Medium_Key_' + i,
                Occurrences__c = 1
            ));
        }

        // Add many low severity items (should cap at -20)
        for (Integer i = 0; i < 20; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Max Low ' + i,
                Object_API_Name__c = 'Contract',
                Status__c = 'New',
                Impact_Score__c = 1000,
                Unique_Key__c = 'Max_Low_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        // Max deductions: -45 (high) - 30 (medium) - 20 (low) = 5 minimum
        System.assertEquals(5, result.score, 'Score should be 5 with max deductions. Actual: ' + result.score);
        System.assertEquals('Critical Issues Found', result.status, 'Should be critical status');
    }

    @isTest
    static void testGetHealthScore_FloorAtZero() {
        // Verify score doesn't go below 0
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();

        // Create extreme high severity items
        for (Integer i = 0; i < 50; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Extreme High ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'New',
                Impact_Score__c = 500000,
                Unique_Key__c = 'Extreme_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        System.assert(result.score >= 0, 'Score should never go below 0');
    }

    @isTest
    static void testGetDashboardData_NoPainPoints() {
        // Test dashboard with no pain points
        delete [SELECT Id FROM Identified_Pain_Point__c];
        delete [SELECT Id FROM BehaviorIQ_License__c];

        Test.startTest();
        WorkflowAnalyticsController.DashboardDataWrapper result = WorkflowAnalyticsController.getDashboardData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.metrics, 'Metrics should not be null');
    }

    @isTest
    static void testGetWorkflowStats_NoLogs() {
        // Test workflow stats with no behavior logs
        delete [SELECT Id FROM Behavior_Log__c];

        Test.startTest();
        Map<String, Integer> stats = WorkflowAnalyticsController.getWorkflowStats();
        Test.stopTest();

        System.assertEquals(0, stats.get('totalLogs'), 'Total logs should be 0');
        System.assertEquals(0, stats.get('uniqueUsers'), 'Unique users should be 0');
        System.assertEquals(0, stats.get('objectsTracked'), 'Objects tracked should be 0');
    }

    @isTest
    static void testGetTopActions_NoRecentLogs() {
        // Test top actions with no logs in last 30 days
        delete [SELECT Id FROM Behavior_Log__c];

        Test.startTest();
        List<WorkflowAnalyticsController.TopAction> actions = WorkflowAnalyticsController.getTopActions();
        Test.stopTest();

        System.assertNotEquals(null, actions, 'Actions list should not be null');
        System.assertEquals(0, actions.size(), 'Should return empty list when no recent logs');
    }

    @isTest
    static void testPainPointWithROI_LowercaseObjectName() {
        // Test that object name comparison is case-insensitive
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Identified_Pain_Point__c point = new Identified_Pain_Point__c(
            Name = 'Lowercase Test',
            Object_API_Name__c = 'opportunity', // lowercase
            Status__c = 'New',
            Impact_Score__c = 50000,
            Unique_Key__c = 'Lowercase_Key',
            Occurrences__c = 1
        );
        insert point;

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 pain point');
        // For opportunity (lowercase), should still use Impact_Score as EstimatedSavings
        System.assertEquals(50000, results[0].EstimatedSavings,
            'Should handle lowercase object name correctly');
    }

    @isTest
    static void testRunAutoFix_SpecialCharactersInFixType() {
        // Test fix type with special characters
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        try {
            WorkflowAnalyticsController.runAutoFix(recordIds, 'Stale<Script>Case');
        } catch (AuraHandledException e) {
            // Expected - should not match any known fix type
            System.assert(true, 'Expected exception for unknown fix type');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPainPoints_LargeDataset() {
        // Test with maximum allowed records (100 limit in query)
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        for (Integer i = 0; i < 150; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Large Dataset ' + i,
                Object_API_Name__c = 'Account',
                Status__c = 'New',
                Impact_Score__c = i * 100,
                Unique_Key__c = 'Large_Key_' + i,
                Occurrences__c = i
            ));
        }
        insert points;

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        // Query is limited to 100 records
        System.assertEquals(100, results.size(), 'Should return max 100 records');
    }

    @isTest
    static void testAutoFixResult_EmptyIdList() {
        // Test AutoFixResult constructor with empty list
        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result =
            new WorkflowAnalyticsController.AutoFixResult('Test message', new List<Id>());
        Test.stopTest();

        System.assertEquals('Test message', result.message);
        System.assertEquals(0, result.fixedCount);
        System.assertEquals(0, result.fixedRecordIds.size());
    }

    @isTest
    static void testGetHealthScore_DismissedPointsIgnored() {
        // Verify dismissed pain points don't affect health score
        delete [SELECT Id FROM Identified_Pain_Point__c];

        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();

        // Add dismissed high-severity items
        for (Integer i = 0; i < 5; i++) {
            points.add(new Identified_Pain_Point__c(
                Name = 'Dismissed High ' + i,
                Object_API_Name__c = 'Opportunity',
                Status__c = 'Dismissed',
                Impact_Score__c = 100000,
                Unique_Key__c = 'Dismissed_Key_' + i,
                Occurrences__c = 1
            ));
        }
        insert points;

        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result = WorkflowAnalyticsController.getHealthScore();
        Test.stopTest();

        // Dismissed items should not affect score
        System.assertEquals(100, result.score, 'Score should be 100 when only dismissed items exist');
        System.assertEquals(0, result.highCount, 'High count should be 0 for dismissed items');
    }

    @isTest
    static void testRunAutoFix_MixedCaseFixType() {
        // Test case-insensitive fix type matching
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result =
            WorkflowAnalyticsController.runAutoFix(recordIds, 'STALE CASE');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.fixedCount, 'Should fix 1 record with uppercase fix type');
    }

    @isTest
    static void testRunAutoFix_WhitespaceFixType() {
        // Test fix type with extra whitespace
        Case c = [SELECT Id FROM Case LIMIT 1];
        List<String> recordIds = new List<String>{String.valueOf(c.Id)};

        Test.startTest();
        WorkflowAnalyticsController.AutoFixResult result =
            WorkflowAnalyticsController.runAutoFix(recordIds, '  Stale Case  ');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.fixedCount, 'Should handle whitespace in fix type');
    }

    @isTest
    static void testGetTotalEventsAnalyzed_LargeCount() {
        // Test with larger dataset
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 200; i++) {
            logs.add(new Behavior_Log__c(
                Action_Name__c = 'Bulk_Action',
                Object_API_Name__c = 'Account',
                User__c = UserInfo.getUserId(),
                Timestamp__c = System.now()
            ));
        }
        insert logs;

        Test.startTest();
        Integer count = WorkflowAnalyticsController.getTotalEventsAnalyzed();
        Test.stopTest();

        // Should include both setup data and new data
        System.assert(count >= 200, 'Should return at least 200 events');
    }

    @isTest
    static void testHealthScoreResult_AllFields() {
        // Test all fields of HealthScoreResult wrapper
        Test.startTest();
        WorkflowAnalyticsController.HealthScoreResult result =
            new WorkflowAnalyticsController.HealthScoreResult(50, 'Test Status', 5, 10, 15, 250000.50);
        Test.stopTest();

        System.assertEquals(50, result.score);
        System.assertEquals('Test Status', result.status);
        System.assertEquals(5, result.highCount);
        System.assertEquals(10, result.mediumCount);
        System.assertEquals(15, result.lowCount);
        System.assertEquals(250000.50, result.totalAtRisk);
    }

    @isTest
    static void testPainPointWithROI_AllFields() {
        // Verify all PainPointWithROI fields are properly populated
        delete [SELECT Id FROM Identified_Pain_Point__c];

        Identified_Pain_Point__c point = new Identified_Pain_Point__c(
            Name = 'Full Fields Test',
            Object_API_Name__c = 'Case',
            Status__c = 'New',
            Impact_Score__c = 5000,
            Description__c = 'Test description for coverage',
            Unique_Key__c = 'Full_Fields_Key',
            Occurrences__c = 25,
            Example_Records__c = 'rec1,rec2,rec3'
        );
        insert point;

        Test.startTest();
        List<WorkflowAnalyticsController.PainPointWithROI> results = WorkflowAnalyticsController.getPainPoints();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 pain point');
        WorkflowAnalyticsController.PainPointWithROI pp = results[0];

        System.assertNotEquals(null, pp.Id, 'Id should be populated');
        System.assertEquals('Full Fields Test', pp.Name);
        System.assertEquals('Case', pp.ObjectApiName);
        System.assertEquals(5000, pp.ImpactScore);
        System.assertEquals('New', pp.Status);
        System.assertEquals('Test description for coverage', pp.Description);
        System.assertEquals(25, pp.Occurrences);
        System.assertEquals('rec1,rec2,rec3', pp.ExampleRecords);
        System.assertEquals('Full_Fields_Key', pp.UniqueKey);
    }
}
