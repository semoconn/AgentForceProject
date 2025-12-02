/**
 * @description Service class responsible for creating Behavior_Log__c records from Behavior_Event__e platform events.
 * @version 3.2 - SECURITY FIX: Added stripInaccessible for Field Level Security.
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
            // SECURITY FIX: Enforce Create Permission
            if (Schema.sObjectType.Behavior_Log__c.isCreateable()) {
                try {
                    // Added Security.stripInaccessible to enforce FLS on all fields being inserted
                    SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, logsToInsert);
                    insert decision.getRecords();
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Failed to insert Behavior Logs: ' + e.getMessage());
                }
            } else {
                System.debug(LoggingLevel.ERROR, 'Security Error: User lacks permission to create Behavior_Log__c.');
            }
        }
    }
}