/**
 * @description Global interface for customer-defined pattern detection and remediation.
 * Enables administrators to write custom Apex logic for patterns that cannot be expressed
 * through standard SOQL-based rules or declarative JSON configurations.
 *
 * Implementations can handle:
 * - Complex multi-object pattern detection
 * - External API-based analysis (e.g., sentiment analysis, fraud detection)
 * - Custom remediation workflows beyond standard fix types
 *
 * Security Note: All implementations should respect FLS/CRUD and execute queries in USER_MODE.
 *
 * @example
 * global class CustomFraudDetector implements PatternPlugin {
 *     global List<Id> analyze(PatternPluginContext context) {
 *         // Custom fraud detection logic
 *         return fraudulentRecordIds;
 *     }
 *
 *     global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
 *         // Custom remediation
 *         PatternPluginResult result = new PatternPluginResult();
 *         // ... process records
 *         return result;
 *     }
 * }
 */
global interface PatternPlugin {

    /**
     * @description Analyze records for pattern violations.
     * Called by PatternAnalysisService during scheduled batch execution.
     *
     * @param context Contains objectApiName, queryCondition (may be null for non-SOQL plugins),
     *                config parsed from Fix_Config__c, and ruleDeveloperName for logging.
     * @return List of record IDs that match the pattern. Return empty list if no matches.
     */
    List<Id> analyze(PatternPluginContext context);

    /**
     * @description Apply remediation to identified records.
     * Called by PatternFixService when user initiates a fix action.
     *
     * @param recordIds Records to fix (from Identified_Pain_Point__c.Example_Records__c)
     * @param config Custom configuration parsed from Behavior_Pattern_Rule__mdt.Fix_Config__c
     * @return Result containing success/failure counts and audit logs for Remediation_Log__c
     */
    PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config);
}
