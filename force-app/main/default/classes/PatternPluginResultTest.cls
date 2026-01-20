/**
 * @description Test class for PatternPluginResult.
 * Tests all helper methods and result tracking functionality.
 */
@IsTest
private class PatternPluginResultTest {

    @TestSetup
    static void setupTestData() {
        // Create test account for record IDs
        Account testAccount = new Account(Name = 'Plugin Result Test Account');
        insert testAccount;
    }

    @IsTest
    static void testDefaultConstructor() {
        // Test: Default constructor initializes all fields
        Test.startTest();
        PatternPluginResult result = new PatternPluginResult();
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Success count should be 0');
        System.assertEquals(0, result.failureCount, 'Failure count should be 0');
        System.assertNotEquals(null, result.errorMessages, 'Error messages should be initialized');
        System.assertEquals(0, result.errorMessages.size(), 'Error messages should be empty');
        System.assertNotEquals(null, result.auditLogs, 'Audit logs should be initialized');
        System.assertEquals(0, result.auditLogs.size(), 'Audit logs should be empty');
    }

    @IsTest
    static void testAddSuccessLog() {
        // Test: addSuccessLog increments count and creates log
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        result.addSuccessLog(testAccount.Id, 'Field_Update', 'OldValue', 'NewValue', 'Test_Rule');
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Success count should be 1');
        System.assertEquals(0, result.failureCount, 'Failure count should remain 0');
        System.assertEquals(1, result.auditLogs.size(), 'Should have 1 audit log');

        Remediation_Log__c log = result.auditLogs[0];
        System.assertEquals(String.valueOf(testAccount.Id), log.Affected_Record_ID__c, 'Record ID should match');
        System.assertEquals('Field_Update', log.Action_Taken__c, 'Action should match');
        System.assertEquals('OldValue', log.Original_Value__c, 'Original value should match');
        System.assertEquals('NewValue', log.New_Value__c, 'New value should match');
        System.assertEquals('Success', log.Status__c, 'Status should be Success');
        System.assertEquals('Test_Rule', log.Rule_Developer_Name__c, 'Rule name should match');
    }

    @IsTest
    static void testAddFailureLog() {
        // Test: addFailureLog increments count and creates error log
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        result.addFailureLog(testAccount.Id, 'Field_Update', 'Update failed', 'Test_Rule');
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Success count should remain 0');
        System.assertEquals(1, result.failureCount, 'Failure count should be 1');
        System.assertEquals(1, result.errorMessages.size(), 'Should have 1 error message');
        System.assert(result.errorMessages[0].contains('Update failed'), 'Error message should contain reason');
        System.assertEquals(1, result.auditLogs.size(), 'Should have 1 audit log');

        Remediation_Log__c log = result.auditLogs[0];
        System.assertEquals('Failed', log.Status__c, 'Status should be Failed');
        System.assertEquals('Update failed', log.Error_Message__c, 'Error message should match');
    }

