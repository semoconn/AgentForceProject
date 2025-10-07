/**
 * Case Behavior Tracking Trigger
 * File: CaseBehaviorTrigger.trigger
 */
trigger CaseBehaviorTrigger on Case (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Case');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}