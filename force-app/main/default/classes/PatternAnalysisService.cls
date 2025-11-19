/**
 * @description Scheduled + Batchable job for analyzing Behavior Logs.
 * @version 14.0 - Phase 2: Implemented Dynamic Thresholds via Behavior_Setting__mdt.
 */
public with sharing class PatternAnalysisService implements Database.Batchable<sObject>, Schedulable {

    // Pattern Definitions
    public static final String SEQUENTIAL_ACTION_PATTERN = 'Sequential_Action_Contact_Task';
    public static final String STALE_OPPORTUNITY_PATTERN = 'Stale_High_Value_Opportunity';
    public static final String UNASSIGNED_LEAD_PATTERN = 'Unassigned_Lead_Created';
    public static final String STALE_CASE_PATTERN = 'Stale_High_Priority_Case';

    // Hardcoded Fallbacks (Safety Net)
    private static final Integer DEFAULT_SEQUENTIAL_THRESHOLD = 5;
    private static final Integer DEFAULT_STALE_OPP_DAYS = 30;
    private static final Integer DEFAULT_LEAD_AGE_HOURS = 24;
    
    // Other Constants
    private static final Long FIVE_MINUTES_MS = 5 * 60 * 1000;
    private static final Decimal STALE_OPP_AMOUNT = 100000;
    private static final Integer STALE_OPP_THRESHOLD = 3; // Count threshold
    private static final Integer UNASSIGNED_LEAD_THRESHOLD = 5; // Count threshold
    private static final Integer STALE_CASE_THRESHOLD = 3; // Count threshold

    // Configuration
    public static final Integer DEFAULT_RETENTION_DAYS = 90;
    private static final String JOB_NAME = 'Pattern Analysis Service';
    
    // Kept as static for testability until moved to MDT in future stories
    public static Integer STALE_CASE_DAYS = 7; 

    // Allow tests to inject mock metadata
    @TestVisible private static Behavior_Setting__mdt mockSettings;

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

    /**
     * @description Retrieves settings from Custom Metadata or falls back to defaults.
     */
    private Behavior_Setting__mdt getSettings() {
        if (mockSettings != null) return mockSettings;

        Behavior_Setting__mdt settings;
        try {
            // NOTE: Metadata queries do not count against SOQL limits in most contexts
             settings = [
                SELECT Sequential_Action_Threshold__c, Stale_Opportunity_Days__c, Unassigned_Lead_Age_Hours__c
                FROM Behavior_Setting__mdt
                WHERE DeveloperName = 'Default'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Behavior_Setting__mdt "Default" record not found. Using hardcoded defaults.');
        }

        if (settings == null) {
            // Create in-memory default record if query fails or returns nothing
            settings = new Behavior_Setting__mdt(
                Sequential_Action_Threshold__c = DEFAULT_SEQUENTIAL_THRESHOLD,
                Stale_Opportunity_Days__c = DEFAULT_STALE_OPP_DAYS,
                Unassigned_Lead_Age_Hours__c = DEFAULT_LEAD_AGE_HOURS
            );
        }
        return settings;
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

        Behavior_Setting__mdt settings = getSettings();
        for (Id userId : logsByUser.keySet()) {
            analyzeContactTaskPattern(userId, logsByUser.get(userId), settings);
        }
    }
    
    private void analyzeContactTaskPattern(Id userId, List<Behavior_Log__c> logs, Behavior_Setting__mdt settings) {
        if (logs.size() < 2) return;

        Integer sequentialCount = 0;
        List<String> exampleIds = new List<String>();
        Integer threshold = (settings.Sequential_Action_Threshold__c != null) ? 
                            settings.Sequential_Action_Threshold__c.intValue() : DEFAULT_SEQUENTIAL_THRESHOLD;

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

        if (sequentialCount >= threshold) {
            upsertPainPoint(
                SEQUENTIAL_ACTION_PATTERN, 'Sequential Task Creation After Contact',
                'Users frequently create Tasks within 5 minutes of creating Contacts.',
                'Contact', sequentialCount, JSON.serialize(exampleIds)
            );
        }
    }

    private void analyzeStaleOpportunities(Behavior_Setting__mdt settings) {
        Integer days = (settings.Stale_Opportunity_Days__c != null) ? 
                       settings.Stale_Opportunity_Days__c.intValue() : DEFAULT_STALE_OPP_DAYS;
        
        Date staleDate = (days == 0) ? Date.today() : Date.today().addDays(-days);
        
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
                'High-value opportunities have not been updated recently (' + days + ' days).',
                'Opportunity', queriedOpps.size(), JSON.serialize(exampleIds));
        }
    }

    private void analyzeUnassignedLeads(Behavior_Setting__mdt settings) {
        Id queueId;
        try {
             queueId = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Unassigned Leads Queue' WITH SECURITY_ENFORCED LIMIT 1]?.Id;
        } catch (Exception e) { return; }

        if(queueId == null) return;

        // Calculate threshold time based on hours
        Integer hours = (settings.Unassigned_Lead_Age_Hours__c != null) ? 
                        settings.Unassigned_Lead_Age_Hours__c.intValue() : DEFAULT_LEAD_AGE_HOURS;
        
        // Use System.now() for hour precision
        Datetime timeThreshold = System.now().addHours(-hours);

        List<Lead> unassignedLeads = new List<Lead>();
        try {
            if(Schema.sObjectType.Lead.isAccessible()) {
                unassignedLeads = [
                    SELECT Id 
                    FROM Lead 
                    WHERE OwnerId = :queueId 
                    AND CreatedDate <= :timeThreshold
                    WITH SECURITY_ENFORCED
                ];
            }
        } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'Error querying leads: ' + e.getMessage()); }

        if (unassignedLeads.size() >= UNASSIGNED_LEAD_THRESHOLD) {
             List<String> exampleIds = new List<String>();
             for(Integer i = 0; i < Math.min(unassignedLeads.size(), 5); i++) exampleIds.add(unassignedLeads[i].Id);

            upsertPainPoint(UNASSIGNED_LEAD_PATTERN, 'Leads Not Being Assigned',
                'Leads have been sitting in the queue unassigned for over ' + hours + ' hours.',
                'Lead', unassignedLeads.size(), JSON.serialize(exampleIds));
        }
    }

    private void analyzeStaleCases() {
        // Keeping this as-is (using static variable) per instructions to only refactor the 3 MDT fields
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
        Behavior_Setting__mdt settings = getSettings();
        
        try { analyzeStaleOpportunities(settings); } catch (Exception e) {}
        try { analyzeUnassignedLeads(settings); } catch (Exception e) {}
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