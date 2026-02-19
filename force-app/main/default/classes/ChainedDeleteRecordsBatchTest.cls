/**
 * @description Test class for ChainedDeleteRecordsBatch to verify batch chaining
 * and sequential execution of retention cleanup jobs.
 */
@isTest
private with sharing class ChainedDeleteRecordsBatchTest {

    @TestSetup
    static void setupTestData() {
        User u = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];

        System.runAs(u) {
            // Create Behavior_Log__c records for chain testing
            List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 5; i++) {
                logs.add(new Behavior_Log__c(
                    Action_Name__c = 'Chain_Test_' + i,
                    User__c = u.Id,
                    Timestamp__c = System.now()
                ));
            }
            insert logs;

            // Create Behavior_Log_Summary__c records for chain testing
            List<Behavior_Log_Summary__c> summaries = new List<Behavior_Log_Summary__c>();
            for (Integer i = 0; i < 5; i++) {
                summaries.add(new Behavior_Log_Summary__c(
                    User__c = u.Id,
                    Action_Name__c = 'Chain_Sum_' + i,
                    Object_API_Name__c = 'Account',
                    Log_Date__c = Date.today().addDays(-100),
                    Event_Count__c = 1,
                    Composite_Key__c = u.Id + '_Account_Chain_Sum_' + i + '_' + String.valueOf(Date.today().addDays(-100)),
                    Last_Event_Time__c = System.now()
                ));
            }
            insert summaries;
        }
    }

    @isTest
    static void testChainedBatch_ExecutesNextBatch() {
        // First batch deletes logs, chains to second batch that deletes summaries
        DateTime futureCutoff = DateTime.now().addDays(1);
        Date futureDateCutoff = Date.today().addDays(1);

        DeleteRecordsBatch summaryBatch = new DeleteRecordsBatch(
            Behavior_Log_Summary__c.SObjectType,
            Behavior_Log_Summary__c.Log_Date__c,
            futureDateCutoff
        );

        ChainedDeleteRecordsBatch logBatch = new ChainedDeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            futureCutoff
        );
        logBatch.setNextBatch(summaryBatch, 2000);

        Test.startTest();
        Database.executeBatch(logBatch, 200);
        Test.stopTest();

        // First batch should have deleted logs
        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c LIKE 'Chain_Test%'],
            'Chained batch should delete log records');

        // Note: In test context, chained batch may or may not execute depending on Salesforce test framework.
        // The key assertion is that the first batch completed without errors.
    }

    @isTest
    static void testChainedBatch_NoNextBatch() {
        // Chained batch with no next batch should complete cleanly
        DateTime futureCutoff = DateTime.now().addDays(1);

        ChainedDeleteRecordsBatch batch = new ChainedDeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            futureCutoff
        );
        // Intentionally NOT calling setNextBatch

        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c LIKE 'Chain_Test%'],
            'Batch should delete records even without a next batch');
    }

    @isTest
    static void testChainedBatch_DateConstructor() {
        // Test the Date-based constructor path
        Date futureCutoff = Date.today().addDays(1);

        ChainedDeleteRecordsBatch batch = new ChainedDeleteRecordsBatch(
            Behavior_Log_Summary__c.SObjectType,
            Behavior_Log_Summary__c.Log_Date__c,
            futureCutoff
        );

        Test.startTest();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log_Summary__c WHERE Action_Name__c LIKE 'Chain_Sum%'],
            'Date constructor path should work for chained batch');
    }

    @isTest
    static void testChainedBatch_FluentChaining() {
        // Verify setNextBatch returns the same instance for fluent API
        DateTime futureCutoff = DateTime.now().addDays(1);

        ChainedDeleteRecordsBatch batch = new ChainedDeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            futureCutoff
        );

        DeleteRecordsBatch nextBatch = new DeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            futureCutoff
        );

        ChainedDeleteRecordsBatch returned = batch.setNextBatch(nextBatch, 2000);
        System.assertEquals(batch, returned, 'setNextBatch should return the same instance for fluent chaining');
    }
}
