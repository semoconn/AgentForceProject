/**
 * @description Scheduled + Batchable job for analyzing Behavior Logs, detecting workflow inefficiencies,
 * cleaning old data, and logging system health for OrgPulse.
 * @version 8.0 - Complete implementation of upsert, delete, and health logging methods.
 */
public class PatternAnalysisService implements Database.Batchable<sObject>, Schedulable {

    private static final Integer DEFAULT_RETENTION_DAYS = 90;
    private static final Integer PATTERN_THRESHOLD = 5;
    private static final String SEQUENTIAL_ACTION_PATTERN = 'Sequential_Action_Contact_Task';
    private static final Long FIVE_MINUTES_MS = 5 * 60 * 1000;
    private static final String JOB_NAME = 'Pattern Analysis Service';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PatternAnalysisService(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Action_Name__c, Object_API_Name__c, Record_ID__c, User__c, CreatedDate ' +
                       'FROM Behavior_Log__c ' +
                       'WHERE CreatedDate = LAST_N_DAYS:1 ' +
                       'AND Action_Name__c = \'Record_Created\' ' +
                       'AND Object_API_Name__c IN (\'Contact\', \'Task\') ' +
                       'ORDER BY User__c, CreatedDate ASC';
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

        Set<String> dismissedKeys = new Set<String>();
        if (!logsByUser.keySet().isEmpty()) {
            for (Suggestion_Dismissal__c dismissal : [
                SELECT Dismissal_Key__c FROM Suggestion_Dismissal__c
                WHERE User__c IN :logsByUser.keySet()
            ]) {
                dismissedKeys.add(dismissal.Dismissal_Key__c);
            }
        }

        for (Id userId : logsByUser.keySet()) {
            String dismissalCheckKey = userId + ':' + SEQUENTIAL_ACTION_PATTERN;
            if (dismissedKeys.contains(dismissalCheckKey)) {
                System.debug('Skipping user ' + userId + ' for pattern ' + SEQUENTIAL_ACTION_PATTERN + ' due to dismissal.');
                continue;
            }
            analyzeUserPattern(userId, logsByUser.get(userId));
        }
    }
    
    private void analyzeUserPattern(Id userId, List<Behavior_Log__c> logs) {
        if (logs.size() < 2) return;

        Integer sequentialCount = 0;
        List<String> exampleIds = new List<String>();

        for (Integer i = 0; i < logs.size() - 1; i++) {
            Behavior_Log__c currentLog = logs[i];
            Behavior_Log__c nextLog = logs[i+1];

            if (currentLog.Object_API_Name__c == 'Contact' && nextLog.Object_API_Name__c == 'Task') {
                Long timeDiff = nextLog.CreatedDate.getTime() - currentLog.CreatedDate.getTime();
                if (timeDiff >= 0 && timeDiff <= FIVE_MINUTES_MS) {
                    sequentialCount++;
                    if (exampleIds.size() < 5) exampleIds.add(currentLog.Record_ID__c);
                }
            }
        }

        if (sequentialCount >= PATTERN_THRESHOLD) {
            upsertPainPoint(
                SEQUENTIAL_ACTION_PATTERN,
                'Sequential Task Creation After Contact',
                'Users frequently create Tasks within 5 minutes of creating Contacts. This can be automated.',
                'Contact',
                sequentialCount,
                JSON.serialize(exampleIds)
            );
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        logJobStatus(bc);
        deleteOldLogs();
    }
    
    /**
     * @description FULL IMPLEMENTATION: Upserts a Pain Point record. Uses a unique key to prevent duplicates.
     */
    private void upsertPainPoint(String key, String label, String description, String obj, Integer count, String examples) {
        Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
            Name = label,
            Unique_Key__c = key,
            Description__c = description,
            Object_API_Name__c = obj,
            Occurrences__c = count,
            Impact_Score__c = count * 10,
            Example_Records__c = examples, // Corrected Field Name
            Last_Detected__c = System.now(),
            Status__c = 'New'
        );
        // Use the external ID field 'Unique_Key__c' to either insert a new record or update an existing one.
        upsert pp Unique_Key__c;
        System.debug('Upserted pain point with key: ' + key);
    }

    /**
     * @description FULL IMPLEMENTATION: Deletes Behavior_Log__c records older than the retention period.
     */
    private void deleteOldLogs() {
        try {
            Date cutoffDate = Date.today().addDays(-DEFAULT_RETENTION_DAYS);
            List<Behavior_Log__c> oldLogs = [SELECT Id FROM Behavior_Log__c WHERE CreatedDate < :cutoffDate LIMIT 10000];
            
            if (!oldLogs.isEmpty()) {
                delete oldLogs;
                System.debug('Deleted ' + oldLogs.size() + ' old behavior logs.');
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to delete old logs: ' + e.getMessage());
        }
    }

    /**
     * @description FULL IMPLEMENTATION: Creates a System_Health_Log__c record to track the execution of this job.
     */
    private void logJobStatus(Database.BatchableContext bc) {
        try {
            AsyncApexJob job = [SELECT Id, Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :bc.getJobId()];
            
            System_Health_Log__c healthLog = new System_Health_Log__c(
                Job_Name__c = JOB_NAME,
                Job_ID__c = job.Id,
                Status__c = (job.NumberOfErrors == 0) ? 'Success' : 'Failed',
                Error_Count__c = job.NumberOfErrors
            );
            
            insert healthLog;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create health log: ' + e.getMessage());
        }
    }
}

