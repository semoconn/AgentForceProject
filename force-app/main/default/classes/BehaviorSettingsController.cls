/**
 * @description       : Controller for the BehaviorIQ Settings LWC. Handles reading and writing Custom Metadata
 *                      and BehaviorIQ_Configuration__c custom object settings.
 * @author            : Gemini
 * @group             : BehaviorIQ
**/
public with sharing class BehaviorSettingsController {

    private static final String METADATA_RECORD_NAME = 'Default';
    private static final String METADATA_FULL_NAME = 'Behavior_Setting.Default';
    private static final String CONFIG_RECORD_NAME = 'Default';

    // Default threshold values for Pattern Analysis
    public static final Integer DEFAULT_STALE_CASE_THRESHOLD = 30;
    public static final Integer DEFAULT_STALE_OPP_THRESHOLD = 90;

    @AuraEnabled(cacheable=true)
    public static Behavior_Setting__mdt getBehaviorSettings() {
        try {
            return [
                SELECT Id, 
                       Stale_Opportunity_Days__c, 
                       Unassigned_Lead_Age_Hours__c, 
                       Sequential_Action_Threshold__c,
                       Stale_Case_Days__c  // NEW: 4th Field
                FROM Behavior_Setting__mdt 
                WHERE DeveloperName = :METADATA_RECORD_NAME 
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Unable to fetch settings: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String updateBehaviorSettings(Integer staleDays, Integer leadHours, Integer seqThreshold, Integer caseDays) {
        try {
            Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
            customMetadata.fullName = METADATA_FULL_NAME;
            customMetadata.label = METADATA_RECORD_NAME; 

            // 1. Opportunity
            Metadata.CustomMetadataValue staleDaysField = new Metadata.CustomMetadataValue();
            staleDaysField.field = 'Stale_Opportunity_Days__c';
            staleDaysField.value = staleDays;
            customMetadata.values.add(staleDaysField);

            // 2. Lead
            Metadata.CustomMetadataValue leadHoursField = new Metadata.CustomMetadataValue();
            leadHoursField.field = 'Unassigned_Lead_Age_Hours__c';
            leadHoursField.value = leadHours;
            customMetadata.values.add(leadHoursField);

            // 3. Bot/Action
            Metadata.CustomMetadataValue seqThresholdField = new Metadata.CustomMetadataValue();
            seqThresholdField.field = 'Sequential_Action_Threshold__c';
            seqThresholdField.value = seqThreshold;
            customMetadata.values.add(seqThresholdField);

            // 4. NEW: Case
            Metadata.CustomMetadataValue caseDaysField = new Metadata.CustomMetadataValue();
            caseDaysField.field = 'Stale_Case_Days__c';
            caseDaysField.value = caseDays;
            customMetadata.values.add(caseDaysField);

            Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
            mdContainer.addMetadata(customMetadata);

            Id jobId = Metadata.Operations.enqueueDeployment(mdContainer, new BehaviorSettingsUpdateCallback());
            
            return String.valueOf(jobId);

        } catch (Exception e) {
            throw new AuraHandledException('Failed to queue setting update: ' + e.getMessage());
        }
    }

    public class BehaviorSettingsUpdateCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            if (result.status == Metadata.DeployStatus.Succeeded) {
                System.debug('BehaviorIQ Settings updated successfully.');
            } else {
                System.debug('BehaviorIQ Settings update failed: ' + result.errorMessage);
            }
        }
    }

    // ==================== CONFIGURATION OBJECT METHODS (Sprint 3.4) ====================

    /**
     * @description Retrieves the Pattern Analysis configuration settings from BehaviorIQ_Configuration__c.
     *              Returns a wrapper with the threshold values, creating defaults if no record exists.
     * @return ConfigSettingsWrapper containing the current threshold settings
     */
    @AuraEnabled(cacheable=true)
    public static ConfigSettingsWrapper getConfigSettings() {
        try {
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                throw new AuraHandledException('You do not have permission to access BehaviorIQ Configuration.');
            }

            // Query without WITH SECURITY_ENFORCED since this is admin configuration
            // and the fields may not have FLS set up yet. Use stripInaccessible for protection.
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Id, Name, Stale_Case_Threshold__c, Stale_Opportunity_Threshold__c
                FROM BehaviorIQ_Configuration__c
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
                // Check if fields were stripped due to FLS - use defaults if so
                Set<String> removedFields = securityDecision.getRemovedFields().get('BehaviorIQ_Configuration__c');

                if (removedFields == null || !removedFields.contains('Stale_Case_Threshold__c')) {
                    wrapper.staleCaseThreshold = config.Stale_Case_Threshold__c != null
                        ? Integer.valueOf(config.Stale_Case_Threshold__c)
                        : DEFAULT_STALE_CASE_THRESHOLD;
                } else {
                    wrapper.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
                }

                if (removedFields == null || !removedFields.contains('Stale_Opportunity_Threshold__c')) {
                    wrapper.staleOpportunityThreshold = config.Stale_Opportunity_Threshold__c != null
                        ? Integer.valueOf(config.Stale_Opportunity_Threshold__c)
                        : DEFAULT_STALE_OPP_THRESHOLD;
                } else {
                    wrapper.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
                }

                wrapper.recordId = config.Id;
            } else {
                // Return defaults if no record exists
                wrapper.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
                wrapper.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
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
     * @description Saves the Pattern Analysis configuration settings to BehaviorIQ_Configuration__c.
     *              Creates the record if it doesn't exist, otherwise updates the existing one.
     * @param staleCaseThreshold The number of days for stale Case detection
     * @param staleOpportunityThreshold The number of days for stale Opportunity detection
     * @return The Id of the upserted configuration record
     */
    @AuraEnabled
    public static Id saveConfigSettings(Integer staleCaseThreshold, Integer staleOpportunityThreshold) {
        try {
            // Validate inputs
            if (staleCaseThreshold == null || staleCaseThreshold < 1 || staleCaseThreshold > 999) {
                throw new AuraHandledException('Stale Case Threshold must be between 1 and 999 days.');
            }
            if (staleOpportunityThreshold == null || staleOpportunityThreshold < 1 || staleOpportunityThreshold > 999) {
                throw new AuraHandledException('Stale Opportunity Threshold must be between 1 and 999 days.');
            }

            // Check object permissions
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isCreateable() ||
                !Schema.sObjectType.BehaviorIQ_Configuration__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to modify BehaviorIQ Configuration.');
            }

            // Try to find existing record
            List<BehaviorIQ_Configuration__c> existingConfigs = [
                SELECT Id, Stale_Case_Threshold__c, Stale_Opportunity_Threshold__c
                FROM BehaviorIQ_Configuration__c
                LIMIT 1
            ];

            BehaviorIQ_Configuration__c configToSave;

            if (!existingConfigs.isEmpty()) {
                // Update existing record
                configToSave = existingConfigs[0];
            } else {
                // Create new record
                configToSave = new BehaviorIQ_Configuration__c(
                    Name = CONFIG_RECORD_NAME
                );
            }

            // Set the threshold values
            configToSave.Stale_Case_Threshold__c = staleCaseThreshold;
            configToSave.Stale_Opportunity_Threshold__c = staleOpportunityThreshold;

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
     * @description Wrapper class for configuration settings to be returned to LWC
     */
    public class ConfigSettingsWrapper {
        @AuraEnabled public Integer staleCaseThreshold;
        @AuraEnabled public Integer staleOpportunityThreshold;
        @AuraEnabled public Id recordId;
    }
}