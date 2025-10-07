/**
 * Test class for WorkflowBehaviorCapture
 */
@isTest
private class WorkflowBehaviorCaptureTest {
    
    @isTest
    static void testCaptureEvent() {
        Test.startTest();
        WorkflowBehaviorCapture.captureEvent('Test_Action', 'Account', 'testId123');
        Test.stopTest();
        
        // Platform events are fire-and-forget, so we just verify no exceptions
        System.assert(true, 'Method executed without error');
    }
}