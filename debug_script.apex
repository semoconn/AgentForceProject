// List all fields on BehaviorIQ_Configuration__c
Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.BehaviorIQ_Configuration__c.fields.getMap();
for (String fieldName : fieldMap.keySet()) {
    System.debug('Field: ' + fieldName);
}
