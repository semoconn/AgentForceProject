/**
 * Generic handler class for behavior tracking on any object.
 * This class is the central entry point for all object triggers.
 * It delegates logging to the WorkflowSuggestionController to ensure
 * DML operations are batched and governor limits are respected.
 * VERSION: 3.1 - Added a test-visible method to clear static variables.
 */
public with sharing class GenericBehaviorTriggerHandler {
    
    // Use a Set of record IDs to prevent recursion on the same record within a transaction.
    private static Set<Id> processedRecordIds = new Set<Id>();
    private String objectName;
    
    // ... all of your existing methods (constructor, run, handleAfterInsert, etc.) remain unchanged ...
    /**
     * Constructor - pass in the object API name
     */
    public GenericBehaviorTriggerHandler(String objectApiName) {
        this.objectName = objectApiName;
    }
    
    /**
     * Main entry point for trigger execution
     */
    public void run(TriggerOperation triggerEvent, List<SObject> newRecords, List<SObject> oldRecords, Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
        
        switch on triggerEvent {
            when AFTER_INSERT {
                handleAfterInsert(newRecords);
            }
            when AFTER_UPDATE {
                handleAfterUpdate(newRecords, oldMap);
            }
            when AFTER_DELETE {
                handleAfterDelete(oldRecords);
            }
            when AFTER_UNDELETE {
                handleAfterUndelete(newRecords);
            }
        }
        
        WorkflowSuggestionController.commitLogs();
    }
    
    private void handleAfterInsert(List<SObject> newRecords) {
        List<SObject> recordsToProcess = filterProcessedRecords(newRecords);
        if (recordsToProcess.isEmpty()) return;

        for (SObject record : recordsToProcess) {
            Map<String, Object> recordData = getRecordData(record);
            logBehaviorEvent('Record_Created', objectName, record.Id, recordData);
        }
        
        if (recordsToProcess.size() > 5) {
            logBehaviorEvent('Bulk_Creation_Detected', objectName, null, new Map<String, Object>{
                'recordCount' => recordsToProcess.size(),
                'createdBy' => UserInfo.getUserId()
            });
        }
    }
    
    private void handleAfterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<SObject> recordsToProcess = filterProcessedRecords(newRecords);
        if (recordsToProcess.isEmpty()) return;
        
        for (SObject newRecord : recordsToProcess) {
            SObject oldRecord = oldMap.get(newRecord.Id);
            Map<String, Object> changes = getChangedFields(newRecord, oldRecord);
            
            if (!changes.isEmpty()) {
                logBehaviorEvent('Record_Updated', objectName, newRecord.Id, new Map<String, Object>{
                    'changedFields' => changes,
                    'changeCount' => changes.size()
                });
            }
        }
        
        if (recordsToProcess.size() > 10) {
            logBehaviorEvent('Mass_Update_Detected', objectName, null, new Map<String, Object>{
                'recordCount' => recordsToProcess.size(),
                'modifiedBy' => UserInfo.getUserId()
            });
        }
    }
    
    private void handleAfterDelete(List<SObject> oldRecords) {
        List<SObject> recordsToProcess = filterProcessedRecords(oldRecords);
        if (recordsToProcess.isEmpty()) return;

        for (SObject record : recordsToProcess) {
            Map<String, Object> recordData = getRecordData(record);
            logBehaviorEvent('Record_Deleted', objectName, record.Id, recordData);
        }
    }
    
    private void handleAfterUndelete(List<SObject> newRecords) {
        List<SObject> recordsToProcess = filterProcessedRecords(newRecords);
        if (recordsToProcess.isEmpty()) return;

        for (SObject record : recordsToProcess) {
            Map<String, Object> recordData = getRecordData(record);
            logBehaviorEvent('Record_Undeleted', objectName, record.Id, recordData);
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
    
    private Map<String, Object> getRecordData(SObject record) {
        Map<String, Object> data = new Map<String, Object>();
        Schema.DescribeSObjectResult objectDescribe = record.getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        data.put('objectType', objectDescribe.getName());
        if (fieldMap.containsKey('Name')) {
            data.put('name', record.get('Name'));
        }
        return data;
    }
    
    private Map<String, Object> getChangedFields(SObject newRecord, SObject oldRecord) {
        Map<String, Object> changes = new Map<String, Object>();
        if (oldRecord == null) return changes;

        Schema.DescribeSObjectResult objectDescribe = newRecord.getSObjectType().getDescribe();
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.isUpdateable() && !fieldDescribe.isCalculated()) {
                try {
                    Object newValue = newRecord.get(fieldName);
                    Object oldValue = oldRecord.get(fieldName);
                    if (newValue != oldValue) {
                        changes.put(fieldName, new Map<String, Object>{
                            'oldValue' => oldValue,
                            'newValue' => newValue
                        });
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Could not access field ' + fieldName);
                }
            }
        }
        return changes;
    }
    
    private void logBehaviorEvent(String actionName, String objectType, Id recordId, Map<String, Object> additionalData) {
        try {
            String behaviorData = JSON.serialize(new Map<String, Object>{
                'triggerContext' => true,
                'timestamp' => DateTime.now(),
                'userId' => UserInfo.getUserId(),
                'username' => UserInfo.getUserName(),
                'additionalData' => additionalData
            });
            
            WorkflowSuggestionController.logWorkflowEvent(
                String.valueOf(recordId), 
                objectType, 
                actionName, 
                behaviorData
            );
            
        } catch (Exception e) {
            System.debug('Error creating behavior log event data: ' + e.getMessage());
        }
    }

    /**
     * @description Clears the static set of processed record IDs.
     * This method is only visible to test classes and is used to ensure
     * that each test can simulate a clean, independent transaction.
     */
    @TestVisible
    private static void clearProcessedIdsForTest() {
        processedRecordIds.clear();
    }
}

