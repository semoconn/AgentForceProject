/**
 * @description Metadata-Driven Batch Engine for BehaviorIQ (Phase 3).
 * Iterates through Behavior_Pattern_Rule__mdt records and executes dynamic SOQL to detect pain points.
 */
public with sharing class PatternAnalysisService implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final String JOB_NAME = 'Pattern Analysis Service';
    public static final Integer DEFAULT_RETENTION_DAYS = 90;

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

    public PatternAnalysisService() {
        dismissedPainPointKeys = new Set<String>();
        pendingSnapshots = new List<Behavior_Snapshot__c>();
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
                List<Behavior_Snapshot__c> todaysSnapshots = [
                    SELECT Id FROM Behavior_Snapshot__c
                    WHERE Snapshot_Date__c = TODAY
                    LIMIT 10000
                ];
                if (!todaysSnapshots.isEmpty()) {
                    delete todaysSnapshots;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to delete today\'s snapshots: ' + e.getMessage());
            }
        }

        // Fetch all defined rules from Metadata
        return [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                   Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c
            FROM Behavior_Pattern_Rule__mdt
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

        // Build and execute the detection query
        List<SObject> detectedRecords = executeDetectionQuery(rule, objectApiName);
        if (detectedRecords == null || detectedRecords.isEmpty()) {
            return;
        }

        // Generate and persist the pain point
        persistDetectionResults(rule, objectApiName, detectedRecords);
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
            return Database.query(queryString);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Rule Execution Failed [' + rule.DeveloperName + ']: ' + e.getMessage());
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

        upsertPainPoint(
            rule.DeveloperName,
            rule.MasterLabel,
            'Automated detection for ' + objectApiName,
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
        Integer errors = 0;
        String extendedStatus = '';

        if (jobId != null) {
            try {
                AsyncApexJob job = [
                    SELECT NumberOfErrors, ExtendedStatus, TotalJobItems, JobItemsProcessed
                    FROM AsyncApexJob
                    WHERE Id = :jobId
                    LIMIT 1
                ];
                errors = job.NumberOfErrors;
                extendedStatus = job.ExtendedStatus;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Unable to query job status: ' + e.getMessage());
            }
        }

        // Log to System_Health_Log__c if accessible
        if (Schema.sObjectType.System_Health_Log__c.isCreateable()) {
            System_Health_Log__c log = new System_Health_Log__c(
                Job_Name__c = JOB_NAME,
                Job_ID__c = jobId,
                Status__c = (errors > 0) ? 'Failed' : 'Success',
                Error_Count__c = errors
            );
            try {
                insert Security.stripInaccessible(AccessType.CREATABLE, new List<System_Health_Log__c>{log}).getRecords();
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Unable to create health log: ' + e.getMessage());
            }
        }

        // Send admin notification email on failure
        if (errors > 0) {
            sendAdminFailureNotification(jobId, errors, extendedStatus);
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
     * @return List<SObject> The matching records with key fields for display
     */
    @AuraEnabled
    public static List<SObject> getPatternMatches(String ruleDeveloperName, Integer limitCount, String includeOnlyRecordIds) {
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

        // Fetch the rule from metadata
        // First try exact match, then try to find base rule name (for timestamped keys from partial fixes)
        String effectiveRuleName = ruleDeveloperName;
        List<Behavior_Pattern_Rule__mdt> rules = [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                   Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c
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
                           Is_Premium__c, Threshold_Default__c, Cost_Per_Incident__c
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

        // Validate FLS for query fields
        if (!validateQueryFieldsAccessible(objectApiName, rule.Query_Condition__c)) {
            String msg = 'One or more fields in the rule are not accessible. Please contact your administrator.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // Get effective query condition with admin threshold injection
        PatternAnalysisService service = new PatternAnalysisService();
        String effectiveCondition = service.getEffectiveQuery(rule);

        if (String.isBlank(effectiveCondition)) {
            String msg = 'Rule has no query condition defined.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // Build dynamic query with display fields based on object type
        String displayFields = getDisplayFieldsForObject(objectApiName);

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
        System.debug(LoggingLevel.INFO, 'Mode: ' + (whitelistIds.isEmpty() ? 'STANDARD (full pattern query)' : 'WHITELIST (' + whitelistIds.size() + ' specific IDs)'));
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
            List<SObject> results = Database.query(queryString);

            // Apply field-level security by stripping inaccessible fields
            // This is more flexible than WITH SECURITY_ENFORCED as it doesn't fail,
            // it just removes fields the user can't see
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
}