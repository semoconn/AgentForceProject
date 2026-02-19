/**
 * @description Test class for CircuitBreakerService.
 * Tests circuit breaker state transitions: Closed → Open → Half_Open → Closed.
 */
@isTest
private with sharing class CircuitBreakerServiceTest {

    @isTest
    static void testCanExecuteWithNoRecord() {
        // No health record exists = Closed = allow execution
        Boolean result = CircuitBreakerService.canExecute('NonExistent_Rule');
        System.assertEquals(true, result, 'Should allow execution when no health record exists');
    }

    @isTest
    static void testCanExecuteWithBlankName() {
        Boolean result = CircuitBreakerService.canExecute('');
        System.assertEquals(true, result, 'Should allow execution for blank rule name');

        result = CircuitBreakerService.canExecute(null);
        System.assertEquals(true, result, 'Should allow execution for null rule name');
    }

    @isTest
    static void testRecordSuccessCreatesRecord() {
        CircuitBreakerService.recordSuccess('Test_Rule');

        List<Rule_Execution_Health__c> records = [
            SELECT Circuit_State__c, Consecutive_Failures__c, Last_Success_Time__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(1, records.size(), 'Should create a health record');
        System.assertEquals('Closed', records[0].Circuit_State__c, 'State should be Closed');
        System.assertEquals(0, records[0].Consecutive_Failures__c, 'Failures should be 0');
        System.assertNotEquals(null, records[0].Last_Success_Time__c, 'Last success time should be set');
    }

    @isTest
    static void testRecordSuccessWithBlankName() {
        // Should not throw, just return silently
        CircuitBreakerService.recordSuccess('');
        CircuitBreakerService.recordSuccess(null);

        List<Rule_Execution_Health__c> records = [SELECT Id FROM Rule_Execution_Health__c];
        System.assertEquals(0, records.size(), 'Should not create records for blank names');
    }

    @isTest
    static void testRecordFailureIncrementsCounter() {
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 1');

        List<Rule_Execution_Health__c> records = [
            SELECT Consecutive_Failures__c, Total_Failure_Count__c, Last_Error__c, Circuit_State__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(1, records.size(), 'Should create a health record');
        System.assertEquals(1, records[0].Consecutive_Failures__c, 'Consecutive failures should be 1');
        System.assertEquals(1, records[0].Total_Failure_Count__c, 'Total failures should be 1');
        System.assertEquals('Error 1', records[0].Last_Error__c, 'Error message should be stored');
        System.assertEquals('Closed', records[0].Circuit_State__c, 'Circuit should still be Closed after 1 failure');
    }

    @isTest
    static void testCircuitOpensAfterThreshold() {
        // Use test override to set threshold to 2 for faster testing
        CircuitBreakerService.testFailureThreshold = 2;
        CircuitBreakerService.testCooldownMinutes = 30;

        CircuitBreakerService.recordFailure('Test_Rule', 'Error 1');
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 2');

        String state = CircuitBreakerService.getCircuitState('Test_Rule');
        System.assertEquals('Open', state, 'Circuit should be Open after exceeding threshold');

        Boolean canExecute = CircuitBreakerService.canExecute('Test_Rule');
        System.assertEquals(false, canExecute, 'Should not allow execution when circuit is Open');

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testCircuitOpensAtDefaultThreshold() {
        // Default threshold is 3
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 1');
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 2');

        // Still Closed after 2 failures
        System.assertEquals('Closed', CircuitBreakerService.getCircuitState('Test_Rule'));
        System.assertEquals(true, CircuitBreakerService.canExecute('Test_Rule'));

        CircuitBreakerService.recordFailure('Test_Rule', 'Error 3');

        // Now Open after 3 failures
        System.assertEquals('Open', CircuitBreakerService.getCircuitState('Test_Rule'));
        System.assertEquals(false, CircuitBreakerService.canExecute('Test_Rule'));
    }

    @isTest
    static void testHalfOpenTransitionAfterCooldown() {
        // Open the circuit
        CircuitBreakerService.testFailureThreshold = 1;
        CircuitBreakerService.recordFailure('Test_Rule', 'Error');

        // Manually set cooldown to the past so it will transition
        Rule_Execution_Health__c health = [
            SELECT Id, Cooldown_Until__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        health.Cooldown_Until__c = System.now().addMinutes(-1);
        update health;

        // Should transition to Half_Open and allow execution
        Boolean canExecute = CircuitBreakerService.canExecute('Test_Rule');
        System.assertEquals(true, canExecute, 'Should allow execution after cooldown expires');

        String state = CircuitBreakerService.getCircuitState('Test_Rule');
        System.assertEquals('Half_Open', state, 'Should be Half_Open after cooldown');

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testSuccessClosesHalfOpenCircuit() {
        // Open the circuit
        CircuitBreakerService.testFailureThreshold = 1;
        CircuitBreakerService.recordFailure('Test_Rule', 'Error');

        // Manually transition to Half_Open
        Rule_Execution_Health__c health = [
            SELECT Id FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        health.Circuit_State__c = 'Half_Open';
        update health;

        // Record success - should close the circuit
        CircuitBreakerService.recordSuccess('Test_Rule');

        String state = CircuitBreakerService.getCircuitState('Test_Rule');
        System.assertEquals('Closed', state, 'Success in Half_Open should close the circuit');

        Rule_Execution_Health__c updated = [
            SELECT Consecutive_Failures__c FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(0, updated.Consecutive_Failures__c, 'Consecutive failures should be reset to 0');

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testFailureInHalfOpenReopensCircuit() {
        // Open the circuit
        CircuitBreakerService.testFailureThreshold = 1;
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 1');

        // Manually transition to Half_Open
        Rule_Execution_Health__c health = [
            SELECT Id FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        health.Circuit_State__c = 'Half_Open';
        health.Consecutive_Failures__c = 0; // Reset for half-open trial
        update health;

        // Record failure in Half_Open - should reopen
        CircuitBreakerService.recordFailure('Test_Rule', 'Error in half-open trial');

        String state = CircuitBreakerService.getCircuitState('Test_Rule');
        System.assertEquals('Open', state, 'Failure in Half_Open should reopen the circuit');

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testResetCircuit() {
        // Open the circuit
        CircuitBreakerService.testFailureThreshold = 1;
        CircuitBreakerService.recordFailure('Test_Rule', 'Error');

        System.assertEquals('Open', CircuitBreakerService.getCircuitState('Test_Rule'));

        // Admin reset
        CircuitBreakerService.resetCircuit('Test_Rule');

        String state = CircuitBreakerService.getCircuitState('Test_Rule');
        System.assertEquals('Closed', state, 'Admin reset should close the circuit');

        Rule_Execution_Health__c health = [
            SELECT Consecutive_Failures__c, Cooldown_Until__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(0, health.Consecutive_Failures__c, 'Failures should be reset');
        System.assertEquals(null, health.Cooldown_Until__c, 'Cooldown should be cleared');

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testResetNonExistentCircuit() {
        // Should not throw for non-existent rule
        CircuitBreakerService.resetCircuit('Nonexistent_Rule');
        // No assertion needed - just verify no exception
    }

    @isTest
    static void testGetCircuitStateDefault() {
        String state = CircuitBreakerService.getCircuitState('NonExistent_Rule');
        System.assertEquals('Closed', state, 'Default state should be Closed');
    }

    @isTest
    static void testTotalFailureCountPersists() {
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 1');
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 2');
        CircuitBreakerService.recordSuccess('Test_Rule'); // Resets consecutive but not total
        CircuitBreakerService.recordFailure('Test_Rule', 'Error 3');

        Rule_Execution_Health__c health = [
            SELECT Consecutive_Failures__c, Total_Failure_Count__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(1, health.Consecutive_Failures__c, 'Consecutive should be 1 after reset+1');
        System.assertEquals(3, health.Total_Failure_Count__c, 'Total should be 3 (lifetime)');
    }

    @isTest
    static void testCooldownUntilSet() {
        CircuitBreakerService.testFailureThreshold = 1;
        CircuitBreakerService.testCooldownMinutes = 120;

        CircuitBreakerService.recordFailure('Test_Rule', 'Error');

        Rule_Execution_Health__c health = [
            SELECT Cooldown_Until__c FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertNotEquals(null, health.Cooldown_Until__c, 'Cooldown should be set');
        // Cooldown should be approximately 120 minutes from now
        DateTime expectedMin = System.now().addMinutes(119);
        DateTime expectedMax = System.now().addMinutes(121);
        System.assert(
            health.Cooldown_Until__c >= expectedMin && health.Cooldown_Until__c <= expectedMax,
            'Cooldown should be approximately 120 minutes from now'
        );

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testMultipleRulesIndependent() {
        CircuitBreakerService.testFailureThreshold = 2;

        CircuitBreakerService.recordFailure('Rule_A', 'Error A1');
        CircuitBreakerService.recordFailure('Rule_A', 'Error A2'); // Opens Rule_A
        CircuitBreakerService.recordFailure('Rule_B', 'Error B1'); // Rule_B still at 1

        System.assertEquals('Open', CircuitBreakerService.getCircuitState('Rule_A'));
        System.assertEquals('Closed', CircuitBreakerService.getCircuitState('Rule_B'));
        System.assertEquals(false, CircuitBreakerService.canExecute('Rule_A'));
        System.assertEquals(true, CircuitBreakerService.canExecute('Rule_B'));

        CircuitBreakerService.resetTestOverrides();
    }

    @isTest
    static void testErrorMessageTruncation() {
        // Create a very long error message (over 32768 chars)
        String longError = 'A'.repeat(40000);
        CircuitBreakerService.recordFailure('Test_Rule', longError);

        Rule_Execution_Health__c health = [
            SELECT Last_Error__c FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assert(health.Last_Error__c.length() <= 32768, 'Error should be truncated to field limit');
    }

    @isTest
    static void testNullErrorMessage() {
        CircuitBreakerService.recordFailure('Test_Rule', null);

        Rule_Execution_Health__c health = [
            SELECT Last_Error__c FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'Test_Rule'
        ];
        System.assertEquals(null, health.Last_Error__c, 'Null error should be stored as null');
    }
}
