/**
 * @description Executes declarative JSON-based fix actions for BehaviorIQ.
 * Parses action configurations from Fix_Config__c and applies them to records
 * without requiring custom Apex code.
 *
 * Supported Action Types:
 * - UpdateField: Set a field to a static value
 * - UpdateFieldFromRecord: Copy value from another field
 * - CreateTask: Create a follow-up task
 * - SendEmail: Send email notification (uses existing EmailService pattern)
 * - PostChatter: Post to record's Chatter feed
 *
 * JSON Schema:
 * {
 *   "actions": [
 *     { "type": "UpdateField", "field": "Status__c", "value": "Canceled" },
 *     { "type": "CreateTask", "subject": "Follow up", "priority": "High" }
 *   ]
 * }
 *
 * Security: All operations execute with USER_MODE and stripInaccessible.
 */
public with sharing class DeclarativeFixExecutor {

    // Reference to parent's pending logs for bulk insert
    private List<Remediation_Log__c> pendingLogs;
    private String ruleDeveloperName;

    // Constants for action types
    private static final String ACTION_UPDATE_FIELD = 'UpdateField';
    private static final String ACTION_UPDATE_FIELD_FROM_RECORD = 'UpdateFieldFromRecord';
    private static final String ACTION_CREATE_TASK = 'CreateTask';
    private static final String ACTION_SEND_EMAIL = 'SendEmail';
    private static final String ACTION_POST_CHATTER = 'PostChatter';

    // Test visibility flags
    @TestVisible private static Boolean forceParseException = false;
    @TestVisible private static Boolean forceUpdateException = false;
    @TestVisible private static Boolean forceTaskException = false;
    @TestVisible private static Boolean forceRollbackException = false;

    /**
     * @description Custom exception for declarative fix errors.
     */
    public class DeclarativeFixException extends Exception {}

    /**
     * @description Constructor accepting the parent's log collection.
     * @param pendingLogs Reference to parent's pending logs list for bulk insert
     * @param ruleDeveloperName The rule name for logging
     */
    public DeclarativeFixExecutor(List<Remediation_Log__c> pendingLogs, String ruleDeveloperName) {
        this.pendingLogs = pendingLogs;
        this.ruleDeveloperName = ruleDeveloperName;
    }

    /**
     * @description Executes declarative actions from JSON configuration.
     * Uses Database.setSavepoint() and rollback() to ensure all actions are atomic.
     * If any action fails, all previous actions in the transaction are rolled back.
     * @param recordIds Records to process
     * @param fixConfigJson JSON configuration with actions array
     */
    public void execute(List<Id> recordIds, String fixConfigJson) {
        if (recordIds == null || recordIds.isEmpty()) {
            return;
        }

        // Parse JSON configuration
        Map<String, Object> config;
        try {
            if (Test.isRunningTest() && forceParseException) {
                throw new JSONException('Forced parse exception for testing');
            }
            config = (Map<String, Object>) JSON.deserializeUntyped(fixConfigJson);
        } catch (Exception e) {
            throw new DeclarativeFixException('Invalid Fix_Config__c JSON: ' + e.getMessage());
        }

        // Get actions array
        List<Object> actions = (List<Object>) config.get('actions');
        if (actions == null || actions.isEmpty()) {
            throw new DeclarativeFixException('Fix_Config__c must contain an "actions" array.');
        }

        // Create savepoint for atomic transaction - all actions succeed or all are rolled back
        Savepoint sp = Database.setSavepoint();

        // Track action index for per-action telemetry (declared outside try for catch block access)
        Integer actionIndex = 0;

        try {
            // Test hook for forcing rollback scenario
            if (Test.isRunningTest() && forceRollbackException) {
                throw new DeclarativeFixException('Forced rollback exception for testing');
            }

            // Execute each action within the transaction boundary
            for (Object actionObj : actions) {
                Map<String, Object> action = (Map<String, Object>) actionObj;
                String actionType = (String) action.get('type');

                if (String.isBlank(actionType)) {
                    throw new DeclarativeFixException('Each action must have a "type" property.');
                }

                // Capture pre-action state for telemetry
                Integer logCountBefore = pendingLogs.size();
                Integer cpuBefore = Limits.getCpuTime();

                executeAction(actionType, action, recordIds);

                // Calculate CPU time consumed by this action
                Integer cpuConsumed = Limits.getCpuTime() - cpuBefore;

                // Tag recently added logs with per-action metrics
                Integer logsToTag = pendingLogs.size() - logCountBefore;
                for (Integer i = pendingLogs.size() - 1; i >= pendingLogs.size() - logsToTag && i >= 0; i--) {
                    pendingLogs[i].Action_Index__c = actionIndex;
                    pendingLogs[i].Execution_Time_Ms__c = cpuConsumed;
                }

                actionIndex++;
            }
        } catch (DeclarativeFixException e) {
            // Rollback all DML operations on declarative fix errors
            Database.rollback(sp);
            // Clear success logs since those operations were rolled back, but keep failure logs
            clearSuccessLogs();
            throw new DeclarativeFixException('Declarative fix rolled back at action index ' + actionIndex + '. Error: ' + e.getMessage());
        } catch (Exception e) {
            // Rollback all DML operations on any unexpected error
            Database.rollback(sp);
            // Clear success logs since those operations were rolled back, but keep failure logs
            clearSuccessLogs();
            throw new DeclarativeFixException('Declarative fix rolled back at action index ' + actionIndex + '. Error: ' + e.getMessage());
        }
    }

    /**
     * @description Routes to appropriate action handler.
     */
    private void executeAction(String actionType, Map<String, Object> action, List<Id> recordIds) {
        switch on actionType {
            when 'UpdateField' {
                executeUpdateField(action, recordIds);
            }
            when 'UpdateFieldFromRecord' {
                executeUpdateFieldFromRecord(action, recordIds);
            }
            when 'CreateTask' {
                executeCreateTask(action, recordIds);
            }
            when 'PostChatter' {
                executePostChatter(action, recordIds);
            }
            when else {
                throw new DeclarativeFixException('Unknown action type: ' + actionType + '. Supported types: UpdateField, UpdateFieldFromRecord, CreateTask, PostChatter');
            }
        }
    }

    /**
     * @description Updates a field to a static value.
     * Config: { "type": "UpdateField", "field": "Status__c", "value": "Canceled" }
     */
    private void executeUpdateField(Map<String, Object> action, List<Id> recordIds) {
        String fieldName = (String) action.get('field');
        Object newValue = action.get('value');

        if (String.isBlank(fieldName)) {
            throw new DeclarativeFixException('UpdateField action requires "field" property.');
        }

        // Determine object type from first record ID
        String objectApiName = recordIds[0].getSObjectType().getDescribe().getName();

        // Validate field accessibility
        if (!isFieldUpdateable(objectApiName, fieldName)) {
            throw new DeclarativeFixException('Field ' + fieldName + ' is not updateable on ' + objectApiName);
        }

        // Query current values for audit logging with USER_MODE for security
        // Note: objectApiName and fieldName are validated via isFieldUpdateable() which uses Schema describe
        String queryString = 'SELECT Id, ' + String.escapeSingleQuotes(fieldName) +
                             ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                             ' WHERE Id IN :recordIds WITH USER_MODE';
        List<SObject> records = Database.query(queryString);

        // Build updates
        List<SObject> updates = new List<SObject>();
        Map<Id, Object> originalValues = new Map<Id, Object>();

        for (SObject rec : records) {
            originalValues.put(rec.Id, rec.get(fieldName));
            SObject updateRec = rec.getSObjectType().newSObject(rec.Id);
            updateRec.put(fieldName, newValue);
            updates.add(updateRec);
        }

        // Execute update with security
        try {
            if (Test.isRunningTest() && forceUpdateException) {
                throw new DmlException('Forced update exception for testing');
            }
            List<SObject> secureUpdates = Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords();
            update as user secureUpdates;

            // Log success
            for (SObject rec : records) {
                addLog(rec.Id, ACTION_UPDATE_FIELD,
                       String.valueOf(originalValues.get(rec.Id)),
                       String.valueOf(newValue),
                       'Success', null);
            }
        } catch (Exception e) {
            // Log failure
            for (Id recId : recordIds) {
                addLog(recId, ACTION_UPDATE_FIELD, null, null, 'Failed', e.getMessage());
            }
            throw new DeclarativeFixException('Failed to update field: ' + e.getMessage());
        }
    }

    /**
     * @description Updates a field by copying value from another field.
     * Config: { "type": "UpdateFieldFromRecord", "targetField": "Status__c", "sourceField": "Previous_Status__c" }
     */
    private void executeUpdateFieldFromRecord(Map<String, Object> action, List<Id> recordIds) {
        String targetField = (String) action.get('targetField');
        String sourceField = (String) action.get('sourceField');

        if (String.isBlank(targetField) || String.isBlank(sourceField)) {
            throw new DeclarativeFixException('UpdateFieldFromRecord action requires "targetField" and "sourceField" properties.');
        }

        String objectApiName = recordIds[0].getSObjectType().getDescribe().getName();

        // Validate field accessibility
        if (!isFieldReadable(objectApiName, sourceField)) {
            throw new DeclarativeFixException('Source field ' + sourceField + ' is not readable on ' + objectApiName);
        }
        if (!isFieldUpdateable(objectApiName, targetField)) {
            throw new DeclarativeFixException('Target field ' + targetField + ' is not updateable on ' + objectApiName);
        }

        // Query current values with USER_MODE for security
        // Note: objectApiName, targetField, sourceField are validated via isFieldReadable/isFieldUpdateable
        String queryString = 'SELECT Id, ' + String.escapeSingleQuotes(targetField) + ', ' +
                             String.escapeSingleQuotes(sourceField) +
                             ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                             ' WHERE Id IN :recordIds WITH USER_MODE';
        List<SObject> records = Database.query(queryString);

        // Build updates
        List<SObject> updates = new List<SObject>();
        Map<Id, Object> originalValues = new Map<Id, Object>();
        Map<Id, Object> newValues = new Map<Id, Object>();

        for (SObject rec : records) {
            originalValues.put(rec.Id, rec.get(targetField));
            Object sourceValue = rec.get(sourceField);
            newValues.put(rec.Id, sourceValue);

            SObject updateRec = rec.getSObjectType().newSObject(rec.Id);
            updateRec.put(targetField, sourceValue);
            updates.add(updateRec);
        }

        try {
            List<SObject> secureUpdates = Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords();
            update as user secureUpdates;

            for (SObject rec : records) {
                addLog(rec.Id, ACTION_UPDATE_FIELD_FROM_RECORD,
                       String.valueOf(originalValues.get(rec.Id)),
                       String.valueOf(newValues.get(rec.Id)),
                       'Success', null);
            }
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_UPDATE_FIELD_FROM_RECORD, null, null, 'Failed', e.getMessage());
            }
            throw new DeclarativeFixException('Failed to copy field value: ' + e.getMessage());
        }
    }

    /**
     * @description Creates follow-up tasks for records.
     * Config: { "type": "CreateTask", "subject": "Follow up", "priority": "High", "dueInDays": 1 }
     */
    private void executeCreateTask(Map<String, Object> action, List<Id> recordIds) {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new DeclarativeFixException('Insufficient permissions to create Tasks.');
        }

        String subject = (String) action.get('subject');
        String priority = (String) action.get('priority');
        Integer dueInDays = action.get('dueInDays') != null ? ((Integer) action.get('dueInDays')) : 1;

        if (String.isBlank(subject)) {
            subject = 'Action Required';
        }
        if (String.isBlank(priority)) {
            priority = 'Normal';
        }

        List<Task> tasks = new List<Task>();
        for (Id recId : recordIds) {
            tasks.add(new Task(
                Subject = subject,
                Priority = priority,
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(dueInDays),
                WhatId = recId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        try {
            if (Test.isRunningTest() && forceTaskException) {
                throw new DmlException('Forced task exception for testing');
            }
            List<SObject> secureTasks = Security.stripInaccessible(AccessType.CREATABLE, tasks).getRecords();
            insert as user secureTasks;

            for (Id recId : recordIds) {
                addLog(recId, ACTION_CREATE_TASK, null, 'Task: ' + subject, 'Success', null);
            }
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_CREATE_TASK, null, null, 'Failed', e.getMessage());
            }
            throw new DeclarativeFixException('Failed to create tasks: ' + e.getMessage());
        }
    }

    /**
     * @description Posts to record's Chatter feed.
     * Config: { "type": "PostChatter", "message": "This record requires attention." }
     */
    private void executePostChatter(Map<String, Object> action, List<Id> recordIds) {
        if (!Schema.sObjectType.FeedItem.isCreateable()) {
            throw new DeclarativeFixException('Insufficient permissions to post Chatter.');
        }

        String message = (String) action.get('message');
        if (String.isBlank(message)) {
            message = 'This record has been flagged by BehaviorIQ and requires attention.';
        }

        List<FeedItem> posts = new List<FeedItem>();
        for (Id recId : recordIds) {
            posts.add(new FeedItem(
                ParentId = recId,
                Body = message
            ));
        }

        try {
            List<SObject> securePosts = Security.stripInaccessible(AccessType.CREATABLE, posts).getRecords();
            insert as user securePosts;

            for (Id recId : recordIds) {
                addLog(recId, ACTION_POST_CHATTER, null, 'Posted: ' + message.abbreviate(100), 'Success', null);
            }
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_POST_CHATTER, null, null, 'Failed', e.getMessage());
            }
            throw new DeclarativeFixException('Failed to post Chatter: ' + e.getMessage());
        }
    }

    // --- HELPER METHODS ---

    /**
     * @description Checks if a field is updateable on the given object.
     */
    private Boolean isFieldUpdateable(String objectApiName, String fieldName) {
        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjType == null) return false;

            Schema.SObjectField field = sObjType.getDescribe().fields.getMap().get(fieldName);
            if (field == null) return false;

            return field.getDescribe().isUpdateable();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Checks if a field is readable on the given object.
     */
    private Boolean isFieldReadable(String objectApiName, String fieldName) {
        try {
            Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjType == null) return false;

            Schema.SObjectField field = sObjType.getDescribe().fields.getMap().get(fieldName);
            if (field == null) return false;

            return field.getDescribe().isAccessible();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Creates a remediation log entry.
     */
    private void addLog(Id recordId, String actionTaken, String originalValue,
                        String newValue, String status, String errorMessage) {
        pendingLogs.add(new Remediation_Log__c(
            Affected_Record_ID__c = String.valueOf(recordId),
            Action_Taken__c = actionTaken,
            Original_Value__c = truncate(originalValue, 255),
            New_Value__c = truncate(newValue, 255),
            Status__c = status,
            Error_Message__c = truncate(errorMessage, 255),
            Rule_Developer_Name__c = this.ruleDeveloperName,
            Executed_By__c = UserInfo.getUserId()
            // Note: CreatedDate is auto-populated by Salesforce
        ));
    }

    /**
     * @description Safely truncates a string.
     */
    private String truncate(String value, Integer maxLength) {
        if (value == null) return null;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    /**
     * @description Clears success logs while preserving failure logs.
     * Used during rollback to remove records of operations that were reverted,
     * while keeping failure logs that document what went wrong.
     */
    private void clearSuccessLogs() {
        List<Remediation_Log__c> failureLogs = new List<Remediation_Log__c>();
        for (Remediation_Log__c log : pendingLogs) {
            if (log.Status__c == 'Failed') {
                failureLogs.add(log);
            }
        }
        pendingLogs.clear();
        pendingLogs.addAll(failureLogs);
    }

    /**
     * @description Resets test flags.
     */
    @TestVisible
    private static void resetTestFlags() {
        forceParseException = false;
        forceUpdateException = false;
        forceTaskException = false;
        forceRollbackException = false;
    }
}
