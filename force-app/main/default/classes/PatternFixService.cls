/**
 * @description Service class for BehaviorIQ Premium "Auto-Fix" features.
 * Metadata-Driven: Uses Behavior_Pattern_Rule__mdt to determine remediation logic.
 * Enterprise-Ready: Includes smart assignment rules, safety net fallbacks, and comprehensive audit logging.
 */
public with sharing class PatternFixService {

    // Constants for action types (matching Remediation_Log__c picklist)
    private static final String ACTION_TASK_CREATION = 'Task_Creation';
    private static final String ACTION_OWNER_ASSIGNMENT = 'Owner_Assignment';
    private static final String ACTION_FIELD_UPDATE = 'Field_Update';

    // Status constants
    private static final String STATUS_SUCCESS = 'Success';
    private static final String STATUS_FAILED = 'Failed';

    // Fallback owner ID - can be configured via custom metadata or hierarchy custom setting
    @TestVisible
    private static Id fallbackOwnerId;

    // Mock rule for testing - allows tests to inject metadata without real CMDT records
    @TestVisible
    private static Behavior_Pattern_Rule__mdt mockRule;

    // Instance variable to track rule name for logging
    private String currentRuleName;

    // Collect logs during execution for bulk insert
    private List<Remediation_Log__c> pendingLogs = new List<Remediation_Log__c>();

    public void executeFix(List<Id> recordIds, String ruleDeveloperName) {
        if (recordIds == null || recordIds.isEmpty()) return;

        this.currentRuleName = ruleDeveloperName;

        // 1. Fetch Rule (use mock if available in test context)
        Behavior_Pattern_Rule__mdt rule;
        if (Test.isRunningTest() && mockRule != null) {
            rule = mockRule;
        } else {
            rule = [
                SELECT Fix_Type__c, Fix_Config__c, Is_Premium__c
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :ruleDeveloperName
                LIMIT 1
            ];
        }

        // 2. Validate License
        if (rule.Is_Premium__c && !LicenseService.isPremium()) {
            throw new AuraHandledException('This is a Premium feature. Please upgrade to execute this fix.');
        }

        // 3. Parse Config
        Map<String, Object> config = new Map<String, Object>();
        if (String.isNotBlank(rule.Fix_Config__c)) {
            config = (Map<String, Object>)JSON.deserializeUntyped(rule.Fix_Config__c);
        }

        // 4. Route Execution
        switch on rule.Fix_Type__c {
            when 'Task_Creation' {
                createTasks(recordIds, config);
            }
            when 'Owner_Assignment' {
                assignOwner(recordIds, config);
            }
            when 'Field_Update' {
                updateFields(recordIds, config);
            }
            when else {
                throw new AuraHandledException('Unknown Fix Type: ' + rule.Fix_Type__c);
            }
        }

        // 5. Persist all audit logs
        insertPendingLogs();
    }

    // --- FIX IMPLEMENTATIONS ---

    private void createTasks(List<Id> recordIds, Map<String, Object> config) {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Tasks.');
        }

        List<Task> tasks = new List<Task>();
        String subject = (String)config.get('subject');

        for (Id recId : recordIds) {
            tasks.add(new Task(
                Subject = (subject != null ? subject : 'Action Required'),
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(1),
                WhatId = recId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        try {
            List<SObject> insertedTasks = Security.stripInaccessible(AccessType.CREATABLE, tasks).getRecords();
            insert insertedTasks;

            // Log successful task creations
            for (Integer i = 0; i < recordIds.size(); i++) {
                addLog(
                    recordIds[i],
                    ACTION_TASK_CREATION,
                    null,
                    'Task Created: ' + (subject != null ? subject : 'Action Required'),
                    STATUS_SUCCESS,
                    null
                );
            }
        } catch (Exception e) {
            // Log failures
            for (Id recId : recordIds) {
                addLog(recId, ACTION_TASK_CREATION, null, null, STATUS_FAILED, e.getMessage());
            }
            throw new AuraHandledException('Failed to create tasks: ' + e.getMessage());
        }
    }

    private void updateFields(List<Id> recordIds, Map<String, Object> config) {
        String field = (String)config.get('field');
        String val = (String)config.get('value');
        if (String.isBlank(field)) return;

        Schema.SObjectType sType = recordIds[0].getSObjectType();

        // Query original values for audit logging
        String soql = 'SELECT Id, ' + String.escapeSingleQuotes(field) + ' FROM ' + sType.getDescribe().getName() + ' WHERE Id IN :recordIds';
        Map<Id, SObject> originalRecords = new Map<Id, SObject>(Database.query(soql));

        List<SObject> records = new List<SObject>();
        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            obj.put(field, val);
            records.add(obj);
        }

        try {
            update Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();

            // Log successful field updates
            for (Id recId : recordIds) {
                String originalValue = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get(field))
                    : null;
                addLog(recId, ACTION_FIELD_UPDATE, originalValue, val, STATUS_SUCCESS, null);
            }
        } catch (Exception e) {
            // Log failures
            for (Id recId : recordIds) {
                String originalValue = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get(field))
                    : null;
                addLog(recId, ACTION_FIELD_UPDATE, originalValue, val, STATUS_FAILED, e.getMessage());
            }
            throw new AuraHandledException('Failed to update fields: ' + e.getMessage());
        }
    }

    /**
     * @description Smart Owner Assignment with Assignment Rules and Safety Net.
     * Uses Database.DMLOptions to trigger standard assignment rules.
     * Falls back to current user if assignment results in a system/queue owner.
     */
    private void assignOwner(List<Id> recordIds, Map<String, Object> config) {
        Schema.SObjectType sType = recordIds[0].getSObjectType();
        String objectName = sType.getDescribe().getName();

        // Query original owner values for audit logging
        String soql = 'SELECT Id, OwnerId FROM ' + objectName + ' WHERE Id IN :recordIds';
        Map<Id, SObject> originalRecords = new Map<Id, SObject>(Database.query(soql));

        // Check if we should use assignment rules (from config or default to true for Lead/Case)
        Boolean useAssignmentRules = true;
        if (config.containsKey('useAssignmentRules')) {
            useAssignmentRules = (Boolean)config.get('useAssignmentRules');
        }

        // Get fallback owner from config or use current user
        Id configuredFallback = null;
        if (config.containsKey('fallbackOwnerId')) {
            String fallbackStr = (String)config.get('fallbackOwnerId');
            if (String.isNotBlank(fallbackStr)) {
                try {
                    configuredFallback = Id.valueOf(fallbackStr);
                } catch (Exception e) {
                    // Invalid ID, ignore and use default fallback
                }
            }
        }
        Id effectiveFallback = configuredFallback != null ? configuredFallback
                            : (fallbackOwnerId != null ? fallbackOwnerId : UserInfo.getUserId());

        List<SObject> records = new List<SObject>();
        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            records.add(obj);
        }

        try {
            // Configure DML options for assignment rules
            Database.DMLOptions dmlOpts = new Database.DMLOptions();

            // Only apply assignment rules for supported objects (Lead, Case)
            if (useAssignmentRules && (objectName == 'Lead' || objectName == 'Case')) {
                dmlOpts.assignmentRuleHeader.useDefaultRule = true;
            }

            // Set the DML options and update
            for (SObject rec : records) {
                rec.setOptions(dmlOpts);
            }

            Database.SaveResult[] results = Database.update(records, false);

            // Process results and apply safety net
            List<SObject> safetyNetUpdates = new List<SObject>();
            Set<Id> needsSafetyNet = new Set<Id>();

            // Re-query to get the assigned owners
            Map<Id, SObject> updatedRecords = new Map<Id, SObject>(Database.query(soql));

            for (Integer i = 0; i < results.size(); i++) {
                Id recId = recordIds[i];
                String originalOwnerId = String.valueOf(originalRecords.get(recId).get('OwnerId'));

                if (results[i].isSuccess()) {
                    Id newOwnerId = (Id)updatedRecords.get(recId).get('OwnerId');

                    // Safety Net: Check if owner needs fallback
                    // Apply safety net if owner is still a queue or unchanged from original "problem" state
                    if (needsSafetyNetFallback(newOwnerId, originalOwnerId, config)) {
                        needsSafetyNet.add(recId);
                        SObject safetyObj = sType.newSObject(recId);
                        safetyObj.put('OwnerId', effectiveFallback);
                        safetyNetUpdates.add(safetyObj);
                    } else {
                        // Log successful assignment
                        addLog(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, String.valueOf(newOwnerId), STATUS_SUCCESS, null);
                    }
                } else {
                    // Log failure
                    String errorMsg = '';
                    for (Database.Error err : results[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    addLog(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED, errorMsg);
                }
            }

            // Apply safety net updates if needed
            if (!safetyNetUpdates.isEmpty()) {
                Database.SaveResult[] safetyResults = Database.update(safetyNetUpdates, false);

                for (Integer i = 0; i < safetyResults.size(); i++) {
                    Id recId = safetyNetUpdates[i].Id;
                    String originalOwnerId = String.valueOf(originalRecords.get(recId).get('OwnerId'));

                    if (safetyResults[i].isSuccess()) {
                        addLog(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, String.valueOf(effectiveFallback), STATUS_SUCCESS,
                               'Safety net applied - assigned to fallback owner');
                    } else {
                        String errorMsg = '';
                        for (Database.Error err : safetyResults[i].getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        addLog(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED,
                               'Safety net failed: ' + errorMsg);
                    }
                }
            }

        } catch (Exception e) {
            // Log failures for all records
            for (Id recId : recordIds) {
                String originalOwnerId = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get('OwnerId'))
                    : null;
                addLog(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED, e.getMessage());
            }
            throw new AuraHandledException('Failed to assign owner: ' + e.getMessage());
        }
    }

    /**
     * @description Determines if a record needs safety net fallback.
     * Returns true if the new owner is a Queue or if assignment didn't change ownership.
     */
    private Boolean needsSafetyNetFallback(Id newOwnerId, String originalOwnerId, Map<String, Object> config) {
        if (newOwnerId == null) return true;

        // Check if owner is a Queue (Queue IDs start with '00G')
        String ownerIdStr = String.valueOf(newOwnerId);
        if (ownerIdStr.startsWith('00G')) {
            return true;
        }

        // Check config for additional safety net conditions
        if (config.containsKey('requireOwnerChange') && (Boolean)config.get('requireOwnerChange')) {
            // If we require owner change and it didn't change, apply safety net
            if (originalOwnerId != null && originalOwnerId == ownerIdStr) {
                return true;
            }
        }

        return false;
    }

    // --- AUDIT LOGGING ---

    /**
     * @description Creates a remediation log entry and adds it to pending logs.
     */
    private void addLog(Id affectedRecordId, String actionTaken, String originalValue,
                        String newValue, String status, String errorMessage) {
        // Check create permission
        if (!Schema.sObjectType.Remediation_Log__c.isCreateable()) {
            return; // Silently skip logging if no permission
        }

        Remediation_Log__c log = new Remediation_Log__c(
            Affected_Record_ID__c = String.valueOf(affectedRecordId),
            Action_Taken__c = actionTaken,
            Original_Value__c = truncateValue(originalValue, 255),
            New_Value__c = truncateValue(newValue, 255),
            Status__c = status,
            Executed_By__c = UserInfo.getUserId(),
            Rule_Developer_Name__c = this.currentRuleName
        );

        if (String.isNotBlank(errorMessage)) {
            log.Error_Message__c = errorMessage;
        }

        pendingLogs.add(log);
    }

    /**
     * @description Inserts all pending remediation logs.
     * Uses partial success to ensure main operation completes even if logging fails.
     */
    private void insertPendingLogs() {
        if (pendingLogs.isEmpty()) return;

        if (!Schema.sObjectType.Remediation_Log__c.isCreateable()) {
            return;
        }

        // Use allOrNone = false to not fail the main operation if logging fails
        Database.insert(pendingLogs, false);
        pendingLogs.clear();
    }

    /**
     * @description Helper to truncate string values to fit field length.
     */
    private String truncateValue(String value, Integer maxLength) {
        if (value == null) return null;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
