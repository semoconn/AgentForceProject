/**
 * @description Scheduled + Batchable job for analyzing Behavior Logs, detecting workflow inefficiencies,
 * cleaning old data, and logging system health for OrgPulse.
 * @version 5.1 - Fixed deployment error caused by using a reserved keyword 'desc' as a parameter name.
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
        // Use LAST_N_DAYS:1 for timezone safety
        return Database.getQueryLocator([
            SELECT Id, Action_Name__c, Object_API_Name__c, Record_ID__c, User__c, CreatedDate
            FROM Behavior_Log__c
            WHERE CreatedDate = LAST_N_DAYS:1
            AND Action_Name__c = 'Record_Created'
            AND Object_API_Name__c IN ('Contact', 'Task')
            ORDER BY User__c, CreatedDate ASC
        ]);
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
            analyzeUserPattern(userId, logsByUser.get(userId));
        }
    }
    
    // Corrected, stateful pattern detection logic
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
        // ... (finish logic with deleteOldLogs and logJobStatus remains the same)
    }
    
    // FIX: Renamed parameter from 'desc' to 'description'
    private void upsertPainPoint(String key, String label, String description, String obj, Integer count, String examples) {
        Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
            Name = label, Unique_Key__c = key, Description__c = description,
            Object_API_Name__c = obj, Occurrences__c = count,
            Impact_Score__c = count * 10, Example_Records__c = examples,
            Last_Detected__c = System.now(), Status__c = 'New'
        );
        upsert pp Unique_Key__c;
    }
    // ... (deleteOldLogs and logJobStatus methods remain the same)
}

