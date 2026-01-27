/**
 * @description Metadata-Driven Batch Engine for BehaviorIQ (Phase 3).
 * Iterates through Behavior_Pattern_Rule__mdt records and executes dynamic SOQL to detect pain points.
 */
public with sharing class PatternAnalysisService implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final String JOB_NAME = 'Pattern Analysis Service';
    public static final Integer DEFAULT_RETENTION_DAYS = 90;

    // Governor limit protection: flush pending snapshots when exceeding this threshold
    // Prevents heap accumulation during batch execution with many rules
    private static final Integer SNAPSHOT_FLUSH_THRESHOLD = 500;

    // @TestVisible variables for metadata-agnostic testing
    @TestVisible private static Behavior_Pattern_Rule__mdt mockRule;
    @TestVisible private static BehaviorIQ_Configuration__c mockConfig;
    @TestVisible private static String lastExecutedQuery;

    // @TestVisible exception triggers for comprehensive test coverage
    // These allow tests to exercise exception handling paths that are otherwise unreachable
    @TestVisible private static Boolean forceSnapshotDeleteException = false;
    @TestVisible private static Boolean forceQueryException = false;
    @TestVisible private static Boolean forceUpsertException = false;
    @TestVisible private static Boolean forceSnapshotInsertException = false;
    @TestVisible private static Boolean forceObjectAccessException = false;
    @TestVisible private static Boolean forceConfigQueryException = false;
    @TestVisible private static Boolean forceDynamicFieldsException = false;
    @TestVisible private static Boolean forcePatternMatchQueryException = false;
    @TestVisible private static Boolean forcePatternMatchGeneralException = false;
    @TestVisible private static Boolean forceObjectNotAccessible = false;
    @TestVisible private static Boolean forceFLSCheckFailure = false;

    /**
     * @description Resets all test exception flags. Call this in test cleanup.
     */
    @TestVisible
    private static void resetTestFlags() {
        forceSnapshotDeleteException = false;
        forceQueryException = false;
        forceUpsertException = false;
        forceSnapshotInsertException = false;
        forceObjectAccessException = false;
        forceConfigQueryException = false;
        forceDynamicFieldsException = false;
        forcePatternMatchQueryException = false;
        forcePatternMatchGeneralException = false;
        forceObjectNotAccessible = false;
        forceFLSCheckFailure = false;
    }

    private Set<String> dismissedPainPointKeys;
    private BehaviorIQ_Configuration__c cachedConfig;
    private List<Behavior_Snapshot__c> pendingSnapshots;
    private Boolean createSnapshots = false;

    // Track rule-level errors for health reporting (Database.Stateful preserves across batches)
    private List<String> ruleErrors = new List<String>();

    public PatternAnalysisService() {
        dismissedPainPointKeys = new Set<String>();
        pendingSnapshots = new List<Behavior_Snapshot__c>();
        ruleErrors = new List<String>();
        loadDismissals();
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PatternAnalysisService(), 50);
    }

    public Iterable<SObject> start(Database.BatchableContext bc) {
        // Enable snapshot creation when running as a batch job
        createSnapshots = true;

        // Delete today's snapshots first to prevent duplicates (replaces separate DeleteSnapshotBatch)
        // This ensures atomic operation - delete and insert happen in same job, no race condition
        if (Schema.sObjectType.Behavior_Snapshot__c.isDeletable()) {
            try {
                // Test hook for exception coverage
                if (Test.isRunningTest() && forceSnapshotDeleteException) {
                    throw new DmlException('Forced test exception for snapshot deletion');
                }
                // TC-6.1: Enforce FLS with SECURITY_ENFORCED
                List<Behavior_Snapshot__c> todaysSnapshots = [
                    SELECT Id FROM Behavior_Snapshot__c
                    WHERE Snapshot_Date__c = TODAY
                    WITH SECURITY_ENFORCED
                    LIMIT 10000
                ];
                if (!todaysSnapshots.isEmpty()) {
                    delete todaysSnapshots;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to delete today\'s snapshots: ' + e.getMessage());
            }
        }

        // Fetch all active rules from Metadata (including plugin fields)
        // Explicitly exclude inactive rules (Is_Active__c = false)
        // Include rules where Is_Active__c is true OR null (for backward compatibility with rules created before Is_Active__c existed)
        return [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                   Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c,
                   Logic_Type__c, Apex_Handler_Class__c, Fix_Config__c, Is_Active__c, Description__c
            FROM Behavior_Pattern_Rule__mdt
            WHERE Is_Active__c != false
        ];
    }

    public void execute(Database.BatchableContext bc, List<Behavior_Pattern_Rule__mdt> rules) {
        for (Behavior_Pattern_Rule__mdt rule : rules) {
            executeRule(rule);
        }
    }

    private void executeRule(Behavior_Pattern_Rule__mdt rule) {
        String objectApiName = rule.Object_API_Name__c;

        // Guard clauses - early return for conditions that prevent execution
        if (!canExecuteRule(rule, objectApiName)) {
            return;
        }

        // Route based on Logic Type (default to 'Standard' for backward compatibility)
        String logicType = String.isNotBlank(rule.Logic_Type__c) ? rule.Logic_Type__c : 'Standard';

        List<SObject> detectedRecords;

        switch on logicType {
            when 'Apex_Plugin' {
                // Invoke custom plugin for analysis
                detectedRecords = executePluginAnalysis(rule, objectApiName);
            }
            when else {
                // 'Standard' and 'Declarative' both use Query_Condition__c for detection
                detectedRecords = executeDetectionQuery(rule, objectApiName);
            }
        }

        if (detectedRecords == null || detectedRecords.isEmpty()) {
            return;
        }

        // Generate and persist the pain point
        persistDetectionResults(rule, objectApiName, detectedRecords);
    }

    /**
     * @description Executes pattern analysis using a custom Apex plugin.
     * @param rule The pattern rule with plugin configuration
     * @param objectApiName The target object API name
     * @return List of detected records from plugin, or null if execution failed
     */
    private List<SObject> executePluginAnalysis(Behavior_Pattern_Rule__mdt rule, String objectApiName) {
        String handlerClass = rule.Apex_Handler_Class__c;

        if (String.isBlank(handlerClass)) {
            System.debug(LoggingLevel.ERROR, 'Rule [' + rule.DeveloperName + '] has Logic_Type__c = Apex_Plugin but no Apex_Handler_Class__c specified.');
            return null;
        }

        try {
            // Build context for plugin
            Map<String, Object> config = new Map<String, Object>();
            if (String.isNotBlank(rule.Fix_Config__c)) {
                config = (Map<String, Object>) JSON.deserializeUntyped(rule.Fix_Config__c);
            }

            PatternPluginContext context = new PatternPluginContext(
                objectApiName,
                rule.Query_Condition__c,
                config,
                rule.DeveloperName
            );

            // Invoke plugin analyze method
            List<Id> matchedIds = PluginInvoker.invokeAnalyze(handlerClass, context);

            if (matchedIds == null || matchedIds.isEmpty()) {
                return new List<SObject>();
            }

            // Query full records for the matched IDs to enable impact calculation
            String selectFields = getSelectFieldsForObject(objectApiName);
            String queryString = 'SELECT ' + selectFields +
                                 ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                                 ' WHERE Id IN :matchedIds' +
                                 ' LIMIT 2000';

            // TC-6.1/6.2: Execute query (class uses 'with sharing' for sharing enforcement)
            return Database.query(queryString);

        } catch (PluginInvoker.PluginException pe) {
            System.debug(LoggingLevel.ERROR, 'Plugin execution failed for rule [' + rule.DeveloperName + ']: ' + pe.getMessage());
            return null;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error in plugin analysis for rule [' + rule.DeveloperName + ']: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Validates whether a rule can be executed based on license, dismissals, and access.
     * @param rule The pattern rule to validate
     * @param objectApiName The target object API name
     * @return True if the rule can be executed, false otherwise
     */
    private Boolean canExecuteRule(Behavior_Pattern_Rule__mdt rule, String objectApiName) {
        // License gate - skip premium rules for non-premium users
        if (rule.Is_Premium__c && !LicenseService.isPremium()) {
            return false;
        }

        // Dismissal check - skip rules the user has dismissed
        if (dismissedPainPointKeys.contains(rule.DeveloperName)) {
            return false;
        }

        // Object existence check - skip rules for objects not in this org
        if ((Test.isRunningTest() && forceObjectNotAccessible) || !isObjectAccessible(objectApiName)) {
            System.debug(LoggingLevel.INFO, 'Skipping rule [' + rule.DeveloperName + ']: Object ' + objectApiName + ' is not accessible.');
            return false;
        }

        // FLS check - skip rules where required fields aren't accessible
        if ((Test.isRunningTest() && forceFLSCheckFailure) || !validateQueryFieldsAccessible(objectApiName, rule.Query_Condition__c)) {
            System.debug(LoggingLevel.WARN, 'Skipping rule [' + rule.DeveloperName + ']: Required fields not accessible.');
            return false;
        }

        return true;
    }

    /**
     * @description Builds and executes the detection query for a rule.
     * @param rule The pattern rule containing query conditions
     * @param objectApiName The target object API name
     * @return List of detected records, or null if query failed
     */
    private List<SObject> executeDetectionQuery(Behavior_Pattern_Rule__mdt rule, String objectApiName) {
        String effectiveCondition = getEffectiveQuery(rule);
        String selectFields = getSelectFieldsForObject(objectApiName);

        String queryString = 'SELECT ' + selectFields +
                             ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                             ' WHERE ' + effectiveCondition +
                             ' LIMIT 2000';

        lastExecutedQuery = queryString;

        try {
            if (Test.isRunningTest() && forceQueryException) {
                throw new QueryException('Forced test exception for query execution');
            }
            // TC-6.1/6.2: Execute query (class uses 'with sharing' for sharing enforcement)
            // FLS is handled by validateQueryFieldsAccessible() before building query
            return Database.query(queryString);
        } catch (Exception e) {
            String errorMsg = 'Rule [' + rule.DeveloperName + ']: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Rule Execution Failed - ' + errorMsg);
            // Track for health log reporting
            ruleErrors.add(errorMsg);
            return null;
        }
    }

    /**
     * @description Determines select fields based on object type for impact calculation.
     * @param objectApiName The target object API name
     * @return Comma-separated list of fields to query
     */
    private String getSelectFieldsForObject(String objectApiName) {
        String objLower = objectApiName.toLowerCase();

        if (objLower == 'opportunity') {
            return 'Id, Amount';
        }
        if (objLower == 'contract') {
            return 'Id, ContractNumber';
        }
        return 'Id';
    }

    /**
     * @description Creates or updates a pain point record from detection results.
     * @param rule The pattern rule that detected the issue
     * @param objectApiName The target object API name
     * @param detectedRecords Records that match the pattern
     */
    private void persistDetectionResults(Behavior_Pattern_Rule__mdt rule, String objectApiName, List<SObject> detectedRecords) {
        Integer count = detectedRecords.size();

        // Collect sample IDs for reference
        List<Id> exampleIds = new List<Id>();
        for (Integer i = 0; i < Math.min(count, 5); i++) {
            exampleIds.add(detectedRecords[i].Id);
        }

        Decimal totalImpact = calculateFinancialImpact(rule, objectApiName, detectedRecords);

        // Use description from metadata if available, otherwise fall back to generic description
        String description = String.isNotBlank(rule.Description__c)
            ? rule.Description__c
            : 'Automated detection for ' + objectApiName;

        upsertPainPoint(
            rule.DeveloperName,
            rule.MasterLabel,
            description,
            objectApiName,
            count,
            JSON.serialize(exampleIds),
            totalImpact
        );
    }

    /**
     * @description Calculates the financial impact of detected records.
     * Opportunities use actual Amount values; other objects use cost-per-incident.
     * @param rule The pattern rule with cost configuration
     * @param objectApiName The target object API name
     * @param records The detected records
     * @return Total financial impact value
     */
    private Decimal calculateFinancialImpact(Behavior_Pattern_Rule__mdt rule, String objectApiName, List<SObject> records) {
        Decimal costPerIncident = rule.Cost_Per_Incident__c != null ? rule.Cost_Per_Incident__c : 0;
        Integer count = records.size();
        String objLower = objectApiName.toLowerCase();

        if (objLower == 'opportunity') {
            Decimal totalAmount = 0;
            for (SObject rec : records) {
                Decimal amt = (Decimal)rec.get('Amount');
                if (amt != null) {
                    totalAmount += amt;
                }
            }
            return totalAmount > 0 ? totalAmount : count * costPerIncident;
        }

        return count * costPerIncident;
    }

    /**
     * @description Extracts the base rule developer name from a potentially timestamped key.
     * Pain points created from partial fixes have keys like "High_Value_Ghosting_1767994173771".
     * This method progressively strips underscore-suffixed segments to find the actual rule.
     * @param uniqueKey The unique key from a pain point
     * @return The base rule developer name that matches metadata, or original if no match found
     */
    @TestVisible
    private static String extractBaseRuleName(String uniqueKey) {
        if (String.isBlank(uniqueKey)) {
            return uniqueKey;
        }

        // Try progressively shorter versions by removing underscore-suffixed segments
        String testKey = uniqueKey;
        while (testKey.contains('_')) {
            // Remove the last underscore segment
            Integer lastUnderscore = testKey.lastIndexOf('_');
            testKey = testKey.substring(0, lastUnderscore);

            // Check if this version exists as a rule
            List<Behavior_Pattern_Rule__mdt> match = [
                SELECT DeveloperName FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :testKey LIMIT 1
            ];
            if (!match.isEmpty()) {
                return testKey;
            }
        }

        // No match found - return original
        return uniqueKey;
    }

    /**
     * @description Checks if an object exists and is accessible in the current org.
     * Uses Schema.getGlobalDescribe() for weak reference checking - prevents crashes
     * when custom objects from managed packages are not installed.
     * @param objectApiName The API name of the object to check
     * @return True if the object exists and is accessible, false otherwise
     */
    @TestVisible
    private static Boolean isObjectAccessible(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceObjectAccessException) {
                throw new System.TypeException('Forced test exception for object accessibility check');
            }
            // Use getGlobalDescribe() for dynamic/weak reference - doesn't crash if object doesn't exist
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            // Schema.getGlobalDescribe() keys are case-insensitive in Apex, but use lowercase for consistency
            Schema.SObjectType sObjType = globalDescribe.get(objectApiName.toLowerCase());

            if (sObjType == null) {
                // Object doesn't exist in this org
                return false;
            }

            // Check if the object is accessible (read permission)
            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            return describeResult.isAccessible();

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking object accessibility for ' + objectApiName + ': ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Validates that all fields referenced in a query condition are accessible.
     * Parses the query condition to extract field names and checks FLS for each.
     * Supports standard fields, custom fields, and relationship traversals (e.g., Account.Rating).
     * @param objectApiName The API name of the object being queried
     * @param queryCondition The WHERE clause condition to validate
     * @return True if all referenced fields are accessible, false otherwise
     */
    @TestVisible
    private static Boolean validateQueryFieldsAccessible(String objectApiName, String queryCondition) {
        if (String.isBlank(queryCondition)) {
            return true; // No condition means no fields to validate
        }

        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            // Use lowercase for case-insensitive lookup
            Schema.SObjectType sObjType = globalDescribe.get(objectApiName.toLowerCase());

            if (sObjType == null) {
                return false;
            }

            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            // Extract field names from the query condition
            Set<String> extractedFields = extractFieldsFromCondition(queryCondition);

            for (String fieldRef : extractedFields) {
                // Handle relationship traversals like "Account.Rating" or "Owner.Type"
                if (fieldRef.contains('.')) {
                    if (!validateRelationshipFieldAccessible(objectApiName, fieldRef, globalDescribe)) {
                        System.debug(LoggingLevel.DEBUG, 'Relationship field not accessible: ' + fieldRef);
                        return false;
                    }
                } else {
                    // Simple field on the base object
                    Schema.SObjectField field = fieldMap.get(fieldRef.toLowerCase());
                    if (field == null) {
                        // Field doesn't exist - might be a special keyword like TRUE, FALSE, etc.
                        // Check if it's a known SOQL literal
                        if (!isKnownSoqlLiteral(fieldRef)) {
                            System.debug(LoggingLevel.DEBUG, 'Field not found: ' + fieldRef + ' on ' + objectApiName);
                            return false;
                        }
                    } else if (!field.getDescribe().isAccessible()) {
                        System.debug(LoggingLevel.DEBUG, 'Field not accessible: ' + fieldRef);
                        return false;
                    }
                }
            }

            return true;

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error validating field accessibility: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Extracts field names from a SOQL WHERE clause condition.
     * Handles common patterns like field = value, field IN (...), field > value, etc.
     * Properly ignores text inside single quotes (string literals).
     * @param condition The WHERE clause condition
     * @return Set of field names referenced in the condition
     */
    private static Set<String> extractFieldsFromCondition(String condition) {
        Set<String> fields = new Set<String>();

        if (String.isBlank(condition)) {
            return fields;
        }

        // Common SOQL operators and keywords to filter out
        Set<String> operators = new Set<String>{
            '=', '!=', '<>', '<', '>', '<=', '>=', 'LIKE', 'IN', 'NOT', 'AND', 'OR',
            'NULL', 'TRUE', 'FALSE', 'INCLUDES', 'EXCLUDES', 'TODAY', 'YESTERDAY',
            'TOMORROW', 'LAST_WEEK', 'THIS_WEEK', 'NEXT_WEEK', 'LAST_MONTH', 'THIS_MONTH',
            'NEXT_MONTH', 'LAST_QUARTER', 'THIS_QUARTER', 'NEXT_QUARTER', 'LAST_YEAR',
            'THIS_YEAR', 'NEXT_YEAR', 'LAST_N_DAYS', 'NEXT_N_DAYS', 'LAST_N_WEEKS',
            'NEXT_N_WEEKS', 'LAST_N_MONTHS', 'NEXT_N_MONTHS', 'LAST_N_QUARTERS',
            'NEXT_N_QUARTERS', 'LAST_N_YEARS', 'NEXT_N_YEARS', 'THIS_FISCAL_QUARTER',
            'LAST_FISCAL_QUARTER', 'NEXT_FISCAL_QUARTER', 'THIS_FISCAL_YEAR',
            'LAST_FISCAL_YEAR', 'NEXT_FISCAL_YEAR', 'LAST_N_FISCAL_QUARTERS',
            'NEXT_N_FISCAL_QUARTERS', 'LAST_N_FISCAL_YEARS', 'NEXT_N_FISCAL_YEARS'
        };

        // First, remove all content inside single quotes (string literals)
        // This prevents treating 'Closed' or 'New' as field names
        String conditionWithoutStrings = condition.replaceAll('\'[^\']*\'', ' ');

        // Tokenize the condition - split on spaces, parentheses, commas, and operators
        String tokenized = conditionWithoutStrings.replaceAll('[(),:]', ' ');
        tokenized = tokenized.replaceAll('!=|<>|<=|>=|=|<|>', ' ');
        List<String> tokens = tokenized.split('\\s+');

        for (String token : tokens) {
            token = token.trim();
            if (String.isBlank(token)) continue;

            // Skip numeric values
            if (token.isNumeric()) continue;

            // Skip date literals with numbers (e.g., LAST_N_DAYS:30 - already handled by : split)
            // but handle LAST_N_DAYS without number
            if (token.contains(':') && !token.contains('.')) continue;

            // Skip known operators and keywords
            if (operators.contains(token.toUpperCase())) continue;

            // This looks like a field reference
            fields.add(token);
        }

        return fields;
    }

    /**
     * @description Validates accessibility of a relationship field traversal.
     * @param baseObjectApiName The API name of the starting object
     * @param fieldRef The relationship field reference (e.g., "Account.Rating")
     * @param globalDescribe The global describe map
     * @return True if all parts of the relationship are accessible
     */
    private static Boolean validateRelationshipFieldAccessible(String baseObjectApiName, String fieldRef,
                                                                Map<String, Schema.SObjectType> globalDescribe) {
        List<String> parts = fieldRef.split('\\.');
        if (parts.size() < 2) {
            return false;
        }

        String relationshipName = parts[0];
        String targetField = parts[1];

        // Get the base object describe - use lowercase for case-insensitive lookup
        Schema.SObjectType baseType = globalDescribe.get(baseObjectApiName.toLowerCase());
        if (baseType == null) {
            return false;
        }

        Schema.DescribeSObjectResult baseDescribe = baseType.getDescribe();
        Map<String, Schema.SObjectField> baseFields = baseDescribe.fields.getMap();

        // Find the relationship field - it might be stored with __r suffix or as a standard relationship
        String lookupFieldName = relationshipName;
        if (relationshipName.endsWith('__r')) {
            lookupFieldName = relationshipName.replace('__r', '__c');
        } else {
            // Standard relationships like "Account" -> "AccountId"
            lookupFieldName = relationshipName + 'Id';
        }

        Schema.SObjectField lookupField = baseFields.get(lookupFieldName.toLowerCase());
        if (lookupField == null) {
            // Try the relationship name directly (for custom relationships)
            lookupField = baseFields.get((relationshipName + '__c').toLowerCase());
        }

        if (lookupField == null) {
            // Special case for Owner relationship
            if (relationshipName.equalsIgnoreCase('Owner')) {
                lookupField = baseFields.get('ownerid');
            }
        }

        if (lookupField == null) {
            System.debug(LoggingLevel.DEBUG, 'Lookup field not found for relationship: ' + relationshipName);
            return false;
        }

        // Check if the lookup field is accessible
        if (!lookupField.getDescribe().isAccessible()) {
            return false;
        }

        // Get the related object type
        Schema.DescribeFieldResult fieldDescribe = lookupField.getDescribe();
        List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();

        if (referenceTo.isEmpty()) {
            return false;
        }

        // Check if the target field on the related object is accessible
        Schema.SObjectType relatedType = referenceTo[0];
        Map<String, Schema.SObjectField> relatedFields = relatedType.getDescribe().fields.getMap();

        Schema.SObjectField targetFieldRef = relatedFields.get(targetField.toLowerCase());
        if (targetFieldRef == null) {
            System.debug(LoggingLevel.DEBUG, 'Target field not found: ' + targetField + ' on ' + relatedType.getDescribe().getName());
            return false;
        }

        return targetFieldRef.getDescribe().isAccessible();
    }

    /**
     * @description Checks if a token is a known SOQL literal or keyword that isn't a field.
     * @param token The token to check
     * @return True if this is a known SOQL literal
     */
    private static Boolean isKnownSoqlLiteral(String token) {
        Set<String> literals = new Set<String>{
            'TRUE', 'FALSE', 'NULL', 'TODAY', 'YESTERDAY', 'TOMORROW',
            'LAST_WEEK', 'THIS_WEEK', 'NEXT_WEEK', 'LAST_MONTH', 'THIS_MONTH',
            'NEXT_MONTH', 'LAST_QUARTER', 'THIS_QUARTER', 'NEXT_QUARTER',
            'LAST_YEAR', 'THIS_YEAR', 'NEXT_YEAR'
        };
        return literals.contains(token.toUpperCase());
    }

    /**
     * @description Gets the effective query condition by injecting Admin configuration values.
     * Replaces LAST_N_DAYS:\d+ and LAST_N_HOURS:\d+ patterns with values from BehaviorIQ_Configuration__c.
     * @param rule The pattern rule containing the query condition
     * @return The modified query condition with injected threshold values
     */
    @TestVisible
    private String getEffectiveQuery(Behavior_Pattern_Rule__mdt rule) {
        String queryCondition = rule.Query_Condition__c;

        if (String.isBlank(queryCondition)) {
            return queryCondition;
        }

        // Get the configuration (cached for performance)
        BehaviorIQ_Configuration__c config = getConfiguration();

        // Map rule DeveloperNames to their corresponding threshold fields
        String ruleName = rule.DeveloperName;
        Decimal thresholdValue = null;

        if (config != null) {
            // Check for Stale_Case rules (days)
            if (ruleName != null && ruleName.startsWithIgnoreCase('Stale_Case')) {
                thresholdValue = config.Stale_Case_Threshold__c;
            }
            // Check for Stale_Opp/Stale_Opportunity rules (days)
            else if (ruleName != null && (ruleName.startsWithIgnoreCase('Stale_Opp') ||
                                           ruleName.startsWithIgnoreCase('Stale_Opportunity'))) {
                thresholdValue = config.Stale_Opportunity_Threshold__c;
            }
        }

        // Apply threshold substitution if we have a configured value
        if (thresholdValue != null) {
            // Use regex to replace LAST_N_DAYS:\d+ with the configured value
            // In Apex, \d needs to be escaped as \\d in the regex string
            String daysPattern = 'LAST_N_DAYS:\\d+';
            String daysReplacement = 'LAST_N_DAYS:' + thresholdValue.intValue();
            queryCondition = queryCondition.replaceAll(daysPattern, daysReplacement);
        }

        // Apply Safety Exclusions (per-object filters from configuration)
        String exclusionCondition = getExclusionCondition(rule.Object_API_Name__c, config);
        if (String.isNotBlank(exclusionCondition)) {
            queryCondition = '(' + queryCondition + ') AND ' + exclusionCondition;
        }

        // Debug logging for troubleshooting query construction
        System.debug(LoggingLevel.DEBUG, 'getEffectiveQuery - Rule: ' + ruleName + ', Final condition: ' + queryCondition);

        return queryCondition;
    }

    /**
     * @description Retrieves the exclusion condition for a specific object from the JSON configuration.
     * Parses the Global_Exclusion_Filter__c field which stores per-object filters as JSON.
     * Example config: {"Account": "Type != 'VIP'", "Lead": "Rating != 'Hot'"}
     * @param objectApiName The API name of the object to get exclusion for
     * @param config The configuration record containing exclusion settings
     * @return The exclusion condition for this object, or null if none defined
     */
    @TestVisible
    private String getExclusionCondition(String objectApiName, BehaviorIQ_Configuration__c config) {
        if (config == null || String.isBlank(objectApiName)) {
            return null;
        }

        String exclusionJson = config.Global_Exclusion_Filter__c;
        if (String.isBlank(exclusionJson)) {
            return null;
        }

        try {
            Map<String, Object> exclusionMap = (Map<String, Object>)JSON.deserializeUntyped(exclusionJson);

            // Look for exact match first, then case-insensitive match
            if (exclusionMap.containsKey(objectApiName)) {
                String condition = (String)exclusionMap.get(objectApiName);
                if (String.isNotBlank(condition)) {
                    // Validate that the exclusion fields are accessible before using
                    if (validateQueryFieldsAccessible(objectApiName, condition)) {
                        System.debug(LoggingLevel.INFO, 'Applying exclusion filter for ' + objectApiName + ': ' + condition);
                        return '(' + condition + ')';
                    } else {
                        System.debug(LoggingLevel.WARN, 'Exclusion filter skipped for ' + objectApiName + ': fields not accessible');
                    }
                }
            }

            // Try case-insensitive lookup
            for (String key : exclusionMap.keySet()) {
                if (key.equalsIgnoreCase(objectApiName)) {
                    String condition = (String)exclusionMap.get(key);
                    if (String.isNotBlank(condition)) {
                        if (validateQueryFieldsAccessible(objectApiName, condition)) {
                            System.debug(LoggingLevel.INFO, 'Applying exclusion filter for ' + objectApiName + ': ' + condition);
                            return '(' + condition + ')';
                        } else {
                            System.debug(LoggingLevel.WARN, 'Exclusion filter skipped for ' + objectApiName + ': fields not accessible');
                        }
                    }
                    break;
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to parse exclusion filter JSON: ' + e.getMessage());
        }

        return null;
    }

    /**
     * @description Retrieves the BehaviorIQ Configuration singleton record.
     * Uses caching to avoid repeated queries within the same execution context.
     * @return The configuration record, or null if none exists
     */
    private BehaviorIQ_Configuration__c getConfiguration() {
        // Return mock config for tests
        if (Test.isRunningTest() && mockConfig != null) {
            return mockConfig;
        }

        // Return cached config if available
        if (cachedConfig != null) {
            return cachedConfig;
        }

        // Query for the singleton configuration record
        // NOTE: Not using WITH SECURITY_ENFORCED because this is a system batch job
        // that needs to read admin configuration regardless of running user's FLS
        if (Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
            try {
                // Test hook for exception coverage
                if (Test.isRunningTest() && forceConfigQueryException) {
                    throw new QueryException('Forced test exception for config query');
                }
                // TC-6.1/6.2: Query config - CRUD check done above, class uses 'with sharing'
                // Note: Configuration is admin-level data; if user lacks FLS, defaults are used (via catch block)
                List<BehaviorIQ_Configuration__c> configs = [
                    SELECT Id, Stale_Case_Threshold__c, Stale_Opportunity_Threshold__c, Global_Exclusion_Filter__c
                    FROM BehaviorIQ_Configuration__c
                    LIMIT 1
                ];

                if (!configs.isEmpty()) {
                    cachedConfig = configs[0];
                    return cachedConfig;
                }
            } catch (Exception e) {
                // If fields don't exist yet, return null to use defaults
                System.debug(LoggingLevel.WARN, 'Unable to query configuration: ' + e.getMessage());
            }
        }

        return null;
    }

    public void finish(Database.BatchableContext bc) {
        insertPendingSnapshots();
        logJobStatus(bc);
        deleteOldLogs();
    }

    // --- HELPER METHODS ---

    private void upsertPainPoint(String key, String label, String description, String obj, Integer count, String examples, Decimal totalImpact) {
        Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
            Unique_Key__c = key,
            Name = label,
            Description__c = description,
            Object_API_Name__c = obj,
            Occurrences__c = count,
            Impact_Score__c = totalImpact,
            Example_Records__c = examples,
            Last_Detected__c = System.now(),
            Status__c = 'New'
        );

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceUpsertException) {
                throw new DmlException('Forced test exception for pain point upsert');
            }
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPSERTABLE, new List<Identified_Pain_Point__c>{pp});
            List<SObject> upsertedRecords = securityDecision.getRecords();
            Database.UpsertResult[] results = Database.upsert(upsertedRecords, Identified_Pain_Point__c.Unique_Key__c, false);

            // Create snapshot if running in batch context and upsert succeeded
            if (createSnapshots && !results.isEmpty() && results[0].isSuccess()) {
                Id painPointId = results[0].getId();
                createSnapshot(key, count, totalImpact, painPointId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Upsert failed: ' + e.getMessage());
        }
    }

    /**
     * @description Creates a snapshot record to track historical trend data.
     * Only called when running in batch context to avoid overhead during real-time operations.
     * Implements automatic flushing when list exceeds SNAPSHOT_FLUSH_THRESHOLD to prevent
     * heap accumulation in large orgs with many pattern rules.
     */
    private void createSnapshot(String metricName, Integer recordCount, Decimal impactScore, Id painPointId) {
        Behavior_Snapshot__c snapshot = new Behavior_Snapshot__c(
            Snapshot_Date__c = Date.today(),
            Metric_Name__c = metricName,
            Record_Count__c = recordCount,
            Impact_Score__c = impactScore,
            Related_Pain_Point__c = painPointId
        );
        pendingSnapshots.add(snapshot);

        // Governor limit protection: flush to database if exceeding threshold
        // This prevents heap accumulation when processing many rules
        if (pendingSnapshots.size() >= SNAPSHOT_FLUSH_THRESHOLD) {
            System.debug(LoggingLevel.INFO, 'PatternAnalysisService: Flushing ' + pendingSnapshots.size() +
                        ' snapshots to prevent heap accumulation');
            insertPendingSnapshots();
        }
    }

    /**
     * @description Inserts all pending snapshot records. Called at the end of batch execution.
     */
    private void insertPendingSnapshots() {
        if (pendingSnapshots.isEmpty()) {
            return;
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceSnapshotInsertException) {
                throw new DmlException('Forced test exception for snapshot insert');
            }
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, pendingSnapshots);
            Database.insert(securityDecision.getRecords(), false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Snapshot insert failed: ' + e.getMessage());
        }

        pendingSnapshots.clear();
    }

    private void loadDismissals() {
        if (Schema.sObjectType.Suggestion_Dismissal__c.isAccessible()) {
            for (Suggestion_Dismissal__c dismissal : [SELECT Dismissal_Key__c FROM Suggestion_Dismissal__c WITH SECURITY_ENFORCED]) {
                if (dismissal.Dismissal_Key__c != null) dismissedPainPointKeys.add(dismissal.Dismissal_Key__c);
            }
        }
    }

    private void deleteOldLogs() {
        if (!Schema.sObjectType.Behavior_Log__c.isDeletable()) return;
        try {
            Date cutoffDate = Date.today().addDays(-DEFAULT_RETENTION_DAYS);
            String isoDate = Datetime.newInstanceGmt(cutoffDate.year(), cutoffDate.month(), cutoffDate.day()).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            Database.executeBatch(new DeleteRecordsBatch('SELECT Id FROM Behavior_Log__c WHERE CreatedDate < ' + isoDate), 2000);
        } catch (Exception e) {}
    }

    private void logJobStatus(Database.BatchableContext bc) {
        String jobId = (bc != null) ? bc.getJobId() : null;
        Integer batchErrors = 0;
        String extendedStatus = '';

        if (jobId != null) {
            try {
                AsyncApexJob job = [
                    SELECT NumberOfErrors, ExtendedStatus, TotalJobItems, JobItemsProcessed
                    FROM AsyncApexJob
                    WHERE Id = :jobId
                    LIMIT 1
                ];
                batchErrors = job.NumberOfErrors;
                extendedStatus = job.ExtendedStatus;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Unable to query job status: ' + e.getMessage());
            }
        }

        // Combine batch-level errors with rule-level errors
        Integer totalErrors = batchErrors + (ruleErrors != null ? ruleErrors.size() : 0);
        Boolean hasRuleErrors = ruleErrors != null && !ruleErrors.isEmpty();

        // Build extended status with rule errors if any
        if (hasRuleErrors) {
            String ruleErrorSummary = 'Rule errors: ' + String.join(ruleErrors, '; ');
            // Truncate if too long (field limit)
            if (ruleErrorSummary.length() > 255) {
                ruleErrorSummary = ruleErrorSummary.substring(0, 252) + '...';
            }
            extendedStatus = String.isNotBlank(extendedStatus)
                ? extendedStatus + ' | ' + ruleErrorSummary
                : ruleErrorSummary;
        }

        // Log to System_Health_Log__c if accessible
        if (Schema.sObjectType.System_Health_Log__c.isCreateable()) {
            System_Health_Log__c log = new System_Health_Log__c(
                Job_Name__c = JOB_NAME,
                Job_ID__c = jobId,
                Status__c = (totalErrors > 0) ? 'Failed' : 'Success',
                Error_Count__c = totalErrors
            );
            // Add error details if field is accessible
            if (hasRuleErrors && Schema.sObjectType.System_Health_Log__c.fields.Error_Details__c.isCreateable()) {
                log.Error_Details__c = String.join(ruleErrors, '\n');
            }
            try {
                insert Security.stripInaccessible(AccessType.CREATABLE, new List<System_Health_Log__c>{log}).getRecords();
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Unable to create health log: ' + e.getMessage());
            }
        }

        // Send admin notification email on failure (batch errors or rule errors)
        if (totalErrors > 0) {
            sendAdminFailureNotification(jobId, totalErrors, extendedStatus);
        }
    }

    /**
     * @description Sends email notification to system admins when the batch job fails.
     * Queries for users with the BehaviorIQ_Admin permission set to determine recipients.
     * @param jobId The AsyncApexJob ID
     * @param errorCount Number of errors that occurred
     * @param extendedStatus Additional error details from the job
     */
    private void sendAdminFailureNotification(String jobId, Integer errorCount, String extendedStatus) {
        try {
            // Find users with BehaviorIQ Admin permission set
            Set<Id> adminUserIds = new Set<Id>();
            for (PermissionSetAssignment psa : [
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'BehaviorIQ_Admin'
                AND Assignee.IsActive = true
                LIMIT 10
            ]) {
                adminUserIds.add(psa.AssigneeId);
            }

            // If no admins found, try to notify the running user (likely a system admin who scheduled the job)
            if (adminUserIds.isEmpty()) {
                adminUserIds.add(UserInfo.getUserId());
            }

            // Build notification email
            String subject = 'BehaviorIQ Alert: Pattern Analysis Job Failed';
            String body = 'The BehaviorIQ Pattern Analysis batch job has completed with errors.\n\n' +
                'Job ID: ' + (jobId != null ? jobId : 'Unknown') + '\n' +
                'Error Count: ' + errorCount + '\n' +
                'Timestamp: ' + Datetime.now().format('yyyy-MM-dd HH:mm:ss z') + '\n\n';

            if (String.isNotBlank(extendedStatus)) {
                body += 'Error Details:\n' + extendedStatus + '\n\n';
            }

            body += 'Please review the System Health Log for more details.\n\n' +
                'This is an automated notification from BehaviorIQ.';

            // Send emails to admin users
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Id adminId : adminUserIds) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(adminId);
                email.setSubject(subject);
                email.setPlainTextBody(body);
                email.setSaveAsActivity(false);
                emails.add(email);
            }

            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send admin failure notification: ' + e.getMessage());
        }
    }

    // --- REMEDIATION PREVIEW API ---

    /**
     * @description Returns matching records for a given pattern rule, allowing users to preview
     * which records will be affected before executing a fix. Respects admin thresholds.
     *
     * When includeOnlyRecordIds is provided (whitelist mode), ONLY those specific records are returned.
     * This is used for partial fix scenarios where we only want to show remaining unfixed records
     * from a pain point's Example_Records__c field.
     *
     * @param ruleDeveloperName The DeveloperName of the Behavior_Pattern_Rule__mdt record
     * @param limitCount Maximum number of records to return (default 50, max 200)
     * @param includeOnlyRecordIds Optional comma-separated list of record IDs to filter to (whitelist).
     *                             When provided, only these records are returned (if they still match the pattern).
     * @param excludeRecordIds Optional comma-separated list of record IDs to exclude (blacklist).
     *                         Used to filter out already-fixed records from the preview.
     * @return List<SObject> The matching records with key fields for display
     */
    @AuraEnabled
    public static List<SObject> getPatternMatches(String ruleDeveloperName, Integer limitCount, String includeOnlyRecordIds, String excludeRecordIds) {
        // Validate inputs
        if (String.isBlank(ruleDeveloperName)) {
            AuraHandledException e = new AuraHandledException('Rule developer name is required.');
            e.setMessage('Rule developer name is required.');
            throw e;
        }

        // Enforce reasonable limits
        if (limitCount == null || limitCount <= 0) {
            limitCount = 50;
        }
        if (limitCount > 200) {
            limitCount = 200;
        }

        // Fetch the rule from metadata (including plugin fields)
        // First try exact match, then try to find base rule name (for timestamped keys from partial fixes)
        String effectiveRuleName = ruleDeveloperName;
        List<Behavior_Pattern_Rule__mdt> rules = [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                   Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c,
                   Logic_Type__c, Apex_Handler_Class__c, Fix_Config__c
            FROM Behavior_Pattern_Rule__mdt
            WHERE DeveloperName = :ruleDeveloperName
            LIMIT 1
        ];

        // If not found, try to extract base rule name (handles timestamped keys like "High_Value_Ghosting_1767994173771")
        if (rules.isEmpty() && ruleDeveloperName.contains('_')) {
            effectiveRuleName = extractBaseRuleName(ruleDeveloperName);
            if (effectiveRuleName != ruleDeveloperName) {
                rules = [
                    SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                           Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c,
                           Logic_Type__c, Apex_Handler_Class__c, Fix_Config__c
                    FROM Behavior_Pattern_Rule__mdt
                    WHERE DeveloperName = :effectiveRuleName
                    LIMIT 1
                ];
            }
        }

        if (rules.isEmpty()) {
            String msg = 'Pattern rule not found: ' + ruleDeveloperName;
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        Behavior_Pattern_Rule__mdt rule = rules[0];

        // License Gate for Premium rules
        if (rule.Is_Premium__c && !LicenseService.isPremium()) {
            String msg = 'This is a Premium feature. Please upgrade to view affected records.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        String objectApiName = rule.Object_API_Name__c;

        // Check if object exists and is accessible
        if (!isObjectAccessible(objectApiName)) {
            String msg = 'Object ' + objectApiName + ' is not accessible or does not exist in this org.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // Check if this is an Apex Plugin rule
        Boolean isApexPlugin = rule.Logic_Type__c == 'Apex_Plugin' && String.isNotBlank(rule.Apex_Handler_Class__c);

        // Validate FLS for query fields (skip for pure Apex plugins without query condition)
        if (!isApexPlugin && !validateQueryFieldsAccessible(objectApiName, rule.Query_Condition__c)) {
            String msg = 'One or more fields in the rule are not accessible. Please contact your administrator.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // Get effective query condition with admin threshold injection
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveCondition = service.getEffectiveQuery(rule);

        // For Apex plugins without a query condition, we'll use the plugin to get record IDs
        if (String.isBlank(effectiveCondition) && !isApexPlugin) {
            String msg = 'Rule has no query condition defined.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // Build dynamic query with display fields based on object type
        String displayFields = getDisplayFieldsForObject(objectApiName);

        // For Apex plugins, invoke the plugin to get matching record IDs
        Set<Id> pluginMatchedIds = new Set<Id>();
        if (isApexPlugin) {
            try {
                Map<String, Object> config = new Map<String, Object>();
                if (String.isNotBlank(rule.Fix_Config__c)) {
                    config = (Map<String, Object>) JSON.deserializeUntyped(rule.Fix_Config__c);
                }
                PatternPluginContext context = new PatternPluginContext(
                    objectApiName,
                    rule.Query_Condition__c,
                    config,
                    rule.DeveloperName
                );
                List<Id> matchedIds = PluginInvoker.invokeAnalyze(rule.Apex_Handler_Class__c, context);
                if (matchedIds != null) {
                    pluginMatchedIds.addAll(matchedIds);
                }
            } catch (Exception pluginEx) {
                String msg = 'Plugin execution failed: ' + pluginEx.getMessage();
                AuraHandledException e = new AuraHandledException(msg);
                e.setMessage(msg);
                throw e;
            }

            if (pluginMatchedIds.isEmpty()) {
                return new List<SObject>(); // No matches from plugin
            }
        }

        // Parse whitelist IDs if provided (for partial fix scenarios)
        Set<Id> whitelistIds = new Set<Id>();
        if (String.isNotBlank(includeOnlyRecordIds)) {
            // Parse the comma-separated or JSON array of IDs
            String cleanIds = includeOnlyRecordIds.trim();
            List<String> idStrings;

            if (cleanIds.startsWith('[')) {
                // JSON array format: ["001...", "001..."]
                try {
                    idStrings = (List<String>)JSON.deserialize(cleanIds, List<String>.class);
                } catch (Exception jsonEx) {
                    // Fall back to comma-separated
                    cleanIds = cleanIds.replace('[', '').replace(']', '').replace('"', '');
                    idStrings = cleanIds.split(',');
                }
            } else {
                // Comma-separated format: 001...,001...
                idStrings = cleanIds.split(',');
            }

            for (String idStr : idStrings) {
                String trimmedId = idStr.trim();
                if (String.isNotBlank(trimmedId)) {
                    try {
                        whitelistIds.add(Id.valueOf(trimmedId));
                    } catch (Exception idEx) {
                        System.debug(LoggingLevel.WARN, 'Invalid ID in whitelist: ' + trimmedId);
                    }
                }
            }
            System.debug(LoggingLevel.INFO, 'Whitelist mode: filtering to ' + whitelistIds.size() + ' specific record IDs');
        }

        // Parse blacklist IDs if provided (for excluding already-fixed records)
        Set<Id> blacklistIds = new Set<Id>();
        if (String.isNotBlank(excludeRecordIds)) {
            // Parse the comma-separated or JSON array of IDs
            String cleanIds = excludeRecordIds.trim();
            List<String> idStrings;

            if (cleanIds.startsWith('[')) {
                // JSON array format: ["001...", "001..."]
                try {
                    idStrings = (List<String>)JSON.deserialize(cleanIds, List<String>.class);
                } catch (Exception jsonEx) {
                    // Fall back to comma-separated
                    cleanIds = cleanIds.replace('[', '').replace(']', '').replace('"', '');
                    idStrings = cleanIds.split(',');
                }
            } else {
                // Comma-separated format: 001...,001...
                idStrings = cleanIds.split(',');
            }

            for (String idStr : idStrings) {
                String trimmedId = idStr.trim();
                if (String.isNotBlank(trimmedId)) {
                    try {
                        blacklistIds.add(Id.valueOf(trimmedId));
                    } catch (Exception idEx) {
                        System.debug(LoggingLevel.WARN, 'Invalid ID in blacklist: ' + trimmedId);
                    }
                }
            }
            System.debug(LoggingLevel.INFO, 'Blacklist mode: excluding ' + blacklistIds.size() + ' already-fixed record IDs');
        }

        // Build the query - if whitelist is provided, use simple ID filter instead of pattern query
        String queryString;
        if (!whitelistIds.isEmpty()) {
            // WHITELIST MODE: Only return records from the whitelist
            // This is used for partial fix scenarios where we only want remaining unfixed records
            queryString = 'SELECT ' + displayFields +
                         ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                         ' WHERE Id IN :whitelistIds' +
                         ' ORDER BY CreatedDate DESC' +
                         ' LIMIT ' + limitCount;
        } else if (!pluginMatchedIds.isEmpty()) {
            // APEX PLUGIN MODE: Use IDs returned by the plugin's analyze() method
            if (!blacklistIds.isEmpty()) {
                // Exclude already-fixed records from plugin results
                pluginMatchedIds.removeAll(blacklistIds);
            }
            queryString = 'SELECT ' + displayFields +
                         ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                         ' WHERE Id IN :pluginMatchedIds' +
                         ' ORDER BY CreatedDate DESC' +
                         ' LIMIT ' + limitCount;
        } else if (!blacklistIds.isEmpty()) {
            // BLACKLIST MODE: Run pattern query but exclude already-fixed records
            queryString = 'SELECT ' + displayFields +
                         ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                         ' WHERE (' + effectiveCondition + ') AND Id NOT IN :blacklistIds' +
                         ' ORDER BY CreatedDate DESC' +
                         ' LIMIT ' + limitCount;
        } else {
            // STANDARD MODE: Run the full pattern query
            queryString = 'SELECT ' + displayFields +
                         ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                         ' WHERE ' + effectiveCondition +
                         ' ORDER BY CreatedDate DESC' +
                         ' LIMIT ' + limitCount;
        }

        // Store for test verification and debug logging
        lastExecutedQuery = queryString;
        System.debug(LoggingLevel.INFO, '=== PatternAnalysisService.getPatternMatches ===');
        System.debug(LoggingLevel.INFO, 'Rule: ' + ruleDeveloperName);
        System.debug(LoggingLevel.INFO, 'Object: ' + objectApiName);
        String modeDescription = 'STANDARD (full pattern query)';
        if (!whitelistIds.isEmpty()) {
            modeDescription = 'WHITELIST (' + whitelistIds.size() + ' specific IDs)';
        } else if (!pluginMatchedIds.isEmpty()) {
            modeDescription = 'APEX_PLUGIN (' + pluginMatchedIds.size() + ' IDs from plugin)';
        } else if (!blacklistIds.isEmpty()) {
            modeDescription = 'BLACKLIST (excluding ' + blacklistIds.size() + ' fixed IDs)';
        }
        System.debug(LoggingLevel.INFO, 'Mode: ' + modeDescription);
        if (whitelistIds.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Original condition: ' + rule.Query_Condition__c);
            System.debug(LoggingLevel.INFO, 'Effective condition: ' + effectiveCondition);
        }
        System.debug(LoggingLevel.INFO, 'Full query: ' + queryString);

        try {
            // Test hooks for exception coverage
            if (Test.isRunningTest() && forcePatternMatchQueryException) {
                throw new QueryException('Forced test QueryException for pattern match');
            }
            if (Test.isRunningTest() && forcePatternMatchGeneralException) {
                throw new System.TypeException('Forced test general exception for pattern match');
            }
            // TC-6.1/6.2: Execute query (class uses 'with sharing' for sharing enforcement)
            // FLS is validated by validateQueryFieldsAccessible() before building query
            List<SObject> results = Database.query(queryString);

            // Apply field-level security by stripping inaccessible fields
            // This provides defense-in-depth - stripInaccessible ensures no
            // inaccessible fields leak to the client
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.READABLE, results);
            return securityDecision.getRecords();
        } catch (QueryException qe) {
            System.debug(LoggingLevel.ERROR, 'Query execution failed: ' + qe.getMessage());
            System.debug(LoggingLevel.ERROR, 'Query: ' + queryString);
            String msg = 'Unable to query records: ' + qe.getMessage();
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error: ' + ex.getMessage());
            String msg = 'Error retrieving records: ' + ex.getMessage();
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }
    }

    /**
     * @description Returns the appropriate display fields for a given object type.
     * Ensures critical fields are included for the remediation preview datatable.
     * @param objectApiName The API name of the object
     * @return Comma-separated list of field names
     */
    private static String getDisplayFieldsForObject(String objectApiName) {
        String objLower = objectApiName.toLowerCase();

        // Case doesn't have a standard Name field, so we handle each object type explicitly
        List<String> fields;

        if (objLower == 'case') {
            // Case uses CaseNumber instead of Name
            fields = new List<String>{ 'Id', 'CaseNumber', 'Subject', 'Status', 'Priority', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'opportunity') {
            fields = new List<String>{ 'Id', 'Name', 'StageName', 'Amount', 'CloseDate', 'Probability', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'lead') {
            fields = new List<String>{ 'Id', 'Name', 'Company', 'Status', 'Email', 'Phone', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'account') {
            fields = new List<String>{ 'Id', 'Name', 'Industry', 'Type', 'Phone', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'contact') {
            fields = new List<String>{ 'Id', 'Name', 'Email', 'Phone', 'Title', 'AccountId', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'task') {
            fields = new List<String>{ 'Id', 'Subject', 'Status', 'Priority', 'ActivityDate', 'CreatedDate', 'OwnerId' };
        } else if (objLower == 'contract') {
            fields = new List<String>{ 'Id', 'ContractNumber', 'Status', 'StartDate', 'EndDate', 'AccountId', 'CreatedDate', 'OwnerId' };
        } else {
            // Default fields for any other object (including custom objects like Project__c)
            // Uses dynamic field detection for custom objects
            fields = getDynamicDisplayFields(objectApiName);
        }

        // Remove duplicates and return
        Set<String> uniqueFields = new Set<String>(fields);
        return String.join(new List<String>(uniqueFields), ', ');
    }

    /**
     * @description Dynamically discovers display fields for custom objects.
     * Looks for common field patterns (Name, Status, OwnerId, etc.) and returns
     * a list of accessible fields suitable for display.
     * @param objectApiName The API name of the custom object
     * @return List of field names to include in the query
     */
    private static List<String> getDynamicDisplayFields(String objectApiName) {
        List<String> fields = new List<String>{ 'Id' };

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceDynamicFieldsException) {
                throw new System.TypeException('Forced test exception for dynamic fields');
            }
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            // Use lowercase for case-insensitive lookup
            Schema.SObjectType sObjType = globalDescribe.get(objectApiName.toLowerCase());

            if (sObjType == null) {
                return fields;
            }

            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();

            // Priority fields to look for (in order of preference)
            List<String> priorityFields = new List<String>{
                'Name',
                'Status__c',
                'Status',
                'OwnerId',
                'CreatedDate',
                'LastModifiedDate',
                'Description__c',
                'Description',
                'Type__c',
                'Type',
                'AccountId',
                'Account__c'
            };

            for (String fieldName : priorityFields) {
                Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
                if (field != null && field.getDescribe().isAccessible()) {
                    fields.add(fieldName);
                }
            }

            // Ensure we have at least some useful fields
            if (fields.size() == 1) {
                // Just Id - add CreatedDate if available
                Schema.SObjectField createdDate = fieldMap.get('createddate');
                if (createdDate != null && createdDate.getDescribe().isAccessible()) {
                    fields.add('CreatedDate');
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting dynamic display fields for ' + objectApiName + ': ' + e.getMessage());
        }

        return fields;
    }

    // Status constants to avoid magic strings
    private static final String STATUS_RESOLVED = 'Resolved';
    private static final String STATUS_DISMISSED = 'Dismissed';
    private static final String STATUS_NEW = 'New';

    /**
     * @description Synchronizes a pain point's Occurrences__c with the live query count.
     * CRITICAL: This method calculates the count SERVER-SIDE using the same query logic
     * as getPatternMatches, rather than accepting a client-provided count (trust boundary).
     *
     * This solves the "dual source of truth" problem where:
     * - Dashboard shows stored Occurrences__c (set by batch, can become stale)
     * - Preview shows live query results (always current)
     *
     * @param painPointId The ID of the Identified_Pain_Point__c record to sync
     * @return SyncResult containing the updated occurrence count and any status changes
     */
    @AuraEnabled
    public static SyncResult syncPainPointOccurrences(String painPointId) {
        SyncResult result = new SyncResult();

        if (String.isBlank(painPointId)) {
            result.success = false;
            result.message = 'Pain point ID is required';
            return result;
        }

        // Validate painPointId is a valid Id format before querying
        try {
            Id.valueOf(painPointId);
        } catch (Exception idEx) {
            result.success = false;
            result.message = 'Invalid pain point ID format';
            return result;
        }

        try {
            // CRUD check for query
            if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
                result.success = false;
                result.message = 'Insufficient permissions to access pain points';
                return result;
            }

            // Query the pain point with FOR UPDATE to prevent race conditions
            List<Identified_Pain_Point__c> painPoints = [
                SELECT Id, Name, Occurrences__c, Status__c, Unique_Key__c,
                       Impact_Score__c, Cost_Per_Incident__c, Object_API_Name__c,
                       Fixed_Record_Ids__c
                FROM Identified_Pain_Point__c
                WHERE Id = :painPointId
                WITH SECURITY_ENFORCED
                LIMIT 1
                FOR UPDATE
            ];

            if (painPoints.isEmpty()) {
                result.success = false;
                result.message = 'Pain point not found';
                return result;
            }

            Identified_Pain_Point__c pp = painPoints[0];
            Integer previousCount = pp.Occurrences__c != null ? pp.Occurrences__c.intValue() : 0;

            // Calculate the LIVE COUNT server-side using the same query logic as getPatternMatches
            // This avoids trust boundary issues with client-provided counts
            // Returns null on errors to distinguish from "true zero" (no matching records)
            Integer liveCount = calculateLiveCount(pp);

            // Handle calculation errors - null means error, not zero
            if (liveCount == null) {
                result.success = false;
                result.message = 'Unable to calculate live count. Check permissions and rule configuration.';
                result.previousCount = previousCount;
                result.newCount = previousCount; // Keep previous count on error
                return result;
            }

            result.previousCount = previousCount;
            result.newCount = liveCount;

            // Only update if the count has changed
            if (previousCount != liveCount) {
                System.debug(LoggingLevel.DEBUG, 'Syncing pain point ' + pp.Name +
                             ': stored=' + previousCount + ', live=' + liveCount);

                // CRUD check for update
                if (!Schema.sObjectType.Identified_Pain_Point__c.isUpdateable()) {
                    result.success = false;
                    result.message = 'Insufficient permissions to update pain points';
                    return result;
                }

                // Update the occurrence count
                pp.Occurrences__c = liveCount;

                // Recalculate impact score based on new count
                // For Opportunity/Contract, keep the stored value (it's cumulative value, not count-based)
                String objName = pp.Object_API_Name__c != null ? pp.Object_API_Name__c.toLowerCase() : '';
                if (objName != 'opportunity' && objName != 'contract') {
                    Decimal costPerIncident = pp.Cost_Per_Incident__c != null ? pp.Cost_Per_Incident__c : 0;
                    pp.Impact_Score__c = liveCount * costPerIncident;
                }

                // If count drops to zero, mark as resolved (all records fixed externally)
                if (liveCount == 0 && pp.Status__c != STATUS_RESOLVED && pp.Status__c != STATUS_DISMISSED) {
                    pp.Status__c = STATUS_RESOLVED;
                    result.statusChanged = true;
                    result.newStatus = STATUS_RESOLVED;
                    System.debug(LoggingLevel.DEBUG, 'Auto-resolving pain point - no matching records remain');
                }

                // Apply FLS enforcement before DML - strip any inaccessible fields
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    new List<Identified_Pain_Point__c>{ pp }
                );
                List<Identified_Pain_Point__c> securedRecords = (List<Identified_Pain_Point__c>) decision.getRecords();

                if (securedRecords.isEmpty()) {
                    result.success = false;
                    result.message = 'Insufficient field permissions to update pain point';
                    return result;
                }

                // Validate that critical fields weren't stripped
                Map<String, Set<String>> removedFields = decision.getRemovedFields();
                if (removedFields.containsKey('Identified_Pain_Point__c')) {
                    Set<String> stripped = removedFields.get('Identified_Pain_Point__c');
                    if (stripped.contains('Occurrences__c') || stripped.contains('Status__c') || stripped.contains('Impact_Score__c')) {
                        result.success = false;
                        result.message = 'Insufficient field-level permissions to update required fields';
                        return result;
                    }
                }

                update securedRecords[0];

                result.success = true;
                result.message = 'Synced: ' + previousCount + ' → ' + liveCount;

                System.debug(LoggingLevel.DEBUG, 'Pain point synced successfully: ' + result.message);

                // CRITICAL: Update Behavior_Snapshot__c to keep trend chart in sync
                // This ensures the trend chart reflects accurate live counts
                updateTrendSnapshot(pp, liveCount);
            } else {
                // Counts match - no update needed
                result.success = true;
                result.message = 'Count already in sync';
            }

        } catch (DmlException dmlEx) {
            // Handle specific DML errors like row lock contention
            System.debug(LoggingLevel.ERROR, 'DML error syncing pain point: ' + dmlEx.getMessage());
            result.success = false;
            if (dmlEx.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
                result.message = 'Record is being updated by another user. Please try again.';
            } else {
                result.message = 'Unable to update pain point. Please try again.';
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error syncing pain point: ' + e.getMessage());
            result.success = false;
            result.message = 'Unable to sync occurrence count. Please try again.';
        }

        return result;
    }

    /**
     * @description Calculates the live count of records matching a pain point's pattern rule.
     * Uses the same query logic as getPatternMatches but returns a COUNT instead of records.
     * This runs server-side to avoid trust boundary issues with client-provided counts.
     *
     * SECURITY: Validates object/field accessibility before executing dynamic queries.
     * Returns null on errors to distinguish from "true zero" (no matching records).
     *
     * @param painPoint The pain point record containing rule key and exclusion info
     * @return The count of currently matching records, or null if calculation failed
     */
    private static Integer calculateLiveCount(Identified_Pain_Point__c painPoint) {
        if (painPoint == null || String.isBlank(painPoint.Unique_Key__c)) {
            return null; // Invalid input - return null to indicate error, not zero
        }

        try {
            // Extract base rule name from potentially timestamped key
            String baseRuleName = extractBaseRuleName(painPoint.Unique_Key__c);

            // Query the rule from metadata
            List<Behavior_Pattern_Rule__mdt> rules = [
                SELECT DeveloperName, Object_API_Name__c, Query_Condition__c,
                       Logic_Type__c, Apex_Handler_Class__c, Fix_Config__c
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :baseRuleName
                LIMIT 1
            ];

            if (rules.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'Rule not found for key: ' + baseRuleName);
                return null; // Rule not found - return null to indicate error
            }

            Behavior_Pattern_Rule__mdt rule = rules[0];
            String objectApiName = rule.Object_API_Name__c;

            // SECURITY: Validate object name against Schema (not escapeSingleQuotes)
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjectType = globalDescribe.get(objectApiName.toLowerCase());
            if (sObjectType == null) {
                System.debug(LoggingLevel.WARN, 'Object not found in schema: ' + objectApiName);
                return null;
            }

            // Use canonical object name from describe
            String canonicalObjectName = sObjectType.getDescribe().getName();

            // Check object accessibility
            if (!sObjectType.getDescribe().isAccessible()) {
                System.debug(LoggingLevel.WARN, 'Object not accessible: ' + canonicalObjectName);
                return null;
            }

            // Build exclusion list from Fixed_Record_Ids__c (with size cap to prevent heap issues)
            Set<Id> excludeIds = parseExcludeIds(painPoint.Fixed_Record_Ids__c, 5000);

            // Check for Apex Plugin rule
            Boolean isApexPlugin = rule.Logic_Type__c == 'Apex_Plugin' && String.isNotBlank(rule.Apex_Handler_Class__c);

            if (isApexPlugin) {
                return calculatePluginCount(rule, canonicalObjectName, excludeIds);
            }

            // Get effective query condition with admin threshold injection
            PatternAnalysisService service = new PatternAnalysisService();
            String effectiveCondition = service.getEffectiveQuery(rule);

            if (String.isBlank(effectiveCondition)) {
                return null;
            }

            // SECURITY: Validate FLS for fields in the query condition before executing
            // This uses the existing validateQueryFieldsAccessible method
            if (!validateQueryFieldsAccessible(canonicalObjectName, effectiveCondition)) {
                System.debug(LoggingLevel.WARN, 'FLS check failed for query condition fields');
                return null;
            }

            // Build COUNT query using validated canonical object name
            String countQuery = 'SELECT COUNT() FROM ' + canonicalObjectName +
                               ' WHERE (' + effectiveCondition + ')';

            if (!excludeIds.isEmpty()) {
                countQuery += ' AND Id NOT IN :excludeIds';
            }

            // Execute count query (class uses 'with sharing' for sharing enforcement)
            Integer count = Database.countQuery(countQuery);
            return count;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error calculating live count: ' + e.getMessage());
            return null; // Error - return null to indicate failure, not zero
        }
    }

    /**
     * @description Calculates count for Apex Plugin rules with sharing enforcement.
     * Re-validates plugin IDs by querying them with sharing to ensure user has access.
     *
     * @param rule The pattern rule metadata
     * @param objectApiName The canonical object API name
     * @param excludeIds Set of IDs to exclude from count
     * @return The count of accessible matching records, or null on error
     */
    private static Integer calculatePluginCount(Behavior_Pattern_Rule__mdt rule, String objectApiName, Set<Id> excludeIds) {
        try {
            Map<String, Object> config = new Map<String, Object>();
            if (String.isNotBlank(rule.Fix_Config__c)) {
                config = (Map<String, Object>) JSON.deserializeUntyped(rule.Fix_Config__c);
            }
            PatternPluginContext context = new PatternPluginContext(
                objectApiName,
                rule.Query_Condition__c,
                config,
                rule.DeveloperName
            );
            List<Id> matchedIds = PluginInvoker.invokeAnalyze(rule.Apex_Handler_Class__c, context);

            if (matchedIds == null || matchedIds.isEmpty()) {
                return 0; // True zero - no matches from plugin
            }

            // Cap plugin results to prevent heap issues
            if (matchedIds.size() > 10000) {
                System.debug(LoggingLevel.WARN, 'Plugin returned too many IDs: ' + matchedIds.size());
                return null;
            }

            // Remove excluded IDs
            Set<Id> matchedSet = new Set<Id>(matchedIds);
            matchedSet.removeAll(excludeIds);

            if (matchedSet.isEmpty()) {
                return 0; // True zero - all matches were excluded
            }

            // SECURITY: Re-validate plugin IDs with sharing enforcement
            // Query IDs to ensure user has access (class is 'with sharing')
            String validationQuery = 'SELECT COUNT() FROM ' + objectApiName +
                                    ' WHERE Id IN :matchedSet';
            Integer accessibleCount = Database.countQuery(validationQuery);

            return accessibleCount;

        } catch (Exception pluginEx) {
            System.debug(LoggingLevel.ERROR, 'Plugin count failed: ' + pluginEx.getMessage());
            return null;
        }
    }

    /**
     * @description Parses a string of record IDs into a Set with a size cap.
     * Handles both JSON array and comma-separated formats.
     *
     * @param idsString The string containing record IDs
     * @param maxSize Maximum number of IDs to parse (heap protection)
     * @return Set of parsed IDs
     */
    private static Set<Id> parseExcludeIds(String idsString, Integer maxSize) {
        Set<Id> excludeIds = new Set<Id>();

        if (String.isBlank(idsString)) {
            return excludeIds;
        }

        String cleanIds = idsString.trim();
        List<String> idStrings;

        if (cleanIds.startsWith('[')) {
            try {
                idStrings = (List<String>)JSON.deserialize(cleanIds, List<String>.class);
            } catch (Exception jsonEx) {
                cleanIds = cleanIds.replace('[', '').replace(']', '').replace('"', '');
                idStrings = cleanIds.split(',');
            }
        } else {
            idStrings = cleanIds.split(',');
        }

        Integer count = 0;
        for (String idStr : idStrings) {
            if (count >= maxSize) {
                System.debug(LoggingLevel.WARN, 'Exclude IDs capped at ' + maxSize);
                break;
            }
            String trimmedId = idStr.trim();
            if (String.isNotBlank(trimmedId)) {
                try {
                    excludeIds.add(Id.valueOf(trimmedId));
                    count++;
                } catch (Exception idEx) {
                    // Skip invalid IDs
                }
            }
        }

        return excludeIds;
    }

    /**
     * @description Updates or creates a Behavior_Snapshot__c record for today to keep trend chart in sync.
     * Called after syncPainPointOccurrences updates a pain point's occurrence count.
     * This ensures the trend chart reflects accurate live counts, not just batch-created snapshots.
     *
     * CONTEXT: This method is designed for single-record real-time sync (called once per user
     * interaction with the preview modal). It is NOT intended for bulk batch processing.
     * The calling method (syncPainPointOccurrences) processes one pain point per invocation.
     *
     * SECURITY: Enforces operation-specific CRUD/FLS checks before DML operations.
     *
     * @param painPoint The pain point that was synced
     * @param newCount The new occurrence count
     */
    private static void updateTrendSnapshot(Identified_Pain_Point__c painPoint, Integer newCount) {
        if (painPoint == null || String.isBlank(painPoint.Unique_Key__c)) {
            return;
        }

        try {
            // Extract base rule name for consistent metric naming
            String metricName = extractBaseRuleName(painPoint.Unique_Key__c);
            Date today = Date.today();
            Boolean isInsert = false;
            Behavior_Snapshot__c snapshot;

            // Look for existing snapshot for this metric today
            // WITH SECURITY_ENFORCED handles query-time FLS enforcement
            List<Behavior_Snapshot__c> existingSnapshots = [
                SELECT Id, Record_Count__c, Impact_Score__c
                FROM Behavior_Snapshot__c
                WHERE Metric_Name__c = :metricName
                AND Snapshot_Date__c = :today
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!existingSnapshots.isEmpty()) {
                // UPDATE PATH: Check update permissions only
                if (!Schema.sObjectType.Behavior_Snapshot__c.isUpdateable()) {
                    System.debug(LoggingLevel.WARN, 'No update permission for Behavior_Snapshot__c - skipping trend update');
                    return;
                }

                snapshot = existingSnapshots[0];
                snapshot.Record_Count__c = newCount;
                snapshot.Impact_Score__c = painPoint.Impact_Score__c;
                isInsert = false;
            } else {
                // INSERT PATH: Check create permissions only
                if (!Schema.sObjectType.Behavior_Snapshot__c.isCreateable()) {
                    System.debug(LoggingLevel.WARN, 'No create permission for Behavior_Snapshot__c - skipping trend update');
                    return;
                }

                snapshot = new Behavior_Snapshot__c(
                    Metric_Name__c = metricName,
                    Snapshot_Date__c = today,
                    Record_Count__c = newCount,
                    Impact_Score__c = painPoint.Impact_Score__c
                );
                isInsert = true;
            }

            // Apply FLS enforcement before DML - use operation-specific access type
            AccessType accessType = isInsert ? AccessType.CREATABLE : AccessType.UPDATABLE;
            SObjectAccessDecision decision = Security.stripInaccessible(
                accessType,
                new List<Behavior_Snapshot__c>{ snapshot }
            );
            List<Behavior_Snapshot__c> securedSnapshots = (List<Behavior_Snapshot__c>) decision.getRecords();

            if (securedSnapshots.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'FLS stripped all fields - cannot update snapshot');
                return;
            }

            // Validate that required fields weren't stripped (especially for inserts)
            Map<String, Set<String>> removedFields = decision.getRemovedFields();
            if (removedFields.containsKey('Behavior_Snapshot__c')) {
                Set<String> stripped = removedFields.get('Behavior_Snapshot__c');
                // For inserts, Metric_Name__c and Snapshot_Date__c are required
                if (isInsert && (stripped.contains('Metric_Name__c') || stripped.contains('Snapshot_Date__c'))) {
                    System.debug(LoggingLevel.WARN, 'FLS stripped required fields (Metric_Name__c or Snapshot_Date__c) - cannot create snapshot');
                    return;
                }
                // Record_Count__c is the primary value we're trying to sync
                if (stripped.contains('Record_Count__c')) {
                    System.debug(LoggingLevel.WARN, 'FLS stripped Record_Count__c - snapshot update would be ineffective');
                    return;
                }
            }

            if (isInsert) {
                insert securedSnapshots;
                System.debug(LoggingLevel.DEBUG, 'Created trend snapshot for ' + metricName + ': count=' + newCount);
            } else {
                update securedSnapshots;
                System.debug(LoggingLevel.DEBUG, 'Updated trend snapshot for ' + metricName + ': count=' + newCount);
            }

        } catch (Exception e) {
            // Log but don't fail the sync - trend update is secondary to the core sync operation
            // Debug logging is acceptable here since this is a "best effort" secondary operation
            System.debug(LoggingLevel.WARN, 'Failed to update trend snapshot for pain point ' +
                         painPoint.Id + ': ' + e.getMessage());
        }
    }

    /**
     * @description Result wrapper for the syncPainPointOccurrences method.
     * Provides detailed feedback about the sync operation.
     */
    public class SyncResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String message = '';
        @AuraEnabled public Integer previousCount = 0;
        @AuraEnabled public Integer newCount = 0;
        @AuraEnabled public Boolean statusChanged = false;
        @AuraEnabled public String newStatus = '';
    }
}