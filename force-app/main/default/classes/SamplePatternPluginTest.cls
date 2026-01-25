/**
 * @description Test class for SamplePatternPlugin.
 * Tests analysis and fix functionality for cold-rated accounts.
 */
@IsTest
private class SamplePatternPluginTest {

    @TestSetup
    static void setupData() {
        // Create accounts with Rating = 'Cold' (should be matched)
        List<Account> coldAccounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            coldAccounts.add(new Account(
                Name = 'Cold Account ' + i,
                Rating = 'Cold'
            ));
        }
        insert coldAccounts;

        // Create accounts with other ratings (should not be matched)
        List<Account> otherAccounts = new List<Account>();
        otherAccounts.add(new Account(Name = 'Hot Account', Rating = 'Hot'));
        otherAccounts.add(new Account(Name = 'Warm Account', Rating = 'Warm'));
        otherAccounts.add(new Account(Name = 'No Rating Account'));
        insert otherAccounts;
    }

    @IsTest
    static void testAnalyze_FindsColdAccounts() {
        // Test: analyze() returns accounts with Rating = 'Cold'
        SamplePatternPlugin plugin = new SamplePatternPlugin();
        PatternPluginContext context = new PatternPluginContext();

        Test.startTest();
        List<Id> results = plugin.analyze(context);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should find 5 cold accounts');
    }

    @IsTest
    static void testAnalyze_ExcludesNonColdAccounts() {
        // Test: analyze() excludes accounts with other ratings
        SamplePatternPlugin plugin = new SamplePatternPlugin();

        Test.startTest();
        List<Id> results = plugin.analyze(null);
        Test.stopTest();

        // Verify all returned accounts have Rating = 'Cold'
        List<Account> returnedAccounts = [SELECT Id, Rating FROM Account WHERE Id IN :results];
        for (Account acc : returnedAccounts) {
            System.assertEquals('Cold', acc.Rating, 'All returned accounts should have Cold rating');
        }
    }

    @IsTest
    static void testFix_CreatesFollowUpTasks() {
        // Test: fix() creates follow-up tasks for the specified accounts
        List<Account> coldAccounts = [SELECT Id FROM Account WHERE Rating = 'Cold' LIMIT 3];
        List<Id> recordIds = new List<Id>();
        for (Account acc : coldAccounts) {
            recordIds.add(acc.Id);
        }

        SamplePatternPlugin plugin = new SamplePatternPlugin();
        Map<String, Object> config = new Map<String, Object>{
            'ruleDeveloperName' => 'Test_Sample_Plugin'
        };

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, config);
        Test.stopTest();

        // Verify tasks were created
        List<Task> createdTasks = [
            SELECT Id, WhatId, Subject, Priority, Status, ActivityDate
            FROM Task
            WHERE WhatId IN :recordIds
        ];

        System.assertEquals(3, createdTasks.size(), 'Should create 3 tasks');
        System.assertEquals('Follow up on cold account', createdTasks[0].Subject, 'Should have correct subject');
        System.assertEquals('Normal', createdTasks[0].Priority, 'Should have Normal priority');
        System.assertEquals('Not Started', createdTasks[0].Status, 'Should have Not Started status');
    }

    @IsTest
    static void testFix_WithNullConfig() {
        // Test: fix() works with null config
        List<Account> coldAccounts = [SELECT Id FROM Account WHERE Rating = 'Cold' LIMIT 2];
        List<Id> recordIds = new List<Id>();
        for (Account acc : coldAccounts) {
            recordIds.add(acc.Id);
        }

        SamplePatternPlugin plugin = new SamplePatternPlugin();

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, null);
        Test.stopTest();

        // Verify tasks were created
        List<Task> createdTasks = [SELECT Id FROM Task WHERE WhatId IN :recordIds];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks even with null config');
    }

    @IsTest
    static void testFix_WithEmptyRecordIds() {
        // Test: fix() handles empty record list
        SamplePatternPlugin plugin = new SamplePatternPlugin();
        Map<String, Object> config = new Map<String, Object>{
            'ruleDeveloperName' => 'Test_Rule'
        };

        Test.startTest();
        PatternPluginResult result = plugin.fix(new List<Id>(), config);
        Test.stopTest();

        // Should not throw exception
        System.assertNotEquals(null, result, 'Should return result object');
    }

    @IsTest
    static void testFix_TaskHasCorrectActivityDate() {
        // Test: Created tasks have activity date set to 7 days from today
        List<Account> coldAccounts = [SELECT Id FROM Account WHERE Rating = 'Cold' LIMIT 1];
        List<Id> recordIds = new List<Id>{ coldAccounts[0].Id };

        SamplePatternPlugin plugin = new SamplePatternPlugin();

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, new Map<String, Object>());
        Test.stopTest();

        Task createdTask = [SELECT ActivityDate FROM Task WHERE WhatId = :recordIds[0] LIMIT 1];
        System.assertEquals(Date.today().addDays(7), createdTask.ActivityDate, 'Activity date should be 7 days from today');
    }

    @IsTest
    static void testFix_ReturnsSuccessLogs() {
        // Test: fix() returns proper success logs
        List<Account> coldAccounts = [SELECT Id FROM Account WHERE Rating = 'Cold' LIMIT 2];
        List<Id> recordIds = new List<Id>();
        for (Account acc : coldAccounts) {
            recordIds.add(acc.Id);
        }

        SamplePatternPlugin plugin = new SamplePatternPlugin();
        Map<String, Object> config = new Map<String, Object>{
            'ruleDeveloperName' => 'Sample_Plugin_Pattern_Test'
        };

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, config);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return result');
        System.assertNotEquals(null, result.auditLogs, 'Should have audit logs');
    }

    @IsTest
    static void testAnalyze_RespectsLimit() {
        // Test: analyze() respects the LIMIT 100 in the query
        // Create additional cold accounts to approach limit
        List<Account> additionalAccounts = new List<Account>();
        for (Integer i = 0; i < 50; i++) {
            additionalAccounts.add(new Account(
                Name = 'Additional Cold Account ' + i,
                Rating = 'Cold'
            ));
        }
        insert additionalAccounts;

        SamplePatternPlugin plugin = new SamplePatternPlugin();

        Test.startTest();
        List<Id> results = plugin.analyze(new PatternPluginContext());
        Test.stopTest();

        // Should return at most 100 results
        System.assert(results.size() <= 100, 'Should respect LIMIT 100');
        System.assert(results.size() >= 5, 'Should include original cold accounts');
    }
}
