// Workflow_Behavior_Event__e
public class WorkflowBehaviorCapture {
    @future
    public static void captureEvent(String action, String objectType, String recordId) {
        Workflow_Behavior_Event__e evt = new Workflow_Behavior_Event__e(
            Action__c = action,
            Object_Type__c = objectType,
            Record_ID__c = recordId,
            User_ID__c = UserInfo.getUserId()
        );
        EventBus.publish(evt);
    }
}