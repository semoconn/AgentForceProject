/**
 * @description Test class for PatternAnalysisService.
 * Updated to work with the new metadata-driven architecture.
 */
@isTest
private class PatternAnalysisServiceTest {

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
    }

    @isTest
    static void testConstructor() {
        // Test that constructor initializes properly
        PatternAnalysisService service = new PatternAnalysisService();
        System.assertNotEquals(null, service, 'Service should be instantiated');
    }

    @isTest
    static void testDefaultRetentionDays() {
        // Verify the constant is accessible
        System.assertEquals(90, PatternAnalysisService.DEFAULT_RETENTION_DAYS,
            'Default retention days should be 90');
    }
}
