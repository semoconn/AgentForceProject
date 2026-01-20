/**
 * @description Test class for DeclarativeFixExecutor.
 * Tests JSON parsing, action execution, and error handling for declarative fixes.
 */
@IsTest
private class DeclarativeFixExecutorTest {

    @TestSetup
    static void setupTestData() {
        // Create test accounts with updateable fields
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Declarative Test Account ' + i,
                Description = 'Original Description',
                Industry = 'Technology'
            ));
        }
        insert accounts;
    }

    @IsTest
    static void testUpdateFieldAction() {
        // Test: UpdateField action successfully updates field
        List<Account> accounts = [SELECT Id FROM Account LIMIT 3];
        List<Id> recordIds = new List<Id>();
        for (Account acc : accounts) {
            recordIds.add(acc.Id);
        }

        String configJson = '{"actions": [{"type": "UpdateField", "field": "Industry", "value": "Healthcare"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(recordIds, configJson);
        Test.stopTest();

        // Verify field updated
        List<Account> updatedAccounts = [SELECT Id, Industry FROM Account WHERE Id IN :recordIds];
        for (Account acc : updatedAccounts) {
            System.assertEquals('Healthcare', acc.Industry, 'Industry should be updated');
        }

        // Verify logs created
        System.assertEquals(3, logs.size(), 'Should create log for each record');
        System.assertEquals('Success', logs[0].Status__c, 'Log should show success');
        System.assertEquals('UpdateField', logs[0].Action_Taken__c, 'Log should show action type');
    }

    @IsTest
    static void testUpdateFieldFromRecordAction() {
        // Test: UpdateFieldFromRecord copies value from another field
        Account testAccount = [SELECT Id, Name, Description FROM Account LIMIT 1];
        testAccount.Description = 'Copy this value';
        update testAccount;

        String configJson = '{"actions": [{"type": "UpdateFieldFromRecord", "targetField": "Site", "sourceField": "Description"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>{ testAccount.Id }, configJson);
        Test.stopTest();

        Account updated = [SELECT Site FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals('Copy this value', updated.Site, 'Site should be copied from Description');
    }

    @IsTest
    static void testCreateTaskAction() {
        // Test: CreateTask action creates tasks
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [{"type": "CreateTask", "subject": "Follow up on account", "priority": "High", "dueInDays": 3}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>{ testAccount.Id }, configJson);
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, Priority, WhatId, ActivityDate FROM Task WHERE WhatId = :testAccount.Id];
        System.assertEquals(1, tasks.size(), 'Should create one task');
        System.assertEquals('Follow up on account', tasks[0].Subject, 'Task subject should match');
        System.assertEquals('High', tasks[0].Priority, 'Task priority should match');
        System.assertEquals(Date.today().addDays(3), tasks[0].ActivityDate, 'Task due date should be 3 days out');
    }

    @IsTest
    static void testCreateTaskDefaultValues() {
        // Test: CreateTask uses defaults when not specified
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [{"type": "CreateTask"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>{ testAccount.Id }, configJson);
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, Priority, ActivityDate FROM Task WHERE WhatId = :testAccount.Id];
        System.assertEquals(1, tasks.size(), 'Should create one task');
        System.assertEquals('Action Required', tasks[0].Subject, 'Should use default subject');
        System.assertEquals('Normal', tasks[0].Priority, 'Should use default priority');
        System.assertEquals(Date.today().addDays(1), tasks[0].ActivityDate, 'Should use default 1 day');
    }

    @IsTest
    static void testPostChatterAction() {
        // Test: PostChatter creates feed item
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [{"type": "PostChatter", "message": "Attention required on this account."}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>{ testAccount.Id }, configJson);
        Test.stopTest();

        List<FeedItem> feeds = [SELECT Body, ParentId FROM FeedItem WHERE ParentId = :testAccount.Id];
        System.assertEquals(1, feeds.size(), 'Should create one feed item');
        System.assertEquals('Attention required on this account.', feeds[0].Body, 'Feed body should match');
    }

    @IsTest
    static void testMultipleActions() {
        // Test: Multiple actions execute in sequence
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [' +
            '{"type": "UpdateField", "field": "Industry", "value": "Finance"},' +
            '{"type": "CreateTask", "subject": "Industry changed"}' +
        ']}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>{ testAccount.Id }, configJson);
        Test.stopTest();

        // Verify both actions executed
        Account updated = [SELECT Industry FROM Account WHERE Id = :testAccount.Id];
        System.assertEquals('Finance', updated.Industry, 'Field should be updated');

        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :testAccount.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created');
        System.assertEquals('Industry changed', tasks[0].Subject, 'Task subject should match');

        // Verify logs for both actions
        System.assertEquals(2, logs.size(), 'Should have logs for both actions');
    }

    @IsTest
    static void testInvalidJsonThrowsException() {
        // Test: Invalid JSON throws DeclarativeFixException
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String invalidJson = 'not valid json';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, invalidJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for invalid JSON');
        System.assert(errorMessage.contains('Invalid Fix_Config__c JSON'), 'Error should mention invalid JSON');
    }

    @IsTest
    static void testMissingActionsArrayThrowsException() {
        // Test: Missing actions array throws exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"noActions": true}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, configJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for missing actions array');
    }

    @IsTest
    static void testUnknownActionTypeThrowsException() {
        // Test: Unknown action type throws exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [{"type": "UnknownAction"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, configJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for unknown action type');
        System.assert(errorMessage.contains('Unknown action type'), 'Error should mention unknown action');
    }

    @IsTest
    static void testUpdateFieldMissingFieldName() {
        // Test: UpdateField without field name throws exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        String configJson = '{"actions": [{"type": "UpdateField", "value": "NewValue"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, configJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for missing field name');
    }

    @IsTest
    static void testEmptyRecordIdsNoOp() {
        // Test: Empty record IDs list is a no-op
        String configJson = '{"actions": [{"type": "UpdateField", "field": "Industry", "value": "Test"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(new List<Id>(), configJson);
        Test.stopTest();

        System.assertEquals(0, logs.size(), 'Should not create any logs for empty input');
    }

    @IsTest
    static void testNullRecordIdsNoOp() {
        // Test: Null record IDs list is a no-op
        String configJson = '{"actions": [{"type": "UpdateField", "field": "Industry", "value": "Test"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(null, configJson);
        Test.stopTest();

        System.assertEquals(0, logs.size(), 'Should not create any logs for null input');
    }

    @IsTest
    static void testForceParseException() {
        // Test: Test hook for parse exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        DeclarativeFixExecutor.forceParseException = true;

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, '{"actions": []}');
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
        }
        DeclarativeFixExecutor.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when parse forced to fail');
    }

    @IsTest
    static void testForceUpdateException() {
        // Test: Test hook for update exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        DeclarativeFixExecutor.forceUpdateException = true;

        String configJson = '{"actions": [{"type": "UpdateField", "field": "Industry", "value": "Test"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, configJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
        }
        DeclarativeFixExecutor.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when update forced to fail');
        // Verify failure logged
        System.assert(logs.size() > 0, 'Should create failure log');
        System.assertEquals('Failed', logs[0].Status__c, 'Log should show failure');
    }

    @IsTest
    static void testForceTaskException() {
        // Test: Test hook for task creation exception
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        DeclarativeFixExecutor.forceTaskException = true;

        String configJson = '{"actions": [{"type": "CreateTask", "subject": "Test"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            executor.execute(new List<Id>{ testAccount.Id }, configJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException e) {
            exceptionThrown = true;
        }
        DeclarativeFixExecutor.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when task creation forced to fail');
    }

    @IsTest
    static void testBulkRecordProcessing() {
        // Test: Bulk processing of records
        List<Account> accounts = [SELECT Id FROM Account];
        List<Id> recordIds = new List<Id>();
        for (Account acc : accounts) {
            recordIds.add(acc.Id);
        }

        String configJson = '{"actions": [{"type": "UpdateField", "field": "Industry", "value": "Bulk Updated"}]}';

        List<Remediation_Log__c> logs = new List<Remediation_Log__c>();
        DeclarativeFixExecutor executor = new DeclarativeFixExecutor(logs, 'Test_Rule');

        Test.startTest();
        executor.execute(recordIds, configJson);
        Test.stopTest();

        // Verify all records updated
        List<Account> updatedAccounts = [SELECT Industry FROM Account WHERE Id IN :recordIds];
        for (Account acc : updatedAccounts) {
            System.assertEquals('Bulk Updated', acc.Industry, 'All records should be updated');
        }

        // Verify logs for all records
        System.assertEquals(accounts.size(), logs.size(), 'Should create log for each record');
    }
}
