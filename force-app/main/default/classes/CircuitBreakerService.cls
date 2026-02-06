/**
 * @description Service for managing circuit breaker state for pattern rule execution.
 * Prevents repeatedly executing rules/plugins that are consistently failing.
 *
 * Circuit States:
 * - Closed: Normal operation, rule executes normally
 * - Open: Rule is blocked due to consecutive failures (auto-set after threshold)
 * - Half_Open: Rule will attempt one trial execution after cooldown period
 *
 * Thresholds:
 * - FAILURE_THRESHOLD: Number of consecutive failures before circuit opens (default 3)
 * - COOLDOWN_MINUTES: Minutes before an open circuit transitions to half-open (default 60)
 */
public with sharing class CircuitBreakerService {

    private static final Integer FAILURE_THRESHOLD = 3;
    private static final Integer COOLDOWN_MINUTES = 60;

    @TestVisible private static Integer testFailureThreshold;
    @TestVisible private static Integer testCooldownMinutes;

    /**
     * @description Resets all test overrides. Call this in test cleanup.
     */
    @TestVisible
    private static void resetTestOverrides() {
        testFailureThreshold = null;
        testCooldownMinutes = null;
    }

    private static Integer getFailureThreshold() {
        return testFailureThreshold != null ? testFailureThreshold : FAILURE_THRESHOLD;
    }

    private static Integer getCooldownMinutes() {
        return testCooldownMinutes != null ? testCooldownMinutes : COOLDOWN_MINUTES;
    }

    /**
     * @description Checks if a rule is allowed to execute based on circuit state.
     * Returns true for Closed circuits, false for Open (unless cooldown expired).
     * Automatically transitions Open → Half_Open when cooldown period expires.
     * @param ruleDeveloperName The rule's DeveloperName
     * @return True if execution is allowed, false if circuit is open
     */
    public static Boolean canExecute(String ruleDeveloperName) {
        if (String.isBlank(ruleDeveloperName)) {
            return true;
        }

        Rule_Execution_Health__c health = getHealthRecord(ruleDeveloperName);
        if (health == null) {
            return true; // No record = never failed = allow
        }

        String state = health.Circuit_State__c;

        if (state == 'Closed') {
            return true;
        }

        if (state == 'Open') {
            // Check if cooldown period has passed
            if (health.Cooldown_Until__c != null && System.now() >= health.Cooldown_Until__c) {
                // Transition to Half_Open for trial execution
                transitionToHalfOpen(health);
                return true;
            }
            return false; // Still within cooldown
        }

        if (state == 'Half_Open') {
            return true; // Allow one trial execution
        }

        return true; // Default to allow for unknown states
    }

    /**
     * @description Records a successful execution. Resets consecutive failure count
     * and closes the circuit.
     * @param ruleDeveloperName The rule's DeveloperName
     */
    public static void recordSuccess(String ruleDeveloperName) {
        if (String.isBlank(ruleDeveloperName)) {
            return;
        }

        Rule_Execution_Health__c health = getOrCreateHealthRecord(ruleDeveloperName);
        health.Consecutive_Failures__c = 0;
        health.Circuit_State__c = 'Closed';
        health.Last_Success_Time__c = System.now();
        health.Cooldown_Until__c = null;
        upsertHealth(health);
    }

    /**
     * @description Records a failed execution. Increments consecutive failure count
     * and opens the circuit if threshold is exceeded.
     * @param ruleDeveloperName The rule's DeveloperName
     * @param errorMessage The error from the failed execution
     */
    public static void recordFailure(String ruleDeveloperName, String errorMessage) {
        if (String.isBlank(ruleDeveloperName)) {
            return;
        }

        Rule_Execution_Health__c health = getOrCreateHealthRecord(ruleDeveloperName);
        health.Consecutive_Failures__c =
            (health.Consecutive_Failures__c != null ? health.Consecutive_Failures__c : 0) + 1;
        health.Total_Failure_Count__c =
            (health.Total_Failure_Count__c != null ? health.Total_Failure_Count__c : 0) + 1;
        health.Last_Failure_Time__c = System.now();
        health.Last_Error__c = errorMessage != null ? errorMessage.abbreviate(32768) : null;

        // Open circuit if threshold exceeded
        if (health.Consecutive_Failures__c >= getFailureThreshold()) {
            health.Circuit_State__c = 'Open';
            health.Cooldown_Until__c = System.now().addMinutes(getCooldownMinutes());
        }

        upsertHealth(health);
    }

    /**
     * @description Gets the current circuit state for a rule.
     * @param ruleDeveloperName The rule's DeveloperName
     * @return The circuit state string, or 'Closed' if no record exists
     */
    public static String getCircuitState(String ruleDeveloperName) {
        Rule_Execution_Health__c health = getHealthRecord(ruleDeveloperName);
        return (health != null && health.Circuit_State__c != null)
            ? health.Circuit_State__c
            : 'Closed';
    }

    /**
     * @description Admin method to manually reset a circuit to Closed state.
     * @param ruleDeveloperName The rule's DeveloperName
     */
    public static void resetCircuit(String ruleDeveloperName) {
        if (String.isBlank(ruleDeveloperName)) {
            throw new IllegalArgumentException('Rule developer name is required to reset circuit breaker.');
        }
        Rule_Execution_Health__c health = getHealthRecordForUpdate(ruleDeveloperName);
        if (health != null) {
            health.Circuit_State__c = 'Closed';
            health.Consecutive_Failures__c = 0;
            health.Cooldown_Until__c = null;
            upsertHealth(health);
        }
    }

    // --- Private Helpers ---

    /**
     * @description Read-only query for circuit state checks (canExecute, getCircuitState).
     * Uses WITH SECURITY_ENFORCED for FLS enforcement.
     */
    private static Rule_Execution_Health__c getHealthRecord(String ruleDeveloperName) {
        if (!Schema.sObjectType.Rule_Execution_Health__c.isAccessible()) {
            return null;
        }
        List<Rule_Execution_Health__c> records = [
            SELECT Id, Rule_Developer_Name__c, Consecutive_Failures__c,
                   Circuit_State__c, Last_Failure_Time__c, Last_Success_Time__c,
                   Last_Error__c, Total_Failure_Count__c, Cooldown_Until__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = :ruleDeveloperName
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    /**
     * @description Write-path query that locks the record to prevent concurrent modification.
     * Uses FOR UPDATE to prevent race conditions between parallel batch executions.
     * CRUD check is manual since FOR UPDATE is incompatible with SECURITY_ENFORCED.
     */
    private static Rule_Execution_Health__c getHealthRecordForUpdate(String ruleDeveloperName) {
        if (!Schema.sObjectType.Rule_Execution_Health__c.isAccessible()) {
            return null;
        }
        List<Rule_Execution_Health__c> records = [
            SELECT Id, Rule_Developer_Name__c, Consecutive_Failures__c,
                   Circuit_State__c, Last_Failure_Time__c, Last_Success_Time__c,
                   Last_Error__c, Total_Failure_Count__c, Cooldown_Until__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = :ruleDeveloperName
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static Rule_Execution_Health__c getOrCreateHealthRecord(String ruleDeveloperName) {
        Rule_Execution_Health__c health = getHealthRecordForUpdate(ruleDeveloperName);
        if (health == null) {
            health = new Rule_Execution_Health__c(
                Rule_Developer_Name__c = ruleDeveloperName,
                Consecutive_Failures__c = 0,
                Total_Failure_Count__c = 0,
                Circuit_State__c = 'Closed'
            );
        }
        return health;
    }

    private static void transitionToHalfOpen(Rule_Execution_Health__c health) {
        health.Circuit_State__c = 'Half_Open';
        upsertHealth(health);
    }

    private static void upsertHealth(Rule_Execution_Health__c health) {
        if (!Schema.sObjectType.Rule_Execution_Health__c.isCreateable()) {
            return;
        }
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPSERTABLE,
                new List<Rule_Execution_Health__c>{ health }
            );
            Database.upsert(decision.getRecords(), Rule_Execution_Health__c.Rule_Developer_Name__c, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CircuitBreaker upsert failed: ' + e.getMessage());
        }
    }
}
