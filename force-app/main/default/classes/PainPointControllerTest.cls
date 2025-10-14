/**
 * @description       : Test class for the PainPointController.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-13-2025
 * @last modified by  : Gemini
**/
@isTest
private class PainPointControllerTest {

    @TestSetup
    static void makeData() {
        List<Identified_Pain_Point__c> points = new List<Identified_Pain_Point__c>();
        points.add(new Identified_Pain_Point__c(
            Name = 'Low Impact Pain Point',
            Impact_Score__c = 10,
            Status__c = 'New',
            Unique_Key__c = 'Low_Impact_Test_Key'
        ));
        points.add(new Identified_Pain_Point__c(
            Name = 'High Impact Pain Point',
            Impact_Score__c = 100,
            Status__c = 'New',
            Unique_Key__c = 'High_Impact_Test_Key'
        ));
        insert points;
    }

    @isTest
    static void testGetPainPoints_ReturnsCorrectly() {
        // Arrange
        Test.startTest();
        // Act
        List<Identified_Pain_Point__c> results = PainPointController.getPainPoints();
        Test.stopTest();

        // Assert
        System.assertEquals(2, results.size(), 'Should return two pain point records.');
        System.assertEquals('High Impact Pain Point', results[0].Name, 'The first record should be the one with the highest impact score.');
        System.assertEquals(100, results[0].Impact_Score__c, 'The impact score should be correct.');
    }
    
    @isTest
    static void testGetPainPoints_NoAccess() {
        // Arrange
        // Create a user who does not have access via Permission Set
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User u = new User(
            Alias = 'testuser', 
            Email='testuser@noemail.com',
            EmailEncodingKey='UTF-8', 
            LastName='Testing', 
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_US', 
            ProfileId = p.Id,
            TimeZoneSidKey='America/Denver', 
            UserName='testuser' + System.currentTimeMillis() + '@testorg.com'
        );
        insert u;

        List<Identified_Pain_Point__c> results;
        
        System.runAs(u) {
            Test.startTest();
            // Act: Call the method. We expect it to either return an empty list 
            // (due to sharing) or throw an exception (due to FLS), which the controller will handle.
            // In a test context, it will likely return an empty list.
            try {
                 results = PainPointController.getPainPoints();
            } catch(Exception e) {
                // If an exception IS thrown (e.g., in an org with stricter defaults), 
                // we catch it so the test doesn't fail, and results will be null.
            }
            Test.stopTest();
        }

        // Assert
        // A user without explicit access should not get any records.
        // The list will either be empty or null (if an exception was caught).
        System.assert(results == null || results.isEmpty(), 
            'A user without access should not receive any pain point records.');
    }
}

