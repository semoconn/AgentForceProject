/**
 * @description       : Controller for the BehaviorIQ Settings LWC. Handles reading and writing
 *                      BehaviorIQ_Configuration__c custom object settings for detection thresholds.
 * @author            : BehaviorIQ
 * @group             : BehaviorIQ
**/
public with sharing class BehaviorSettingsController {

    private static final String CONFIG_RECORD_NAME = 'Default';

    // Default threshold values for Detection Thresholds
    public static final Integer DEFAULT_STALE_CASE_THRESHOLD = 30;
    public static final Integer DEFAULT_STALE_OPP_THRESHOLD = 90;
    public static final Integer DEFAULT_UNASSIGNED_LEAD_HOURS = 48;
    public static final Integer DEFAULT_LEAD_HOARDING_DAYS = 5;
    public static final Integer DEFAULT_HIGH_VALUE_INACTIVITY_DAYS = 14;
    public static final Decimal DEFAULT_HIGH_VALUE_AMOUNT = 50000;
    public static final Integer DEFAULT_CONTRACT_EXPIRY_DAYS = 30;

    // Default retention values for Data Retention
    public static final Integer DEFAULT_RAW_LOG_RETENTION_DAYS = 14;
    public static final Integer DEFAULT_SUMMARY_RETENTION_DAYS = 365;

    /**
     * @description Retrieves all detection threshold settings from BehaviorIQ_Configuration__c.
     *              Returns a wrapper with the threshold values, using defaults if no record exists.
     * @return ConfigSettingsWrapper containing the current threshold settings
     */
    @AuraEnabled(cacheable=true)
    public static ConfigSettingsWrapper getConfigSettings() {
        try {
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                throw new AuraHandledException('You do not have permission to access BehaviorIQ Configuration.');
            }

            // Use USER_MODE for sharing/FLS enforcement, then stripInaccessible for additional protection
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Id, Name,
                       Stale_Case_Threshold__c,
                       Stale_Opportunity_Threshold__c,
                       Unassigned_Lead_Hours__c,
                       Lead_Hoarding_Days__c,
                       High_Value_Inactivity_Days__c,
                       High_Value_Amount_Threshold__c,
                       Contract_Expiry_Days__c,
                       Raw_Log_Retention_Days__c,
                       Summary_Retention_Days__c
                FROM BehaviorIQ_Configuration__c
                WITH USER_MODE
                LIMIT 1
            ];

            // Apply field-level security using stripInaccessible
            SObjectAccessDecision securityDecision = Security.stripInaccessible(
                AccessType.READABLE,
                configs
            );
            List<BehaviorIQ_Configuration__c> accessibleConfigs = (List<BehaviorIQ_Configuration__c>) securityDecision.getRecords();

            ConfigSettingsWrapper wrapper = new ConfigSettingsWrapper();

            if (!accessibleConfigs.isEmpty()) {
                BehaviorIQ_Configuration__c config = accessibleConfigs[0];
                Set<String> removedFields = securityDecision.getRemovedFields().get('BehaviorIQ_Configuration__c');

                wrapper.staleCaseThreshold = getIntegerValue(config.Stale_Case_Threshold__c, removedFields, 'Stale_Case_Threshold__c', DEFAULT_STALE_CASE_THRESHOLD);
                wrapper.staleOpportunityThreshold = getIntegerValue(config.Stale_Opportunity_Threshold__c, removedFields, 'Stale_Opportunity_Threshold__c', DEFAULT_STALE_OPP_THRESHOLD);
                wrapper.unassignedLeadHours = getIntegerValue(config.Unassigned_Lead_Hours__c, removedFields, 'Unassigned_Lead_Hours__c', DEFAULT_UNASSIGNED_LEAD_HOURS);
                wrapper.leadHoardingDays = getIntegerValue(config.Lead_Hoarding_Days__c, removedFields, 'Lead_Hoarding_Days__c', DEFAULT_LEAD_HOARDING_DAYS);
                wrapper.highValueInactivityDays = getIntegerValue(config.High_Value_Inactivity_Days__c, removedFields, 'High_Value_Inactivity_Days__c', DEFAULT_HIGH_VALUE_INACTIVITY_DAYS);
                wrapper.highValueAmountThreshold = getDecimalValue(config.High_Value_Amount_Threshold__c, removedFields, 'High_Value_Amount_Threshold__c', DEFAULT_HIGH_VALUE_AMOUNT);
                wrapper.contractExpiryDays = getIntegerValue(config.Contract_Expiry_Days__c, removedFields, 'Contract_Expiry_Days__c', DEFAULT_CONTRACT_EXPIRY_DAYS);
                wrapper.rawLogRetentionDays = getIntegerValue(config.Raw_Log_Retention_Days__c, removedFields, 'Raw_Log_Retention_Days__c', DEFAULT_RAW_LOG_RETENTION_DAYS);
                wrapper.summaryRetentionDays = getIntegerValue(config.Summary_Retention_Days__c, removedFields, 'Summary_Retention_Days__c', DEFAULT_SUMMARY_RETENTION_DAYS);
                wrapper.recordId = config.Id;
            } else {
                // Return defaults if no record exists
                wrapper.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
                wrapper.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
                wrapper.unassignedLeadHours = DEFAULT_UNASSIGNED_LEAD_HOURS;
                wrapper.leadHoardingDays = DEFAULT_LEAD_HOARDING_DAYS;
                wrapper.highValueInactivityDays = DEFAULT_HIGH_VALUE_INACTIVITY_DAYS;
                wrapper.highValueAmountThreshold = DEFAULT_HIGH_VALUE_AMOUNT;
                wrapper.contractExpiryDays = DEFAULT_CONTRACT_EXPIRY_DAYS;
                wrapper.rawLogRetentionDays = DEFAULT_RAW_LOG_RETENTION_DAYS;
                wrapper.summaryRetentionDays = DEFAULT_SUMMARY_RETENTION_DAYS;
                wrapper.recordId = null;
            }

            return wrapper;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch configuration settings: ' + e.getMessage());
        }
    }

    /**
     * @description Helper method to safely get Integer value from config field with FLS check
     */
    private static Integer getIntegerValue(Decimal fieldValue, Set<String> removedFields, String fieldName, Integer defaultValue) {
        if (removedFields != null && removedFields.contains(fieldName)) {
            return defaultValue;
        }
        return fieldValue != null ? Integer.valueOf(fieldValue) : defaultValue;
    }

    /**
     * @description Helper method to safely get Decimal value from config field with FLS check
     */
    private static Decimal getDecimalValue(Decimal fieldValue, Set<String> removedFields, String fieldName, Decimal defaultValue) {
        if (removedFields != null && removedFields.contains(fieldName)) {
            return defaultValue;
        }
        return fieldValue != null ? fieldValue : defaultValue;
    }

    /**
     * @description Saves all detection threshold settings to BehaviorIQ_Configuration__c.
     *              Creates the record if it doesn't exist, otherwise updates the existing one.
     * @param staleCaseThreshold Days for stale Case detection
     * @param staleOpportunityThreshold Days for stale Opportunity detection
     * @param unassignedLeadHours Hours before unassigned leads are flagged
     * @param leadHoardingDays Days before lead hoarding is flagged
     * @param highValueInactivityDays Days of inactivity for high-value opportunities
     * @param highValueAmountThreshold Amount threshold for "high value" opportunities
     * @param contractExpiryDays Days before contract expiry to flag
     * @param rawLogRetentionDays Days to retain raw behavior logs
     * @param summaryRetentionDays Days to retain summary/snapshot data
     * @return The Id of the upserted configuration record
     */
    @AuraEnabled
    public static Id saveConfigSettings(
        Integer staleCaseThreshold,
        Integer staleOpportunityThreshold,
        Integer unassignedLeadHours,
        Integer leadHoardingDays,
        Integer highValueInactivityDays,
        Decimal highValueAmountThreshold,
        Integer contractExpiryDays,
        Integer rawLogRetentionDays,
        Integer summaryRetentionDays
    ) {
        try {
            // Validate inputs
            validateThreshold(staleCaseThreshold, 'Stale Case Threshold', 1, 999);
            validateThreshold(staleOpportunityThreshold, 'Stale Opportunity Threshold', 1, 999);
            validateThreshold(unassignedLeadHours, 'Unassigned Lead Hours', 1, 720);
            validateThreshold(leadHoardingDays, 'Lead Hoarding Days', 1, 999);
            validateThreshold(highValueInactivityDays, 'High-Value Inactivity Days', 1, 999);
            validateThreshold(contractExpiryDays, 'Contract Expiry Days', 1, 999);
            validateThreshold(rawLogRetentionDays, 'Raw Log Retention Days', 7, 90);
            validateThreshold(summaryRetentionDays, 'Summary Retention Days', 30, 730);

            if (highValueAmountThreshold == null || highValueAmountThreshold < 1 || highValueAmountThreshold > 999999999) {
                throw new AuraHandledException('High-Value Amount Threshold must be between 1 and 999,999,999.');
            }

            // Check object permissions
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isCreateable() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to modify BehaviorIQ Configuration.');
            }

            // Try to find existing record with USER_MODE for security
            List<BehaviorIQ_Configuration__c> existingConfigs = [
                SELECT Id
                FROM BehaviorIQ_Configuration__c
                WITH USER_MODE
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

            // Set all threshold values
            configToSave.Stale_Case_Threshold__c = staleCaseThreshold;
            configToSave.Stale_Opportunity_Threshold__c = staleOpportunityThreshold;
            configToSave.Unassigned_Lead_Hours__c = unassignedLeadHours;
            configToSave.Lead_Hoarding_Days__c = leadHoardingDays;
            configToSave.High_Value_Inactivity_Days__c = highValueInactivityDays;
            configToSave.High_Value_Amount_Threshold__c = highValueAmountThreshold;
            configToSave.Contract_Expiry_Days__c = contractExpiryDays;
            configToSave.Raw_Log_Retention_Days__c = rawLogRetentionDays;
            configToSave.Summary_Retention_Days__c = summaryRetentionDays;

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
            throw new AuraHandledException('Failed to save configuration settings: ' + e.getMessage());
        }
    }

    /**
     * @description Helper method to validate threshold values
     */
    private static void validateThreshold(Integer value, String fieldName, Integer minValue, Integer maxValue) {
        if (value == null || value < minValue || value > maxValue) {
            throw new AuraHandledException(fieldName + ' must be between ' + minValue + ' and ' + maxValue + '.');
        }
    }

    /**
     * @description Wrapper class for configuration settings to be returned to LWC
     */
    public class ConfigSettingsWrapper {
        @AuraEnabled public Integer staleCaseThreshold;
        @AuraEnabled public Integer staleOpportunityThreshold;
        @AuraEnabled public Integer unassignedLeadHours;
        @AuraEnabled public Integer leadHoardingDays;
        @AuraEnabled public Integer highValueInactivityDays;
        @AuraEnabled public Decimal highValueAmountThreshold;
        @AuraEnabled public Integer contractExpiryDays;
        @AuraEnabled public Integer rawLogRetentionDays;
        @AuraEnabled public Integer summaryRetentionDays;
        @AuraEnabled public Id recordId;
    }

    /**
     * @description Validates if a custom object rule can be created.
     * Custom objects require Premium license for pattern rule creation.
     * @param objectApiName The API name of the object to validate
     * @return Boolean true if the object is valid for rule creation
     * @throws AuraHandledException if custom object without Premium license or object not found
     */
    @AuraEnabled
    public static Boolean validateCustomObjectRule(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }

        // Check if this is a custom object (ends with __c)
        Boolean isCustomObject = objectApiName.endsWithIgnoreCase('__c');

        if (isCustomObject) {
            if (!LicenseService.isPremium()) {
                throw new AuraHandledException(
                    'Custom Object rules require a BehaviorIQ Premium license. ' +
                    'Please upgrade to create rules for ' + objectApiName
                );
            }
        }

        // Verify the object exists and is accessible
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType sObjType = globalDescribe.get(objectApiName.toLowerCase());

        if (sObjType == null) {
            throw new AuraHandledException('Object not found: ' + objectApiName);
        }

        if (!sObjType.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have access to: ' + objectApiName);
        }

        return true;
    }
}
