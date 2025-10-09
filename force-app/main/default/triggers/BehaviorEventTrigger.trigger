/**
 * @description Subscribes to the Workflow_Behavior_Event__e and logs the data.
 */
trigger BehaviorEventTrigger on Workflow_Behavior_Event__e (after insert) {
    
    for (Workflow_Behavior_Event__e event : Trigger.New) {
        WorkflowSuggestionController.logWorkflowEvent(
            event.Record_ID__c,
            event.Object_Type__c,
            event.Action__c,
            event.Behavior_Data__c
        );
    }

    // Commit all the logs that were generated from this batch of events.
    WorkflowSuggestionController.commitLogs();
}