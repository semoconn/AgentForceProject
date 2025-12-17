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
                   Is_Premium__c, Threshold_Default__c
            FROM Behavior_Pattern_Rule__mdt
        ];
    }

    public void execute(Database.BatchableContext bc, List<Behavior_Pattern_Rule__mdt> rules) {
        for (Behavior_Pattern_Rule__mdt rule : rules) {
            executeRule(rule);
        }
    }

    private void executeRule(Behavior_Pattern_Rule__mdt rule) {
        // 1. License Gate
        if (rule.Is_Premium__c && !LicenseService.isPremium()) {
            return;
        }

        // 2. Dismissal Check
        if (dismissedPainPointKeys.contains(rule.DeveloperName)) {
            return;
        }

        // 3. Dynamic Detection with Admin Configuration Injection
        String effectiveCondition = getEffectiveQuery(rule);
        String queryString = 'SELECT Id FROM ' + String.escapeSingleQuotes(rule.Object_API_Name__c) +
                             ' WHERE ' + effectiveCondition +
                             ' LIMIT 2000';

        // Store the executed query for test verification
        lastExecutedQuery = queryString;

        List<SObject> detectedRecords = new List<SObject>();

        try {
            // NOTE: We rely on the Admin's rule definition being correct.
            // Using Database.query without SECURITY_ENFORCED allows the engine to see
            // records the current user might not, which is intended for system monitoring.
            detectedRecords = Database.query(queryString);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Rule Execution Failed [' + rule.DeveloperName + ']: ' + e.getMessage());
            return;
        }

        // 4. Result Generation
        if (!detectedRecords.isEmpty()) {
            Integer count = detectedRecords.size();
            List<Id> exampleIds = new List<Id>();
            for (Integer i = 0; i < Math.min(count, 5); i++) {
                exampleIds.add(detectedRecords[i].Id);
            }

            upsertPainPoint(
                rule.DeveloperName,
                rule.MasterLabel,
                'Automated detection for ' + rule.Object_API_Name__c,
                rule.Object_API_Name__c,
                count,
                JSON.serialize(exampleIds)
            );
        }
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

        // Debug logging for troubleshooting query construction
        System.debug(LoggingLevel.DEBUG, 'getEffectiveQuery - Rule: ' + ruleName + ', Final condition: ' + queryCondition);

        return queryCondition;
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
                List<BehaviorIQ_Configuration__c> configs = [
                    SELECT Id, Stale_Case_Threshold__c, Stale_Opportunity_Threshold__c
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

    private void upsertPainPoint(String key, String label, String description, String obj, Integer count, String examples) {
        Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
            Unique_Key__c = key,
            Name = label,
            Description__c = description,
            Object_API_Name__c = obj,
            Occurrences__c = count,
            Impact_Score__c = count * 10,
            Example_Records__c = examples,
            Last_Detected__c = System.now(),
            Status__c = 'New'
        );

        try {
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPSERTABLE, new List<Identified_Pain_Point__c>{pp});
            List<SObject> upsertedRecords = securityDecision.getRecords();
            Database.UpsertResult[] results = Database.upsert(upsertedRecords, Identified_Pain_Point__c.Unique_Key__c, false);

            // Create snapshot if running in batch context and upsert succeeded
            if (createSnapshots && !results.isEmpty() && results[0].isSuccess()) {
                Id painPointId = results[0].getId();
                createSnapshot(key, count, count * 10, painPointId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Upsert failed: ' + e.getMessage());
        }
    }

    /**
     * @description Creates a snapshot record to track historical trend data.
     * Only called when running in batch context to avoid overhead during real-time operations.
     */
    private void createSnapshot(String metricName, Integer recordCount, Integer impactScore, Id painPointId) {
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
        if (!Schema.sObjectType.System_Health_Log__c.isCreateable()) return;

        String jobId = (bc != null) ? bc.getJobId() : null;
        Integer errors = 0;
        if(jobId != null) {
            try { errors = [SELECT NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId].NumberOfErrors; } catch(Exception e){}
        }

        System_Health_Log__c log = new System_Health_Log__c(
            Job_Name__c = JOB_NAME, Job_ID__c = jobId,
            Status__c = (errors > 0) ? 'Failed' : 'Success', Error_Count__c = errors
        );
        try { insert Security.stripInaccessible(AccessType.CREATABLE, new List<System_Health_Log__c>{log}).getRecords(); } catch(Exception e) {}
    }

    // --- REMEDIATION PREVIEW API ---

    /**
     * @description Returns matching records for a given pattern rule, allowing users to preview
     * which records will be affected before executing a fix. Respects admin thresholds.
     * @param ruleDeveloperName The DeveloperName of the Behavior_Pattern_Rule__mdt record
     * @param limitCount Maximum number of records to return (default 50, max 200)
     * @return List<SObject> The matching records with key fields for display
     */
    @AuraEnabled
    public static List<SObject> getPatternMatches(String ruleDeveloperName, Integer limitCount) {
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
        List<Behavior_Pattern_Rule__mdt> rules = [
            SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                   Is_Premium__c, Threshold_Default__c
            FROM Behavior_Pattern_Rule__mdt
            WHERE DeveloperName = :ruleDeveloperName
            LIMIT 1
        ];

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
        String objectApiName = rule.Object_API_Name__c;
        String displayFields = getDisplayFieldsForObject(objectApiName);

        String queryString = 'SELECT ' + displayFields +
                             ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                             ' WHERE ' + effectiveCondition +
                             ' ORDER BY CreatedDate DESC' +
                             ' LIMIT ' + limitCount;

        // Store for test verification and debug logging
        lastExecutedQuery = queryString;
        System.debug(LoggingLevel.INFO, '=== PatternAnalysisService.getPatternMatches ===');
        System.debug(LoggingLevel.INFO, 'Rule: ' + ruleDeveloperName);
        System.debug(LoggingLevel.INFO, 'Object: ' + objectApiName);
        System.debug(LoggingLevel.INFO, 'Original condition: ' + rule.Query_Condition__c);
        System.debug(LoggingLevel.INFO, 'Effective condition: ' + effectiveCondition);
        System.debug(LoggingLevel.INFO, 'Full query: ' + queryString);

        try {
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
        } else {
            // Default fields for any other object
            fields = new List<String>{ 'Id', 'Name', 'CreatedDate', 'OwnerId' };
        }

        // Remove duplicates and return
        Set<String> uniqueFields = new Set<String>(fields);
        return String.join(new List<String>(uniqueFields), ', ');
    }
}