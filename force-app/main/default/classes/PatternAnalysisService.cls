/**
 * @description Scheduled + Batchable job for analyzing Behavior Logs, detecting workflow inefficiencies,
 *               cleaning old data, and logging system health for OrgPulse.
 * @version 3.1 - Apex-compliant enterprise version (replaced putIfAbsent with standard pattern).
 */
public class PatternAnalysisService implements Database.Batchable<sObject>, Schedulable {

    private static final Integer DEFAULT_RETENTION_DAYS = 90;
    private static final Integer PATTERN_THRESHOLD = 5;
    private static final String SEQUENTIAL_ACTION_PATTERN = 'Sequential_Action_Contact_Task';
    private static final Long FIVE_MINUTES_MS = 5 * 60 * 1000;

    // === Schedulable entry point ===
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PatternAnalysisService(), 200);
    }

    // === Batchable start ===
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Action_Name__c, Object_API_Name__c, Record_ID__c, User__c, CreatedDate
            FROM Behavior_Log__c
            WHERE CreatedDate = LAST_N_DAYS:1
            AND Action_Name__c = 'Record_Created'
            AND Object_API_Name__c IN ('Contact', 'Task')
            ORDER BY User__c, CreatedDate ASC
        ]);
    }

    // === Batchable execute ===
    public void execute(Database.BatchableContext bc, List<Behavior_Log__c> scope) {
        if (scope.isEmpty()) return;

        try {
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

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PatternAnalysisService execute error: ' + e.getMessage());
        }
    }

    // === Batchable finish ===
    public void finish(Database.BatchableContext bc) {
        try {
            deleteOldLogs();

            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, CreatedBy.Email
                FROM AsyncApexJob WHERE Id = :bc.getJobId()
                LIMIT 1
            ];

            String status = (job.NumberOfErrors > 0) ? 'Failed' : 'Success';
            logJobStatus(status, job);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in finish method: ' + e.getMessage());
        }
    }

    // === Helper: Delete old logs ===
    private void deleteOldLogs() {
        Date cutoff = Date.today().addDays(-DEFAULT_RETENTION_DAYS);
        List<Behavior_Log__c> oldLogs = [
            SELECT Id FROM Behavior_Log__c
            WHERE CreatedDate < :cutoff
            LIMIT 10000
        ];
        if (!oldLogs.isEmpty()) {
            Database.delete(oldLogs, false);
        }
    }

    // === Core pattern detection ===
    private void analyzeUserPattern(Id userId, List<Behavior_Log__c> logs) {
        if (logs.size() < 2) return;

        // Logs are already ordered by CreatedDate in the query.
        Integer sequentialCount = 0;
        List<String> exampleIds = new List<String>();

        for (Integer i = 0; i < logs.size() - 1; i++) {
            Behavior_Log__c current = logs[i];
            Behavior_Log__c next = logs[i + 1];

            if (current.Object_API_Name__c == 'Contact' && next.Object_API_Name__c == 'Task') {
                Long timeDiff = next.CreatedDate.getTime() - current.CreatedDate.getTime();
                if (timeDiff >= 0 && timeDiff <= FIVE_MINUTES_MS) {
                    sequentialCount++;
                    if (exampleIds.size() < 3) exampleIds.add(current.Record_ID__c);
                }
            }
        }

        if (sequentialCount >= PATTERN_THRESHOLD) {
            upsertPainPoint(
                SEQUENTIAL_ACTION_PATTERN,
                'Sequential Task Creation After Contact',
                'Users frequently create Tasks within 5 minutes of creating Contacts. Suggest automation.',
                'Contact',
                sequentialCount,
                JSON.serialize(exampleIds)
            );
        }
    }

    // === Helper: Upsert pain point ===
    private void upsertPainPoint(
        String uniqueName,
        String label,
        String description,
        String objectApiName,
        Integer occurrences,
        String exampleData
    ) {
        try {
            Identified_Pain_Point__c painPoint = new Identified_Pain_Point__c(
                Unique_Key__c = uniqueName,
                Name = label,
                Description__c = description,
                Object_API_Name__c = objectApiName,
                Status__c = 'New',
                Occurrences__c = occurrences,
                Impact_Score__c = occurrences * 10,
                Example_Records__c = exampleData,
                Last_Detected__c = System.now()
            );
            upsert painPoint Unique_Key__c;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error upserting pain point: ' + e.getMessage());
        }
    }

    // === Helper: Log job status ===
    private void logJobStatus(String status, AsyncApexJob job) {
        try {
            insert new System_Health_Log__c(
                Job_Name__c = 'Pattern Analysis Service',
                Job_ID__c = job.Id,
                Status__c = status,
                Error_Count__c = job.NumberOfErrors
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error logging job status: ' + e.getMessage());
        }
    }
}
