/**
 * @description Trigger to process Behavior_Event__e platform events
 * and create corresponding Behavior_Log__c records.
 * @version 2.0 - Final version for Sprint 1.
 */
trigger BehaviorEventTrigger on Behavior_Event__e (after insert) {
    // Process all new events by passing them to the service class.
    // This trigger acts as the subscriber in our event-driven framework.
    BehaviorLogService.createLogsFromEvents(Trigger.new);
}