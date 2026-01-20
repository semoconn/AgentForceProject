/**
 * @description Controller for the Pattern Rule Manager LWC. Provides CRUD operations
 *              for Behavior_Pattern_Rule__mdt custom metadata records, schema introspection
 *              for visual query building, and validation utilities.
 * @author      BehaviorIQ
 * @group       BehaviorIQ
 */
public with sharing class PatternRuleManagerController {

    // ==================== READ OPERATIONS ====================

    /**
     * @description Returns all pattern rules as wrappers with computed display fields.
     * @return List of RuleWrapper containing all pattern rule metadata
     */
    @AuraEnabled(cacheable=true)
    public static List<RuleWrapper> getAllPatternRules() {
        try {
            List<RuleWrapper> result = new List<RuleWrapper>();

            List<Behavior_Pattern_Rule__mdt> rules = [
                SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                       Threshold_Default__c, Fix_Type__c, Fix_Config__c, Logic_Type__c,
                       Apex_Handler_Class__c, Is_Premium__c, Cost_Per_Incident__c, Is_Active__c
                FROM Behavior_Pattern_Rule__mdt
                ORDER BY MasterLabel ASC
            ];

            // Get object labels from schema
            Map<String, String> objectLabels = getObjectLabelMap();

            for (Behavior_Pattern_Rule__mdt rule : rules) {
                RuleWrapper wrapper = new RuleWrapper();
                wrapper.developerName = rule.DeveloperName;
                wrapper.label = rule.MasterLabel;
                wrapper.objectApiName = rule.Object_API_Name__c;
                wrapper.objectLabel = objectLabels.containsKey(rule.Object_API_Name__c?.toLowerCase())
                    ? objectLabels.get(rule.Object_API_Name__c.toLowerCase())
                    : rule.Object_API_Name__c;
                wrapper.queryCondition = rule.Query_Condition__c;
                wrapper.thresholdDefault = rule.Threshold_Default__c;
                wrapper.fixType = rule.Fix_Type__c;
                wrapper.fixConfig = rule.Fix_Config__c;
                wrapper.logicType = rule.Logic_Type__c != null ? rule.Logic_Type__c : 'Standard';
                wrapper.apexHandlerClass = rule.Apex_Handler_Class__c;
                wrapper.isPremium = rule.Is_Premium__c == true;
                wrapper.costPerIncident = rule.Cost_Per_Incident__c;
                wrapper.isActive = rule.Is_Active__c != false; // Default to true if null

                // Compute badge class
                if (wrapper.isPremium) {
                    wrapper.badgeClass = 'premium';
                } else if (wrapper.logicType == 'Apex_Plugin') {
                    wrapper.badgeClass = 'plugin';
                } else if (wrapper.logicType == 'Declarative') {
                    wrapper.badgeClass = 'declarative';
                } else {
                    wrapper.badgeClass = 'standard';
                }

                result.add(wrapper);
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch pattern rules: ' + e.getMessage());
        }
    }

    /**
     * @description Returns a single rule by its developer name for editing.
     * @param developerName The DeveloperName of the rule to retrieve
     * @return RuleWrapper containing the rule data
     */
    @AuraEnabled(cacheable=true)
    public static RuleWrapper getRuleByDeveloperName(String developerName) {
        try {
            if (String.isBlank(developerName)) {
                throw new AuraHandledException('Developer name is required.');
            }

            List<Behavior_Pattern_Rule__mdt> rules = [
                SELECT DeveloperName, MasterLabel, Object_API_Name__c, Query_Condition__c,
                       Threshold_Default__c, Fix_Type__c, Fix_Config__c, Logic_Type__c,
                       Apex_Handler_Class__c, Is_Premium__c, Cost_Per_Incident__c, Is_Active__c
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];

            if (rules.isEmpty()) {
                throw new AuraHandledException('Rule not found: ' + developerName);
            }

            Behavior_Pattern_Rule__mdt rule = rules[0];
            Map<String, String> objectLabels = getObjectLabelMap();

            RuleWrapper wrapper = new RuleWrapper();
            wrapper.developerName = rule.DeveloperName;
            wrapper.label = rule.MasterLabel;
            wrapper.objectApiName = rule.Object_API_Name__c;
            wrapper.objectLabel = objectLabels.containsKey(rule.Object_API_Name__c?.toLowerCase())
                ? objectLabels.get(rule.Object_API_Name__c.toLowerCase())
                : rule.Object_API_Name__c;
            wrapper.queryCondition = rule.Query_Condition__c;
            wrapper.thresholdDefault = rule.Threshold_Default__c;
            wrapper.fixType = rule.Fix_Type__c;
            wrapper.fixConfig = rule.Fix_Config__c;
            wrapper.logicType = rule.Logic_Type__c != null ? rule.Logic_Type__c : 'Standard';
            wrapper.apexHandlerClass = rule.Apex_Handler_Class__c;
            wrapper.isPremium = rule.Is_Premium__c == true;
            wrapper.costPerIncident = rule.Cost_Per_Incident__c;
            wrapper.isActive = rule.Is_Active__c != false;

            // Parse Fix_Config__c JSON if present
            if (String.isNotBlank(rule.Fix_Config__c)) {
                try {
                    wrapper.fixConfigParsed = (Map<String, Object>) JSON.deserializeUntyped(rule.Fix_Config__c);
                } catch (Exception e) {
                    wrapper.fixConfigParsed = new Map<String, Object>();
                }
            }

            return wrapper;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch rule: ' + e.getMessage());
        }
    }

    /**
     * @description Returns all accessible SObjects for the object picker.
     *              Includes both standard and custom objects.
     * @return List of ObjectWrapper containing object labels and API names
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectWrapper> getAvailableObjects() {
        try {
            List<ObjectWrapper> result = new List<ObjectWrapper>();
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            for (String objName : globalDescribe.keySet()) {
                Schema.SObjectType sObjType = globalDescribe.get(objName);
                Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();

                // Only include accessible, queryable objects that are not system objects
                if (describeResult.isAccessible() &&
                    describeResult.isQueryable() &&
                    !describeResult.getName().endsWith('__Share') &&
                    !describeResult.getName().endsWith('__History') &&
                    !describeResult.getName().endsWith('__Feed') &&
                    !describeResult.getName().startsWith('Behavior') && // Exclude our own objects
                    !describeResult.getName().startsWith('Identified_Pain_Point')) {

                    ObjectWrapper wrapper = new ObjectWrapper();
                    wrapper.label = describeResult.getLabel();
                    wrapper.value = describeResult.getName();
                    wrapper.isCustom = describeResult.isCustom();
                    result.add(wrapper);
                }
            }

            // Sort by label
            result.sort();

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch available objects: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the list of fields for a given object.
     *              Reuses pattern from ExclusionBuilderController.
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
                    wrapper.isNillable = fieldDescribe.isNillable();
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
     * @param objectName The API name of the object
     * @param fieldName The API name of the picklist field
     * @return List of PicklistOption containing picklist values
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistValues(String objectName, String fieldName) {
        try {
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                throw new AuraHandledException('Object name and field name are required.');
            }

            List<PicklistOption> result = new List<PicklistOption>();

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

            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();

            for (Schema.PicklistEntry entry : picklistEntries) {
                if (entry.isActive()) {
                    PicklistOption option = new PicklistOption();
                    option.label = entry.getLabel();
                    option.value = entry.getValue();
                    result.add(option);
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
     * @description Returns the Fix_Type__c picklist values from the metadata field.
     * @return List of PicklistOption containing fix type options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFixTypeOptions() {
        try {
            List<PicklistOption> result = new List<PicklistOption>();

            Schema.DescribeFieldResult fieldDescribe = Behavior_Pattern_Rule__mdt.Fix_Type__c.getDescribe();
            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();

            for (Schema.PicklistEntry entry : picklistEntries) {
                if (entry.isActive()) {
                    PicklistOption option = new PicklistOption();
                    option.label = entry.getLabel().replace('_', ' ');
                    option.value = entry.getValue();
                    result.add(option);
                }
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch fix type options: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the Logic_Type__c picklist values from the metadata field.
     * @return List of PicklistOption containing logic type options
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLogicTypeOptions() {
        try {
            List<PicklistOption> result = new List<PicklistOption>();

            Schema.DescribeFieldResult fieldDescribe = Behavior_Pattern_Rule__mdt.Logic_Type__c.getDescribe();
            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();

            for (Schema.PicklistEntry entry : picklistEntries) {
                if (entry.isActive()) {
                    PicklistOption option = new PicklistOption();
                    option.label = entry.getLabel().replace('_', ' ');
                    option.value = entry.getValue();
                    result.add(option);
                }
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch logic type options: ' + e.getMessage());
        }
    }

    // ==================== WRITE OPERATIONS ====================

    /**
     * @description Saves a pattern rule using the Metadata API.
     *              Supports both create and update operations.
     * @param ruleJson JSON string containing the rule data
     * @return The deployment job ID
     */
    @AuraEnabled
    public static String savePatternRule(String ruleJson) {
        try {
            if (String.isBlank(ruleJson)) {
                throw new AuraHandledException('Rule data is required.');
            }

            RuleWrapper rule = (RuleWrapper) JSON.deserialize(ruleJson, RuleWrapper.class);

            // Validate required fields
            if (String.isBlank(rule.label)) {
                throw new AuraHandledException('Rule label is required.');
            }
            if (String.isBlank(rule.developerName)) {
                throw new AuraHandledException('Developer name is required.');
            }
            if (String.isBlank(rule.objectApiName)) {
                throw new AuraHandledException('Object API name is required.');
            }
            if (String.isBlank(rule.fixType)) {
                throw new AuraHandledException('Fix type is required.');
            }

            // Validate custom object rules require premium
            if (rule.objectApiName.endsWithIgnoreCase('__c') && !LicenseService.isPremium()) {
                throw new AuraHandledException(
                    'Custom Object rules require a BehaviorIQ Premium license. ' +
                    'Please upgrade to create rules for ' + rule.objectApiName
                );
            }

            // Validate object exists
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(rule.objectApiName.toLowerCase());
            if (sObjType == null) {
                throw new AuraHandledException('Object not found: ' + rule.objectApiName);
            }

            // Build metadata record
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = 'Behavior_Pattern_Rule.' + rule.developerName;
            customMetadata.label = rule.label;

            // Add field values
            addMetadataValue(customMetadata, 'Object_API_Name__c', rule.objectApiName);
            addMetadataValue(customMetadata, 'Query_Condition__c', rule.queryCondition);
            addMetadataValue(customMetadata, 'Threshold_Default__c', rule.thresholdDefault);
            addMetadataValue(customMetadata, 'Fix_Type__c', rule.fixType);
            addMetadataValue(customMetadata, 'Fix_Config__c', rule.fixConfig);
            addMetadataValue(customMetadata, 'Logic_Type__c', rule.logicType);
            addMetadataValue(customMetadata, 'Apex_Handler_Class__c', rule.apexHandlerClass);
            addMetadataValue(customMetadata, 'Is_Premium__c', rule.isPremium);
            addMetadataValue(customMetadata, 'Cost_Per_Incident__c', rule.costPerIncident);
            addMetadataValue(customMetadata, 'Is_Active__c', rule.isActive != false);

            // Deploy
            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, new PatternRuleDeployCallback());

            return String.valueOf(jobId);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save pattern rule: ' + e.getMessage());
        }
    }

    /**
     * @description Deactivates a pattern rule by setting Is_Active__c to false.
     * @param developerName The DeveloperName of the rule to deactivate
     * @return The deployment job ID
     */
    @AuraEnabled
    public static String deactivateRule(String developerName) {
        try {
            if (String.isBlank(developerName)) {
                throw new AuraHandledException('Developer name is required.');
            }

            // Verify rule exists
            List<Behavior_Pattern_Rule__mdt> rules = [
                SELECT DeveloperName, MasterLabel
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];

            if (rules.isEmpty()) {
                throw new AuraHandledException('Rule not found: ' + developerName);
            }

            // Build metadata update
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = 'Behavior_Pattern_Rule.' + developerName;
            customMetadata.label = rules[0].MasterLabel;

            addMetadataValue(customMetadata, 'Is_Active__c', false);

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, new PatternRuleDeployCallback());

            return String.valueOf(jobId);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to deactivate rule: ' + e.getMessage());
        }
    }

    /**
     * @description Reactivates a pattern rule by setting Is_Active__c to true.
     * @param developerName The DeveloperName of the rule to reactivate
     * @return The deployment job ID
     */
    @AuraEnabled
    public static String reactivateRule(String developerName) {
        try {
            if (String.isBlank(developerName)) {
                throw new AuraHandledException('Developer name is required.');
            }

            // Verify rule exists
            List<Behavior_Pattern_Rule__mdt> rules = [
                SELECT DeveloperName, MasterLabel
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :developerName
                LIMIT 1
            ];

            if (rules.isEmpty()) {
                throw new AuraHandledException('Rule not found: ' + developerName);
            }

            // Build metadata update
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = 'Behavior_Pattern_Rule.' + developerName;
            customMetadata.label = rules[0].MasterLabel;

            addMetadataValue(customMetadata, 'Is_Active__c', true);

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, new PatternRuleDeployCallback());

            return String.valueOf(jobId);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to reactivate rule: ' + e.getMessage());
        }
    }

    // ==================== VALIDATION & TESTING ====================

    /**
     * @description Validates a query condition for syntax and FLS.
     * @param objectName The target object API name
     * @param condition The SOQL WHERE clause to validate
     * @return ValidationResult with validation status and details
     */
    @AuraEnabled
    public static ValidationResult validateQueryCondition(String objectName, String condition) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.referencedFields = new List<String>();
        result.inaccessibleFields = new List<String>();

        try {
            if (String.isBlank(objectName)) {
                result.isValid = false;
                result.errorMessage = 'Object name is required.';
                return result;
            }

            if (String.isBlank(condition)) {
                // Empty condition is valid (matches all records)
                return result;
            }

            // Get object schema
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(objectName.toLowerCase());

            if (sObjType == null) {
                result.isValid = false;
                result.errorMessage = 'Object not found: ' + objectName;
                return result;
            }

            Schema.DescribeSObjectResult describeResult = sObjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            // Extract field names from condition
            Set<String> extractedFields = extractFieldsFromCondition(condition);
            result.referencedFields.addAll(extractedFields);

            // Validate each field
            for (String fieldRef : extractedFields) {
                // Handle relationship fields (e.g., Account.Name)
                if (fieldRef.contains('.')) {
                    // Skip validation for relationship fields for now
                    continue;
                }

                Schema.SObjectField field = fieldMap.get(fieldRef.toLowerCase());

                if (field == null) {
                    result.isValid = false;
                    result.inaccessibleFields.add(fieldRef);
                    result.errorMessage = 'Field not found: ' + fieldRef;
                } else if (!field.getDescribe().isAccessible()) {
                    result.isValid = false;
                    result.inaccessibleFields.add(fieldRef);
                    result.errorMessage = 'Field not accessible: ' + fieldRef;
                }
            }

            // Try to execute a count query to validate syntax
            if (result.isValid) {
                try {
                    String testQuery = 'SELECT COUNT() FROM ' + objectName + ' WHERE ' + condition + ' LIMIT 1';
                    Database.countQuery(testQuery);
                } catch (Exception e) {
                    result.isValid = false;
                    result.errorMessage = 'Invalid query syntax: ' + e.getMessage();
                }
            }

            return result;

        } catch (Exception e) {
            result.isValid = false;
            result.errorMessage = 'Validation error: ' + e.getMessage();
            return result;
        }
    }

    /**
     * @description Tests a pattern query and returns the count of matching records.
     * @param objectName The target object API name
     * @param condition The SOQL WHERE clause
     * @return The count of matching records
     */
    @AuraEnabled
    public static Integer testPatternQuery(String objectName, String condition) {
        try {
            if (String.isBlank(objectName)) {
                throw new AuraHandledException('Object name is required.');
            }

            // Validate object exists and is accessible
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType sObjType = globalDescribe.get(objectName.toLowerCase());

            if (sObjType == null) {
                throw new AuraHandledException('Object not found: ' + objectName);
            }

            if (!sObjType.getDescribe().isAccessible()) {
                throw new AuraHandledException('Object not accessible: ' + objectName);
            }

            // Build and execute count query
            String query = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objectName);

            if (String.isNotBlank(condition)) {
                query += ' WHERE ' + condition;
            }

            return Database.countQuery(query);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Query test failed: ' + e.getMessage());
        }
    }

    // ==================== HELPER METHODS ====================

    /**
     * @description Helper to add a field value to custom metadata.
     */
    private static void addMetadataValue(Metadata.CustomMetadata md, String fieldName, Object value) {
        Metadata.CustomMetadataValue mdValue = new Metadata.CustomMetadataValue();
        mdValue.field = fieldName;
        mdValue.value = value;
        md.values.add(mdValue);
    }

    /**
     * @description Helper to get object labels from schema.
     */
    private static Map<String, String> getObjectLabelMap() {
        Map<String, String> result = new Map<String, String>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describeResult = globalDescribe.get(objName).getDescribe();
            result.put(objName, describeResult.getLabel());
        }

        return result;
    }

    /**
     * @description Extracts field names from a SOQL WHERE condition.
     */
    private static Set<String> extractFieldsFromCondition(String condition) {
        Set<String> fields = new Set<String>();

        if (String.isBlank(condition)) {
            return fields;
        }

        // List of SOQL keywords and operators to exclude
        Set<String> excludeTokens = new Set<String>{
            'AND', 'OR', 'NOT', 'IN', 'LIKE', 'NULL', 'TRUE', 'FALSE',
            'TODAY', 'YESTERDAY', 'TOMORROW', 'THIS_WEEK', 'LAST_WEEK', 'NEXT_WEEK',
            'THIS_MONTH', 'LAST_MONTH', 'NEXT_MONTH', 'THIS_QUARTER', 'LAST_QUARTER',
            'NEXT_QUARTER', 'THIS_YEAR', 'LAST_YEAR', 'NEXT_YEAR', 'THIS_FISCAL_QUARTER',
            'LAST_FISCAL_QUARTER', 'NEXT_FISCAL_QUARTER', 'THIS_FISCAL_YEAR',
            'LAST_FISCAL_YEAR', 'NEXT_FISCAL_YEAR', 'LAST_N_DAYS', 'NEXT_N_DAYS',
            'LAST_N_WEEKS', 'NEXT_N_WEEKS', 'LAST_N_MONTHS', 'NEXT_N_MONTHS',
            'LAST_N_QUARTERS', 'NEXT_N_QUARTERS', 'LAST_N_YEARS', 'NEXT_N_YEARS',
            'INCLUDES', 'EXCLUDES'
        };

        // Remove string literals
        String conditionWithoutStrings = condition.replaceAll('\'[^\']*\'', ' ');

        // Tokenize
        String tokenized = conditionWithoutStrings.replaceAll('[(),:<>=!]', ' ');
        List<String> tokens = tokenized.split('\\s+');

        for (String token : tokens) {
            token = token.trim();

            if (String.isBlank(token)) {
                continue;
            }

            // Skip if it's a keyword
            if (excludeTokens.contains(token.toUpperCase())) {
                continue;
            }

            // Skip if it's a number
            if (token.isNumeric()) {
                continue;
            }

            // Skip date literal parameters (e.g., the "30" in LAST_N_DAYS:30)
            if (Pattern.matches('^\\d+$', token)) {
                continue;
            }

            // This is likely a field name
            fields.add(token);
        }

        return fields;
    }

    // ==================== CALLBACK CLASS ====================

    /**
     * @description Callback handler for metadata deployment.
     */
    public class PatternRuleDeployCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            if (result.status == Metadata.DeployStatus.Succeeded) {
                System.debug('Pattern Rule deployment succeeded.');
            } else {
                System.debug('Pattern Rule deployment failed: ' + result.errorMessage);
            }
        }
    }

    // ==================== WRAPPER CLASSES ====================

    /**
     * @description Wrapper class for pattern rule data.
     */
    public class RuleWrapper {
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String queryCondition;
        @AuraEnabled public Decimal thresholdDefault;
        @AuraEnabled public String fixType;
        @AuraEnabled public String fixConfig;
        @AuraEnabled public Map<String, Object> fixConfigParsed;
        @AuraEnabled public String logicType;
        @AuraEnabled public String apexHandlerClass;
        @AuraEnabled public Boolean isPremium;
        @AuraEnabled public Decimal costPerIncident;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String badgeClass;
    }

    /**
     * @description Wrapper class for object metadata.
     */
    public class ObjectWrapper implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean isCustom;

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
        @AuraEnabled public Boolean isNillable;

        public Integer compareTo(Object compareTo) {
            FieldWrapper other = (FieldWrapper) compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.compareTo(other.label);
        }
    }

    /**
     * @description Wrapper class for picklist options.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Wrapper class for validation results.
     */
    public class ValidationResult {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public List<String> referencedFields;
        @AuraEnabled public List<String> inaccessibleFields;
    }
}
