/**
 * @description       : Controller for the BehaviorIQ Settings LWC. Handles reading and writing Custom Metadata.
 * @author            : Gemini
 * @group             : BehaviorIQ
**/
public with sharing class BehaviorSettingsController {

    private static final String METADATA_RECORD_NAME = 'Default';
    private static final String METADATA_FULL_NAME = 'Behavior_Setting.Default';

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
}