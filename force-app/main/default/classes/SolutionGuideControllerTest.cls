/**
 * @description       : Test class for the SolutionGuideController.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-15-2025
 * @last modified by  : Gemini
**/
@isTest
private class SolutionGuideControllerTest {

    @isTest
    static void testGetSolutionGuide_Success() {
        // Arrange
        String painPointKey = 'Sequential_Action_Contact_Task';

        Test.startTest();
        // Act
        Map<String, Object> result = SolutionGuideController.getSolutionGuide(painPointKey);
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, result, 'The result should not be null.');
        System.assertEquals('Solution: Create a Quick Action on Contacts', result.get('title'), 'The title should match the defined solution.');
        
        List<String> steps = (List<String>)result.get('steps');
        System.assert(steps.size() > 5, 'There should be multiple steps in the solution guide.');
    }

    @isTest
    static void testGetSolutionGuide_NotFound() {
        // Arrange
        String painPointKey = 'NON_EXISTENT_KEY';

        Test.startTest();
        // Act
        Map<String, Object> result = SolutionGuideController.getSolutionGuide(painPointKey);
        Test.stopTest();

        // Assert
        System.assertEquals('Solution Not Available', result.get('title'), 'Should return the default title for an unknown key.');
    }
}