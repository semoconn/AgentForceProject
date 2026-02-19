/**
 * @description Test class for DeleteRecordsBatch to ensure coverage on executable logic paths.
 * @version 2.0 - Updated to use Schema token constructors (injection-proof).
 */
@isTest
private with sharing class DeleteRecordsBatchTest {

    @TestSetup
    static void setupTestData() {
        User u = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];

        System.runAs(u) {
            // Create logs for deletion
            List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 20; i++) {
                logs.add(new Behavior_Log__c(
                    Action_Name__c = 'To_Delete_' + i,
                    User__c = u.Id,
                    Timestamp__c = System.now()
                ));
            }
            insert logs;

            // Insert a log that should remain (not targeted by cutoff)
            List<Behavior_Log__c> keepLog = new List<Behavior_Log__c>{
                new Behavior_Log__c(
                    Action_Name__c = 'Dml_Fail_Log',
                    User__c = u.Id,
                    Timestamp__c = System.now()
                )
            };
            insert keepLog;
        }
    }

    @isTest
    static void test01_SuccessfulDeletion() {
        // Use DateTime constructor — cutoff in the future deletes all records
        DateTime futureCutoff = DateTime.now().addDays(1);

        Test.startTest();
        Database.executeBatch(new DeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            futureCutoff
        ), 200);
        Test.stopTest();

        // All logs should be deleted (cutoff is in the future)
        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c], 'All logs should be deleted when cutoff is in the future.');
    }

    @isTest
    static void test02_EmptyScopeAndNonDeletablePath() {
        // Use DateTime constructor — cutoff far in the past returns no records
        DateTime pastCutoff = Datetime.newInstanceGmt(1900, 1, 1);
        Integer initialCount = [SELECT COUNT() FROM Behavior_Log__c];

        Test.startTest();
        Database.executeBatch(new DeleteRecordsBatch(
            Behavior_Log__c.SObjectType,
            Behavior_Log__c.CreatedDate,
            pastCutoff
        ), 200);
        Test.stopTest();

        // Assert: No deletion happened
        System.assertEquals(initialCount, [SELECT COUNT() FROM Behavior_Log__c], 'No deletion should occur for empty scope.');
    }

    @isTest
    static void test03_DeleteSummaryRecords() {
        // Verify DeleteRecordsBatch works with Behavior_Log_Summary__c (Date field constructor)
        User u = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];

        System.runAs(u) {
            List<Behavior_Log_Summary__c> summaries = new List<Behavior_Log_Summary__c>();
            for (Integer i = 0; i < 5; i++) {
                summaries.add(new Behavior_Log_Summary__c(
                    User__c = u.Id,
                    Action_Name__c = 'Delete_Test_' + i,
                    Object_API_Name__c = 'Account',
                    Log_Date__c = Date.today().addDays(-100),
                    Event_Count__c = 1,
                    Composite_Key__c = u.Id + '_Account_Delete_Test_' + i + '_' + String.valueOf(Date.today().addDays(-100)),
                    Last_Event_Time__c = System.now()
                ));
            }
            insert summaries;
        }

        // Date cutoff: anything before yesterday should delete the -100 day records
        Date cutoff = Date.today().addDays(-1);

        Test.startTest();
        Database.executeBatch(new DeleteRecordsBatch(
            Behavior_Log_Summary__c.SObjectType,
            Behavior_Log_Summary__c.Log_Date__c,
            cutoff
        ), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log_Summary__c WHERE Action_Name__c LIKE 'Delete_Test%'],
            'All targeted summaries should be deleted');
    }
}
