/**
 * Contract Behavior Tracking Trigger
 * File: ContractBehaviorTrigger.trigger
 */
trigger ContractBehaviorTrigger on Contract (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Contract');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}
