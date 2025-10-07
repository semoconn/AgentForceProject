/**
 * Contact Behavior Tracking Trigger
 * File: ContactBehaviorTrigger.trigger
 */
trigger ContactBehaviorTrigger on Contact (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Contact');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}