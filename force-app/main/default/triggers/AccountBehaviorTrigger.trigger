/**
 * Account Behavior Tracking Trigger
 * Routes all trigger events to the handler class for better maintainability
 */
trigger AccountBehaviorTrigger on Account (
    before insert, after insert,
    before update, after update, 
    before delete, after delete,
    after undelete
) {
    
    // Route all trigger logic to the handler class
    AccountBehaviorTriggerHandler.run(
        Trigger.operationType,
        Trigger.new,
        Trigger.old,
        Trigger.newMap,
        Trigger.oldMap
    );
}