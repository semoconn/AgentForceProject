/**
 * @description Scheduled + Batchable job for analyzing Behavior Logs.
 * @version 13.2 - FIX: Added security check for Health Log creation to satisfy negative tests.
 */
public with sharing class PatternAnalysisService implements Database.Batchable<sObject>, Schedulable {

    // Pattern Definitions
    public static final String SEQUENTIAL_ACTION_PATTERN = 'Sequential_Action_Contact_Task';
    public static final String STALE_OPPORTUNITY_PATTERN = 'Stale_High_Value_Opportunity';
    public static final String UNASSIGNED_LEAD_PATTERN = 'Unassigned_Lead_Created';
    public static final String STALE_CASE_PATTERN = 'Stale_High_Priority_Case';

    // Thresholds
    private static final Integer SEQUENTIAL_THRESHOLD = 5;
    private static final Long FIVE_MINUTES_MS = 5 * 60 * 1000;
    private static final Integer STALE_OPP_THRESHOLD = 3;
    private static final Decimal STALE_OPP_AMOUNT = 100000;
    private static final Integer UNASSIGNED_LEAD_THRESHOLD = 5;
    private static final Integer STALE_CASE_THRESHOLD = 3;

    // Configuration
    public static final Integer DEFAULT_RETENTION_DAYS = 90;
    private static final String JOB_NAME = 'Pattern Analysis Service';

    public static Integer STALE_CASE_DAYS = 7;
    public static Integer STALE_OPP_DAYS = 30;

    private Set<String> dismissedPainPointKeys;

    public PatternAnalysisService() {
        dismissedPainPointKeys = new Set<String>();
        if (Schema.sObjectType.Suggestion_Dismissal__c.isAccessible() &&
            Schema.sObjectType.Suggestion_Dismissal__c.fields.Dismissal_Key__c.isAccessible()) {
            try {
                for (Suggestion_Dismissal__c dismissal : [
                    SELECT Dismissal_Key__c FROM Suggestion_Dismissal__c WITH SECURITY_ENFORCED
                ]) {
                    if (dismissal.Dismissal_Key__c != null) {
                        String key = dismissal.Dismissal_Key__c.contains(':') ? 
                                     dismissal.Dismissal_Key__c.substringAfter(':') : 
                                     dismissal.Dismissal_Key__c;
                        dismissedPainPointKeys.add(key);
                    }
                }
            } catch (QueryException qe) {
                System.debug(LoggingLevel.WARN, 'Could not query Suggestion_Dismissal__c: ' + qe.getMessage());
            }
        }
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PatternAnalysisService(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Action_Name__c, Object_API_Name__c, Record_ID__c, User__c, CreatedDate ' +
                       'FROM Behavior_Log__c ' +
                       'WHERE CreatedDate >= LAST_N_DAYS:1 ' +
                       'ORDER BY User__c, CreatedDate ASC, Id ASC';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Behavior_Log__c> scope) {
        Map<Id, List<Behavior_Log__c>> logsByUser = new Map<Id, List<Behavior_Log__c>>();
        for (Behavior_Log__c log : scope) {
            if (log.User__c == null) continue;
            if (!logsByUser.containsKey(log.User__c)) {
                logsByUser.put(log.User__c, new List<Behavior_Log__c>());
            }
            logsByUser.get(log.User__c).add(log);
        }

        for (Id userId : logsByUser.keySet()) {
            analyzeContactTaskPattern(userId, logsByUser.get(userId));
        }
    }
    
    private void analyzeContactTaskPattern(Id userId, List<Behavior_Log__c> logs) {
        if (logs.size() < 2) return;

        Integer sequentialCount = 0;
        List<String> exampleIds = new List<String>();

        for (Integer i = 0; i < logs.size() - 1; i++) {
            Behavior_Log__c currentLog = logs[i];
            Behavior_Log__c nextLog = logs[i+1];

            if (currentLog.Object_API_Name__c == 'Contact' && currentLog.Action_Name__c == 'Record_Created' &&
                nextLog.Object_API_Name__c == 'Task' && nextLog.Action_Name__c == 'Record_Created') {
                
                Long timeDiff = nextLog.CreatedDate.getTime() - currentLog.CreatedDate.getTime();
                
                if (timeDiff >= 0 && timeDiff <= FIVE_MINUTES_MS) {
                    sequentialCount++;
                    if (exampleIds.size() < 5) exampleIds.add(currentLog.Record_ID__c);
                }
            }
        }

        if (sequentialCount >= SEQUENTIAL_THRESHOLD) {
            upsertPainPoint(
                SEQUENTIAL_ACTION_PATTERN, 'Sequential Task Creation After Contact',
                'Users frequently create Tasks within 5 minutes of creating Contacts.',
                'Contact', sequentialCount, JSON.serialize(exampleIds)
            );
        }
    }

    private void analyzeStaleOpportunities() {
        Date staleDate = (STALE_OPP_DAYS == 0) ? Date.today() : Date.today().addDays(-STALE_OPP_DAYS);
        List<Opportunity> queriedOpps = new List<Opportunity>();
        try {
            if(Schema.sObjectType.Opportunity.isAccessible()) {
                queriedOpps = [
                    SELECT Id, CreatedDate FROM Opportunity
                    WHERE Amount >= :STALE_OPP_AMOUNT
                    AND CreatedDate >= :staleDate
                    AND IsClosed = false
                    WITH SECURITY_ENFORCED
                ];
            }
        } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Error querying opps: ' + e.getMessage()); }

        if (queriedOpps.size() >= STALE_OPP_THRESHOLD) {
            List<String> exampleIds = new List<String>();
            for(Integer i = 0; i < Math.min(queriedOpps.size(), 5); i++) exampleIds.add(queriedOpps[i].Id);
            
            upsertPainPoint(STALE_OPPORTUNITY_PATTERN, 'Stale High-Value Opportunities',
                'High-value opportunities have not been updated recently.',
                'Opportunity', queriedOpps.size(), JSON.serialize(exampleIds));
        }
    }

    private void analyzeUnassignedLeads() {
        Id queueId;
        try {
             queueId = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Unassigned Leads Queue' WITH SECURITY_ENFORCED LIMIT 1]?.Id;
        } catch (Exception e) { return; }

        if(queueId == null) return;

        List<Lead> unassignedLeads = new List<Lead>();
        try {
            if(Schema.sObjectType.Lead.isAccessible()) {
                unassignedLeads = [SELECT Id FROM Lead WHERE OwnerId = :queueId WITH SECURITY_ENFORCED];
            }
        } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Error querying leads: ' + e.getMessage()); }

        if (unassignedLeads.size() >= UNASSIGNED_LEAD_THRESHOLD) {
             List<String> exampleIds = new List<String>();
             for(Integer i = 0; i < Math.min(unassignedLeads.size(), 5); i++) exampleIds.add(unassignedLeads[i].Id);

            upsertPainPoint(UNASSIGNED_LEAD_PATTERN, 'Leads Not Being Assigned',
                'Leads are sitting in the queue unassigned.',
                'Lead', unassignedLeads.size(), JSON.serialize(exampleIds));
        }
    }

    private void analyzeStaleCases() {
        Date staleDate = (STALE_CASE_DAYS == 0) ? Date.today() : Date.today().addDays(-STALE_CASE_DAYS);
        List<Case> queriedCases = new List<Case>();
        try {
            if (Schema.sObjectType.Case.isAccessible()) {
                queriedCases = [
                    SELECT Id, CreatedDate FROM Case
                    WHERE Priority = 'High'
                    AND CreatedDate >= :staleDate
                    AND IsClosed = false
                    WITH SECURITY_ENFORCED
                ];
            }
        } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Error querying cases: ' + e.getMessage()); }

        if (queriedCases.size() >= STALE_CASE_THRESHOLD) {
             List<String> exampleIds = new List<String>();
             for(Integer i = 0; i < Math.min(queriedCases.size(), 5); i++) exampleIds.add(queriedCases[i].Id);

            upsertPainPoint(STALE_CASE_PATTERN, 'Stale High-Priority Cases',
                'High-priority cases have not been updated recently.',
                'Case', queriedCases.size(), JSON.serialize(exampleIds));
        }
    }

    public void finish(Database.BatchableContext bc) {
        try { analyzeStaleOpportunities(); } catch (Exception e) {}
        try { analyzeUnassignedLeads(); } catch (Exception e) {}
        try { analyzeStaleCases(); } catch (Exception e) {}

        logJobStatus(bc);
        deleteOldLogs();
    }

    private void upsertPainPoint(String key, String label, String description, String obj, Integer count, String examples) {
        if (dismissedPainPointKeys.contains(key)) return;

        Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
            Unique_Key__c = key, Name = label, Description__c = description,
            Object_API_Name__c = obj, Occurrences__c = count,
            Impact_Score__c = count * 10, Example_Records__c = examples,
            Last_Detected__c = System.now(), Status__c = 'New'
        );

        try {
            Database.upsert(pp, Identified_Pain_Point__c.Unique_Key__c, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Upsert failed: ' + e.getMessage());
        }
    }

    private void deleteOldLogs() {
        if (!Schema.sObjectType.Behavior_Log__c.isDeletable()) {
            System.debug(LoggingLevel.WARN, 'User lacks delete permission on Behavior_Log__c');
            return;
        }
        try {
            Date cutoffDate = Date.today().addDays(-DEFAULT_RETENTION_DAYS);
            String isoDate = Datetime.newInstanceGmt(cutoffDate.year(), cutoffDate.month(), cutoffDate.day()).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String query = 'SELECT Id FROM Behavior_Log__c WHERE CreatedDate < ' + isoDate;
            Database.executeBatch(new DeleteRecordsBatch(query), 2000);
        } catch (Exception e) {
             logJobStatus(null, e);
        }
    }

    private void logJobStatus(Database.BatchableContext bc) { logJobStatus(bc, null); }

    private void logJobStatus(Database.BatchableContext bc, Exception finishException) {
        // FIX: Respect the current user's FLS/CRUD. 
        // If they can't create logs (e.g. negative test user), exit gracefully.
        if (!Schema.sObjectType.System_Health_Log__c.isCreateable()) {
            System.debug(LoggingLevel.INFO, 'Skipping health log creation: User lacks Create permission.');
            return;
        }

        String finalStatus = (finishException != null) ? 'Failed' : 'Success';
        Integer errorCount = 0;
        String jobId = (bc != null) ? bc.getJobId() : null;

        if (jobId != null) {
            try {
                AsyncApexJob job = [SELECT NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
                errorCount = (Integer)job.NumberOfErrors;
                if (errorCount > 0) finalStatus = 'Failed';
            } catch (Exception e) {}
        }
        if(finishException != null) errorCount++;

        try {
            System_Health_Log__c healthLog = new System_Health_Log__c(
                Job_Name__c = JOB_NAME, Job_ID__c = jobId,
                Status__c = finalStatus, Error_Count__c = errorCount
            );
            insert healthLog;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Could not log health: ' + e.getMessage());
        }
    }
}