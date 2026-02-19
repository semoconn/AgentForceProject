/**
 * @description       : Test class for the SolutionGuideController.
 * @author            : Gemini
 * @group             : BehaviorIQ
 * @last modified on  : 10-21-2025
 * @last modified by  : Gemini
**/
@isTest
private with sharing class SolutionGuideControllerTest {

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

    @isTest
    static void testGetSolutionGuide_MetadataPath() {
        // Contact_Data_Gap has manualFixSteps in its Fix_Config__c metadata
        Test.startTest();
        Map<String, Object> result = SolutionGuideController.getSolutionGuide('Contact_Data_Gap');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a solution');
        // Metadata path returns 'How to Fix: ...' title format
        String title = (String)result.get('title');
        System.assert(title != null && title.startsWith('How to Fix:'),
            'Metadata solution should have "How to Fix:" title prefix. Got: ' + title);
        System.assertEquals('metadata', result.get('source'), 'Should flag source as metadata');
        List<String> steps = (List<String>)result.get('steps');
        System.assert(steps != null && steps.size() > 0, 'Metadata solution should have steps');
    }

    @isTest
    static void testGetSolutionGuide_NullKey() {
        Test.startTest();
        Map<String, Object> result = SolutionGuideController.getSolutionGuide(null);
        Test.stopTest();

        // Null key: getMetadataSolutionGuide returns null (blank check), falls through to else block
        System.assertEquals('Solution Not Available', result.get('title'),
            'Null key should fall through to default solution');
    }

    @isTest
    static void testGetSolutionGuide_BlankKey() {
        Test.startTest();
        Map<String, Object> result = SolutionGuideController.getSolutionGuide('');
        Test.stopTest();

        System.assertEquals('Solution Not Available', result.get('title'),
            'Blank key should fall through to default solution');
    }

    @isTest
    static void testGetSolutionGuide_TimestampedMetadataKey() {
        // Test extractBaseRuleName with a timestamped key that matches a real CMDT rule
        Test.startTest();
        Map<String, Object> result = SolutionGuideController.getSolutionGuide('Contact_Data_Gap_1767994173771');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a solution for timestamped key');
        String title = (String)result.get('title');
        // Should extract base name 'Contact_Data_Gap' and find metadata
        System.assert(title != null && title.startsWith('How to Fix:'),
            'Timestamped key should resolve via metadata. Got: ' + title);
    }
}