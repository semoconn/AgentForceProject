/**
 * @description Controller for the Exclusion Builder LWC. Provides schema metadata
 *              for building visual exclusion rules and saves them to BehaviorIQ_Configuration__c.
 * @author      BehaviorIQ
 * @group       BehaviorIQ
 */
public with sharing class ExclusionBuilderController {

    private static final String CONFIG_RECORD_NAME = 'Default';

    /**
     * @description Default list of supported objects for exclusion rules.
     *              These are the standard objects commonly monitored by BehaviorIQ.
     */
    private static final List<String> DEFAULT_MONITORED_OBJECTS = new List<String>{
        'Account', 'Case', 'Contact', 'Contract', 'Lead', 'Opportunity', 'Task'
    };

    /**
     * @description Returns the list of objects available for exclusion rules.
     *              First checks the Monitored_Objects__c configuration field,
     *              then falls back to default supported objects.
     * @return List of ObjectWrapper containing object labels and API names
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectWrapper> getMonitoredObjects() {
        try {
            List<ObjectWrapper> result = new List<ObjectWrapper>();
            Set<String> objectNames = new Set<String>();

            // Try to get configured monitored objects from BehaviorIQ_Configuration__c
            if (Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                List<BehaviorIQ_Configuration__c> configs = [
                    SELECT Id, Monitored_Objects__c
                    FROM BehaviorIQ_Configuration__c
                    LIMIT 1
                ];

                if (!configs.isEmpty() && String.isNotBlank(configs[0].Monitored_Objects__c)) {
                    // Parse comma-separated list of object names
                    for (String objName : configs[0].Monitored_Objects__c.split(',')) {
                        objectNames.add(objName.trim());
                    }
                }
            }

            // Fall back to defaults if no configuration found
            if (objectNames.isEmpty()) {
                objectNames.addAll(DEFAULT_MONITORED_OBJECTS);
            }

            // Get schema descriptions for the objects
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            for (String objName : objectNames) {
                Schema.SObjectType sObjType = globalDescribe.get(objName.toLowerCase());
                if (sObjType != null) {
                    Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
                    if (describeResult.isAccessible()) {
                        ObjectWrapper wrapper = new ObjectWrapper();
                        wrapper.label = describeResult.getLabel();
                        wrapper.value = describeResult.getName();
                        result.add(wrapper);
                    }
                }
            }

            // Sort by label
            result.sort();

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch monitored objects: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the list of fields for a given object.
     *              Includes label, API name, and data type for smart input rendering.
     * @param objectName The API name of the object
     * @return List of FieldWrapper containing field metadata
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldWrapper> getObjectFields(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                throw new AuraHandledException('Object name is required.');
            }

            List<FieldWrapper> result = new List<FieldWrapper>();

            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(objectName.toLowerCase());

            if (sObjType == null) {
                throw new AuraHandledException('Object not found: ' + objectName);
            }

            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            if (!describeResult.isAccessible()) {
                throw new AuraHandledException('Object not accessible: ' + objectName);
            }

            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

                // Only include accessible and filterable fields
                if (fieldDescribe.isAccessible() && fieldDescribe.isFilterable()) {
                    FieldWrapper wrapper = new FieldWrapper();
                    wrapper.label = fieldDescribe.getLabel();
                    wrapper.value = fieldDescribe.getName();
                    wrapper.dataType = String.valueOf(fieldDescribe.getType());
                    result.add(wrapper);
                }
            }

            // Sort by label
            result.sort();

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch object fields: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the picklist values for a given picklist field.
     *              Only returns active picklist values.
     * @param objectName The API name of the object
     * @param fieldName The API name of the picklist field
     * @return List of PicklistWrapper containing picklist options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistWrapper> getPicklistValues(String objectName, String fieldName) {
        try {
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                throw new AuraHandledException('Object name and field name are required.');
            }

            List<PicklistWrapper> result = new List<PicklistWrapper>();

            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(objectName.toLowerCase());

            if (sObjType == null) {
                throw new AuraHandledException('Object not found: ' + objectName);
            }

            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            if (field == null) {
                throw new AuraHandledException('Field not found: ' + fieldName);
            }

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (!fieldDescribe.isAccessible()) {
                throw new AuraHandledException('Field not accessible: ' + fieldName);
            }

            // Get picklist values
            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();

            for (Schema.PicklistEntry entry : picklistEntries) {
                // Only include active values
                if (entry.isActive()) {
                    PicklistWrapper wrapper = new PicklistWrapper();
                    wrapper.label = entry.getLabel();
                    wrapper.value = entry.getValue();
                    result.add(wrapper);
                }
            }

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch picklist values: ' + e.getMessage());
        }
    }

    /**
     * @description Retrieves the current exclusion configuration from BehaviorIQ_Configuration__c.
     * @return ExclusionConfigWrapper containing the current JSON config and record Id
     */
    @AuraEnabled(cacheable=true)
    public static ExclusionConfigWrapper getExclusionConfig() {
        try {
            ExclusionConfigWrapper wrapper = new ExclusionConfigWrapper();
            wrapper.jsonConfig = '{}';
            wrapper.recordId = null;

            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                throw new AuraHandledException('You do not have permission to access BehaviorIQ Configuration.');
            }

            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Id, Global_Exclusion_Filter__c
                FROM BehaviorIQ_Configuration__c
                LIMIT 1
            ];

            if (!configs.isEmpty()) {
                wrapper.recordId = configs[0].Id;
                wrapper.jsonConfig = String.isNotBlank(configs[0].Global_Exclusion_Filter__c)
                    ? configs[0].Global_Exclusion_Filter__c
                    : '{}';
            }

            return wrapper;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch exclusion configuration: ' + e.getMessage());
        }
    }

    /**
     * @description Saves the exclusion configuration to BehaviorIQ_Configuration__c.
     *              Creates the record if it doesn't exist, otherwise updates it.
     * @param jsonConfig The JSON configuration string to save
     * @return The Id of the upserted configuration record
     */
    @AuraEnabled
    public static Id saveExclusions(String jsonConfig) {
        try {
            // Validate JSON format
            if (String.isBlank(jsonConfig)) {
                jsonConfig = '{}';
            } else {
                // Attempt to parse to validate JSON
                try {
                    JSON.deserializeUntyped(jsonConfig);
                } catch (Exception e) {
                    throw new AuraHandledException('Invalid JSON format: ' + e.getMessage());
                }
            }

            // Check object permissions
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isCreateable() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to modify BehaviorIQ Configuration.');
            }

            // Try to find existing record
            List<BehaviorIQ_Configuration__c> existingConfigs = [
                SELECT Id, Global_Exclusion_Filter__c
                FROM BehaviorIQ_Configuration__c
                LIMIT 1
            ];

            BehaviorIQ_Configuration__c configToSave;

            if (!existingConfigs.isEmpty()) {
                configToSave = existingConfigs[0];
            } else {
                configToSave = new BehaviorIQ_Configuration__c(
                    Name = CONFIG_RECORD_NAME
                );
            }

            configToSave.Global_Exclusion_Filter__c = jsonConfig;

            // Use Security.stripInaccessible for field-level security
            SObjectAccessDecision securityDecision = Security.stripInaccessible(
                AccessType.UPSERTABLE,
                new List<BehaviorIQ_Configuration__c>{ configToSave }
            );

            upsert securityDecision.getRecords();

            return ((BehaviorIQ_Configuration__c) securityDecision.getRecords()[0]).Id;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save exclusion configuration: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper class for object metadata.
     */
    public class ObjectWrapper implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public Integer compareTo(Object compareTo) {
            ObjectWrapper other = (ObjectWrapper) compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.compareTo(other.label);
        }
    }

    /**
     * @description Wrapper class for field metadata.
     */
    public class FieldWrapper implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String dataType;

        public Integer compareTo(Object compareTo) {
            FieldWrapper other = (FieldWrapper) compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.compareTo(other.label);
        }
    }

    /**
     * @description Wrapper class for picklist values.
     */
    public class PicklistWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Wrapper class for exclusion configuration.
     */
    public class ExclusionConfigWrapper {
        @AuraEnabled public String jsonConfig;
        @AuraEnabled public Id recordId;
    }
}
