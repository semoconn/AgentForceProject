/**
 * @description Pattern plugin that detects duplicate records based on a configurable field.
 * Identifies records where multiple entries share the same field value (e.g., Email, Phone, Name).
 * Supports Lead, Contact, Account, and custom objects.
 * Only supports text-type fields that can be used in GROUP BY (String, Email, Phone, URL).
 * Note: TextArea/Long Text Area fields are not supported as they cannot be grouped in SOQL.
 *
 * Security: Uses WITH USER_MODE for sharing/FLS enforcement, Schema validation for
 * object/field accessibility, and bind variables to prevent SOQL injection.
 *
 * @group BehaviorIQ Plugins
 * @since 2025-01
 */
global with sharing class DuplicateRecordPlugin implements PatternPlugin {

    private static final Integer QUERY_LIMIT = 2000;
    // Only text-based fields that support GROUP BY in SOQL (excludes Long Text Area/Rich Text Area)
    private static final Set<Schema.DisplayType> SUPPORTED_FIELD_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL
    };
    // Objects that can be linked via Task.WhoId (Person objects)
    private static final Set<String> WHO_ID_OBJECTS = new Set<String>{'Contact', 'Lead'};
    // Objects that cannot be linked via Task.WhatId (system/special objects)
    private static final Set<String> UNSUPPORTED_WHAT_ID_OBJECTS = new Set<String>{
        'User', 'Group', 'RecordType', 'Profile', 'PermissionSet'
    };

    /**
     * @description Finds records that have duplicate values in the configured field.
     * Uses aggregation to identify field values that appear more than once,
     * then returns all record IDs with those duplicate values.
     *
     * @param context Contains objectApiName, config with duplicateField setting
     * @return List of record IDs that have duplicates
     */
    global List<Id> analyze(PatternPluginContext context) {
        List<Id> duplicateRecordIds = new List<Id>();

        // Extract configuration
        String objectApiName = context.objectApiName;
        Map<String, Object> config = context.config != null ? context.config : new Map<String, Object>();
        String duplicateField = (String) config.get('duplicateField');
        Boolean excludeNulls = config.get('excludeNulls') != null ? (Boolean) config.get('excludeNulls') : true;

        if (String.isBlank(duplicateField)) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: No duplicateField configured');
            return duplicateRecordIds;
        }

        // Validate object and field accessibility
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: Object not found - ' + objectApiName);
            return duplicateRecordIds;
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        if (!describeResult.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: Object not accessible - ' + objectApiName);
            return duplicateRecordIds;
        }

        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        Schema.SObjectField field = fieldMap.get(duplicateField);
        if (field == null) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: Field not found - ' + duplicateField);
            return duplicateRecordIds;
        }

        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        if (!fieldDescribe.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: Field not accessible - ' + duplicateField);
            return duplicateRecordIds;
        }

        // Validate field type is supported (text-based fields only)
        if (!SUPPORTED_FIELD_TYPES.contains(fieldDescribe.getType())) {
            System.debug(LoggingLevel.WARN, 'DuplicateRecordPlugin: Unsupported field type - ' + fieldDescribe.getType());
            return duplicateRecordIds;
        }

        // Get validated API names from Schema (do not use escapeSingleQuotes on identifiers)
        String validatedObjectName = describeResult.getName();
        String validatedFieldName = fieldDescribe.getName();

        // Step 1: Find field values that appear more than once (using validated API names)
        Set<String> duplicateValues = findDuplicateFieldValues(validatedObjectName, validatedFieldName, excludeNulls);

        if (duplicateValues.isEmpty()) {
            return duplicateRecordIds;
        }

        // Step 2: Get all record IDs with those duplicate values (using bind variables)
        duplicateRecordIds = getRecordsWithDuplicateValues(validatedObjectName, validatedFieldName, duplicateValues);

        return duplicateRecordIds;
    }

    /**
     * @description Finds field values that appear more than once in the object.
     * Uses validated API names from Schema - no escaping needed for identifiers.
     * @param validatedObjectName Schema-validated object API name
     * @param validatedFieldName Schema-validated field API name
     * @param excludeNulls Whether to exclude null values from duplicate detection
     */
    private Set<String> findDuplicateFieldValues(String validatedObjectName, String validatedFieldName, Boolean excludeNulls) {
        Set<String> duplicateValues = new Set<String>();

        // Build aggregate query using validated identifiers (no escaping needed - validated via Schema)
        // Note: WITH USER_MODE must come after WHERE clause but before GROUP BY
        String nullClause = excludeNulls ? ' WHERE ' + validatedFieldName + ' != null' : '';
        String aggregateQuery = 'SELECT ' + validatedFieldName + ' fieldValue, COUNT(Id) cnt ' +
                                'FROM ' + validatedObjectName +
                                nullClause +
                                ' WITH USER_MODE' +
                                ' GROUP BY ' + validatedFieldName +
                                ' HAVING COUNT(Id) > 1' +
                                ' LIMIT ' + QUERY_LIMIT;

        try {
            // Field/object names are Schema-validated via validateSObjectTypeAndField
            List<AggregateResult> results = Database.query(aggregateQuery);  // NOPMD - ApexSOQLInjection

            for (AggregateResult ar : results) {
                Object fieldValue = ar.get('fieldValue');
                if (fieldValue != null) {
                    duplicateValues.add(String.valueOf(fieldValue));
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DuplicateRecordPlugin aggregate query error: ' + e.getMessage());
        }

        return duplicateValues;
    }

    /**
     * @description Gets all record IDs that have one of the duplicate values.
     * Uses bind variables for safe query construction.
     * @param validatedObjectName Schema-validated object API name
     * @param validatedFieldName Schema-validated field API name
     * @param duplicateValues Set of duplicate field values to search for
     */
    private List<Id> getRecordsWithDuplicateValues(String validatedObjectName, String validatedFieldName, Set<String> duplicateValues) {
        List<Id> recordIds = new List<Id>();

        if (duplicateValues.isEmpty()) {
            return recordIds;
        }

        // Use bind variable for safe query construction (avoids SOQL injection and large IN clause issues)
        String recordQuery = 'SELECT Id FROM ' + validatedObjectName +
                            ' WHERE ' + validatedFieldName + ' IN :duplicateValues' +
                            ' WITH USER_MODE' +
                            ' LIMIT ' + QUERY_LIMIT;

        try {
            // Field/object names are Schema-validated, duplicateValues uses bind variable
            List<SObject> records = Database.query(recordQuery);  // NOPMD - ApexSOQLInjection

            for (SObject record : records) {
                recordIds.add(record.Id);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DuplicateRecordPlugin record query error: ' + e.getMessage());
        }

        return recordIds;
    }

    /**
     * @description Creates follow-up tasks for records with duplicates.
     * Each affected record gets a task assigned to its owner to review and merge.
     *
     * @param recordIds List of record IDs identified as duplicates
     * @param config Configuration including taskSubject, duplicateField
     * @return PatternPluginResult with success/failure counts and audit logs
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        PatternPluginResult result = new PatternPluginResult();

        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        String ruleName = config != null ? (String) config.get('ruleDeveloperName') : 'Duplicate_Records';
        String taskSubject = config != null && config.get('taskSubject') != null
            ? (String) config.get('taskSubject')
            : 'Review potential duplicate records';
        String duplicateField = config != null ? (String) config.get('duplicateField') : 'Unknown';

        // Check Task object CRUD access (required - cannot proceed without object access)
        if (!Schema.SObjectType.Task.isCreateable()) {
            for (Id recordId : recordIds) {
                result.addFailureLog(recordId, 'Task_Creation', 'Insufficient access to create Tasks', ruleName);
            }
            return result;
        }

        // Build tasks for each duplicate record, tracking source record ID for result correlation
        List<Task> tasksToInsert = new List<Task>();
        Map<Integer, Id> indexToSourceRecordId = new Map<Integer, Id>();
        Integer taskIndex = 0;

        for (Id recordId : recordIds) {
            String sObjectName = recordId.getSobjectType().getDescribe().getName();

            // Validate object can be linked to Task
            if (UNSUPPORTED_WHAT_ID_OBJECTS.contains(sObjectName)) {
                result.addFailureLog(recordId, 'Task_Creation',
                    'Object type ' + sObjectName + ' cannot be linked to Tasks', ruleName);
                continue;
            }

            Task t = new Task(
                Subject = taskSubject + ' (Duplicate ' + duplicateField + ')',
                ActivityDate = Date.today().addDays(7),
                Priority = 'Normal',
                Status = 'Not Started',
                Description = 'This record has been identified as a potential duplicate based on the ' +
                             duplicateField + ' field. Please review and merge if appropriate.'
            );

            // Set WhatId or WhoId based on object type
            if (WHO_ID_OBJECTS.contains(sObjectName)) {
                t.WhoId = recordId;
            } else {
                t.WhatId = recordId;
            }

            tasksToInsert.add(t);
            indexToSourceRecordId.put(taskIndex, recordId);
            taskIndex++;
        }

        // If all records were filtered out, return early
        if (tasksToInsert.isEmpty()) {
            return result;
        }

        // Apply FLS stripping before insert (handles field-level security automatically)
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, tasksToInsert);
        List<Task> securedTasks = (List<Task>) decision.getRecords();

        // Validate list size consistency (stripInaccessible strips fields, not records)
        if (securedTasks.size() != tasksToInsert.size()) {
            // Unexpected size mismatch - log all as failures for safety
            for (Id recordId : indexToSourceRecordId.values()) {
                result.addFailureLog(recordId, 'Task_Creation',
                    'Security validation produced unexpected result count', ruleName);
            }
            return result;
        }

        // Insert tasks with partial success handling
        Database.SaveResult[] saveResults = Database.insert(securedTasks, false);

        // Correlate results using tracked index mapping
        for (Integer i = 0; i < saveResults.size(); i++) {
            Id originalRecordId = indexToSourceRecordId.get(i);

            if (saveResults[i].isSuccess()) {
                result.addSuccessLog(
                    originalRecordId,
                    'Task_Creation',
                    null,
                    'Task ' + saveResults[i].getId() + ' created',
                    ruleName
                );
            } else {
                String errorMsg = '';
                for (Database.Error err : saveResults[i].getErrors()) {
                    errorMsg += err.getMessage() + '; ';
                }
                result.addFailureLog(originalRecordId, 'Task_Creation', errorMsg, ruleName);
            }
        }

        return result;
    }
}
