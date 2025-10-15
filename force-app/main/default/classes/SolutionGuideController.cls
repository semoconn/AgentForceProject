/**
 * @description       : Provides the content for the Solution Guide modal in the OrgPulse dashboard.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-15-2025
 * @last modified by  : Gemini
**/
public with sharing class SolutionGuideController {

    /**
     * @description Returns a structured solution guide based on the unique key of a pain point.
     * @param       painPointKey The Unique_Key__c of the Identified_Pain_Point__c record.
     * @return      Map<String, Object> A map containing the title and a list of step-by-step instructions.
    **/
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSolutionGuide(String painPointKey) {
        Map<String, Object> solution = new Map<String, Object>();

        // In a future premium version, this could query a custom object for dynamic solutions.
        // For the Lite version, we'll define the solutions directly in Apex.
        if (painPointKey == 'Sequential_Action_Contact_Task') {
            solution.put('title', 'Solution: Create a Quick Action on Contacts');
            solution.put('steps', new List<String>{
                'Navigate to Setup > Object Manager > Contact.',
                'Go to "Buttons, Links, and Actions" and click "New Action".',
                'Action Type: "Create a Record"',
                'Target Object: "Task"',
                'Label: "New Follow-Up Task" (the name will be New_Follow_Up_Task)',
                'Click "Save".',
                'On the next screen, you can predefine fields. For example, set the "Subject" to "Follow-up". You can also hide fields you don\'t want users to see.',
                'Navigate back to the Contact object in Object Manager and go to "Page Layouts".',
                'Edit your desired page layout(s).',
                'In the palette, select "Mobile & Lightning Actions", find your "New Follow-Up Task" action, and drag it into the "Salesforce Mobile and Lightning Experience Actions" section.',
                'Click "Save". Your users will now see this button on Contact pages.'
            });
        } else {
            // Default message if no specific guide is found
            solution.put('title', 'Solution Not Available');
            solution.put('steps', new List<String>{'A detailed solution guide for this pain point is not yet available in the Lite version.'});
        }

        return solution;
    }
}