/**
 * @description Service class to programmatically create Quick Actions using the Metadata API.
 * This is an advanced technique that allows your application to modify an org's configuration.
 * NOTE: This requires a special permission set to be granted to the user running it.
 */
public with sharing class QuickActionService {

    // The endpoint for the Metadata API
    private static final String METADATA_ENDPOINT = URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/60.0';

    /**
     * @description Wrapper class to hold the result of the Quick Action creation.
     */
    public class QuickActionResult {
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String message;
        @AuraEnabled public String actionName;
    }

    /**
     * @description Main method callable from an LWC to create a simple "Update a Record" Quick Action.
     * @param objectApiName - The API name of the object (e.g., 'Contact').
     * @param actionLabel   - The user-friendly label for the action (e.g., 'Log a Call').
     * @return              - A QuickActionResult object.
     */
    @AuraEnabled
    public static QuickActionResult createSimpleUpdateAction(String objectApiName, String actionLabel) {
        QuickActionResult result = new QuickActionResult();
        String actionName = actionLabel.replaceAll('[^a-zA-Z0-9]', '_'); // Create a valid API name

        try {
            // Step 1: Create the Quick Action metadata component
            MetadataService.QuickAction quickAction = new MetadataService.QuickAction();
            quickAction.fullName = objectApiName + '.' + actionName;
            quickAction.label = actionLabel;
            quickAction.type_x = 'Update'; // This defines it as an "Update a Record" action
            quickAction.optionsCreateFeedItem = false; // We don't want a Chatter post
            
            // This is required for Update actions
            MetadataService.QuickActionLayout layout = new MetadataService.QuickActionLayout();
            layout.layoutSectionStyle = 'TwoColumnsLeftToRight';
            layout.quickActionLayoutColumns = new List<MetadataService.QuickActionLayoutColumn>();
            layout.quickActionLayoutColumns.add(new MetadataService.QuickActionLayoutColumn());
            layout.quickActionLayoutColumns.get(0).quickActionLayoutItems = new List<MetadataService.QuickActionLayoutItem>();
            quickAction.quickActionLayout = layout;

            // Step 2: Create the service and session header
            MetadataService.MetadataPort service = createService();
            
            // Step 3: Deploy the new Quick Action
            List<MetadataService.SaveResult> results = service.createMetadata(
                new List<MetadataService.Metadata>{ quickAction }
            );

            // Step 4: Handle the result
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
        }
        return result;
    }

    /**
     * @description Creates an instance of the MetadataPort service to interact with the API.
     */
    private static MetadataService.MetadataPort createService() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();
        service.endpoint_x = METADATA_ENDPOINT;
        return service;
    }
}
