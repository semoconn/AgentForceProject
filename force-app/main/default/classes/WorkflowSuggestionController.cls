/**
 * @description Controller for managing workflow logging and suggestion logic.
 * Handles events from both LWC and Apex triggers to capture user behavior.
 * VERSION: 4.0 - Corrected suggestion logic to exclude system-generated insights.
 */
public with sharing class WorkflowSuggestionController {

    // A static list to hold all logs generated within a single transaction.
    private static List<Workflow_Log__c> logsToInsert = new List<Workflow_Log__c>();

    @AuraEnabled
    public static void logWorkflowEvent(String recordId, String objectApiName, String actionName, String behaviorData) {
        // This method no longer performs an immediate DML insert.
        // Instead, it adds the new log to a static list to be inserted later.
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

    /**
     * @description This method commits all the batched logs in a single DML statement.
     * It should be called by the trigger handler at the end of the transaction.
     */
    public static void commitLogs() {
        if (!logsToInsert.isEmpty()) {
            // Use a temporary list to hold the logs for this commit.
            List<Workflow_Log__c> logsToCommit = logsToInsert;
            logsToInsert = new List<Workflow_Log__c>(); // Clear the static list immediately

            try {
                insert logsToCommit;

                // After inserting, run pattern checks on the newly created logs.
                Map<String, Set<String>> objectToActionMap = new Map<String, Set<String>>();
                for (Workflow_Log__c log : logsToCommit) {
                    if (!objectToActionMap.containsKey(log.Object_API_Name__c)) {
                        objectToActionMap.put(log.Object_API_Name__c, new Set<String>());
                    }
                    objectToActionMap.get(log.Object_API_Name__c).add(log.Action_Name__c);
                }

                for (String objName : objectToActionMap.keySet()) {
                    for (String actionName : objectToActionMap.get(objName)) {
                        checkForPatterns(objName, actionName);
                    }
                }
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
        try {
            // ✅ FIX: Added a WHERE clause to exclude system-generated insights
            // from the count. This makes the logic more accurate.
            List<Workflow_Log__c> userLogs = [
                SELECT Id
                FROM Workflow_Log__c
                WHERE Object_API_Name__c = :objectApiName
                AND User__c = :UserInfo.getUserId()
                AND Action_Name__c != 'INSIGHT_GENERATED' // <-- THE FIX
                AND CreatedDate = LAST_N_DAYS:30
                LIMIT 100
            ];
            
            if (userLogs.size() >= 5) {
                return true;
            }
            
            return false;
        } catch (Exception e) {
            System.debug('Error in shouldShowSuggestion: ' + e.getMessage());
            return false;
        }
    }
    
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
        if (Auth.SessionManagement.getCurrentSession().containsKey('SourceIp')) {
            return Auth.SessionManagement.getCurrentSession().get('SourceIp');
        }
        return 'IP_NOT_AVAILABLE';
    }
}

