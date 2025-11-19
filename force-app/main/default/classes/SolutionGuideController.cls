/**
 * @description       : Provides the content for the Solution Guide modal in the BehaviorIQ dashboard.
 * @version           : 3.0 - FEATURE: Added solution guide for Stale Cases pattern.
**/
public with sharing class SolutionGuideController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSolutionGuide(String painPointKey) {
        Map<String, Object> solution = new Map<String, Object>();

        if (painPointKey == 'Sequential_Action_Contact_Task') {
            solution.put('title', 'Solution: Create a Quick Action on Contacts');
            solution.put('steps', new List<String>{
                'Navigate to Setup > Object Manager > Contact.',
                'Go to "Buttons, Links, and Actions" and click "New Action".',
                'Set Action Type to "Create a Record", Target Object to "Task", and Label it "New Follow-Up Task".',
                'Click Save. On the next screen, you can pre-define field values, like setting the Subject to "Follow-up".',
                'Navigate to Contact > Page Layouts and edit your layout(s).',
                'In the palette, find "Mobile & Lightning Actions", drag your "New Follow-Up Task" action into the actions section, and Save.',
                'This button will now appear on Contact pages, saving your users multiple clicks.'
            });
        } else if (painPointKey == 'Stale_High_Value_Opportunity') {
            solution.put('title', 'Solution: Build a Stale Opportunity Notifier Flow');
            solution.put('steps', new List<String>{
                'Navigate to Setup > Process Automation > Flows and click "New Flow".',
                'Select "Scheduled-Triggered Flow".',
                'Set the schedule to run daily.',
                'Choose "Opportunity" as the object and configure the trigger to run when "LastModifiedDate" is less than "TODAY() - 30" and "IsClosed" is false.',
                'Add an "Action" element to the flow.',
                'Search for and select "Send Email Alert". Configure an email alert to be sent to the Opportunity Owner.',
                'Alternatively, you can post to a Chatter group or send a custom notification to alert sales managers.',
                'Save and activate the flow. This will automatically notify users about their high-value deals that are going cold.'
            });
        } else if (painPointKey == 'Unassigned_Lead') {
            solution.put('title', 'Solution: Implement Lead Assignment Rules');
            solution.put('steps', new List<String>{
                'Navigate to Setup > Feature Settings > Marketing > Lead Assignment Rules.',
                'Create a new rule (or edit your existing active rule).',
                'Click "New" under "Rule Entries" to define the criteria.',
                'Set the criteria for the rule. For example, "Lead: Country equals USA".',
                'Select the user or queue to assign the lead to if the criteria are met.',
                'You can create multiple entries to handle different types of leads (e.g., based on region, product interest, etc.).',
                'Ensure the "Active" checkbox is checked on the main rule page to enable it.',
                'Now, new leads matching your criteria will be automatically routed to the correct person or team.'
            });
        // --- NEW SOLUTION GUIDE ---
        } else if (painPointKey == 'Stale_High_Priority_Case') {
            solution.put('title', 'Solution: Use Escalation Rules for Stale Cases');
            solution.put('steps', new List<String>{
                'Navigate to Setup > Feature Settings > Service > Escalation Rules.',
                'Click "New Escalation Rule". Give it a name like "High Priority Case Escalation" and make it Active.',
                'Click on the rule name to create "Rule Entries".',
                'Set the criteria for the entry, for example: "Case: Priority equals High" and "Case: Status not equal to Closed".',
                'Define your business hours if applicable.',
                'Under "Escalation Actions", specify the time criteria (e.g., escalate after 7 days of no modification).',
                'Add an Escalation Action, such as "Assign to" a Tier 2 support queue and "Notify" the support manager.',
                'Save and activate the rule. The system will now automatically escalate critical cases that are not being addressed.'
            });
        } else {
            solution.put('title', 'Solution Not Available');
            solution.put('steps', new List<String>{'A detailed solution guide for this pain point is not yet available.'});
        }

        return solution;
    }
}