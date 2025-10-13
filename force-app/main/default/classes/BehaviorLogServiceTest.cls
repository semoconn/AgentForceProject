/**
 * @description Test class for the BehaviorLogService.
 * This class verifies that the service correctly subscribes to Platform Events
 * and creates Behavior_Log__c records.
 */
@isTest
private class BehaviorLogServiceTest {

    @isTest
    static void testEventProcessing() {
        // ARRANGE: No data setup needed, we will fire the event directly.

        Test.startTest();

        // ACT: Publish a Behavior Event
        Behavior_Event__e testEvent = new Behavior_Event__e(
            Action_Name__c = 'Test Action',
            Object_API_Name__c = 'Account',
            Record_ID__c = '001xx000003DGgPAAW',
            User_ID__c = UserInfo.getUserId(),
            Behavior_Data__c = '{"test":true}'
        );
        EventBus.publish(testEvent);

        Test.stopTest(); // This ensures the platform event is processed by the trigger

        // ASSERT: Verify that a Behavior_Log__c record was created
        List<Behavior_Log__c> logs = [
            SELECT Id, Action_Name__c, Object_API_Name__c, Record_ID__c, User__c, Behavior_Data__c
            FROM Behavior_Log__c
        ];
        
        System.assertEquals(1, logs.size(), 'One Behavior Log record should have been created.');
        System.assertEquals('Test Action', logs[0].Action_Name__c);
        System.assertEquals('Account', logs[0].Object_API_Name__c);
        System.assertEquals(UserInfo.getUserId(), logs[0].User__c);
        System.assertEquals('{"test":true}', logs[0].Behavior_Data__c);
    }
}
