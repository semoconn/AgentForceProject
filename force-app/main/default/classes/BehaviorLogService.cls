/**
 * @description Service class responsible for creating Behavior_Log__c records from Behavior_Event__e platform events.
 * @version 3.0 - Added robust debugging and ensures all fields are mapped.
 */
public with sharing class BehaviorLogService {

    public static void createLogsFromEvents(List<Behavior_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        // --- DIAGNOSTIC DEBUG LINE ---
        // This will log the exact payload received from the event bus.
        System.debug(LoggingLevel.ERROR, 'EVENT PAYLOAD RECEIVED: ' + JSON.serialize(events));

        List<Behavior_Log__c> logsToInsert = new List<Behavior_Log__c>();

        for (Behavior_Event__e event : events) {
            logsToInsert.add(new Behavior_Log__c(
                Action_Name__c      = event.Action_Name__c,
                Object_API_Name__c  = event.Object_API_Name__c,
                Record_ID__c        = event.Record_ID__c,
                User__c             = event.User_ID__c,
                Behavior_Data__c    = event.Behavior_Data__c
            ));
        }

        if (!logsToInsert.isEmpty()) {
            try {
                insert logsToInsert;
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, 'Failed to insert Behavior Logs: ' + e.getMessage());
                // In a real production scenario, you might add more robust error handling here.
            }
        }
    }
}