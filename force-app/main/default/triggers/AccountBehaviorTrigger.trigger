/**
 * Account Behavior Tracking Trigger
 * File: AccountBehaviorTrigger.trigger
 */
trigger AccountBehaviorTrigger on Account (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Account');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}