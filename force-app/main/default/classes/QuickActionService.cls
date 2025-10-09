/**
 * @description Service class to programmatically create and deploy Quick Actions.
 * VERSION 3.0: Now automatically adds the created Quick Action to the default page layout.
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
        String fullActionName = objectApiName + '.' + actionName;

        try {
            MetadataService.MetadataPort service = createService();

            // Step 1: Create the Quick Action metadata component (same as before)
            MetadataService.QuickAction quickAction = new MetadataService.QuickAction();
            quickAction.fullName = fullActionName;
            quickAction.label = actionLabel;
            quickAction.type_x = 'Update';
            quickAction.optionsCreateFeedItem = false;
            
            MetadataService.QuickActionLayout layout = new MetadataService.QuickActionLayout();
            layout.layoutSectionStyle = 'TwoColumnsLeftToRight';
            layout.quickActionLayoutColumns = new List<MetadataService.QuickActionLayoutColumn>{ new MetadataService.QuickActionLayoutColumn() };
            layout.quickActionLayoutColumns[0].quickActionLayoutItems = new List<MetadataService.QuickActionLayoutItem>();
            quickAction.quickActionLayout = layout;
            
            // Step 2: Deploy the Quick Action
            List<MetadataService.SaveResult> createResults = service.createMetadata(
                new List<MetadataService.Metadata>{ quickAction }
            );

            // Step 3: Handle the result and add to layout on success
            for (MetadataService.SaveResult res : createResults) {
                if (res.success) {
                    // --- NEW LOGIC ---
                    // On success, automatically add the action to the page layout
                    addQuickActionToLayout(service, objectApiName, actionName);
                    // --- END NEW LOGIC ---

                    result.isSuccess = true;
                    result.message = 'Quick Action "' + actionLabel + '" was created and added to the page layout successfully!';
                    result.actionName = res.fullName;
                } else {
                    result.isSuccess = false;
                    result.message = 'Error creating Quick Action: ' + res.errors[0].message;
                }
            }
        } catch (Exception e) {
            result.isSuccess = false;
            result.message = 'An unexpected error occurred: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'QuickActionService Error: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
        }
        return result;
    }

    /**
     * @description Adds a newly created Quick Action to the default layout for an object.
     */
    @TestVisible
    private static void addQuickActionToLayout(MetadataService.MetadataPort service, String objectApiName, String actionName) {
        // Assume the default layout name is in the format 'Object-Layout'
        String layoutName = objectApiName + '-' + objectApiName + ' Layout';

        // 1. Read the existing layout metadata
        MetadataService.Layout layoutMetadata = (MetadataService.Layout) service.readMetadata('Layout', new String[] { layoutName }).getRecords()[0];

        // 2. Add the new quick action to the list
        if (layoutMetadata.quickActionList == null) {
            layoutMetadata.quickActionList = new MetadataService.QuickActionList();
            layoutMetadata.quickActionList.quickActionListItems = new List<MetadataService.QuickActionListItem>();
        }
        
        MetadataService.QuickActionListItem newActionItem = new MetadataService.QuickActionListItem();
        newActionItem.quickActionName = objectApiName + '.' + actionName;
        layoutMetadata.quickActionList.quickActionListItems.add(newActionItem);

        // 3. Update the layout
        service.updateMetadata(new List<MetadataService.Metadata>{ layoutMetadata });
    }
    
    /**
     * @description Helper to create and configure the MetadataPort service.
     */
    private static MetadataService.MetadataPort createService() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        service.endpoint_x = 'callout:AgentForce_Metadata_API';
        return service;
    }
}