/**
 * @description Service class to programmatically create Quick Actions using the Metadata API.
 * VERSION 2.0: Updated to use a Named Credential for secure and reliable authentication.
 */
public with sharing class QuickActionService {

    public class QuickActionResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public String actionName;
    }

    @AuraEnabled
    public static QuickActionResult createSimpleUpdateAction(String objectApiName, String actionLabel) {
        QuickActionResult result = new QuickActionResult();
        String actionName = actionLabel.replaceAll('[^a-zA-Z0-9]', '_');

        try {
            // Step 1: Create the Metadata API service and set the endpoint
            MetadataService.MetadataPort service = new MetadataService.MetadataPort();
            // ✅ FIX: Use the Named Credential for the endpoint.
            // This tells Salesforce to handle authentication automatically and securely.
            service.endpoint_x = 'callout:AgentForce_Metadata_API';

            // Step 2: Create the Quick Action metadata component (same as before)
            MetadataService.QuickAction quickAction = new MetadataService.QuickAction();
            quickAction.fullName = objectApiName + '.' + actionName;
            quickAction.label = actionLabel;
            quickAction.type_x = 'Update';
            quickAction.optionsCreateFeedItem = false;
            
            MetadataService.QuickActionLayout layout = new MetadataService.QuickActionLayout();
            layout.layoutSectionStyle = 'TwoColumnsLeftToRight';
            layout.quickActionLayoutColumns = new List<MetadataService.QuickActionLayoutColumn>();
            layout.quickActionLayoutColumns.add(new MetadataService.QuickActionLayoutColumn());
            layout.quickActionLayoutColumns.get(0).quickActionLayoutItems = new List<MetadataService.QuickActionLayoutItem>();
            quickAction.quickActionLayout = layout;
            
            // Step 3: Deploy the Quick Action (no session header needed)
            List<MetadataService.SaveResult> results = service.createMetadata(
                new List<MetadataService.Metadata>{ quickAction }
            );

            // Step 4: Handle the result (same as before)
            for (MetadataService.SaveResult res : results) {
                if (res.success) {
                    result.isSuccess = true;
                    result.message = 'Quick Action "' + actionLabel + '" created successfully. Please add it to the page layout.';
                    result.actionName = res.fullName;
                } else {
                    result.isSuccess = false;
                    result.message = 'Error: ' + res.errors[0].message;
                }
            }
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'An unexpected error occurred: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'QuickActionService Error: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
        }
        return result;
    }
}

