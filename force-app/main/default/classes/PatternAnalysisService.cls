/**
 * @description Metadata-Driven Batch Engine for BehaviorIQ (Phase 3).
 * Iterates through Behavior_Pattern_Rule__mdt records and executes dynamic SOQL to detect pain points.
 */
public with sharing class PatternAnalysisService implements Database.Batchable<SObject>, Schedulable {

    private static final String JOB_NAME = 'Pattern Analysis Service';
    public static final Integer DEFAULT_RETENTION_DAYS = 90;
    
    private Set<String> dismissedPainPointKeys;

    public PatternAnalysisService() {
        dismissedPainPointKeys = new Set<String>();
        loadDismissals();
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PatternAnalysisService(), 50);
    }

    public Iterable<SObject> start(Database.BatchableContext bc) {
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

        // 3. Dynamic Detection
        String queryString = 'SELECT Id FROM ' + String.escapeSingleQuotes(rule.Object_API_Name__c) + 
                             ' WHERE ' + rule.Query_Condition__c + 
                             ' LIMIT 2000';

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

    public void finish(Database.BatchableContext bc) {
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
            Database.upsert(securityDecision.getRecords(), Identified_Pain_Point__c.Unique_Key__c, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Upsert failed: ' + e.getMessage());
        }
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
}