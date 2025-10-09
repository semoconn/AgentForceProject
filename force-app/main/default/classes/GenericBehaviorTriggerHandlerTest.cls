/**
 * @description Comprehensive test class for the GenericBehaviorTriggerHandler.
 * This class ensures the handler works correctly for all DML events,
 * handles bulk operations, and is truly generic by testing its
 * functionality on multiple SObjects (Account, Contact, Lead, Opportunity, Case).
 * @see         GenericBehaviorTriggerHandler
 */
@isTest
private class GenericBehaviorTriggerHandlerTest {

    /**
     * @description Creates common test data available for all test methods.
     */
    @TestSetup
    static void makeData(){
        Account parentAccount = new Account(Name = 'Parent Test Account');
        insert parentAccount;
    }

    //================================================================
    // ACCOUNT TRIGGER TESTS
    //================================================================

    @isTest
    static void testAccountInsertSingleRecord() {
        // ARRANGE
        Account testAcc = new Account(Name = 'Test Account Insert');

        // ACT
        Test.startTest();
            insert testAcc;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testAcc.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account insert.');
    }

    @isTest
    static void testAccountUpdateSingleRecord() {
        // ARRANGE
        Account testAcc = [SELECT Id, Name FROM Account LIMIT 1];
        
        // ACT
        testAcc.Name = 'Updated Account Name';
        Test.startTest();
            update testAcc;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testAcc.Id AND Action_Name__c = 'Record_Updated'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account update.');
    }

    @isTest
    static void testAccountDeleteSingleRecord() {
        // ARRANGE
        Account testAcc = [SELECT Id FROM Account LIMIT 1];
        
        // ACT
        Test.startTest();
            delete testAcc;
        Test.stopTest(); // Ensures Platform Event is processed
        
        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testAcc.Id AND Action_Name__c = 'Record_Deleted'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account delete.');
    }

    @isTest
    static void testAccountUndeleteSingleRecord() {
        // ARRANGE
        Account testAcc = new Account(Name = 'Test Undelete Account');
        insert testAcc;
        Id accId = testAcc.Id;
        delete testAcc;
        
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
        
        Account deletedAcc = [SELECT Id FROM Account WHERE Id = :accId ALL ROWS];
        
        // ACT
        Test.startTest();
            undelete deletedAcc;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id FROM Workflow_Log__c
            WHERE Record_ID__c = :accId AND Action_Name__c = 'Record_Undeleted'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account undelete.');
    }

    //================================================================
    // CONTACT TRIGGER TESTS
    //================================================================

    @isTest
    static void testContactInsertSingleRecord() {
        // ARRANGE
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];
        Contact testCon = new Contact(LastName = 'TestContact', AccountId = parentAcc.Id);
        
        // ACT
        Test.startTest();
            insert testCon;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testCon.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Contact insert.');
    }

    @isTest
    static void testContactUpdateSingleRecord() {
        // ARRANGE
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];
        Contact testCon = new Contact(LastName = 'OriginalContact', AccountId = parentAcc.Id);
        insert testCon;
        
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
        
        // ACT
        testCon.LastName = 'UpdatedContact';
        Test.startTest();
            update testCon;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        List<Workflow_Log__c> logs = [
            SELECT Id FROM Workflow_Log__c
            WHERE Record_ID__c = :testCon.Id AND Action_Name__c = 'Record_Updated'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Contact update.');
    }

    //================================================================
    // LEAD, OPPORTUNITY, CASE TESTS
    //================================================================
    @isTest
    static void testLeadInsertSingleRecord() {
        Lead testLead = new Lead(LastName = 'TestLead', Company = 'Test Corp');
        
        Test.startTest();
            insert testLead;
        Test.stopTest(); // Ensures Platform Event is processed

        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testLead.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Lead insert.');
    }

    @isTest
    static void testOpportunityInsertSingleRecord() {
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];
        Opportunity testOpp = new Opportunity(Name = 'Test Opp', StageName = 'Prospecting', CloseDate = Date.today().addMonths(1), AccountId = parentAcc.Id);

        Test.startTest();
            insert testOpp;
        Test.stopTest(); // Ensures Platform Event is processed

        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testOpp.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Opportunity insert.');
    }

    @isTest
    static void testCaseInsertSingleRecord() {
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];
        Case testCase = new Case(Subject = 'Test Case', Status = 'New', AccountId = parentAcc.Id);

        Test.startTest();
            insert testCase;
        Test.stopTest(); // Ensures Platform Event is processed

        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testCase.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Case insert.');
    }

    //================================================================
    // BULK OPERATION TESTS
    //================================================================

    @isTest
    static void testAccountInsertBulkRecords() {
        // ARRANGE
        List<Account> accountList = new List<Account>();
        for(Integer i = 0; i < 50; i++) {
            accountList.add(new Account(Name = 'Bulk Test Account ' + i));
        }
        
        // ACT
        Test.startTest();
            insert accountList;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        // Query for the total number of logs created by this test, excluding setup data.
        Integer creationLogsCount = [
            SELECT COUNT() FROM Workflow_Log__c 
            WHERE Action_Name__c = 'Record_Created' 
            AND CreatedDate = TODAY
        ];
        System.assert(creationLogsCount >= 50, 'At least 50 creation logs should exist. Found: ' + creationLogsCount);

        List<Workflow_Log__c> bulkLogs = [
            SELECT Id FROM Workflow_Log__c WHERE Action_Name__c = 'Bulk_Creation_Detected'
        ];
        System.assertEquals(1, bulkLogs.size(), 'A single bulk creation log should be created.');
    }

    @isTest
    static void testAccountUpdateBulkRecords() {
        // ARRANGE
        List<Account> accountList = new List<Account>();
        for(Integer i = 0; i < 50; i++) {
            accountList.add(new Account(Name = 'Bulk Update Account ' + i));
        }
        insert accountList;

        for(Account acc : accountList) {
            acc.Name = acc.Name + ' (Updated)';
        }
        
        GenericBehaviorTriggerHandler.clearProcessedIdsForTest();

        // ACT
        Test.startTest();
            update accountList;
        Test.stopTest(); // Ensures Platform Event is processed

        // ASSERT
        Integer updateLogsCount = [
            SELECT COUNT() FROM Workflow_Log__c 
            WHERE Action_Name__c = 'Record_Updated'
            AND CreatedDate = TODAY // Filter to this test's execution
        ];
        System.assert(updateLogsCount >= 50, 'At least 50 update logs should exist. Found: ' + updateLogsCount);

        List<Workflow_Log__c> bulkLogs = [
            SELECT Id FROM Workflow_Log__c WHERE Action_Name__c = 'Mass_Update_Detected'
        ];
        System.assertEquals(1, bulkLogs.size(), 'A single mass update log should be created.');
    }
}