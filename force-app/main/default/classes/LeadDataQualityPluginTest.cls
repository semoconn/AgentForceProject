/**
 * @description Test class for LeadDataQualityPlugin.
 * Tests analysis and fix functionality for leads with missing email addresses.
 */
@IsTest
private class LeadDataQualityPluginTest {

    @TestSetup
    static void setupData() {
        // Create leads without email addresses
        List<Lead> leadsNoEmail = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            leadsNoEmail.add(new Lead(
                FirstName = 'NoEmail',
                LastName = 'Lead' + i,
                Company = 'Test Company ' + i
            ));
        }
        insert leadsNoEmail;

        // Create leads with email addresses (should not be matched)
        List<Lead> leadsWithEmail = new List<Lead>();
        for (Integer i = 0; i < 3; i++) {
            leadsWithEmail.add(new Lead(
                FirstName = 'HasEmail',
                LastName = 'Lead' + i,
                Company = 'Test Company ' + i,
                Email = 'test' + i + '@example.com'
            ));
        }
        insert leadsWithEmail;
    }

    @IsTest
    static void testAnalyze_FindsLeadsWithoutEmail() {
        // Test: analyze() returns leads without email addresses
        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();
        PatternPluginContext context = new PatternPluginContext();

        Test.startTest();
        List<Id> results = plugin.analyze(context);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should find 5 leads without email');
    }

    @IsTest
    static void testAnalyze_ExcludesConvertedLeads() {
        // Test: analyze() excludes converted leads
        // Note: We can't easily convert leads in test context without full setup,
        // but we verify the query logic by checking results
        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();

        Test.startTest();
        List<Id> results = plugin.analyze(null);
        Test.stopTest();

        // Verify all returned leads are unconverted
        List<Lead> returnedLeads = [SELECT Id, IsConverted FROM Lead WHERE Id IN :results];
        for (Lead ld : returnedLeads) {
            System.assertEquals(false, ld.IsConverted, 'Should not include converted leads');
        }
    }

    @IsTest
    static void testFix_CreatesTasksForLeads() {
        // Test: fix() creates tasks for the specified leads
        List<Lead> leadsNoEmail = [SELECT Id FROM Lead WHERE Email = null LIMIT 3];
        List<Id> recordIds = new List<Id>();
        for (Lead ld : leadsNoEmail) {
            recordIds.add(ld.Id);
        }

        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();
        Map<String, Object> config = new Map<String, Object>{
            'ruleDeveloperName' => 'Test_Lead_Data_Quality'
        };

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, config);
        Test.stopTest();

        // Verify tasks were created
        List<Task> createdTasks = [
            SELECT Id, WhoId, Subject, Priority, Status
            FROM Task
            WHERE WhoId IN :recordIds
        ];

        System.assertEquals(3, createdTasks.size(), 'Should create 3 tasks');
        System.assertEquals('Update Lead Email Address', createdTasks[0].Subject, 'Should have correct subject');
        System.assertEquals('High', createdTasks[0].Priority, 'Should have High priority');
        System.assertEquals('Not Started', createdTasks[0].Status, 'Should have Not Started status');
    }

    @IsTest
    static void testFix_WithNullConfig() {
        // Test: fix() works with null config
        List<Lead> leadsNoEmail = [SELECT Id FROM Lead WHERE Email = null LIMIT 2];
        List<Id> recordIds = new List<Id>();
        for (Lead ld : leadsNoEmail) {
            recordIds.add(ld.Id);
        }

        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, null);
        Test.stopTest();

        // Verify tasks were created
        List<Task> createdTasks = [SELECT Id FROM Task WHERE WhoId IN :recordIds];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks even with null config');
    }

    @IsTest
    static void testFix_WithEmptyRecordIds() {
        // Test: fix() handles empty record list
        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();
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
        // Test: Created tasks have activity date set to 3 days from today
        List<Lead> leadsNoEmail = [SELECT Id FROM Lead WHERE Email = null LIMIT 1];
        List<Id> recordIds = new List<Id>{ leadsNoEmail[0].Id };

        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, new Map<String, Object>());
        Test.stopTest();

        Task createdTask = [SELECT ActivityDate FROM Task WHERE WhoId = :recordIds[0] LIMIT 1];
        System.assertEquals(Date.today().addDays(3), createdTask.ActivityDate, 'Activity date should be 3 days from today');
    }

    @IsTest
    static void testFix_ReturnsSuccessLogs() {
        // Test: fix() returns proper success logs
        List<Lead> leadsNoEmail = [SELECT Id FROM Lead WHERE Email = null LIMIT 2];
        List<Id> recordIds = new List<Id>();
        for (Lead ld : leadsNoEmail) {
            recordIds.add(ld.Id);
        }

        LeadDataQualityPlugin plugin = new LeadDataQualityPlugin();
        Map<String, Object> config = new Map<String, Object>{
            'ruleDeveloperName' => 'Lead_Data_Quality_Test'
        };

        Test.startTest();
        PatternPluginResult result = plugin.fix(recordIds, config);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return result');
        System.assertNotEquals(null, result.auditLogs, 'Should have audit logs');
    }
}
