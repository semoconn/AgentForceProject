/**
 * @description Provides data for the BehaviorIQ analytics dashboard.
 * @version 2.0 - DEMO FIX: Added better error handling and null checks
 * @last modified on  : 11-05-2025
 */
public with sharing class WorkflowAnalyticsController {
    
    public class TopAction {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String actionName { get; set; }
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public Integer count { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getWorkflowStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        try {
            // Total logs count
            stats.put('totalLogs', [SELECT COUNT() FROM Behavior_Log__c]);
            
            // Unique users in last 30 days
            AggregateResult[] uniqueUsers = [
                SELECT COUNT_DISTINCT(User__c) userCount 
                FROM Behavior_Log__c 
                WHERE CreatedDate = LAST_N_DAYS:30
            ];
            stats.put('uniqueUsers', uniqueUsers.isEmpty() ? 0 : (Integer)uniqueUsers[0].get('userCount'));
            
            // Distinct objects tracked
            AggregateResult[] objectsTracked = [
                SELECT COUNT_DISTINCT(Object_API_Name__c) objectCount 
                FROM Behavior_Log__c
            ];
            stats.put('objectsTracked', objectsTracked.isEmpty() ? 0 : (Integer)objectsTracked[0].get('objectCount'));
            
            System.debug('Workflow Stats: ' + stats);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting workflow stats: ' + e.getMessage());
            // Return zeros instead of throwing error
            stats.put('totalLogs', 0);
            stats.put('uniqueUsers', 0);
            stats.put('objectsTracked', 0);
        }
        return stats;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> topActions = new List<TopAction>();
        try {
            List<AggregateResult> results = [
                SELECT Action_Name__c actionName, Object_API_Name__c objectName, COUNT(Id) actionCount
                FROM Behavior_Log__c
                WHERE CreatedDate = LAST_N_DAYS:30
                GROUP BY Action_Name__c, Object_API_Name__c
                ORDER BY COUNT(Id) DESC
                LIMIT 10
            ];
            
            for (AggregateResult ar : results) {
                TopAction action = new TopAction();
                action.id = (String)ar.get('actionName') + (String)ar.get('objectName');
                action.actionName = (String)ar.get('actionName');
                action.objectName = (String)ar.get('objectName');
                action.count = (Integer)ar.get('actionCount');
                topActions.add(action);
            }
            
            System.debug('Top Actions: ' + topActions.size() + ' records');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting top actions: ' + e.getMessage());
            // Return empty list instead of throwing error
        }
        return topActions;
    }

    /**
     * @description Gets the most recent System_Health_Log__c record to display on the dashboard.
     * @return System_Health_Log__c The latest health log record, or null if none exists.
    **/
    @AuraEnabled(cacheable=true)
    public static System_Health_Log__c getSystemHealth() {
        try {
            if (!Schema.sObjectType.System_Health_Log__c.isAccessible()) {
                System.debug(LoggingLevel.WARN, 'User does not have permission to view system health logs.');
                return null;
            }
            
            List<System_Health_Log__c> logs = [
                SELECT Id, CreatedDate, Status__c, Job_Name__c, Error_Count__c
                FROM System_Health_Log__c 
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];

            if (!logs.isEmpty()) {
                System.debug('System Health Log found: ' + logs[0].Status__c);
                return logs[0];
            } else {
                System.debug('No System Health Log records found.');
                return null;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting system health: ' + e.getMessage());
            return null;
        }
    }
}