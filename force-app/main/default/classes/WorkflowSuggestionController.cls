public with sharing class WorkflowSuggestionController {
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
        insert log;
        
        // Check for patterns and trigger AgentForce analysis
        checkForPatterns(objectApiName, actionName);
    }
    
    private static void checkForPatterns(String objectType, String action) {
        // Query for similar behaviors in the last 24 hours
        List<Workflow_Log__c> recentLogs = [
            SELECT Id, Action_Name__c, User__c, CreatedDate 
            FROM Workflow_Log__c 
            WHERE Object_API_Name__c = :objectType 
            AND Action_Name__c = :action 
            AND CreatedDate = LAST_N_DAYS:1
        ];
        
        if (recentLogs.size() >= 3) {
            // Trigger AgentForce analysis
            generateInsight(objectType, action, recentLogs.size());
        }
    }
    
    /**
     * Generate insights based on detected patterns
     */
    private static void generateInsight(String objectType, String action, Integer occurrenceCount) {
        // Create an insight record or trigger your AgentForce logic
        System.debug('Pattern detected: ' + action + ' on ' + objectType + ' occurred ' + occurrenceCount + ' times in last 24 hours');
        
        // You can add logic here to:
        // 1. Create a custom object record to store the insight
        // 2. Send a platform event
        // 3. Trigger an AgentForce action
        // 4. Send an email notification
        
        // Example: Create a simple log entry
        try {
            Workflow_Log__c insightLog = new Workflow_Log__c(
                Object_API_Name__c = objectType,
                Action_Name__c = 'INSIGHT_GENERATED',
                Behavior_Data__c = JSON.serialize(new Map<String, Object>{
                    'patternDetected' => action,
                    'occurrences' => occurrenceCount,
                    'timeframe' => '24 hours',
                    'timestamp' => DateTime.now()
                }),
                User__c = UserInfo.getUserId()
            );
            insert insightLog;
        } catch (Exception e) {
            System.debug('Error creating insight log: ' + e.getMessage());
        }
    }
    
    /**
     * Check if a workflow suggestion should be shown to the user
     * @param recordId - The record ID being worked on
     * @param objectApiName - The API name of the object
     * @return Boolean - true if suggestion should be shown
     */
    @AuraEnabled(cacheable=true)
    public static Boolean shouldShowSuggestion(String recordId, String objectApiName) {
        try {
            // Query for recent similar workflows by this user
            List<Workflow_Log__c> userLogs = [
                SELECT Id, Action_Name__c, CreatedDate
                FROM Workflow_Log__c
                WHERE Object_API_Name__c = :objectApiName
                AND User__c = :UserInfo.getUserId()
                AND CreatedDate = LAST_N_DAYS:30
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
            
            // If user has performed similar actions 5+ times, suggest automation
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
     * Get the current user's session ID
     * Note: This is a simplified version. In production, you may want to use
     * a more robust method or store session data differently
     */
    private static String getSessionId() {
        String sessionId = UserInfo.getSessionId();
        // If running in a test context, session ID might be null
        return (sessionId != null) ? sessionId : 'TEST_SESSION_' + DateTime.now().getTime();
    }
    
    /**
     * Get the client's IP address
     * Note: This attempts to get the IP from the current request
     * In Lightning components, this may not always be available
     */
    private static String getClientIP() {
        String ipAddress = 'Unknown';
        
        try {
            // Try to get IP from Auth.SessionManagement (if available)
            Map<String, String> sessionInfo = Auth.SessionManagement.getCurrentSession();
            if (sessionInfo != null && sessionInfo.containsKey('SourceIp')) {
                ipAddress = sessionInfo.get('SourceIp');
            }
        } catch (Exception e) {
            System.debug('Could not retrieve IP address: ' + e.getMessage());
            // Return a default value if IP cannot be determined
            ipAddress = 'IP_NOT_AVAILABLE';
        }
        
        return ipAddress;
    }
}