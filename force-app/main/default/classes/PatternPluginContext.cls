/**
 * @description Context object passed to PatternPlugin.analyze() method.
 * Encapsulates all information needed for pattern analysis, supporting both
 * SOQL-based and non-SOQL (external API) plugin implementations.
 *
 * Using a context object instead of individual parameters allows the interface
 * to evolve without breaking existing implementations.
 */
global class PatternPluginContext {

    /**
     * @description The API name of the target object (e.g., 'Opportunity', 'Lead', 'Custom__c').
     * Always populated from Behavior_Pattern_Rule__mdt.Object_API_Name__c.
     */
    @AuraEnabled
    global String objectApiName { get; set; }

    /**
     * @description The SOQL WHERE clause condition from Behavior_Pattern_Rule__mdt.Query_Condition__c.
     * May be null for plugins that don't use SOQL (e.g., external API integrations).
     * When populated, plugins can use this as a base query or ignore it entirely.
     */
    @AuraEnabled
    global String queryCondition { get; set; }

    /**
     * @description Custom configuration parsed from Behavior_Pattern_Rule__mdt.Fix_Config__c.
     * Contains plugin-specific settings as a Map. Will be empty Map if no config defined.
     */
    @AuraEnabled
    global Map<String, Object> config { get; set; }

    /**
     * @description The DeveloperName of the Behavior_Pattern_Rule__mdt record.
     * Useful for logging, debugging, and rule-specific behavior.
     */
    @AuraEnabled
    global String ruleDeveloperName { get; set; }

    /**
     * @description Default constructor initializing empty config map.
     */
    global PatternPluginContext() {
        this.config = new Map<String, Object>();
    }

    /**
     * @description Full constructor for convenient instantiation.
     * @param objectApiName Target object API name
     * @param queryCondition SOQL WHERE clause (may be null)
     * @param config Custom configuration map
     * @param ruleDeveloperName Rule developer name for logging
     */
    global PatternPluginContext(String objectApiName, String queryCondition,
                                 Map<String, Object> config, String ruleDeveloperName) {
        this.objectApiName = objectApiName;
        this.queryCondition = queryCondition;
        this.config = config != null ? config : new Map<String, Object>();
        this.ruleDeveloperName = ruleDeveloperName;
    }
}
