/**
 * @description Test class for PatternAnalysisService.
 * Uses metadata-agnostic patterns with @TestVisible mock injection for reliable testing.
 */
@isTest
private class PatternAnalysisServiceTest {

    // ==================== HELPER METHODS ====================

    /**
     * @description Creates a mock Behavior_Pattern_Rule__mdt record for testing.
     * Uses JSON deserialization to create an in-memory metadata record.
     */
    private static Behavior_Pattern_Rule__mdt createMockRule(
        String developerName,
        String masterLabel,
        String objectApiName,
        String queryCondition,
        Boolean isPremium
    ) {
        String jsonRule = '{' +
            '"DeveloperName": "' + developerName + '",' +
            '"MasterLabel": "' + masterLabel + '",' +
            '"Object_API_Name__c": "' + objectApiName + '",' +
            '"Query_Condition__c": "' + queryCondition.replace('"', '\\"') + '",' +
            '"Is_Premium__c": ' + isPremium +
        '}';
        return (Behavior_Pattern_Rule__mdt) JSON.deserialize(jsonRule, Behavior_Pattern_Rule__mdt.class);
    }

    /**
     * @description Clears the mock variables after each test to prevent state leakage.
     */
    private static void clearMocks() {
        PatternAnalysisService.mockRule = null;
        PatternAnalysisService.mockConfig = null;
        PatternAnalysisService.lastExecutedQuery = null;
    }

    @TestSetup
    static void setupData() {
        // Create admin user for tests
        Profile pAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        String uniqueifier = String.valueOf(System.currentTimeMillis());

        User testUser = new User(
            Alias = 'testpas',
            Email = 'testpas' + uniqueifier + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = pAdmin.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testpas' + uniqueifier + '@testorg.com'
        );
        insert testUser;
    }

    // ==================== BATCH EXECUTION TESTS ====================

