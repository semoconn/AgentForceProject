/**
 * @description Sample PatternPlugin implementation for detecting and remediating
 * expired Quote Requests. This demonstrates the plugin architecture for custom objects.
 *
 * Pattern Detection: Finds Quote Requests where:
 * - Status is 'Draft' or 'Pending Review'
 * - Expiration Date has passed
 *
 * Remediation: Updates Status to 'Expired' and creates follow-up task.
 *
 * Usage: Configure a Behavior_Pattern_Rule__mdt with:
 * - Logic_Type__c: 'Apex_Plugin'
 * - Apex_Handler_Class__c: 'ExpiredQuoteRequestPlugin'
 * - Object_API_Name__c: 'Quote_Request__c'
 * - Is_Premium__c: true (Premium feature)
 */
global class ExpiredQuoteRequestPlugin implements PatternPlugin {

    /**
     * @description Analyzes Quote Requests for expiration pattern.
     * Demonstrates both SOQL-based and custom logic capabilities.
     */
    global List<Id> analyze(PatternPluginContext context) {
        // Validate we're targeting the correct object
        if (context.objectApiName != 'Quote_Request__c') {
            System.debug(LoggingLevel.WARN, 'ExpiredQuoteRequestPlugin: Expected Quote_Request__c but got ' + context.objectApiName);
            return new List<Id>();
        }

        // Get threshold from config (default: expired = before today)
        Integer gracePeriodDays = 0;
        if (context.config != null && context.config.containsKey('gracePeriodDays')) {
            gracePeriodDays = (Integer) context.config.get('gracePeriodDays');
        }

        Date expirationThreshold = Date.today().addDays(-gracePeriodDays);

        // Query for expired quote requests (using USER_MODE for security)
        List<Quote_Request__c> expiredRequests;
        try {
            expiredRequests = [
                SELECT Id, Name, Status__c, Expiration_Date__c, Requested_Amount__c
                FROM Quote_Request__c
                WHERE Status__c IN ('Draft', 'Pending Review')
                AND Expiration_Date__c != null
                AND Expiration_Date__c < :expirationThreshold
                WITH USER_MODE
                LIMIT 2000
            ];
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'ExpiredQuoteRequestPlugin: Query failed - ' + e.getMessage());
            return new List<Id>();
        }

        // Extract IDs
        List<Id> expiredIds = new List<Id>();
        for (Quote_Request__c req : expiredRequests) {
            expiredIds.add(req.Id);
        }

        System.debug(LoggingLevel.INFO, 'ExpiredQuoteRequestPlugin: Found ' + expiredIds.size() + ' expired quote requests');
        return expiredIds;
    }

    /**
     * @description Remediates expired Quote Requests by updating status and creating tasks.
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        PatternPluginResult result = new PatternPluginResult();

        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        // Get configuration options
        Boolean createTask = true;
        String taskSubject = 'Expired Quote Request - Follow Up Required';
        if (config != null) {
            if (config.containsKey('createTask')) {
                createTask = (Boolean) config.get('createTask');
            }
            if (config.containsKey('taskSubject')) {
                taskSubject = (String) config.get('taskSubject');
            }
        }

        // Query current records for snapshot and update
        Map<Id, Quote_Request__c> recordMap = new Map<Id, Quote_Request__c>([
            SELECT Id, Name, Status__c, Expiration_Date__c, Requested_Amount__c, OwnerId
            FROM Quote_Request__c
            WHERE Id IN :recordIds
            WITH USER_MODE
        ]);

        // Prepare updates
        List<Quote_Request__c> updates = new List<Quote_Request__c>();
        List<Task> tasks = new List<Task>();

        for (Id recId : recordIds) {
            Quote_Request__c req = recordMap.get(recId);
            if (req == null) continue;

            // Store original value for audit
            String originalStatus = req.Status__c;

            // Update status
            updates.add(new Quote_Request__c(
                Id = recId,
                Status__c = 'Expired'
            ));

            // Create follow-up task if configured
            if (createTask && Schema.sObjectType.Task.isCreateable()) {
                tasks.add(new Task(
                    Subject = taskSubject,
                    Priority = 'High',
                    Status = 'Not Started',
                    ActivityDate = Date.today().addDays(1),
                    WhatId = recId,
                    OwnerId = req.OwnerId,
                    Description = 'Quote Request ' + req.Name + ' has expired. Original amount: $' +
                                  (req.Requested_Amount__c != null ? String.valueOf(req.Requested_Amount__c) : '0') +
                                  '. Please follow up with the customer.'
                ));
            }

            // Create snapshot for undo capability
            String snapshot = JSON.serialize(req);
            result.addSuccessLogWithSnapshot(
                recId,
                'Status_Update',
                originalStatus,
                'Expired',
                snapshot,
                'Expired_Quote_Requests'
            );
        }

        // Execute updates
        try {
            if (!updates.isEmpty()) {
                List<SObject> secureUpdates = Security.stripInaccessible(AccessType.UPDATABLE, updates).getRecords();
                update secureUpdates;
            }

            if (!tasks.isEmpty()) {
                List<SObject> secureTasks = Security.stripInaccessible(AccessType.CREATABLE, tasks).getRecords();
                insert secureTasks;
            }

        } catch (DmlException e) {
            // Log failures - reset success count and add failures
            result.successCount = 0;
            result.auditLogs.clear();

            for (Id recId : recordIds) {
                result.addFailureLog(recId, 'Status_Update', e.getMessage(), 'Expired_Quote_Requests');
            }
        }

        return result;
    }
}
