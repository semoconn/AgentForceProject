/**
 * @description Controller for managing workflow logging and suggestion logic.
 * VERSION: 5.1 - Added pattern checking to commitLogs and updated to use Custom Metadata.
 */
public with sharing class WorkflowSuggestionController {

    private static List<Workflow_Log__c> logsToInsert = new List<Workflow_Log__c>();

    @AuraEnabled
    public static void logWorkflowEvent(String recordId, String objectApiName, String actionName, String behaviorData) {
        // This method remains unchanged
        Workflow_Log__c log = new Workflow_Log__c(
            Record_ID__c = recordId,
            Object_API_Name__c = objectApiName,
            Action_Name__c = actionName,
            Behavior_Data__c = behaviorData,
            User__c = UserInfo.getUserId(),
            Session_ID__c = getSessionId(),
            IP_Address__c = getClientIP()
        );
        logsToInsert.add(log);
    }

    public static void commitLogs() {
        if (logsToInsert.isEmpty()) {
            return;
        }

        List<Workflow_Log__c> logsToCommit = new List<Workflow_Log__c>(logsToInsert);
        logsToInsert.clear();

        try {
            insert logsToCommit;

            // --- NEW LOGIC ---
            // After inserting, check for patterns on the records we just committed.
            // This ensures pattern checking is not missed.
            Set<String> uniqueActions = new Set<String>();
            for(Workflow_Log__c log : logsToCommit) {
                // Create a unique key for each Object-Action pair to avoid redundant checks
                String key = log.Object_API_Name__c + ':' + log.Action_Name__c;
                if (!uniqueActions.contains(key)) {
                    checkForPatterns(log.Object_API_Name__c, log.Action_Name__c);
                    uniqueActions.add(key);
                }
            }
            // --- END NEW LOGIC ---

        } catch (Exception e) {
            System.debug('Error inserting workflow logs: ' + e.getMessage());
        }
    }
    
    private static void checkForPatterns(String objectType, String action) {
        // This method remains unchanged
        List<Workflow_Log__c> recentLogs = [
            SELECT Id
            FROM Workflow_Log__c 
            WHERE Object_API_Name__c = :objectType 
            AND Action_Name__c = :action 
            AND CreatedDate = LAST_N_DAYS:1
        ];
        
        if (recentLogs.size() >= 3) {
            generateInsight(objectType, action, recentLogs.size());
        }
    }
    
    private static void generateInsight(String objectType, String action, Integer occurrenceCount) {
        // This method remains unchanged
        try {
            Workflow_Log__c insightLog = new Workflow_Log__c(
                Object_API_Name__c = objectType,
                Action_Name__c = 'INSIGHT_GENERATED',
                Behavior_Data__c = JSON.serialize(new Map<String, Object>{
                    'patternDetected' => action,
                    'occurrences' => occurrenceCount
                }),
                User__c = UserInfo.getUserId()
            );
            insert insightLog;
        } catch (Exception e) {
            System.debug('Error creating insight log: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean shouldShowSuggestion(String recordId, String objectApiName) {
        // This method with the Custom Metadata query remains unchanged from our last step
        Id currentUserId = UserInfo.getUserId();
        String actionName = 'Record_Created';

        String dismissalKey = currentUserId + ':' + objectApiName + ':' + actionName;
        Integer dismissedCount = [SELECT COUNT() FROM Suggestion_Dismissal__c WHERE Dismissal_Key__c = :dismissalKey];
        if (dismissedCount > 0) {
            return false;
        }

        AgentForce_Setting__mdt setting = [SELECT Suggestion_Threshold__c FROM AgentForce_Setting__mdt WHERE DeveloperName = 'Default_Settings' LIMIT 1];
        Decimal suggestionThreshold = setting.Suggestion_Threshold__c;

        try {
            List<Workflow_Log__c> userLogs = [
                SELECT Id FROM Workflow_Log__c
                WHERE Object_API_Name__c = :objectApiName AND User__c = :currentUserId
                AND Action_Name__c = :actionName AND Action_Name__c != 'INSIGHT_GENERATED'
                AND CreatedDate = LAST_N_DAYS:30
            ];
            
            if (userLogs.size() >= suggestionThreshold) {
                return true;
            }
            
            return false;
        } catch (Exception e) {
            System.debug('Error in shouldShowSuggestion: ' + e.getMessage());
            return false;
        }
    }

    // Other helper methods (dismissSuggestion, getSessionId, etc.) remain unchanged
    @AuraEnabled
    public static void dismissSuggestion(String objectApiName, String actionName) {
        Id currentUserId = UserInfo.getUserId();
        String dismissalKey = currentUserId + ':' + objectApiName + ':' + actionName;

        Suggestion_Dismissal__c dismissal = new Suggestion_Dismissal__c(
            User__c = currentUserId,
            Object_API_Name__c = objectApiName,
            Action_Name__c = actionName,
            Dismissal_Key__c = dismissalKey
        );
        upsert dismissal Dismissal_Key__c;
    }

    private static String getSessionId() {
        if (Test.isRunningTest()) { return 'TEST_SESSION_ID'; }
        return UserInfo.getSessionId();
    }
    
    private static String getClientIP() {
        if (Test.isRunningTest()) { return '127.0.0.1'; }
        if (Auth.SessionManagement.getCurrentSession() != null && Auth.SessionManagement.getCurrentSession().containsKey('SourceIp')) {
            return Auth.SessionManagement.getCurrentSession().get('SourceIp');
        }
        return 'IP_NOT_AVAILABLE';
    }
}