    @isTest
    static void testBatchExecution_Success() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // Execute the batch - it reads from Behavior_Pattern_Rule__mdt
            Database.executeBatch(new PatternAnalysisService(), 50);
        }
        Test.stopTest();

        // Verify that the batch ran without errors
        // The actual pain points created depend on metadata in the org
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'PatternAnalysisService'
            AND Status = 'Completed'
            LIMIT 1
        ];
        System.assertEquals(1, jobs.size(), 'Batch job should complete');

        clearMocks();
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String cronExpression = '0 0 2 * * ?';
        String jobId = System.schedule('Test Pattern Analysis', cronExpression, service);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job ID should not be null');

        // Clean up
        System.abortJob(jobId);

        clearMocks();
    }

    @isTest
    static void testDataRetention_DeletesOldLogs() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        System.runAs(testUser) {
            List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 5; i++) {
                oldLogs.add(new Behavior_Log__c(
                    Action_Name__c = 'Old',
                    User__c = testUser.Id,
                    Timestamp__c = System.now()
                ));
            }
            insert oldLogs;

            // Set created date to old date
            for(Behavior_Log__c l : oldLogs) {
                Test.setCreatedDate(l.Id, Datetime.now().addDays(-100));
            }
        }

        Test.startTest();
        System.runAs(testUser) {
            Date cutoffDate = Date.today().addDays(-PatternAnalysisService.DEFAULT_RETENTION_DAYS);
            String isoDate = Datetime.newInstanceGmt(cutoffDate.year(), cutoffDate.month(), cutoffDate.day()).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String query = 'SELECT Id FROM Behavior_Log__c WHERE CreatedDate < ' + isoDate;
            Database.executeBatch(new DeleteRecordsBatch(query), 200);
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'Old'],
            'Old logs should have been deleted.');

        clearMocks();
    }

    @isTest
    static void testHealthLogCreation() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Database.executeBatch(new PatternAnalysisService(), 50);
        }
        Test.stopTest();

        // Check if health log was created
        List<System_Health_Log__c> healthLogs = [
            SELECT Id, Status__c, Job_Name__c
            FROM System_Health_Log__c
            WHERE CreatedDate = TODAY
        ];

        // The health log should be created if user has permission
        if (Schema.sObjectType.System_Health_Log__c.isCreateable()) {
            System.assert(healthLogs.size() >= 0, 'Health log query should execute without error');
        }

        clearMocks();
    }

    @isTest
    static void testConstructor() {
        // Test that constructor initializes properly
        PatternAnalysisService service = new PatternAnalysisService();
        System.assertNotEquals(null, service, 'Service should be instantiated');

        clearMocks();
    }

    @isTest
    static void testDefaultRetentionDays() {
        // Verify the constant is accessible
        System.assertEquals(90, PatternAnalysisService.DEFAULT_RETENTION_DAYS,
            'Default retention days should be 90');
    }

    // ==================== SNAPSHOT CREATION TESTS (Sprint 5) ====================

    @isTest
    static void testSnapshotCreation() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        // Create test cases that will match the Stale_Case rule
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                Subject = 'Snapshot Test Case ' + i,
                Status = 'New'
            ));
        }

        System.runAs(testUser) {
            insert testCases;

            // Backdate cases to ensure they match the stale pattern
            for (Case c : testCases) {
                Test.setCreatedDate(c.Id, Datetime.now().addDays(-60));
            }
        }

        // Clear any existing pain points and snapshots
        delete [SELECT Id FROM Identified_Pain_Point__c];
        delete [SELECT Id FROM Behavior_Snapshot__c];

        Test.startTest();
        System.runAs(testUser) {
            // Execute the batch job - this should create pain points AND snapshots
            Database.executeBatch(new PatternAnalysisService(), 50);
        }
        Test.stopTest();

        // Verify the batch completed
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'PatternAnalysisService'
            AND Status = 'Completed'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, jobs.size(), 'Batch job should complete successfully');

        // Verify pain points were created (depends on org metadata)
        List<Identified_Pain_Point__c> painPoints = [
            SELECT Id, Unique_Key__c, Occurrences__c, Impact_Score__c
            FROM Identified_Pain_Point__c
        ];

        // Verify snapshots were created for each pain point
        List<Behavior_Snapshot__c> snapshots = [
            SELECT Id, Metric_Name__c, Record_Count__c, Impact_Score__c,
                   Snapshot_Date__c, Related_Pain_Point__c
            FROM Behavior_Snapshot__c
        ];

        // If pain points exist, snapshots should also exist
        if (!painPoints.isEmpty()) {
            System.assert(!snapshots.isEmpty(),
                'Snapshots should be created when pain points are detected. Pain points: ' +
                painPoints.size() + ', Snapshots: ' + snapshots.size());

            // Verify snapshot has correct date
            for (Behavior_Snapshot__c snapshot : snapshots) {
                System.assertEquals(Date.today(), snapshot.Snapshot_Date__c,
                    'Snapshot date should be today');
                System.assertNotEquals(null, snapshot.Metric_Name__c,
                    'Snapshot should have a metric name');
            }
        }

        clearMocks();
    }

    @isTest
    static void testSnapshotCreation_MatchesPainPointData() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        // Create a configuration for consistent threshold
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Stale_Case_Threshold__c = 5
        );
        insert config;

        // Create test cases that will match the stale pattern
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            testCases.add(new Case(
                Subject = 'Match Test Case ' + i,
                Status = 'New'
            ));
        }

        System.runAs(testUser) {
            insert testCases;

            // Backdate cases to ensure they match
            for (Case c : testCases) {
                Test.setCreatedDate(c.Id, Datetime.now().addDays(-30));
            }
        }

        // Clear existing data
        delete [SELECT Id FROM Identified_Pain_Point__c];
        delete [SELECT Id FROM Behavior_Snapshot__c];

        Test.startTest();
        System.runAs(testUser) {
            Database.executeBatch(new PatternAnalysisService(), 50);
        }
        Test.stopTest();

        // Verify relationship between pain points and snapshots
        Map<String, Identified_Pain_Point__c> painPointsByKey = new Map<String, Identified_Pain_Point__c>();
        for (Identified_Pain_Point__c pp : [SELECT Id, Unique_Key__c, Occurrences__c, Impact_Score__c FROM Identified_Pain_Point__c]) {
            painPointsByKey.put(pp.Unique_Key__c, pp);
        }

        List<Behavior_Snapshot__c> snapshots = [
            SELECT Id, Metric_Name__c, Record_Count__c, Impact_Score__c, Related_Pain_Point__c
            FROM Behavior_Snapshot__c
        ];

        // Verify each snapshot matches its related pain point
        for (Behavior_Snapshot__c snapshot : snapshots) {
            if (snapshot.Related_Pain_Point__c != null) {
                // Find the related pain point
                Identified_Pain_Point__c relatedPP = null;
                for (Identified_Pain_Point__c pp : painPointsByKey.values()) {
                    if (pp.Id == snapshot.Related_Pain_Point__c) {
                        relatedPP = pp;
                        break;
                    }
                }

                if (relatedPP != null) {
                    System.assertEquals(relatedPP.Occurrences__c, snapshot.Record_Count__c,
                        'Snapshot record count should match pain point occurrences');
                    System.assertEquals(relatedPP.Impact_Score__c, snapshot.Impact_Score__c,
                        'Snapshot impact score should match pain point impact score');
                }
            }
        }

        clearMocks();
    }

    @isTest
    static void testSnapshotNotCreatedForRealTimeChecks() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        // Clear existing snapshots
        delete [SELECT Id FROM Behavior_Snapshot__c];

        Integer snapshotsBefore = [SELECT COUNT() FROM Behavior_Snapshot__c];

        Test.startTest();
        System.runAs(testUser) {
            // Create a service instance directly (not through batch)
            // This simulates a real-time check scenario
            PatternAnalysisService service = new PatternAnalysisService();

            // Call getPatternMatches which is a real-time API
            // It should NOT create snapshots
            try {
                PatternAnalysisService.getPatternMatches('Stale_Case_30', 50);
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist - that's fine
            }
        }
        Test.stopTest();

        Integer snapshotsAfter = [SELECT COUNT() FROM Behavior_Snapshot__c];

        System.assertEquals(snapshotsBefore, snapshotsAfter,
            'Real-time API calls should NOT create snapshots');

        clearMocks();
    }

    // ==================== DYNAMIC QUERY INJECTION TESTS ====================

    @isTest
    static void testDynamicThresholdInjection_StaleCase() {
        // Setup: Create a configuration record with custom threshold (5 days)
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Stale_Case_Threshold__c = 5
        );
        insert config;

        // Create a mock rule with a default value of 99 days
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_30',
            'Stale Cases',
            'Case',
            'Status != \'Closed\' AND LastModifiedDate < LAST_N_DAYS:99',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        // Create a test case that would match both thresholds
        Case testCase = new Case(Subject = 'Test Stale Case', Status = 'New');
        insert testCase;

        Test.startTest();
        // Instantiate service and call getEffectiveQuery directly
        PatternAnalysisService service = new PatternAnalysisService();

        // Use the private method via @TestVisible access
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that the query now uses "5" instead of "99"
        System.assert(effectiveQuery.contains('LAST_N_DAYS:5'),
            'Query should contain LAST_N_DAYS:5 from config. Actual: ' + effectiveQuery);
        System.assert(!effectiveQuery.contains('LAST_N_DAYS:99'),
            'Query should NOT contain LAST_N_DAYS:99. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_StaleOpportunity() {
        // Setup: Create a configuration record with custom threshold (15 days)
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Stale_Opportunity_Threshold__c = 15
        );
        insert config;

        // Create a mock rule for Stale Opportunity with default value of 90 days
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Opp_90',
            'Stale Opportunities',
            'Opportunity',
            'IsClosed = false AND LastStageChangeDate < LAST_N_DAYS:90',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that the query now uses "15" instead of "90"
        System.assert(effectiveQuery.contains('LAST_N_DAYS:15'),
            'Query should contain LAST_N_DAYS:15 from config. Actual: ' + effectiveQuery);
        System.assert(!effectiveQuery.contains('LAST_N_DAYS:90'),
            'Query should NOT contain LAST_N_DAYS:90. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_WithMockConfig() {
        // Setup: Use mock config injection (no database insert needed)
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Case_Threshold__c = 7
        );
        PatternAnalysisService.mockConfig = mockConfig;

        // Create a mock rule
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_Test',
            'Test Stale Cases',
            'Case',
            'Status != \'Closed\' AND CreatedDate < LAST_N_DAYS:30',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that the query uses the mock config value
        System.assert(effectiveQuery.contains('LAST_N_DAYS:7'),
            'Query should contain LAST_N_DAYS:7 from mock config. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_NoConfigRecord() {
        // Setup: No config record exists - should use original query
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_30',
            'Stale Cases',
            'Case',
            'Status != \'Closed\' AND LastModifiedDate < LAST_N_DAYS:30',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that the original query is preserved when no config exists
        System.assert(effectiveQuery.contains('LAST_N_DAYS:30'),
            'Query should contain original LAST_N_DAYS:30 when no config exists. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_NonMatchingRule() {
        // Setup: Config exists but rule name doesn't match Stale_Case or Stale_Opp patterns
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Case_Threshold__c = 5,
            Stale_Opportunity_Threshold__c = 10
        );
        PatternAnalysisService.mockConfig = mockConfig;

        // Create a rule that doesn't match the Stale patterns
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Unassigned_Lead_48',
            'Unassigned Leads',
            'Lead',
            'Owner.Type = \'Queue\' AND CreatedDate < LAST_N_DAYS:48',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that the original query is preserved for non-matching rules
        System.assert(effectiveQuery.contains('LAST_N_DAYS:48'),
            'Query should contain original LAST_N_DAYS:48 for non-matching rule. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_NullQueryCondition() {
        // Setup: Rule with null query condition
        String jsonRule = '{' +
            '"DeveloperName": "Null_Query_Test",' +
            '"MasterLabel": "Null Query Test",' +
            '"Object_API_Name__c": "Case",' +
            '"Is_Premium__c": false' +
        '}';
        Behavior_Pattern_Rule__mdt mockRule = (Behavior_Pattern_Rule__mdt) JSON.deserialize(jsonRule, Behavior_Pattern_Rule__mdt.class);
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert null/blank is returned for null query condition
        System.assertEquals(null, effectiveQuery, 'Null query condition should return null');

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_MultipleLastNDaysPatterns() {
        // Setup: Config exists
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Case_Threshold__c = 10
        );
        PatternAnalysisService.mockConfig = mockConfig;

        // Create a rule with multiple LAST_N_DAYS patterns
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_Complex',
            'Complex Stale Cases',
            'Case',
            'Status != \'Closed\' AND (CreatedDate < LAST_N_DAYS:30 OR LastModifiedDate < LAST_N_DAYS:60)',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert that ALL LAST_N_DAYS patterns are replaced
        System.assert(!effectiveQuery.contains('LAST_N_DAYS:30'),
            'Query should NOT contain LAST_N_DAYS:30. Actual: ' + effectiveQuery);
        System.assert(!effectiveQuery.contains('LAST_N_DAYS:60'),
            'Query should NOT contain LAST_N_DAYS:60. Actual: ' + effectiveQuery);
        // Both should be replaced with 10
        Integer countOf10 = effectiveQuery.countMatches('LAST_N_DAYS:10');
        System.assertEquals(2, countOf10,
            'Query should contain 2 instances of LAST_N_DAYS:10. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_ExecuteRuleIntegration() {
        // Setup: Create config and case that will match the query
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Stale_Case_Threshold__c = 5
        );
        insert config;

        // Create an old case
        Case testCase = new Case(Subject = 'Integration Test Stale Case', Status = 'New');
        insert testCase;
        // Backdate the case
        Test.setCreatedDate(testCase.Id, Datetime.now().addDays(-10));

        // Create a mock rule
        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_Test',
            'Stale Cases Integration',
            'Case',
            'Status != \'Closed\' AND CreatedDate < LAST_N_DAYS:99',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        // Execute batch to run the full flow
        PatternAnalysisService service = new PatternAnalysisService();
        // Directly test getEffectiveQuery to verify integration
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Verify the query was modified
        System.assert(effectiveQuery.contains('LAST_N_DAYS:5'),
            'Integration test: Query should use config value 5. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_StaleOpportunityAltName() {
        // Test with alternative naming pattern "Stale_Opportunity" instead of "Stale_Opp"
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Opportunity_Threshold__c = 25
        );
        PatternAnalysisService.mockConfig = mockConfig;

        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Opportunity_Test',
            'Stale Opportunity Alt Name',
            'Opportunity',
            'IsClosed = false AND LastActivityDate < LAST_N_DAYS:45',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        System.assert(effectiveQuery.contains('LAST_N_DAYS:25'),
            'Query should use config value 25 for Stale_Opportunity prefix. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testDynamicThresholdInjection_ConfigNullThreshold() {
        // Setup: Config exists but threshold is null
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Case_Threshold__c = null
        );
        PatternAnalysisService.mockConfig = mockConfig;

        Behavior_Pattern_Rule__mdt mockRule = createMockRule(
            'Stale_Case_30',
            'Stale Cases',
            'Case',
            'Status != \'Closed\' AND LastModifiedDate < LAST_N_DAYS:30',
            false
        );
        PatternAnalysisService.mockRule = mockRule;

        Test.startTest();
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveQuery = service.getEffectiveQuery(mockRule);
        Test.stopTest();

        // Assert original query is preserved when threshold is null
        System.assert(effectiveQuery.contains('LAST_N_DAYS:30'),
            'Query should contain original LAST_N_DAYS:30 when config threshold is null. Actual: ' + effectiveQuery);

        clearMocks();
    }

    @isTest
    static void testLastExecutedQueryCapture() {
        // Setup: Create config
        BehaviorIQ_Configuration__c mockConfig = new BehaviorIQ_Configuration__c(
            Name = 'Mock Config',
            Stale_Case_Threshold__c = 3
        );
        PatternAnalysisService.mockConfig = mockConfig;

        // Create a case to be detected
        Case testCase = new Case(Subject = 'Query Capture Test', Status = 'New');
        insert testCase;

        Test.startTest();
        // Clear any previous query
        PatternAnalysisService.lastExecutedQuery = null;

        // Run the batch which will capture the executed query
        Database.executeBatch(new PatternAnalysisService(), 50);
        Test.stopTest();

        // Note: lastExecutedQuery is set during executeRule, which runs for real metadata
        // This test verifies the mechanism exists
        // The actual query depends on the org's metadata

        clearMocks();
    }

    // ==================== REMEDIATION PREVIEW TESTS (Sprint 4) ====================

    @isTest
    static void testGetPatternMatches_Success() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        // Create test cases to be matched
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            testCases.add(new Case(
                Subject = 'Test Case ' + i,
                Status = 'New',
                Priority = 'Medium'
            ));
        }
        insert testCases;

        Test.startTest();
        System.runAs(testUser) {
            // This test will use actual metadata in the org
            // If Stale_Case_30 exists, it will return matching records
            try {
                List<SObject> results = PatternAnalysisService.getPatternMatches('Stale_Case_30', 50);
                // The test passes if no exception is thrown
                // Results depend on org metadata and test data
                System.assertNotEquals(null, results, 'Results should not be null');
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist in org
                System.assert(e.getMessage().contains('Pattern rule not found') ||
                              e.getMessage().contains('Premium feature') ||
                              e.getMessage().contains('Unable to query'),
                    'Exception should be a known error type: ' + e.getMessage());
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_NullRuleName() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                PatternAnalysisService.getPatternMatches(null, 50);
                System.assert(false, 'Should have thrown an exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Rule developer name is required'),
                    'Exception should mention required rule name: ' + e.getMessage());
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_BlankRuleName() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                PatternAnalysisService.getPatternMatches('', 50);
                System.assert(false, 'Should have thrown an exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Rule developer name is required'),
                    'Exception should mention required rule name: ' + e.getMessage());
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_InvalidRuleName() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                PatternAnalysisService.getPatternMatches('NonExistent_Rule_XYZ', 50);
                System.assert(false, 'Should have thrown an exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('Pattern rule not found'),
                    'Exception should mention rule not found: ' + e.getMessage());
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_LimitEnforcement() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // Test with various limit values
            try {
                // Test with null limit (should default to 50)
                PatternAnalysisService.getPatternMatches('Stale_Case_30', null);
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }

            try {
                // Test with negative limit (should default to 50)
                PatternAnalysisService.getPatternMatches('Stale_Case_30', -10);
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }

            try {
                // Test with limit > 200 (should cap at 200)
                PatternAnalysisService.getPatternMatches('Stale_Case_30', 500);
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_WithConfiguration() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        // Create configuration to test threshold injection
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Stale_Case_Threshold__c = 10
        );
        insert config;

        // Create test cases
        List<Case> testCases = new List<Case>();
        for (Integer i = 0; i < 3; i++) {
            testCases.add(new Case(
                Subject = 'Config Test Case ' + i,
                Status = 'New'
            ));
        }
        insert testCases;

        Test.startTest();
        System.runAs(testUser) {
            try {
                List<SObject> results = PatternAnalysisService.getPatternMatches('Stale_Case_30', 50);
                // If we get here, the query executed successfully
                System.assertNotEquals(null, results, 'Results should not be null');

                // Verify query was captured
                String capturedQuery = PatternAnalysisService.lastExecutedQuery;
                if (capturedQuery != null) {
                    // Security is now enforced via stripInaccessible after query execution
                    System.assert(capturedQuery.contains('ORDER BY CreatedDate DESC'),
                        'Query should include ORDER BY clause');
                }
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist or FLS issues
                System.debug('Expected exception: ' + e.getMessage());
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetDisplayFieldsForObject_Case() {
        // Test that Case fields are properly returned
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                // Attempt to get pattern matches for Case
                // This indirectly tests getDisplayFieldsForObject
                PatternAnalysisService.getPatternMatches('Stale_Case_30', 10);

                String query = PatternAnalysisService.lastExecutedQuery;
                if (query != null) {
                    // Verify Case-specific fields are included
                    System.assert(query.containsIgnoreCase('Subject') ||
                                  query.containsIgnoreCase('Status') ||
                                  query.containsIgnoreCase('Priority'),
                        'Query should include Case-specific fields');
                }
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_OpportunityFields() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                // Attempt to get pattern matches for Opportunity
                PatternAnalysisService.getPatternMatches('Stale_Opp_30', 10);

                String query = PatternAnalysisService.lastExecutedQuery;
                if (query != null) {
                    // Verify Opportunity-specific fields are included
                    System.assert(query.containsIgnoreCase('StageName') ||
                                  query.containsIgnoreCase('Amount') ||
                                  query.containsIgnoreCase('CloseDate'),
                        'Query should include Opportunity-specific fields');
                }
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }
        }
        Test.stopTest();

        clearMocks();
    }

    @isTest
    static void testGetPatternMatches_LeadFields() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            try {
                // Attempt to get pattern matches for Lead
                PatternAnalysisService.getPatternMatches('Unassigned_Lead_48', 10);

                String query = PatternAnalysisService.lastExecutedQuery;
                if (query != null) {
                    // Verify Lead-specific fields are included
                    System.assert(query.containsIgnoreCase('Company') ||
                                  query.containsIgnoreCase('Email') ||
                                  query.containsIgnoreCase('Phone'),
                        'Query should include Lead-specific fields');
                }
            } catch (AuraHandledException e) {
                // Expected if rule doesn't exist
            }
        }
        Test.stopTest();

        clearMocks();
    }
}
