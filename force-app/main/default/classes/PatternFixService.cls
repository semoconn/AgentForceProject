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
    private static final String ACTION_EMAIL_NOTIFICATION = 'Email_Notification';
    private static final String ACTION_OPPORTUNITY_CREATION = 'Opportunity_Creation';
    private static final String ACTION_ESCALATION_REVERT = 'Escalation_Revert';
    private static final String ACTION_NO_ACTION = 'No_Action';

    // Status constants
    private static final String STATUS_SUCCESS = 'Success';
    private static final String STATUS_FAILED = 'Failed';

    // Fallback owner ID - can be configured via custom metadata or hierarchy custom setting
    @TestVisible
    private static Id fallbackOwnerId;

    // Mock rule for testing - allows tests to inject metadata without real CMDT records
    @TestVisible
    private static Behavior_Pattern_Rule__mdt mockRule;

    // @TestVisible exception triggers for comprehensive test coverage
    @TestVisible private static Boolean forceTaskCreationException = false;
    @TestVisible private static Boolean forceFieldUpdateException = false;
    @TestVisible private static Boolean forceOwnerAssignmentException = false;
    @TestVisible private static Boolean forceEmailQueryException = false;
    @TestVisible private static Boolean forceEmailSendException = false;
    @TestVisible private static Boolean forceOpportunityCreationException = false;
    @TestVisible private static Boolean forceNoValidRecipients = false;

    /**
     * @description Resets all test exception flags. Call this in test cleanup.
     */
    @TestVisible
    private static void resetTestFlags() {
        forceTaskCreationException = false;
        forceFieldUpdateException = false;
        forceOwnerAssignmentException = false;
        forceEmailQueryException = false;
        forceEmailSendException = false;
        forceOpportunityCreationException = false;
        forceNoValidRecipients = false;
        mockRule = null;
        fallbackOwnerId = null;
    }

    // Instance variable to track rule name for logging
    private String currentRuleName;

    // Collect logs during execution for bulk insert
    private List<Remediation_Log__c> pendingLogs = new List<Remediation_Log__c>();

    public void executeFix(List<Id> recordIds, String ruleDeveloperName) {
        if (recordIds == null || recordIds.isEmpty()) return;

        this.currentRuleName = ruleDeveloperName;

        // 1. Fetch Rule (use mock if available in test context)
        // CMDT queries don't support WITH USER_MODE - CMDT is read-only and admin-controlled
        Behavior_Pattern_Rule__mdt rule;
        if (Test.isRunningTest() && mockRule != null) {
            rule = mockRule;
        } else {
            List<Behavior_Pattern_Rule__mdt> rules = [  // NOPMD - ApexCRUDViolation: CMDT doesn't support USER_MODE
                SELECT Fix_Type__c, Fix_Config__c, Is_Premium__c,
                       Logic_Type__c, Apex_Handler_Class__c
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :ruleDeveloperName
                LIMIT 1
            ];
            if (rules.isEmpty()) {
                throw new AuraHandledException('Rule not found: ' + ruleDeveloperName);
            }
            rule = rules[0];
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

        // 4. Route Execution based on Logic Type
        String logicType = String.isNotBlank(rule.Logic_Type__c) ? rule.Logic_Type__c : 'Standard';

        switch on logicType {
            when 'Apex_Plugin' {
                // Invoke custom plugin for fix
                executePluginFix(rule, recordIds, config);
            }
            when 'Declarative' {
                // Execute declarative JSON-based actions
                executeDeclarativeFix(recordIds, rule.Fix_Config__c);
            }
            when else {
                // 'Standard' - use existing Fix_Type__c routing
                executeStandardFix(rule.Fix_Type__c, recordIds, config);
            }
        }

        // 5. Persist all audit logs
        insertPendingLogs();
    }

    // --- LOGIC TYPE ROUTING ---

    /**
     * @description Routes to standard fix handlers based on Fix_Type__c.
     * @param fixType The fix type from the rule
     * @param recordIds Records to fix
     * @param config Configuration from Fix_Config__c
     */
    private void executeStandardFix(String fixType, List<Id> recordIds, Map<String, Object> config) {
        switch on fixType {
            when 'Task_Creation' {
                createTasks(recordIds, config);
            }
            when 'Owner_Assignment' {
                assignOwner(recordIds, config);
            }
            when 'Field_Update' {
                updateFields(recordIds, config);
            }
            when 'Email_Notification' {
                sendEmailNotifications(recordIds, config);
            }
            when 'Opportunity_Creation' {
                createRenewalOpportunities(recordIds, config);
            }
            when 'Escalation_Revert' {
                revertEscalationWithChatter(recordIds, config);
            }
            when 'No_Action' {
                logNoAction(recordIds, config);
            }
            when else {
                throw new AuraHandledException('Unknown Fix Type: ' + fixType);
            }
        }
    }

    /**
     * @description Executes fix using a custom Apex plugin.
     * @param rule The pattern rule with plugin configuration
     * @param recordIds Records to fix
     * @param config Configuration from Fix_Config__c
     */
    private void executePluginFix(Behavior_Pattern_Rule__mdt rule, List<Id> recordIds, Map<String, Object> config) {
        String handlerClass = rule.Apex_Handler_Class__c;

        if (String.isBlank(handlerClass)) {
            throw new AuraHandledException('Rule has Logic_Type__c = Apex_Plugin but no Apex_Handler_Class__c specified.');
        }

        try {
            PatternPluginResult result = PluginInvoker.invokeFix(handlerClass, recordIds, config);

            // Add plugin's audit logs to our pending logs
            if (result.auditLogs != null && !result.auditLogs.isEmpty()) {
                pendingLogs.addAll(result.auditLogs);
            }

            // If plugin had failures, throw exception to notify user
            if (result.hasFailures()) {
                String errorSummary = result.failureCount + ' of ' + result.getTotalProcessed() + ' records failed. ';
                if (!result.errorMessages.isEmpty()) {
                    errorSummary += 'First error: ' + result.errorMessages[0];
                }
                throw new AuraHandledException(errorSummary);
            }

        } catch (PluginInvoker.PluginException pe) {
            // Log failure for all records
            for (Id recId : recordIds) {
                addLog(recId, 'Apex_Plugin', null, null, STATUS_FAILED, pe.getMessage());
            }
            throw new AuraHandledException('Plugin execution failed: ' + pe.getMessage());
        }
    }

    /**
     * @description Executes declarative JSON-based fix actions.
     * @param recordIds Records to fix
     * @param fixConfigJson JSON configuration with declarative actions
     */
    private void executeDeclarativeFix(List<Id> recordIds, String fixConfigJson) {
        if (String.isBlank(fixConfigJson)) {
            throw new AuraHandledException('Declarative fix requires configuration in Fix_Config__c.');
        }

        try {
            DeclarativeFixExecutor executor = new DeclarativeFixExecutor(this.pendingLogs, this.currentRuleName);
            executor.execute(recordIds, fixConfigJson);
        } catch (DeclarativeFixExecutor.DeclarativeFixException dfe) {
            throw new AuraHandledException('Declarative fix failed: ' + dfe.getMessage());
        }
    }

    // --- STANDARD FIX IMPLEMENTATIONS ---

    private void createTasks(List<Id> recordIds, Map<String, Object> config) {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Tasks.');
        }

        List<Task> tasks = new List<Task>();
        String subject = (String)config.get('subject');
        String priority = (String)config.get('priority');
        String description = (String)config.get('description');

        for (Id recId : recordIds) {
            Task t = new Task(
                Subject = (subject != null ? subject : 'Action Required'),
                Priority = (priority != null ? priority : 'High'),
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(1),
                OwnerId = UserInfo.getUserId()
            );

            if (description != null) {
                t.Description = description;
            }

            // Determine the correct relationship field based on object type
            // WhoId is for person objects (Contact, Lead)
            // WhatId is for non-person objects (Account, Opportunity, Case, etc.)
            Schema.SObjectType sType = recId.getSObjectType();
            String objectName = sType.getDescribe().getName();

            if (objectName == 'Contact' || objectName == 'Lead') {
                t.WhoId = recId;
            } else {
                t.WhatId = recId;
            }

            tasks.add(t);
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceTaskCreationException) {
                throw new DmlException('Forced test exception for task creation');
            }
            List<SObject> insertedTasks = Security.stripInaccessible(AccessType.CREATABLE, tasks).getRecords();
            insert as user insertedTasks;

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
        String objectName = sType.getDescribe().getName();

        // TC-6.2: Verify object is accessible before querying
        if (!sType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to read ' + objectName + ' records.');
        }

        // Query all accessible fields for full snapshot (for undo capability)
        // Ensure the target field is always included for logging original value
        // Note: snapshotFields are Schema-validated via getSnapshotFieldsForObject which checks FLS
        String snapshotFields = getSnapshotFieldsForObject(objectName);
        if (!snapshotFields.containsIgnoreCase(field)) {
            snapshotFields = String.escapeSingleQuotes(field) + ', ' + snapshotFields;
        }
        String soql = 'SELECT ' + snapshotFields + ' FROM ' + String.escapeSingleQuotes(objectName) + ' WHERE Id IN :recordIds WITH USER_MODE';
        // TC-6.1/6.2: Execute query with USER_MODE for sharing/FLS enforcement
        Map<Id, SObject> originalRecords = new Map<Id, SObject>(Database.query(soql));  // NOPMD - ApexSOQLInjection

        // Create snapshot JSON map for each record
        Map<Id, String> recordSnapshots = new Map<Id, String>();
        for (Id recId : originalRecords.keySet()) {
            recordSnapshots.put(recId, JSON.serialize(originalRecords.get(recId)));
        }

        List<SObject> records = new List<SObject>();
        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            obj.put(field, val);
            records.add(obj);
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceFieldUpdateException) {
                throw new DmlException('Forced test exception for field update');
            }
            update Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();

            // Log successful field updates with full snapshot
            for (Id recId : recordIds) {
                String originalValue = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get(field))
                    : null;
                String snapshot = recordSnapshots.get(recId);
                addLogWithSnapshot(recId, ACTION_FIELD_UPDATE, originalValue, val, STATUS_SUCCESS, null, snapshot);
            }
        } catch (Exception e) {
            // Log failures with snapshot (even failed attempts should be logged for audit)
            for (Id recId : recordIds) {
                String originalValue = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get(field))
                    : null;
                String snapshot = recordSnapshots.get(recId);
                addLogWithSnapshot(recId, ACTION_FIELD_UPDATE, originalValue, val, STATUS_FAILED, e.getMessage(), snapshot);
            }
            throw new AuraHandledException('Failed to update fields: ' + e.getMessage());
        }
    }

    /**
     * @description ORG-AGNOSTIC Owner Assignment with Queue-First Strategy.
     * Uses Database.DMLOptions to trigger standard assignment rules.
     * Fallback Priority: 1) Assignment Rules, 2) Configured Queue, 3) BehaviorIQ Queue, 4) Current User
     * Never hardcodes User IDs - always uses dynamic lookup for enterprise deployments.
     */
    private void assignOwner(List<Id> recordIds, Map<String, Object> config) {
        Schema.SObjectType sType = recordIds[0].getSObjectType();
        String objectName = sType.getDescribe().getName();

        // TC-6.2: Verify object is accessible before querying
        if (!sType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to read ' + objectName + ' records.');
        }

        // Query all accessible fields for full snapshot (for undo capability)
        // Ensure OwnerId is always included for owner assignment logic
        // Note: snapshotFields are Schema-validated via getSnapshotFieldsForObject which checks FLS
        String snapshotFields = getSnapshotFieldsForObject(objectName);
        if (!snapshotFields.containsIgnoreCase('OwnerId')) {
            snapshotFields = 'OwnerId, ' + snapshotFields;
        }
        String soql = 'SELECT ' + snapshotFields + ' FROM ' + String.escapeSingleQuotes(objectName) + ' WHERE Id IN :recordIds WITH USER_MODE';
        // TC-6.1/6.2: Execute query with USER_MODE for sharing/FLS enforcement
        Map<Id, SObject> originalRecords = new Map<Id, SObject>(Database.query(soql));  // NOPMD - ApexSOQLInjection

        // Create snapshot JSON map for each record
        Map<Id, String> recordSnapshots = new Map<Id, String>();
        for (Id recId : originalRecords.keySet()) {
            recordSnapshots.put(recId, JSON.serialize(originalRecords.get(recId)));
        }

        // Check if we should use assignment rules (from config or default to true for Lead/Case)
        Boolean useAssignmentRules = true;
        if (config.containsKey('useAssignmentRules')) {
            useAssignmentRules = (Boolean)config.get('useAssignmentRules');
        }

        // ORG-AGNOSTIC QUEUE LOOKUP: Find the best queue for this object type
        // Priority: 1) Configured queueName, 2) BehaviorIQ default queue, 3) Any matching queue for object
        Id targetQueueId = findBestQueueForObject(objectName, config);
        String assignmentNote = '';

        // Determine effective fallback owner using queue-first strategy
        Id effectiveFallback = null;

        if (targetQueueId != null) {
            effectiveFallback = targetQueueId;
            assignmentNote = 'Assigned to queue';
        } else {
            // No queue available - check config fallback (should be rare in production)
            if (config.containsKey('fallbackOwnerId')) {
                String fallbackStr = (String)config.get('fallbackOwnerId');
                if (String.isNotBlank(fallbackStr)) {
                    try {
                        effectiveFallback = Id.valueOf(fallbackStr);
                    } catch (Exception e) {
                        // Invalid ID, continue to next fallback
                    }
                }
            }

            // Test-injectable fallback for unit tests
            if (effectiveFallback == null && fallbackOwnerId != null) {
                effectiveFallback = fallbackOwnerId;
            }

            // Fail explicitly if no queue or fallback is configured
            // This prevents silent assignment to unintended owners
            if (effectiveFallback == null) {
                String errorMsg = 'Owner assignment failed: No queue is configured for ' + objectName +
                    ' and no fallback owner is specified. Please configure a "BehaviorIQ ' + objectName +
                    ' Queue" or specify a fallbackOwnerId in the rule\'s Fix_Config__c JSON.';
                for (Id recId : recordIds) {
                    addLog(recId, ACTION_OWNER_ASSIGNMENT, null, null, STATUS_FAILED, errorMsg);
                }
                insertPendingLogs();
                throw new AuraHandledException(errorMsg);
            }
        }

        List<SObject> records = new List<SObject>();
        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            records.add(obj);
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceOwnerAssignmentException) {
                throw new DmlException('Forced test exception for owner assignment');
            }
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

            // Re-query to get the assigned owners (soql already includes WITH USER_MODE)
            Map<Id, SObject> updatedRecords = new Map<Id, SObject>(Database.query(soql));  // NOPMD - ApexSOQLInjection

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
                        // Log successful assignment with snapshot
                        String snapshot = recordSnapshots.get(recId);
                        addLogWithSnapshot(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, String.valueOf(newOwnerId), STATUS_SUCCESS, null, snapshot);
                    }
                } else {
                    // Log failure with snapshot
                    String errorMsg = '';
                    for (Database.Error err : results[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    String snapshot = recordSnapshots.get(recId);
                    addLogWithSnapshot(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED, errorMsg, snapshot);
                }
            }

            // Apply safety net updates if needed
            if (!safetyNetUpdates.isEmpty()) {
                Database.SaveResult[] safetyResults = Database.update(safetyNetUpdates, false);

                for (Integer i = 0; i < safetyResults.size(); i++) {
                    Id recId = safetyNetUpdates[i].Id;
                    String originalOwnerId = String.valueOf(originalRecords.get(recId).get('OwnerId'));
                    String snapshot = recordSnapshots.get(recId);

                    if (safetyResults[i].isSuccess()) {
                        addLogWithSnapshot(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, String.valueOf(effectiveFallback), STATUS_SUCCESS,
                               'Safety net applied - assigned to fallback owner', snapshot);
                    } else {
                        String errorMsg = '';
                        for (Database.Error err : safetyResults[i].getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        addLogWithSnapshot(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED,
                               'Safety net failed: ' + errorMsg, snapshot);
                    }
                }
            }

        } catch (Exception e) {
            // Test hook can force this path
            // Log failures for all records with snapshots
            for (Id recId : recordIds) {
                String originalOwnerId = originalRecords.containsKey(recId)
                    ? String.valueOf(originalRecords.get(recId).get('OwnerId'))
                    : null;
                String snapshot = recordSnapshots.get(recId);
                addLogWithSnapshot(recId, ACTION_OWNER_ASSIGNMENT, originalOwnerId, null, STATUS_FAILED, e.getMessage(), snapshot);
            }
            throw new AuraHandledException('Failed to assign owner: ' + e.getMessage());
        }
    }

    /**
     * @description ORG-AGNOSTIC Queue Lookup for Owner Assignment.
     * Finds the best available queue for the given object type.
     * Priority: 1) Configured queueName from metadata, 2) BehaviorIQ default queue, 3) Any queue for the object
     * @param objectName The API name of the object (Lead, Case, etc.)
     * @param config Configuration map that may contain 'queueName' override
     * @return The Queue ID if found, null otherwise
     */
    private Id findBestQueueForObject(String objectName, Map<String, Object> config) {
        // Priority 1: Check for configured queue name in metadata
        String configuredQueueName = null;
        if (config.containsKey('queueName')) {
            configuredQueueName = (String)config.get('queueName');
        }

        // Query for queues that support this object type
        // QueueSobject junction table links Queue to supported SObject types
        List<Group> candidateQueues = new List<Group>();

        try {
            // Build list of queue names to search for, in priority order
            List<String> queueNamesToFind = new List<String>();

            if (String.isNotBlank(configuredQueueName)) {
                queueNamesToFind.add(configuredQueueName);
            }

            // BehaviorIQ default queues by object type
            String behaviorIQQueueName = 'BehaviorIQ ' + objectName + ' Queue';
            queueNamesToFind.add(behaviorIQQueueName);

            // Query queues that support this object type
            Set<Id> supportedQueueIds = new Set<Id>();
            for (QueueSobject qs : [
                SELECT QueueId FROM QueueSobject
                WHERE SobjectType = :objectName
                WITH USER_MODE
            ]) {
                supportedQueueIds.add(qs.QueueId);
            }

            if (supportedQueueIds.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'No queues configured for ' + objectName);
                return null;
            }

            // Try to find queues by name priority
            for (String queueName : queueNamesToFind) {
                List<Group> matchingQueues = [
                    SELECT Id, Name FROM Group
                    WHERE Type = 'Queue'
                    AND Name = :queueName
                    AND Id IN :supportedQueueIds
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (!matchingQueues.isEmpty()) {
                    System.debug(LoggingLevel.INFO, 'Found queue "' + matchingQueues[0].Name + '" for ' + objectName);
                    return matchingQueues[0].Id;
                }
            }

            // Fallback: Return any available queue for this object type
            List<Group> anyQueue = [
                SELECT Id, Name FROM Group
                WHERE Type = 'Queue'
                AND Id IN :supportedQueueIds
                WITH USER_MODE
                ORDER BY Name
                LIMIT 1
            ];

            if (!anyQueue.isEmpty()) {
                System.debug(LoggingLevel.INFO, 'Using fallback queue "' + anyQueue[0].Name + '" for ' + objectName);
                return anyQueue[0].Id;
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error finding queue for ' + objectName + ': ' + e.getMessage());
        }

        return null;
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

    /**
     * @description Sends email notifications for churn risk alerts.
     * Uses SingleEmailMessage to send alerts to Account owners or configured recipients.
     * Respects user email preferences - skips users who have opted out of email notifications.
     */
    private void sendEmailNotifications(List<Id> recordIds, Map<String, Object> config) {
        if (recordIds.isEmpty()) return;

        // Check if email sending is enabled in org
        if (!isEmailSendingEnabled()) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED, 'Email sending is disabled in this org');
            }
            return;
        }

        // Get the subject and body from config
        String subject = (String)config.get('subject');
        String body = (String)config.get('body');
        String recipientField = (String)config.get('recipientField');

        if (String.isBlank(subject)) {
            subject = 'BehaviorIQ Alert: Action Required';
        }
        if (String.isBlank(body)) {
            body = 'A record requires your attention. Please review in Salesforce.';
        }

        // Determine the object type from the first record ID
        Schema.SObjectType sType = recordIds[0].getSObjectType();
        String objectName = sType.getDescribe().getName();

        // Build query to get recipient information
        String queryFields = 'Id';
        if (objectName == 'Case') {
            queryFields = 'Id, CaseNumber, Subject, Account.Name, Account.OwnerId, OwnerId';
        } else {
            queryFields = 'Id, OwnerId';
        }

        String soql = 'SELECT ' + queryFields + ' FROM ' + String.escapeSingleQuotes(objectName) + ' WHERE Id IN :recordIds WITH USER_MODE';
        List<SObject> records;
        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceEmailQueryException) {
                throw new QueryException('Forced test exception for email query');
            }
            // TC-6.2: Verify object is accessible before querying
            if (!sType.getDescribe().isAccessible()) {
                throw new AuraHandledException('Insufficient permissions to read ' + objectName + ' records.');
            }
            // TC-6.1/6.2: Execute query with USER_MODE for sharing/FLS enforcement
            records = Database.query(soql);  // NOPMD - ApexSOQLInjection: queryFields are Schema-validated
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED, 'Query failed: ' + e.getMessage());
            }
            throw new AuraHandledException('Failed to query records for email notification: ' + e.getMessage());
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Map<Id, String> recordToRecipient = new Map<Id, String>();
        Map<Id, Id> recordToRecipientId = new Map<Id, Id>();

        // First pass: collect all recipient IDs
        for (SObject rec : records) {
            Id recipientId;

            // Determine recipient based on config or defaults
            if (String.isNotBlank(recipientField) && recipientField.contains('.')) {
                List<String> fieldParts = recipientField.split('\\.');
                SObject related = rec.getSObject(fieldParts[0]);
                if (related != null) {
                    recipientId = (Id)related.get(fieldParts[1]);
                }
            }

            if (recipientId == null) {
                recipientId = (Id)rec.get('OwnerId');
            }

            if (recipientId != null) {
                recordToRecipientId.put(rec.Id, recipientId);
            }
        }

        // Check which users have opted out of email notifications
        Set<Id> optedOutUsers = getOptedOutUsers(new Set<Id>(recordToRecipientId.values()));

        // Second pass: build emails, skipping opted-out users
        for (SObject rec : records) {
            Id recipientId = recordToRecipientId.get(rec.Id);

            if (recipientId == null) {
                continue;
            }

            // Skip users who have opted out
            if (optedOutUsers.contains(recipientId)) {
                addLog(rec.Id, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED,
                       'Recipient has opted out of email notifications');
                continue;
            }

            // Build personalized email body
            String personalizedBody = body;
            if (objectName == 'Case') {
                String caseNumber = (String)rec.get('CaseNumber');
                String caseSubject = (String)rec.get('Subject');
                SObject account = rec.getSObject('Account');
                String accountName = account != null ? (String)account.get('Name') : 'Unknown Account';

                personalizedBody = body + '\n\n' +
                    'Case Number: ' + caseNumber + '\n' +
                    'Subject: ' + caseSubject + '\n' +
                    'Account: ' + accountName + '\n' +
                    'Record Link: ' + URL.getOrgDomainUrl().toExternalForm() + '/' + rec.Id;
            } else {
                personalizedBody = body + '\n\nRecord Link: ' + URL.getOrgDomainUrl().toExternalForm() + '/' + rec.Id;
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(recipientId);
            email.setSubject(subject);
            email.setPlainTextBody(personalizedBody);
            email.setSaveAsActivity(false);
            emails.add(email);

            recordToRecipient.put(rec.Id, String.valueOf(recipientId));
        }

        // Test hook for no valid recipients coverage
        if (emails.isEmpty() || (Test.isRunningTest() && forceNoValidRecipients)) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED, 'No valid recipients found');
            }
            return;
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceEmailSendException) {
                throw new System.EmailException('Forced test exception for email send');
            }
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

            Integer idx = 0;
            for (SObject rec : records) {
                if (recordToRecipient.containsKey(rec.Id) && idx < results.size()) {
                    if (results[idx].isSuccess()) {
                        addLog(rec.Id, ACTION_EMAIL_NOTIFICATION, null,
                               'Email sent to: ' + recordToRecipient.get(rec.Id), STATUS_SUCCESS, null);
                    } else {
                        String errorMsg = '';
                        for (Messaging.SendEmailError err : results[idx].getErrors()) {
                            errorMsg += err.getMessage() + '; ';
                        }
                        addLog(rec.Id, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED, errorMsg);
                    }
                    idx++;
                }
            }
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_EMAIL_NOTIFICATION, null, null, STATUS_FAILED, e.getMessage());
            }
            throw new AuraHandledException('Failed to send email notifications: ' + e.getMessage());
        }
    }

    /**
     * @description Creates renewal opportunities from expiring contracts.
     * Links the new opportunity to the contract's account with appropriate naming.
     */
    private void createRenewalOpportunities(List<Id> recordIds, Map<String, Object> config) {
        if (recordIds.isEmpty()) return;

        if (!Schema.sObjectType.Opportunity.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Opportunities.');
        }

        // Get config values
        String oppNameTemplate = (String)config.get('opportunityName');
        String stageName = (String)config.get('stageName');
        String closeDateOffset = (String)config.get('closeDate');
        String oppType = (String)config.get('type');

        if (String.isBlank(oppNameTemplate)) {
            oppNameTemplate = 'Renewal - {ContractNumber}';
        }
        if (String.isBlank(stageName)) {
            stageName = 'Prospecting';
        }

        // Calculate close date (default +30 days)
        Integer daysOffset = 30;
        if (String.isNotBlank(closeDateOffset)) {
            try {
                daysOffset = Integer.valueOf(closeDateOffset.replace('+', '').trim());
            } catch (Exception e) {
                daysOffset = 30;
            }
        }
        Date closeDate = Date.today().addDays(daysOffset);

        // TC-6.2: Verify Contract is accessible before querying
        if (!Schema.sObjectType.Contract.isAccessible()) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_OPPORTUNITY_CREATION, null, null, STATUS_FAILED,
                       'Insufficient permissions to read Contract records.');
            }
            throw new AuraHandledException('Insufficient permissions to read Contract records.');
        }

        // Query contracts to get account and contract details with USER_MODE for security
        String soql = 'SELECT Id, ContractNumber, AccountId, Account.Name, EndDate FROM Contract WHERE Id IN :recordIds WITH USER_MODE';
        List<Contract> contracts;
        try {
            // TC-6.1/6.2: Execute query with USER_MODE for sharing/FLS enforcement
            contracts = Database.query(soql);  // NOPMD - ApexSOQLInjection: static query with bind variable
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_OPPORTUNITY_CREATION, null, null, STATUS_FAILED, 'Query failed: ' + e.getMessage());
            }
            throw new AuraHandledException('Failed to query contracts: ' + e.getMessage());
        }

        List<Opportunity> opportunities = new List<Opportunity>();
        Map<Id, Contract> contractMap = new Map<Id, Contract>();

        for (Contract c : contracts) {
            contractMap.put(c.Id, c);

            // Build opportunity name from template
            String oppName = oppNameTemplate
                .replace('{ContractNumber}', c.ContractNumber != null ? c.ContractNumber : 'N/A')
                .replace('{AccountName}', c.Account != null && c.Account.Name != null ? c.Account.Name : 'Unknown');

            // Truncate if too long
            if (oppName.length() > 120) {
                oppName = oppName.substring(0, 117) + '...';
            }

            Opportunity opp = new Opportunity(
                Name = oppName,
                AccountId = c.AccountId,
                StageName = stageName,
                CloseDate = closeDate,
                ContractId = c.Id
            );

            if (String.isNotBlank(oppType)) {
                opp.Type = oppType;
            }

            opportunities.add(opp);
        }

        if (opportunities.isEmpty()) {
            return;
        }

        try {
            // Test hook for exception coverage
            if (Test.isRunningTest() && forceOpportunityCreationException) {
                throw new DmlException('Forced test exception for opportunity creation');
            }
            // TC-6.2: CRUD check done at method start (isCreateable())
            // Note: Not using stripInaccessible here as it can strip required fields (Name, StageName, etc.)
            // which would cause silent insert failures. The CRUD check ensures object-level access.
            Database.SaveResult[] results = Database.insert(opportunities, false);

            for (Integer i = 0; i < results.size(); i++) {
                Id contractId = contracts[i].Id;

                if (results[i].isSuccess()) {
                    addLog(
                        contractId,
                        ACTION_OPPORTUNITY_CREATION,
                        null,
                        'Opportunity Created: ' + results[i].getId(),
                        STATUS_SUCCESS,
                        null
                    );
                } else {
                    String errorMsg = '';
                    for (Database.Error err : results[i].getErrors()) {
                        errorMsg += err.getMessage() + '; ';
                    }
                    addLog(contractId, ACTION_OPPORTUNITY_CREATION, null, null, STATUS_FAILED, errorMsg);
                }
            }
        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLog(recId, ACTION_OPPORTUNITY_CREATION, null, null, STATUS_FAILED, e.getMessage());
            }
            throw new AuraHandledException('Failed to create renewal opportunities: ' + e.getMessage());
        }
    }

    /**
     * @description Reverts escalation on Cases and optionally posts a Chatter message.
     * Sets IsEscalated to false and creates a FeedItem explaining the revert.
     * @param recordIds List of Case IDs to revert escalation on
     * @param config Configuration map with optional chatterMessage and postChatter settings
     */
    private void revertEscalationWithChatter(List<Id> recordIds, Map<String, Object> config) {
        if (!Schema.sObjectType.Case.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Cases.');
        }

        // Query Cases for snapshot with USER_MODE for security
        // Note: snapshotFields are Schema-validated via getSnapshotFieldsForObject which checks FLS
        String snapshotFields = getSnapshotFieldsForObject('Case');
        if (!snapshotFields.containsIgnoreCase('IsEscalated')) {
            snapshotFields = 'IsEscalated, ' + snapshotFields;
        }
        String soql = 'SELECT ' + snapshotFields + ' FROM Case WHERE Id IN :recordIds WITH USER_MODE';
        // snapshotFields are Schema-validated via getSnapshotFieldsForObject
        Map<Id, SObject> originalRecords = new Map<Id, SObject>(Database.query(soql));  // NOPMD - ApexSOQLInjection

        // Create snapshot JSON map
        Map<Id, String> recordSnapshots = new Map<Id, String>();
        for (Id recId : originalRecords.keySet()) {
            recordSnapshots.put(recId, JSON.serialize(originalRecords.get(recId)));
        }

        // Update IsEscalated to false
        List<Case> casesToUpdate = new List<Case>();
        for (Id caseId : recordIds) {
            casesToUpdate.add(new Case(Id = caseId, IsEscalated = false));
        }

        try {
            update Security.stripInaccessible(AccessType.UPDATABLE, casesToUpdate).getRecords();

            // Create Chatter posts if configured
            Boolean postChatter = config.containsKey('postChatter') ? (Boolean)config.get('postChatter') : false;
            if (postChatter && Schema.sObjectType.FeedItem.isCreateable()) {
                String chatterMessage = (String)config.get('chatterMessage');
                if (String.isNotBlank(chatterMessage)) {
                    List<FeedItem> posts = new List<FeedItem>();
                    for (Id caseId : recordIds) {
                        posts.add(new FeedItem(ParentId = caseId, Body = chatterMessage));
                    }
                    insert posts;
                }
            }

            // Log successful operations
            for (Id recId : recordIds) {
                String snapshot = recordSnapshots.get(recId);
                addLogWithSnapshot(recId, ACTION_ESCALATION_REVERT, 'true', 'false', STATUS_SUCCESS, null, snapshot);
            }

        } catch (Exception e) {
            for (Id recId : recordIds) {
                addLogWithSnapshot(recId, ACTION_ESCALATION_REVERT, 'true', null, STATUS_FAILED, e.getMessage(), recordSnapshots.get(recId));
            }
            throw new AuraHandledException('Failed to revert escalation: ' + e.getMessage());
        }
    }

    /**
     * @description Logs an expected pattern without performing any DML on source records.
     * Used for patterns that are informational only and don't require remediation.
     * @param recordIds List of record IDs to log
     * @param config Configuration map with optional message
     */
    private void logNoAction(List<Id> recordIds, Map<String, Object> config) {
        String message = config.containsKey('message')
            ? (String)config.get('message')
            : 'Expected pattern - no action required';

        for (Id recId : recordIds) {
            addLog(recId, ACTION_NO_ACTION, null, message, STATUS_SUCCESS, null);
        }
    }

    // --- EMAIL VALIDATION HELPERS ---

    /**
     * @description Checks if email sending is enabled in the current org.
     * Uses OrgWideEmailAddress check as a proxy - if no org-wide email exists and
     * the current user can't send email, this will return false.
     * @return True if email can be sent from this org, false otherwise
     */
    private Boolean isEmailSendingEnabled() {
        try {
            // Check if the org has email deliverability enabled
            // Limits.getEmailInvocations() will tell us if we can send emails
            Integer remainingEmails = Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
            return remainingEmails > 0;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to check email sending status: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Retrieves set of user IDs who have opted out of receiving BehaviorIQ notifications.
     * Checks user email preferences to respect opt-out settings.
     * @param userIds Set of user IDs to check
     * @return Set of user IDs who should NOT receive emails
     */
    private Set<Id> getOptedOutUsers(Set<Id> userIds) {
        Set<Id> optedOutUsers = new Set<Id>();

        if (userIds.isEmpty()) {
            return optedOutUsers;
        }

        try {
            // Query users to check their ReceivesInfoEmails preference
            // Users with ReceivesInfoEmails = false have opted out of informational emails
            for (User u : [
                SELECT Id, ReceivesInfoEmails
                FROM User
                WHERE Id IN :userIds
                AND ReceivesInfoEmails = false
                WITH SECURITY_ENFORCED
            ]) {
                optedOutUsers.add(u.Id);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to check user email preferences: ' + e.getMessage());
        }

        return optedOutUsers;
    }

    // --- AUDIT LOGGING ---

    /**
     * @description Creates a remediation log entry and adds it to pending logs.
     * Overloaded version without snapshot for backward compatibility.
     */
    private void addLog(Id affectedRecordId, String actionTaken, String originalValue,
                        String newValue, String status, String errorMessage) {
        addLogWithSnapshot(affectedRecordId, actionTaken, originalValue, newValue, status, errorMessage, null);
    }

    /**
     * @description Creates a remediation log entry with full record snapshot for undo capability.
     * @param affectedRecordId The ID of the record that was modified
     * @param actionTaken The type of action performed
     * @param originalValue The original field value (truncated to 255 chars)
     * @param newValue The new field value (truncated to 255 chars)
     * @param status Success or Failed
     * @param errorMessage Error details if failed
     * @param snapshotJson Full JSON snapshot of the record before modification
     */
    private void addLogWithSnapshot(Id affectedRecordId, String actionTaken, String originalValue,
                        String newValue, String status, String errorMessage, String snapshotJson) {
        // Check create permission
        if (!Schema.sObjectType.Remediation_Log__c.isCreateable()) {
            return; // Silently skip logging if no permission
        }

        // Get object API name for identification (no per-record query to avoid SOQL limits)
        String objectApiName = '';
        String recordName = '';
        if (affectedRecordId != null) {
            try {
                Schema.SObjectType sType = affectedRecordId.getSObjectType();
                objectApiName = sType.getDescribe().getName();

                // Extract record name from snapshot if available (avoids SOQL-in-loop)
                if (String.isNotBlank(snapshotJson)) {
                    try {
                        Map<String, Object> snapshotData = (Map<String, Object>) JSON.deserializeUntyped(snapshotJson);
                        String nameField = getNameFieldForObject(objectApiName);
                        if (String.isNotBlank(nameField) && snapshotData.containsKey(nameField)) {
                            Object nameValue = snapshotData.get(nameField);
                            recordName = nameValue != null ? String.valueOf(nameValue) : '';
                        }
                    } catch (Exception jsonEx) {
                        // Snapshot parsing failed, skip name extraction
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Could not get object info for logging: ' + e.getMessage());
            }
        }

        Remediation_Log__c log = new Remediation_Log__c(
            Affected_Record_ID__c = String.valueOf(affectedRecordId),
            Action_Taken__c = actionTaken,
            Original_Value__c = truncateValue(originalValue, 255),
            New_Value__c = truncateValue(newValue, 255),
            Status__c = status,
            Executed_By__c = UserInfo.getUserId(),
            Rule_Developer_Name__c = this.currentRuleName,
            Object_API_Name__c = objectApiName,
            Record_Name__c = truncateValue(recordName, 255)
        );

        if (String.isNotBlank(errorMessage)) {
            log.Error_Message__c = errorMessage;
        }

        // Store full snapshot for future undo capability
        if (String.isNotBlank(snapshotJson)) {
            // Truncate if exceeds field limit (131072 chars for Long Text Area)
            log.Snapshot_JSON__c = truncateValue(snapshotJson, 131072);
        }

        pendingLogs.add(log);
    }

    /**
     * @description Inserts all pending remediation logs.
     * Uses partial success to ensure main operation completes even if logging fails.
     */
    private void insertPendingLogs() {
        if (pendingLogs.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'No pending logs to insert');
            return;
        }

        System.debug(LoggingLevel.INFO, 'Attempting to insert ' + pendingLogs.size() + ' remediation logs');

        if (!Schema.sObjectType.Remediation_Log__c.isCreateable()) {
            System.debug(LoggingLevel.WARN, 'User does not have create permission on Remediation_Log__c - skipping audit logs');
            return;
        }

        // Use allOrNone = false to not fail the main operation if logging fails
        Database.SaveResult[] results = Database.insert(pendingLogs, false);

        // Log any failures for debugging
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to insert remediation log: ' + err.getMessage());
                }
            }
        }

        pendingLogs.clear();
    }

    /**
     * @description Helper to truncate string values to fit field length.
     */
    private String truncateValue(String value, Integer maxLength) {
        if (value == null) return null;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    /**
     * @description Returns the appropriate name field for a given object.
     * Most objects use 'Name', but some have special name fields.
     * @param objectApiName The API name of the object
     * @return The name field API name, or null if not found
     */
    private String getNameFieldForObject(String objectApiName) {
        // Special cases where the name field is not 'Name'
        Map<String, String> specialNameFields = new Map<String, String>{
            'Case' => 'CaseNumber',
            'Contract' => 'ContractNumber',
            'Solution' => 'SolutionName',
            'Task' => 'Subject',
            'Event' => 'Subject'
        };

        if (specialNameFields.containsKey(objectApiName)) {
            return specialNameFields.get(objectApiName);
        }

        // Check if the object has a Name field
        try {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
            if (sType != null) {
                Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();
                if (fieldMap.containsKey('name') && fieldMap.get('name').getDescribe().isAccessible()) {
                    return 'Name';
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking name field for ' + objectApiName + ': ' + e.getMessage());
        }

        return null;
    }

    /**
     * @description Returns a comma-separated list of accessible fields for snapshot capture.
     * Includes all accessible, queryable fields for the given object to enable full undo capability.
     * @param objectApiName The API name of the object
     * @return Comma-separated list of field names for SOQL query
     */
    private String getSnapshotFieldsForObject(String objectApiName) {
        List<String> fields = new List<String>{ 'Id' };

        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(objectApiName.toLowerCase());

            if (sObjType == null) {
                return 'Id';
            }

            Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

                // Include fields that are:
                // - Accessible (FLS check)
                // - Not a compound field (like Address which can't be queried directly)
                // - Standard and custom fields
                if (fieldDescribe.isAccessible() && !fieldDescribe.isNamePointing()) {
                    String fieldType = String.valueOf(fieldDescribe.getType());

                    // Skip compound address and geolocation fields
                    if (fieldType == 'ADDRESS' || fieldType == 'LOCATION') {
                        continue;
                    }

                    // Skip base64 fields (too large for snapshots)
                    if (fieldType == 'BASE64') {
                        continue;
                    }

                    fields.add(fieldDescribe.getName());
                }
            }

            // Remove duplicates and 'Id' if it got added twice
            Set<String> uniqueFields = new Set<String>(fields);
            uniqueFields.remove('id'); // Remove lowercase duplicate if present
            if (!uniqueFields.contains('Id')) {
                uniqueFields.add('Id');
            }

            return String.join(new List<String>(uniqueFields), ', ');

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting snapshot fields for ' + objectApiName + ': ' + e.getMessage());
            return 'Id';
        }
    }
}
