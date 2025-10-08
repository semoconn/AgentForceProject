/**
 * @description Controller for managing workflow logging and suggestion logic.
 * VERSION: 5.0 - Added user-specific checks and dismissal logic.
 */
public with sharing class WorkflowSuggestionController {

    // A static list to hold all logs generated within a single transaction.
    private static List<Workflow_Log__c> logsToInsert = new List<Workflow_Log__c>();

    // (logWorkflowEvent and commitLogs methods remain the same)
    @AuraEnabled
    public static void logWorkflowEvent(String recordId, String objectApiName, String actionName, String behaviorData) {
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
        if (!logsToInsert.isEmpty()) {
            List<Workflow_Log__c> logsToCommit = new List<Workflow_Log__c>(logsToInsert);
            logsToInsert.clear();

            try {
                insert logsToCommit;
                // Pattern checking logic can be called here if needed
            } catch (Exception e) {
                System.debug('Error inserting workflow logs: ' + e.getMessage());
            }
        }
    }
    
    private static void checkForPatterns(String objectType, String action) {
        // This logic remains the same.
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
        Id currentUserId = UserInfo.getUserId();
        String actionName = 'Record_Created'; // For now, we only detect this pattern

        // ✅ FIX #2: First, check if this suggestion has been dismissed by the user
        String dismissalKey = currentUserId + ':' + objectApiName + ':' + actionName;
        Integer dismissedCount = [SELECT COUNT() FROM Suggestion_Dismissal__c WHERE Dismissal_Key__c = :dismissalKey];
        if (dismissedCount > 0) {
            return false; // User has already dismissed this, so don't show it.
        }

        try {
            // ✅ FIX #1: The query now filters by the current user's ID
            List<Workflow_Log__c> userLogs = [
                SELECT Id
                FROM Workflow_Log__c
                WHERE Object_API_Name__c = :objectApiName
                AND User__c = :currentUserId
                AND Action_Name__c = :actionName
                AND Action_Name__c != 'INSIGHT_GENERATED'
                AND CreatedDate = LAST_N_DAYS:30
            ];
            
            // The threshold for showing the suggestion
            if (userLogs.size() >= 5) {
                return true;
            }
            
            return false;
        } catch (Exception e) {
            System.debug('Error in shouldShowSuggestion: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Creates a dismissal record so a suggestion is not shown to a user again.
     * @param objectApiName - The API name of the object for the suggestion.
     * @param actionName    - The name of the action being dismissed.
     */
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

        // Use upsert to prevent duplicates, just in case.
        upsert dismissal Dismissal_Key__c;
    }

    // ... (getSessionId and getClientIP methods remain the same) ...
    private static String getSessionId() {
        if (Test.isRunningTest()) {
            return 'TEST_SESSION_ID';
        }
        return UserInfo.getSessionId();
    }
    
    private static String getClientIP() {
        if (Test.isRunningTest()) {
            return '127.0.0.1';
        }
        if (Auth.SessionManagement.getCurrentSession() != null && Auth.SessionManagement.getCurrentSession().containsKey('SourceIp')) {
            return Auth.SessionManagement.getCurrentSession().get('SourceIp');
        }
        return 'IP_NOT_AVAILABLE';
    }
}

