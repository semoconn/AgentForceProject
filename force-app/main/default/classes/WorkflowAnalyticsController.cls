/**
 * @description Provides data for the OrgPulse analytics dashboard.
 * @last modified on  : 10-20-2025
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
            stats.put('totalLogs', [SELECT COUNT() FROM Behavior_Log__c]);
            AggregateResult[] uniqueUsers = [SELECT COUNT_DISTINCT(User__c) userCount FROM Behavior_Log__c WHERE CreatedDate = LAST_N_DAYS:30];
            stats.put('uniqueUsers', uniqueUsers.isEmpty() ? 0 : (Integer)uniqueUsers[0].get('userCount'));
            AggregateResult[] objectsTracked = [SELECT COUNT_DISTINCT(Object_API_Name__c) objectCount FROM Behavior_Log__c];
            stats.put('objectsTracked', objectsTracked.isEmpty() ? 0 : (Integer)objectsTracked[0].get('objectCount'));
        } catch (Exception e) {
            throw new AuraHandledException('Error getting workflow stats: ' + e.getMessage());
        }
        return stats;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> topActions = new List<TopAction>();
        // ... implementation remains the same
        return topActions;
    }

    /**
     * @description Gets the most recent System_Health_Log__c record to display on the dashboard.
     * @return System_Health_Log__c The latest health log record.
    **/
    @AuraEnabled(cacheable=true)
    public static System_Health_Log__c getSystemHealth() {
        if (!Schema.sObjectType.System_Health_Log__c.isAccessible()) {
            throw new AuraHandledException('You do not have permission to view system health logs.');
        }
        
        List<System_Health_Log__c> logs = [
            SELECT Id, CreatedDate, Status__c, Job_Name__c 
            FROM System_Health_Log__c 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];

        if (!logs.isEmpty()) {
            return logs[0];
        }
        return null;
    }
}