/**
 * @description Provides data for the AgentForce analytics dashboard.
 * This class uses aggregate queries to efficiently summarize workflow log data.
 */
public with sharing class WorkflowAnalyticsController {
    
    /**
     * @description Wrapper class for returning top action data to the LWC.
     */
    public class TopAction {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String actionName { get; set; }
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public Integer count { get; set; }
    }

    /**
     * @description Gets overall workflow statistics for display in stat cards.
     * @return Map<String, Integer> A map of key stats (totalLogs, uniqueUsers, objectsTracked).
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getWorkflowStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        
        try {
            stats.put('totalLogs', [SELECT COUNT() FROM Workflow_Log__c]);

            AggregateResult[] uniqueUsers = [SELECT COUNT_DISTINCT(User__c) userCount FROM Workflow_Log__c];
            stats.put('uniqueUsers', uniqueUsers.isEmpty() ? 0 : (Integer)uniqueUsers[0].get('userCount'));
            
            AggregateResult[] objectsTracked = [SELECT COUNT_DISTINCT(Object_API_Name__c) objectCount FROM Workflow_Log__c];
            stats.put('objectsTracked', objectsTracked.isEmpty() ? 0 : (Integer)objectsTracked[0].get('objectCount'));
            
        } catch (Exception e) {
            throw new AuraHandledException('Error getting workflow stats: ' + e.getMessage());
        }
        
        return stats;
    }
    
    /**
     * @description Gets the top 10 most frequently performed actions in the last 30 days.
     * @return List<TopAction> A list of top actions, ordered by count descending.
     */
    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> topActions = new List<TopAction>();
        try {
            List<AggregateResult> results = [
                SELECT Action_Name__c actionName, Object_API_Name__c objectName, COUNT(Id) actionCount
                FROM Workflow_Log__c
                WHERE CreatedDate = LAST_N_DAYS:30
                AND Action_Name__c != 'INSIGHT_GENERATED'
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
        } catch (Exception e) {
            throw new AuraHandledException('Error getting top actions: ' + e.getMessage());
        }
        return topActions;
    }
}
