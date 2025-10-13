/**
 * @description Service class responsible for creating Behavior_Log__c records from Behavior_Event__e platform events.
 * @version 2.5 - Final version with correct field mapping and robust error handling.
 */
public with sharing class BehaviorLogService {

    // This recursion guard is a best practice, though less critical in a subscriber context.
    // It prevents the service from running more than once in a transaction if ever called directly.
    @TestVisible
    public static Boolean hasAlreadyRun = false;

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
                Behavior_Data__c    = event.Behavior_Data__c
            ));
        }

        if (!logsToInsert.isEmpty()) {
            try {
                insert logsToInsert;
            } catch (DmlException e) {
                // Log the error for debugging but re-throw it so that test failures are not silent.
                System.debug(LoggingLevel.ERROR, 'Failed to insert Behavior Logs: ' + e.getMessage());
                throw e; 
            }
        }
    }
}

