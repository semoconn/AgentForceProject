/**
 * @description Pattern plugin that detects records missing required file attachments.
 * Identifies records (e.g., Closed Won Opportunities, Closed Cases) that should have
 * attached documents but don't have any ContentDocumentLinks (Salesforce Files).
 *
 * Security: Uses WITH USER_MODE for sharing/FLS enforcement, Schema validation for
 * object accessibility, and admin-configured filter conditions (same security model
 * as Query_Condition__c in PatternAnalysisService - requires metadata deployment access).
 *
 * @group BehaviorIQ Plugins
 * @since 2025-01
 */
global with sharing class MissingAttachmentPlugin implements PatternPlugin {

    private static final Integer QUERY_LIMIT = 2000;

    /**
     * @description Finds records that match the filter condition but have no file attachments.
     * First queries records matching the condition, then checks ContentDocumentLink
     * to identify records with zero attachments.
     *
     * @param context Contains objectApiName, queryCondition, config with filterCondition
     * @return List of record IDs that have no attachments
     */
    global List<Id> analyze(PatternPluginContext context) {
        List<Id> recordsWithoutAttachments = new List<Id>();

        // Extract configuration
        String objectApiName = context.objectApiName;
        Map<String, Object> config = context.config != null ? context.config : new Map<String, Object>();
        String filterCondition = (String) config.get('filterCondition');

        // Use Query_Condition__c as fallback if filterCondition not in config
        if (String.isBlank(filterCondition) && String.isNotBlank(context.queryCondition)) {
            filterCondition = context.queryCondition;
        }

        if (String.isBlank(filterCondition)) {
            System.debug(LoggingLevel.WARN, 'MissingAttachmentPlugin: No filter condition configured');
            return recordsWithoutAttachments;
        }

        // Validate object accessibility
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            System.debug(LoggingLevel.WARN, 'MissingAttachmentPlugin: Object not found - ' + objectApiName);
            return recordsWithoutAttachments;
        }

        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        if (!describeResult.isAccessible()) {
            System.debug(LoggingLevel.WARN, 'MissingAttachmentPlugin: Object not accessible - ' + objectApiName);
            return recordsWithoutAttachments;
        }

        // Check ContentDocumentLink accessibility
        Schema.SObjectType cdlType = Schema.getGlobalDescribe().get('ContentDocumentLink');
        if (cdlType == null || !cdlType.getDescribe().isAccessible()) {
            System.debug(LoggingLevel.WARN, 'MissingAttachmentPlugin: ContentDocumentLink not accessible');
            return recordsWithoutAttachments;
        }

        // Get validated object name from Schema
        String validatedObjectName = describeResult.getName();

        // Step 1: Get candidate records matching the filter condition
        Set<Id> candidateRecordIds = getCandidateRecords(validatedObjectName, filterCondition);

        if (candidateRecordIds.isEmpty()) {
            return recordsWithoutAttachments;
        }

        // Step 2: Find records that have attachments
        Set<Id> recordsWithAttachments = getRecordsWithAttachments(candidateRecordIds);

        // Step 3: Return records that have no attachments
        for (Id recordId : candidateRecordIds) {
            if (!recordsWithAttachments.contains(recordId)) {
                recordsWithoutAttachments.add(recordId);
            }
        }

        return recordsWithoutAttachments;
    }

    /**
     * @description Gets candidate records matching the filter condition.
     * The filter condition comes from admin-configured pattern rule metadata (Behavior_Pattern_Rule__mdt).
     * This follows the same security model as Query_Condition__c in PatternAnalysisService -
     * only admins with custom metadata deployment access can configure these conditions.
     * WITH USER_MODE enforces the running user's sharing and FLS permissions.
     */
    private Set<Id> getCandidateRecords(String validatedObjectName, String filterCondition) {
        Set<Id> recordIds = new Set<Id>();

        // Build query with the filter condition
        // Note: filterCondition is admin-configured, similar to Query_Condition__c
        String recordQuery = 'SELECT Id FROM ' + validatedObjectName +
                            ' WHERE ' + filterCondition +
                            ' WITH USER_MODE' +
                            ' LIMIT ' + QUERY_LIMIT;

        try {
            List<SObject> records = Database.query(recordQuery);
            for (SObject record : records) {
                recordIds.add(record.Id);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MissingAttachmentPlugin candidate query error: ' + e.getMessage());
        }

        return recordIds;
    }

    /**
     * @description Gets the set of record IDs that have at least one attachment.
     * Uses aggregate query on ContentDocumentLink to efficiently check for file attachments.
     * Uses GROUP BY to avoid issues with records having multiple attachments.
     */
    private Set<Id> getRecordsWithAttachments(Set<Id> candidateRecordIds) {
        Set<Id> recordsWithAttachments = new Set<Id>();

        if (candidateRecordIds.isEmpty()) {
            return recordsWithAttachments;
        }

        try {
            // Use aggregate query to get distinct LinkedEntityIds efficiently
            // This avoids the issue of LIMIT cutting off records with multiple attachments
            List<AggregateResult> results = [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :candidateRecordIds
                WITH USER_MODE
                GROUP BY LinkedEntityId
            ];

            for (AggregateResult ar : results) {
                recordsWithAttachments.add((Id) ar.get('LinkedEntityId'));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MissingAttachmentPlugin attachment query error: ' + e.getMessage());
        }

        return recordsWithAttachments;
    }

    /**
     * @description Creates follow-up tasks for records missing attachments.
     * Each affected record gets a task to add required documentation.
     *
     * @param recordIds List of record IDs missing attachments
     * @param config Configuration including taskSubject
     * @return PatternPluginResult with success/failure counts and audit logs
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        PatternPluginResult result = new PatternPluginResult();

        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        String ruleName = config != null ? (String) config.get('ruleDeveloperName') : 'Missing_Attachment';
        String taskSubject = config != null && config.get('taskSubject') != null
            ? (String) config.get('taskSubject')
            : 'Add required documentation';

        // Check Task object CRUD access
        if (!Schema.SObjectType.Task.isCreateable()) {
            for (Id recordId : recordIds) {
                result.addFailureLog(recordId, 'Task_Creation', 'Insufficient access to create Tasks', ruleName);
            }
            return result;
        }

        // Objects that cannot be linked via Task.WhatId
        Set<String> unsupportedWhatIdObjects = new Set<String>{'User', 'Group', 'RecordType', 'Profile', 'PermissionSet'};
        Set<String> whoIdObjects = new Set<String>{'Contact', 'Lead'};

        // Build tasks for each record missing attachments
        List<Task> tasksToInsert = new List<Task>();
        Map<Integer, Id> indexToSourceRecordId = new Map<Integer, Id>();
        Integer taskIndex = 0;

        for (Id recordId : recordIds) {
            String sObjectName = recordId.getSobjectType().getDescribe().getName();

            // Validate object can be linked to Task
            if (unsupportedWhatIdObjects.contains(sObjectName)) {
                result.addFailureLog(recordId, 'Task_Creation',
                    'Object type ' + sObjectName + ' cannot be linked to Tasks', ruleName);
                continue;
            }

            Task t = new Task(
                Subject = taskSubject,
                ActivityDate = Date.today().addDays(7),
                Priority = 'Normal',
                Status = 'Not Started',
                Description = 'This record is missing required file attachments. ' +
                             'Please upload the necessary documentation.'
            );

            // Set WhatId or WhoId based on object type
            if (whoIdObjects.contains(sObjectName)) {
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

        // Apply FLS stripping before insert
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
