/**
 * @description Test class for GenericBehaviorTriggerHandler.
 * @version 2.5 - Final version incorporating recursion guard reset for accurate multi-DML testing.
 */
@isTest
private with sharing class GenericBehaviorTriggerHandlerTest {

    @TestSetup
    static void makeData() {
        insert new Account(Name='Test Parent Account');
    }

    @isTest
    static void testAccountInsertCreatesBehaviorLog() {
        // Ensure a clean state for the recursion guard.
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();

        Test.startTest();
            insert new Account(Name = 'Test Account Insert');
            // Force the platform event to be delivered immediately for testing.
            Test.getEventBus().deliver();
        Test.stopTest(); 

        List<Behavior_Log__c> logs = [SELECT Id FROM Behavior_Log__c WHERE Action_Name__c = 'Record_Created'];
        System.assertEquals(1, logs.size(), 'A log should be created on Account insert.');
    }

    @isTest
    static void testContactUpdateCreatesBehaviorLog() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact testCon = new Contact(LastName = 'OriginalName', AccountId = acc.Id);
        insert testCon;

        // CRITICAL FIX: Clear the static recursion guard after the initial insert
        // so the subsequent update will be processed as a new transaction.
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();

        Test.startTest();
            testCon.LastName = 'Updated Name';
            update testCon;
            Test.getEventBus().deliver();
        Test.stopTest();

        List<Behavior_Log__c> logs = [SELECT Id FROM Behavior_Log__c WHERE Action_Name__c = 'Record_Updated'];
        System.assertEquals(1, logs.size(), 'A log should be created on Contact update.');
    }
    
    @isTest
    static void testLeadDeleteCreatesBehaviorLog() {
        Lead testLead = new Lead(LastName = 'ToDelete', Company = 'Test Corp');
        insert testLead;

        // CRITICAL FIX: Clear the guard so the delete operation will be processed.
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();

        Test.startTest();
            delete testLead;
            Test.getEventBus().deliver();
        Test.stopTest(); 

        List<Behavior_Log__c> logs = [SELECT Id FROM Behavior_Log__c WHERE Action_Name__c = 'Record_Deleted'];
        System.assertEquals(1, logs.size(), 'A log should be created on Lead delete.');
    }

    @isTest
    static void testCaseUndeleteCreatesBehaviorLog() {
        Case testCase = new Case(Subject = 'Test Undelete');
        insert testCase;
        
        // CRITICAL FIX: Clear the guard after the setup insert.
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
        
        Test.startTest();
            delete testCase;
            // The undelete is part of the same test transaction block as delete,
            // but targets a different DML operation (delete vs undelete),
            // so we add another clear for absolute safety.
            GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
            undelete testCase;
            Test.getEventBus().deliver();
        Test.stopTest();

        List<Behavior_Log__c> logs = [SELECT Action_Name__c FROM Behavior_Log__c WHERE Action_Name__c = 'Record_Undeleted'];
        System.assertEquals(1, logs.size(), 'A log should be created on Case undelete.');
    }
}