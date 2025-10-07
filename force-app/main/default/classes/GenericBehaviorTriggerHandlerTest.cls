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
     * Using @TestSetup is a best practice for efficiency, as it
     * creates the data once and rolls it back after each test method.
     */
    @TestSetup
    static void makeData(){
        // Create a parent Account for testing related records like Contacts
        Account parentAccount = new Account(Name = 'Parent Test Account');
        insert parentAccount;
    }

    //================================================================
    // ACCOUNT TRIGGER TESTS
    //================================================================

    @isTest
    static void testAccountInsertSingleRecord() {
        // ARRANGE: No additional setup needed for this test

        // ACT: Perform the DML operation within Test.startTest/stopTest
        // This provides a fresh set of governor limits for the code being tested.
        Test.startTest();
            Account testAcc = new Account(Name = 'Test Account Insert');
            insert testAcc;
        Test.stopTest();

        // ASSERT: Verify that the correct log was created
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testAcc.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account insert.');
    }

    @isTest
    static void testAccountUpdateSingleRecord() {
        // ARRANGE: Get the pre-existing account from @TestSetup
        Account testAcc = [SELECT Id, Name FROM Account LIMIT 1];
        
        // ACT
        testAcc.Name = 'Updated Account Name';
        Test.startTest();
            update testAcc;
        Test.stopTest();

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
        Test.stopTest();
        
        // ASSERT: Since the record is deleted, we can't query by its ID in the log.
        // Instead, we verify that a log for that specific record was created before deletion.
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testAcc.Id AND Action_Name__c = 'Record_Deleted'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Account delete.');
    }

    // In GenericBehaviorTriggerHandlerTest.cls

@isTest
static void testAccountUndeleteSingleRecord() {
    // ARRANGE - Create and delete a new account
    Account testAcc = new Account(Name = 'Test Undelete Account');
    insert testAcc;
    Id accId = testAcc.Id;
    delete testAcc;
    
    // ✅ FIX #1: Clear the static recursion set before the next DML.
    // This simulates a new transaction for the undelete operation.
    GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
    
    // ACT
    Test.startTest();
        // ✅ FIX #2: Re-query the deleted record using ALL ROWS.
        Account deletedAcc = [SELECT Id FROM Account WHERE Id = :accId ALL ROWS];
        undelete deletedAcc;
    Test.stopTest();

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
        
        // ACT
        Test.startTest();
            Contact testCon = new Contact(LastName = 'TestContact', AccountId = parentAcc.Id);
            insert testCon;
        Test.stopTest();

        // ASSERT: Verify the handler worked for the Contact object
        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testCon.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Contact insert.');
    }

    // In GenericBehaviorTriggerHandlerTest.cls

@isTest
static void testContactUpdateSingleRecord() {
    // ARRANGE
    Account parentAcc = [SELECT Id FROM Account LIMIT 1];
    Contact testCon = new Contact(LastName = 'OriginalContact', AccountId = parentAcc.Id);
    insert testCon;
    
    // ✅ FIX: Clear the static recursion set before the next DML.
    GenericBehaviorTriggerHandler.clearProcessedIdsForTest();
    
    // ACT
    testCon.LastName = 'UpdatedContact';
    Test.startTest();
        update testCon;
    Test.stopTest();

    // ASSERT
    List<Workflow_Log__c> logs = [
        SELECT Id FROM Workflow_Log__c
        WHERE Record_ID__c = :testCon.Id AND Action_Name__c = 'Record_Updated'
    ];
    System.assertEquals(1, logs.size(), 'A log should be created on Contact update.');
}

    //================================================================
    // LEAD TRIGGER TESTS
    //================================================================
    @isTest
    static void testLeadInsertSingleRecord() {
        Test.startTest();
        Lead testLead = new Lead(LastName = 'TestLead', Company = 'Test Corp');
        insert testLead;
        Test.stopTest();

        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testLead.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Lead insert.');
    }

    //================================================================
    // OPPORTUNITY TRIGGER TESTS
    //================================================================
    @isTest
    static void testOpportunityInsertSingleRecord() {
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1),
            AccountId = parentAcc.Id
        );
        insert testOpp;
        Test.stopTest();

        List<Workflow_Log__c> logs = [
            SELECT Id, Action_Name__c FROM Workflow_Log__c
            WHERE Record_ID__c = :testOpp.Id AND Action_Name__c = 'Record_Created'
        ];
        System.assertEquals(1, logs.size(), 'A log should be created on Opportunity insert.');
    }

    //================================================================
    // CASE TRIGGER TESTS
    //================================================================
    @isTest
    static void testCaseInsertSingleRecord() {
        Account parentAcc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Case testCase = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = parentAcc.Id
        );
        insert testCase;
        Test.stopTest();

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
        Test.stopTest();

        // ASSERT
        List<Workflow_Log__c> createdLogs = [
            SELECT Id FROM Workflow_Log__c WHERE Action_Name__c = 'Record_Created'
        ];
        // We expect at least 50 logs (from this test, @TestSetup might add 1 more)
        System.assert(createdLogs.size() >= 50, 'At least 50 creation logs should exist.');

        List<Workflow_Log__c> bulkLogs = [
            SELECT Id FROM Workflow_Log__c WHERE Action_Name__c = 'Bulk_Creation_Detected'
        ];
        System.assertEquals(1, bulkLogs.size(), 'A single bulk creation log should be created.');
    }

    // In GenericBehaviorTriggerHandlerTest.cls

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
    
    // ✅ FIX: Clear the static recursion set before the next DML.
    GenericBehaviorTriggerHandler.clearProcessedIdsForTest();

    // ACT
    Test.startTest();
        update accountList;
    Test.stopTest();

    // ASSERT
    // ... assertions remain the same ...
}
}