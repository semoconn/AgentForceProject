/**
 * Task Behavior Tracking Trigger
 * File: TaskBehaviorTrigger.trigger
 * Description: Captures DML events on the Task object to be processed by the OrgPulse engine.
 */
trigger TaskBehaviorTrigger on Task (after insert, after update, after delete, after undelete) {
    GenericBehaviorTriggerHandler handler = new GenericBehaviorTriggerHandler('Task');
    handler.run(Trigger.operationType, Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap);
}
