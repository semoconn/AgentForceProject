/**
 * @description Controller for the BehaviorIQ Dashboard LWC.
 * Handles data retrieval for behavioral analytics, dashboard metrics, and initiates Auto-Fix actions.
 * Enforces strict security and masking of exceptions.
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
    
    // --- NEW: Analytics Structures ---

    public class TopAction {
        @AuraEnabled public String id;
        @AuraEnabled public String actionName;
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer count;
    }

    // --- EXISTING METHODS (Preserved) ---

    @AuraEnabled(cacheable=true)
    public static List<Identified_Pain_Point__c> getPainPoints() {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to view Pain Points.');
        }

        try {
            // FIX: Changed filter from 'Active' to 'New' to match Schema/Test Data
            List<Identified_Pain_Point__c> points = [
                SELECT Id, Name, Object_API_Name__c, Impact_Score__c, Status__c, Description__c, Occurrences__c, Example_Records__c
                FROM Identified_Pain_Point__c
                WHERE Status__c = 'New'
                ORDER BY Impact_Score__c DESC
                LIMIT 50
            ];
            
            // Enforce Security on the result set
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, points);
            return (List<Identified_Pain_Point__c>) decision.getRecords();

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving analytics data. Please check logs.');
        }
    }

    @AuraEnabled
    public static String runAutoFix(List<Id> recordIds, String fixType) {
        // License Check
        if (!LicenseService.isPremium()) {
            throw new AuraHandledException('This is a Premium feature. Please upgrade BehaviorIQ to enable Auto-Fix.');
        }

        if (recordIds == null || recordIds.isEmpty()) {
            throw new AuraHandledException('No records selected for Auto-Fix.');
        }

        try {
            // Normalize inputs to be safe
            String normalizedType = (fixType != null) ? fixType.toLowerCase() : '';

            // Route to the appropriate fix logic in PatternFixService
            // Added fallbacks for Object Names ('case', 'lead') to be more robust for UI calls
            if (normalizedType.contains('case')) {
                PatternFixService.fixStaleCases(recordIds);
                return 'Success: Created high-priority tasks for ' + recordIds.size() + ' stale cases.';
            } else if (normalizedType.contains('lead')) {
                PatternFixService.fixUnassignedLeads(recordIds);
                return 'Success: Ownership claimed for ' + recordIds.size() + ' leads.';
            } else {
                throw new AuraHandledException('Unknown Auto-Fix type: ' + fixType);
            }
        } catch (Exception e) {
            // IMPROVED EXCEPTION HANDLING:
            // If the Service throws an AuraHandledException (e.g. Permission denied), throw it directly
            // so the UI sees the specific message instead of "Script-thrown exception".
            if (e instanceof AuraHandledException) {
                throw e;
            }
            // Otherwise, mask the internal stack trace but present the message
            throw new AuraHandledException('Auto-Fix failed: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String dismissSuggestion(Id painPointId) {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isUpdateable() || 
            !Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Pain Points.');
        }

        try {
            Identified_Pain_Point__c point = new Identified_Pain_Point__c(
                Id = painPointId,
                Status__c = 'Dismissed'
            );
            
            // Enforce Security on Update
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<Identified_Pain_Point__c>{point});
            update decision.getRecords();
            
            return 'Suggestion dismissed successfully.';
        } catch (Exception e) {
            throw new AuraHandledException('Error dismissing suggestion.');
        }
    }

    // --- NEW: Dashboard Initialization Method ---

    @AuraEnabled(cacheable=true)
    public static DashboardDataWrapper getDashboardData() {
        try {
            DashboardDataWrapper data = new DashboardDataWrapper();
            
            // 1. Inject License Status (The Gate)
            data.isPremium = LicenseService.isPremium(); 
            
            // 2. Fetch Metrics (Aggregated from Pain Points)
            data.metrics = getMetrics();

            // 3. Fetch Recent Logs 
            data.recentLogs = [
                SELECT Id, Action_Name__c, User__r.Name, CreatedDate, Object_API_Name__c 
                FROM Behavior_Log__c 
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC 
                LIMIT 10 
            ];

            return data;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load dashboard data: ' + e.getMessage());
        }
    }

    private static List<MetricWrapper> getMetrics() {
        List<MetricWrapper> metrics = new List<MetricWrapper>();
        
        // Aggregate from Identified_Pain_Point__c
        try {
            for (AggregateResult ar : [
                SELECT Status__c, Count(Id) cnt 
                FROM Identified_Pain_Point__c 
                WITH SECURITY_ENFORCED 
                GROUP BY Status__c
            ]) {
                String status = (String)ar.get('Status__c');
                Integer count = (Integer)ar.get('cnt');
                
                // Using 'New' as Active equivalent based on schema constraints
                if (status == 'New' || status == 'Active') {
                    metrics.add(new MetricWrapper('Active Anomalies', count, '+2%', 'alert', 'active_anomalies'));
                } else if (status == 'Dismissed') {
                    metrics.add(new MetricWrapper('Dismissed', count, '0%', 'success', 'dismissed_anomalies'));
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Metric Aggregation Error: ' + e.getMessage());
        }
        
        // If no data, add a placeholder or default metric
        if (metrics.isEmpty()) {
             Integer staleOppCount = 0;
             try {
                // Check if user has access to Opportunity before query
                if (Schema.sObjectType.Opportunity.isAccessible()) {
                    staleOppCount = [SELECT Count() FROM Opportunity WHERE LastStageChangeDate < LAST_N_DAYS:30 AND IsClosed = false WITH SECURITY_ENFORCED];
                }
             } catch (Exception e) { /* Handle lack of Opp access gracefully */ }
             
             metrics.add(new MetricWrapper('Stale Opportunities', staleOppCount, 'Live', 'warning', 'stale_opps'));
        }

        return metrics;
    }

    // --- NEW: Restored Analytics Methods ---

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getWorkflowStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        
        try {
            stats.put('totalLogs', [SELECT Count() FROM Behavior_Log__c WITH SECURITY_ENFORCED]);
            
            AggregateResult[] userResults = [SELECT User__c FROM Behavior_Log__c WITH SECURITY_ENFORCED GROUP BY User__c];
            stats.put('uniqueUsers', userResults.size());
            
            AggregateResult[] objectResults = [SELECT Object_API_Name__c FROM Behavior_Log__c WITH SECURITY_ENFORCED GROUP BY Object_API_Name__c];
            stats.put('objectsTracked', objectResults.size());
        } catch (Exception e) {
            throw new AuraHandledException('Unable to calculate stats.');
        }
        
        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> actions = new List<TopAction>();
        
        try {
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
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching top actions.');
        }
        return actions;
    }

    @AuraEnabled(cacheable=true)
    public static System_Health_Log__c getSystemHealth() {
        try {
            List<System_Health_Log__c> logs = [
                SELECT Id, Job_Name__c, Status__c, CreatedDate 
                FROM System_Health_Log__c 
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC 
                LIMIT 1 
            ];
            return logs.isEmpty() ? null : logs[0];
        } catch (Exception e) {
            return null; // Return null if error or no access, allowing UI to handle gracefully
        }
    }
}