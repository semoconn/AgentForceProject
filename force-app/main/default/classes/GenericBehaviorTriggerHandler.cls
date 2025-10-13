/**
 * @description Generic handler for behavior tracking on any SObject. Publishes a Behavior_Event__e.
 * @version 2.3 - Final version with a TestVisible method to clear the recursion guard for proper testing.
 */
public with sharing class GenericBehaviorTriggerHandler {
    
    private static Set<Id> processedRecordIds = new Set<Id>();
    private String objectName;
    
    public GenericBehaviorTriggerHandler(String objectApiName) {
        this.objectName = objectApiName;
    }
    
    public void run(TriggerOperation triggerEvent, List<SObject> newRecords, List<SObject> oldRecords, Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
        switch on triggerEvent {
            when AFTER_INSERT {
                handleAfterDML(newRecords, 'Record_Created', null);
            }
            when AFTER_UPDATE {
                handleAfterDML(newRecords, 'Record_Updated', oldMap);
            }
            when AFTER_DELETE {
                handleAfterDML(oldRecords, 'Record_Deleted', null);
            }
            when AFTER_UNDELETE {
                handleAfterDML(newRecords, 'Record_Undeleted', null);
            }
        }
    }
    
    private void handleAfterDML(List<SObject> records, String actionName, Map<Id, SObject> oldMap) {
        List<SObject> recordsToProcess = filterProcessedRecords(records);
        if (recordsToProcess.isEmpty()) {
            return;
        }

        List<Behavior_Event__e> eventsToPublish = new List<Behavior_Event__e>();
        for (SObject record : recordsToProcess) {
            Map<String, Object> behaviorDataMap = new Map<String, Object>();
            if (actionName == 'Record_Updated' && oldMap != null) {
                behaviorDataMap.put('changedFields', getChangedFields(record, oldMap.get(record.Id)));
            }

            eventsToPublish.add(new Behavior_Event__e(
                Action_Name__c = actionName,
                Object_API_Name__c = this.objectName,
                Record_ID__c = record.Id,
                User_ID__c = UserInfo.getUserId(),
                Behavior_Data__c = JSON.serialize(behaviorDataMap)
            ));
        }

        if (!eventsToPublish.isEmpty()) {
            EventBus.publish(eventsToPublish);
        }
    }

    private List<SObject> filterProcessedRecords(List<SObject> records) {
        List<SObject> recordsToProcess = new List<SObject>();
        if (records == null) return recordsToProcess;

        for (SObject record : records) {
            if (!processedRecordIds.contains(record.Id)) {
                recordsToProcess.add(record);
                processedRecordIds.add(record.Id);
            }
        }
        return recordsToProcess;
    }
    
    private Map<String, Object> getChangedFields(SObject newRecord, SObject oldRecord) {
        Map<String, Object> changes = new Map<String, Object>();
        if (oldRecord == null) return changes;

        Map<String, Schema.SObjectField> fieldMap = newRecord.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : fieldMap.keySet()) {
            if (newRecord.get(fieldName) != oldRecord.get(fieldName)) {
                changes.put(fieldName, new Map<String, Object>{
                    'oldValue' => oldRecord.get(fieldName),
                    'newValue' => newRecord.get(fieldName)
                });
            }
        }
        return changes;
    }

    @TestVisible
    private static void clearProcessedIdsForTest() {
        processedRecordIds.clear();
    }
}

