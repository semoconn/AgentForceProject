/**
 * @description Controller for the BehaviorIQ Dashboard.
 * Aggregates behavioral data and injects License status for UI gating.
 * Contains legacy analytics methods (WorkflowStats, TopActions) and new DashboardWrapper logic.
 */
public with sharing class WorkflowAnalyticsController {

    // --- NEW: Dashboard & Gating Structures ---

    public class DashboardDataWrapper {
        @AuraEnabled public Boolean isPremium { get; set; }
        @AuraEnabled public List<MetricWrapper> metrics { get; set; }
        @AuraEnabled public List<Behavior_Log__c> recentLogs { get; set; }
        
        public DashboardDataWrapper() {
            this.isPremium = false;
            this.metrics = new List<MetricWrapper>();
            this.recentLogs = new List<Behavior_Log__c>();
        }
    }

    public class MetricWrapper {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Integer count { get; set; }
        @AuraEnabled public String trend { get; set; } 
        @AuraEnabled public String type { get; set; } // 'alert', 'success', 'warning'
        @AuraEnabled public String key { get; set; }
        
        public MetricWrapper(String label, Integer count, String trend, String type, String key) {
            this.label = label;
            this.count = count;
            this.trend = trend;
            this.type = type;
            this.key = key;
        }
    }
    
    // --- ORIGINAL: Analytics Structures ---

    public class TopAction {
        @AuraEnabled public String id;
        @AuraEnabled public String actionName;
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer count;
    }

    // --- NEW: Dashboard Initialization Method ---

    @AuraEnabled(cacheable=true)
    public static DashboardDataWrapper getDashboardData() {
        DashboardDataWrapper data = new DashboardDataWrapper();
        
        // 1. Inject License Status (The Gate)
        data.isPremium = LicenseService.isPremium();
        
        // 2. Fetch Metrics (Aggregated from Pain Points)
        data.metrics = getMetrics();

        // 3. Fetch Recent Logs 
        // FIX: Used CreatedDate instead of Timestamp__c (which doesn't exist on Behavior_Log__c)
        data.recentLogs = [
            SELECT Id, Action_Name__c, User__r.Name, CreatedDate, Object_API_Name__c 
            FROM Behavior_Log__c 
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC 
            LIMIT 10 
        ];

        return data;
    }

    private static List<MetricWrapper> getMetrics() {
        List<MetricWrapper> metrics = new List<MetricWrapper>();
        
        // Aggregate from Identified_Pain_Point__c
        for (AggregateResult ar : [
            SELECT Status__c, Count(Id) cnt 
            FROM Identified_Pain_Point__c 
            WITH SECURITY_ENFORCED 
            GROUP BY Status__c
        ]) {
            String status = (String)ar.get('Status__c');
            Integer count = (Integer)ar.get('cnt');
            
            if (status == 'Active') {
                metrics.add(new MetricWrapper('Active Anomalies', count, '+2%', 'alert', 'active_anomalies'));
            } else if (status == 'Dismissed') {
                metrics.add(new MetricWrapper('Dismissed', count, '0%', 'success', 'dismissed_anomalies'));
            }
        }
        
        // If no data, add a placeholder or default metric
        if (metrics.isEmpty()) {
             Integer staleOppCount = [SELECT Count() FROM Opportunity WHERE LastStageChangeDate < LAST_N_DAYS:30 AND IsClosed = false WITH SECURITY_ENFORCED];
             metrics.add(new MetricWrapper('Stale Opportunities', staleOppCount, 'Live', 'warning', 'stale_opps'));
        }

        return metrics;
    }

    // --- NEW: Premium Action ---

    @AuraEnabled
    public static void runAutoFix(List<Id> recordIds) {
        // CRITICAL: Server-side Gate
        LicenseService.enforcePremiumGate();
        
        // Logic would go here. For MVP, we just validate the gate allows entry.
    }

    // --- ORIGINAL: Restored Analytics Methods ---

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getWorkflowStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        
        stats.put('totalLogs', [SELECT Count() FROM Behavior_Log__c WITH SECURITY_ENFORCED]);
        
        // FIX: Correct way to count distinct groups in SOQL
        // We select the grouping field, then count the number of rows returned by the aggregate query
        AggregateResult[] userResults = [SELECT User__c FROM Behavior_Log__c WITH SECURITY_ENFORCED GROUP BY User__c];
        stats.put('uniqueUsers', userResults.size());
        
        AggregateResult[] objectResults = [SELECT Object_API_Name__c FROM Behavior_Log__c WITH SECURITY_ENFORCED GROUP BY Object_API_Name__c];
        stats.put('objectsTracked', objectResults.size());
        
        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> actions = new List<TopAction>();
        
        List<AggregateResult> results = [
            SELECT Action_Name__c actionName, Object_API_Name__c objectName, COUNT(Id) actionCount
            FROM Behavior_Log__c
            WHERE CreatedDate = LAST_N_DAYS:30
            WITH SECURITY_ENFORCED
            GROUP BY Action_Name__c, Object_API_Name__c
            ORDER BY COUNT(Id) DESC
            LIMIT 10
        ];
        
        for (AggregateResult ar : results) {
            TopAction action = new TopAction();
            action.actionName = (String)ar.get('actionName');
            action.objectName = (String)ar.get('objectName');
            action.count = (Integer)ar.get('actionCount');
            action.id = action.actionName + action.objectName;
            actions.add(action);
        }
        return actions;
    }

    @AuraEnabled(cacheable=true)
    public static System_Health_Log__c getSystemHealth() {
        // FIX: Used CreatedDate instead of Timestamp__c
        List<System_Health_Log__c> logs = [
            SELECT Id, Job_Name__c, Status__c, CreatedDate 
            FROM System_Health_Log__c 
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC 
            LIMIT 1 
        ];
        return logs.isEmpty() ? null : logs[0];
    }
}