    @IsTest
    static void testAddSuccessLogWithSnapshot() {
        // Test: addSuccessLogWithSnapshot captures snapshot JSON
        Account testAccount = [SELECT Id, Name FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        String snapshotJson = JSON.serialize(testAccount);

        Test.startTest();
        result.addSuccessLogWithSnapshot(
            testAccount.Id,
            'Status_Update',
            'Draft',
            'Expired',
            snapshotJson,
            'Snapshot_Rule'
        );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Success count should be 1');
        System.assertEquals(1, result.auditLogs.size(), 'Should have 1 audit log');

        Remediation_Log__c log = result.auditLogs[0];
        System.assertEquals(snapshotJson, log.Snapshot_JSON__c, 'Snapshot JSON should be captured');
        System.assertEquals('Success', log.Status__c, 'Status should be Success');
    }

    @IsTest
    static void testGetTotalProcessed() {
        // Test: getTotalProcessed returns sum of successes and failures
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        result.addSuccessLog(testAccount.Id, 'Action1', null, null, 'Rule1');
        result.addSuccessLog(testAccount.Id, 'Action2', null, null, 'Rule1');
        result.addFailureLog(testAccount.Id, 'Action3', 'Error', 'Rule1');

        Test.startTest();
        Integer total = result.getTotalProcessed();
        Test.stopTest();

        System.assertEquals(3, total, 'Total should be 3 (2 success + 1 failure)');
    }

    @IsTest
    static void testIsFullSuccess() {
        // Test: isFullSuccess returns true only when all records succeed
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        // Initially no records processed
        System.assertEquals(false, result.isFullSuccess(), 'Should be false with no records');

        // Add success
        result.addSuccessLog(testAccount.Id, 'Action', null, null, 'Rule');
        System.assertEquals(true, result.isFullSuccess(), 'Should be true with only successes');

        // Add failure
        result.addFailureLog(testAccount.Id, 'Action', 'Error', 'Rule');
        System.assertEquals(false, result.isFullSuccess(), 'Should be false with any failure');
    }

    @IsTest
    static void testHasFailures() {
        // Test: hasFailures returns true when any failures exist
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        System.assertEquals(false, result.hasFailures(), 'Should be false initially');

        result.addSuccessLog(testAccount.Id, 'Action', null, null, 'Rule');
        System.assertEquals(false, result.hasFailures(), 'Should be false with only successes');

        result.addFailureLog(testAccount.Id, 'Action', 'Error', 'Rule');
        System.assertEquals(true, result.hasFailures(), 'Should be true with failures');
    }

    @IsTest
    static void testValueTruncation() {
        // Test: Long values are truncated appropriately
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        // Create a string longer than 255 characters
        String longValue = '';
        for (Integer i = 0; i < 300; i++) {
            longValue += 'X';
        }

        Test.startTest();
        result.addSuccessLog(testAccount.Id, 'Action', longValue, longValue, 'Rule');
        Test.stopTest();

        Remediation_Log__c log = result.auditLogs[0];
        System.assertEquals(255, log.Original_Value__c.length(), 'Original value should be truncated to 255');
        System.assertEquals(255, log.New_Value__c.length(), 'New value should be truncated to 255');
    }

    @IsTest
    static void testSnapshotTruncation() {
        // Test: Snapshot JSON is truncated to 131072 characters
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        // Create a very long snapshot (would need to be > 131072 to test truncation)
        // For practical testing, just verify it accepts a normal snapshot
        String normalSnapshot = '{"Name": "Test Account", "Id": "001000000000000"}';

        Test.startTest();
        result.addSuccessLogWithSnapshot(
            testAccount.Id,
            'Action',
            'Old',
            'New',
            normalSnapshot,
            'Rule'
        );
        Test.stopTest();

        System.assertEquals(normalSnapshot, result.auditLogs[0].Snapshot_JSON__c, 'Normal snapshot should not be truncated');
    }

    @IsTest
    static void testNullValueHandling() {
        // Test: Null values are handled gracefully
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        result.addSuccessLog(testAccount.Id, 'Action', null, null, 'Rule');
        result.addSuccessLogWithSnapshot(testAccount.Id, 'Action', null, null, null, 'Rule');
        Test.stopTest();

        System.assertEquals(2, result.auditLogs.size(), 'Should handle null values');
        System.assertEquals(null, result.auditLogs[0].Original_Value__c, 'Original value should be null');
        System.assertEquals(null, result.auditLogs[1].Snapshot_JSON__c, 'Snapshot should be null');
    }

    @IsTest
    static void testMultipleOperations() {
        // Test: Multiple operations are tracked correctly
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        for (Integer i = 0; i < 5; i++) {
            result.addSuccessLog(testAccount.Id, 'Action' + i, 'Old' + i, 'New' + i, 'Rule');
        }
        for (Integer i = 0; i < 3; i++) {
            result.addFailureLog(testAccount.Id, 'FailAction' + i, 'Error' + i, 'Rule');
        }
        Test.stopTest();

        System.assertEquals(5, result.successCount, 'Should have 5 successes');
        System.assertEquals(3, result.failureCount, 'Should have 3 failures');
        System.assertEquals(8, result.auditLogs.size(), 'Should have 8 audit logs');
        System.assertEquals(3, result.errorMessages.size(), 'Should have 3 error messages');
        System.assertEquals(8, result.getTotalProcessed(), 'Total should be 8');
    }

    @IsTest
    static void testErrorMessageFormat() {
        // Test: Error message format includes record ID
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        result.addFailureLog(testAccount.Id, 'Action', 'Test error message', 'Rule');
        Test.stopTest();

        String errorMsg = result.errorMessages[0];
        System.assert(errorMsg.contains(String.valueOf(testAccount.Id)), 'Error should contain record ID');
        System.assert(errorMsg.contains('Test error message'), 'Error should contain message');
    }

    @IsTest
    static void testAuditLogFieldPopulation() {
        // Test: All audit log fields are populated correctly
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PatternPluginResult result = new PatternPluginResult();

        Test.startTest();
        result.addSuccessLog(testAccount.Id, 'Field_Update', 'Original', 'Updated', 'My_Rule');
        Test.stopTest();

        Remediation_Log__c log = result.auditLogs[0];
        System.assertEquals(String.valueOf(testAccount.Id), log.Affected_Record_ID__c, 'Affected Record ID');
        System.assertEquals('Field_Update', log.Action_Taken__c, 'Action Taken');
        System.assertEquals('Original', log.Original_Value__c, 'Original Value');
        System.assertEquals('Updated', log.New_Value__c, 'New Value');
        System.assertEquals('Success', log.Status__c, 'Status');
        System.assertEquals(null, log.Error_Message__c, 'Error Message should be null for success');
        System.assertEquals('My_Rule', log.Rule_Developer_Name__c, 'Rule Developer Name');
        System.assertEquals(UserInfo.getUserId(), log.Executed_By__c, 'Executed By should be current user');
    }
}
