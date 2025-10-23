/**
 * @description       : Test class for the SolutionGuideController.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-21-2025
 * @last modified by  : Gemini
**/
@isTest
private class SolutionGuideControllerTest {

    @isTest
    static void testGetSolutionGuide_AllPaths() {
        Test.startTest();

        // Test Path 1: Sequential Contact -> Task
        Map<String, Object> result1 = SolutionGuideController.getSolutionGuide('Sequential_Action_Contact_Task');
        System.assertEquals('Solution: Create a Quick Action on Contacts', result1.get('title'), 'Title should match for Sequential_Action_Contact_Task');
        System.assert(((List<String>)result1.get('steps')).size() > 0, 'Should have steps for Sequential_Action_Contact_Task');

        // Test Path 2: Stale Opportunity
        Map<String, Object> result2 = SolutionGuideController.getSolutionGuide('Stale_High_Value_Opportunity');
        System.assertEquals('Solution: Build a Stale Opportunity Notifier Flow', result2.get('title'), 'Title should match for Stale_High_Value_Opportunity');
        System.assert(((List<String>)result2.get('steps')).size() > 0, 'Should have steps for Stale_High_Value_Opportunity');
        
        // Test Path 3: Unassigned Lead
        Map<String, Object> result3 = SolutionGuideController.getSolutionGuide('Unassigned_Lead');
        System.assertEquals('Solution: Implement Lead Assignment Rules', result3.get('title'), 'Title should match for Unassigned_Lead');
        System.assert(((List<String>)result3.get('steps')).size() > 0, 'Should have steps for Unassigned_Lead');

        // Test Path 4: Stale Case (The new one)
        Map<String, Object> result4 = SolutionGuideController.getSolutionGuide('Stale_High_Priority_Case');
        System.assertEquals('Solution: Use Escalation Rules for Stale Cases', result4.get('title'), 'Title should match for Stale_High_Priority_Case');
        System.assert(((List<String>)result4.get('steps')).size() > 0, 'Should have steps for Stale_High_Priority_Case');
        
        // Test Path 5: Not Found (Else block)
        Map<String, Object> result5 = SolutionGuideController.getSolutionGuide('A_KEY_THAT_DOES_NOT_EXIST');
        System.assertEquals('Solution Not Available', result5.get('title'), 'Should return default title for a non-existent key');
        
        Test.stopTest();
    }
}