/**
 * @description Service class responsible for creating Behavior_Log__c records from Behavior_Event__e platform events.
 * Also creates/updates daily aggregate Behavior_Log_Summary__c records for efficient analytics.
 * @version 4.0 - Added dual-write: raw logs + daily summary aggregates for storage optimization.
 */
public with sharing class BehaviorLogService {

    public static void createLogsFromEvents(List<Behavior_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<Behavior_Log__c> logsToInsert = new List<Behavior_Log__c>();

        for (Behavior_Event__e event : events) {
            logsToInsert.add(new Behavior_Log__c(
                Action_Name__c      = event.Action_Name__c,
                Object_API_Name__c  = event.Object_API_Name__c,
                Record_ID__c        = event.Record_ID__c,
                User__c             = event.User_ID__c,
                Behavior_Data__c    = event.Behavior_Data__c,
                Timestamp__c        = System.now()
            ));
        }

        if (!logsToInsert.isEmpty()) {
            if (Schema.sObjectType.Behavior_Log__c.isCreateable()) {
                try {
                    SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, logsToInsert);
                    insert decision.getRecords();
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Failed to insert Behavior Logs: ' + e.getMessage());
                }
            } else {
                System.debug(LoggingLevel.ERROR, 'Security Error: User lacks permission to create Behavior_Log__c.');
            }
        }

        // Dual-write: create/update daily summary aggregates
        // Summary failures must not break the raw log pipeline
        createSummariesFromEvents(events);
    }

    /**
     * @description Aggregates events by User + Object + Action + Date and upserts
     * daily summary records. Uses Composite_Key__c as the external ID for upsert.
     * Existing summary counts are incremented (not replaced).
     * @param events The platform events to aggregate
     */
    private static void createSummariesFromEvents(List<Behavior_Event__e> events) {
        // Step 1: Aggregate events by composite key
        Map<String, Behavior_Log_Summary__c> summaryMap = new Map<String, Behavior_Log_Summary__c>();
        String todayStr = String.valueOf(Date.today());

        for (Behavior_Event__e event : events) {
            if (event.User_ID__c == null) {
                continue;
            }

            String key = event.User_ID__c + '_' +
                         event.Object_API_Name__c + '_' +
                         event.Action_Name__c + '_' +
                         todayStr;

            if (summaryMap.containsKey(key)) {
                Behavior_Log_Summary__c existing = summaryMap.get(key);
                existing.Event_Count__c = existing.Event_Count__c + 1;
                existing.Last_Event_Time__c = System.now();
            } else {
                summaryMap.put(key, new Behavior_Log_Summary__c(
                    User__c             = event.User_ID__c,
                    Object_API_Name__c  = event.Object_API_Name__c,
                    Action_Name__c      = event.Action_Name__c,
                    Log_Date__c         = Date.today(),
                    Event_Count__c      = 1,
                    Composite_Key__c    = key,
                    Last_Event_Time__c  = System.now()
                ));
            }
        }

        if (summaryMap.isEmpty()) {
            return;
        }

        // Step 2: Query existing summaries to add counts (not replace)
        Map<String, Behavior_Log_Summary__c> existingSummaries = new Map<String, Behavior_Log_Summary__c>();
        Set<String> keys = summaryMap.keySet();

        if (Schema.sObjectType.Behavior_Log_Summary__c.isAccessible()) {
            try {
                for (Behavior_Log_Summary__c existing : [
                    SELECT Id, Composite_Key__c, Event_Count__c
                    FROM Behavior_Log_Summary__c
                    WHERE Composite_Key__c IN :keys
                    WITH SECURITY_ENFORCED
                ]) {
                    existingSummaries.put(existing.Composite_Key__c, existing);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to query existing summaries: ' + e.getMessage());
            }
        }

        // Step 3: Merge counts — add new counts to existing records
        List<Behavior_Log_Summary__c> toUpsert = new List<Behavior_Log_Summary__c>();
        for (String key : summaryMap.keySet()) {
            Behavior_Log_Summary__c newSummary = summaryMap.get(key);
            if (existingSummaries.containsKey(key)) {
                Behavior_Log_Summary__c existingSummary = existingSummaries.get(key);
                existingSummary.Event_Count__c = existingSummary.Event_Count__c + newSummary.Event_Count__c;
                existingSummary.Last_Event_Time__c = newSummary.Last_Event_Time__c;
                toUpsert.add(existingSummary);
            } else {
                toUpsert.add(newSummary);
            }
        }

        // Step 4: Upsert with security
        if (Schema.sObjectType.Behavior_Log_Summary__c.isCreateable()) {
            try {
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPSERTABLE, toUpsert
                );
                Database.upsert(decision.getRecords(), Behavior_Log_Summary__c.Composite_Key__c, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to upsert Behavior Log Summaries: ' + e.getMessage());
            }
        }
    }
}
