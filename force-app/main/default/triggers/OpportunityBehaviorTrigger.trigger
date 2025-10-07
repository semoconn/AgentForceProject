/**
 * Opportunity Behavior Tracking Trigger
 * File: OpportunityBehaviorTrigger.trigger
 */
trigger OpportunityBehaviorTrigger on Opportunity (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Opportunity');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}