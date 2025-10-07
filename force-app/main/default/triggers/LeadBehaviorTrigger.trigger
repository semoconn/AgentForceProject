/**
 * Lead Behavior Tracking Trigger
 * File: LeadBehaviorTrigger.trigger
 */
trigger LeadBehaviorTrigger on Lead (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Lead');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}