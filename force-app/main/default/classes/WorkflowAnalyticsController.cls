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
            System.debug(LoggingLevel.ERROR, 'getPainPoints Error: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving analytics data. Please check logs.');
        }
    }

    /**
     * @description Result wrapper for Auto-Fix operations to support "Inbox Zero" UX
     */
    public class AutoFixResult {
        @AuraEnabled public String message;
        @AuraEnabled public List<String> fixedRecordIds;
        @AuraEnabled public Integer fixedCount;

        public AutoFixResult(String message, List<Id> fixedIds) {
            this.message = message;
            this.fixedRecordIds = new List<String>();
            for (Id recId : fixedIds) {
                this.fixedRecordIds.add(String.valueOf(recId));
            }
            this.fixedCount = fixedIds.size();
        }
    }

    @AuraEnabled
    public static AutoFixResult runAutoFix(List<String> recordIds, String fixType) {
        // License Check
        if (!LicenseService.isPremium()) {
            String msg = 'This is a Premium feature. Please upgrade BehaviorIQ to enable Auto-Fix.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        if (recordIds == null || recordIds.isEmpty()) {
            String msg = 'No records selected for Auto-Fix.';
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }

        // CRITICAL FIX: Convert List<String> to List<Id>
        List<Id> idList = new List<Id>();
        for (String idStr : recordIds) {
            try {
                idList.add((Id)idStr);
            } catch (Exception ex) {
                String msg = 'Invalid Record ID format: ' + idStr;
                AuraHandledException e = new AuraHandledException(msg);
                e.setMessage(msg);
                throw e;
            }
        }

        System.debug('runAutoFix called with:');
        System.debug('  recordIds: ' + recordIds);
        System.debug('  fixType: ' + fixType);
        System.debug('  Converted to Id List: ' + idList);

        try {
            // Normalize the fixType to handle variations
            String normalizedType = (fixType != null) ? fixType.toLowerCase().trim() : '';
            String successMessage;

            // Route to appropriate fix method based on type
            if (normalizedType.contains('case')) {
                fixStaleCases(idList);
                successMessage = 'Created high-priority tasks for ' + idList.size() + ' stale cases.';
            } else if (normalizedType.contains('lead')) {
                fixUnassignedLeads(idList);
                successMessage = 'Ownership claimed for ' + idList.size() + ' leads.';
            } else if (normalizedType.contains('opportunity')) {
                fixStaleOpportunities(idList);
                successMessage = 'Created follow-up tasks for ' + idList.size() + ' stale opportunities.';
            } else {
                // Try metadata-driven approach for other types
                try {
                    PatternFixService service = new PatternFixService();
                    String metaName = fixType.replace(' ', '_');
                    service.executeFix(idList, metaName);
                    successMessage = 'Auto-Fix executed for ' + fixType;
                } catch (Exception metaEx) {
                    System.debug(LoggingLevel.ERROR, 'Metadata-driven fix failed: ' + metaEx.getMessage());
                    String msg = 'Auto-Fix not yet implemented for: ' + fixType;
                    AuraHandledException e = new AuraHandledException(msg);
                    e.setMessage(msg);
                    throw e;
                }
            }

            // Return result with fixed record IDs for UI state management
            return new AutoFixResult(successMessage, idList);

        } catch (AuraHandledException ahe) {
            // Re-throw AuraHandledException as-is
            throw ahe;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'runAutoFix Error: ' + ex.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + ex.getStackTraceString());
            String msg = 'Auto-Fix failed: ' + ex.getMessage();
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }
    }

    // --- LEGACY FIX METHODS (Kept for backward compatibility) ---
    
    private static void fixStaleCases(List<Id> recordIds) {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Tasks.');
        }

        List<Task> tasks = new List<Task>();
        for (Id caseId : recordIds) {
            tasks.add(new Task(
                Subject = 'URGENT: Follow up on stale case',
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(1),
                WhatId = caseId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, tasks);
        insert decision.getRecords();
    }

    private static void fixUnassignedLeads(List<Id> recordIds) {
        if (!Schema.sObjectType.Lead.isUpdateable() || 
            !Schema.sObjectType.Lead.fields.OwnerId.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Leads.');
        }

        List<Lead> leads = new List<Lead>();
        for (Id leadId : recordIds) {
            leads.add(new Lead(
                Id = leadId,
                OwnerId = UserInfo.getUserId()
            ));
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, leads);
        update decision.getRecords();
    }

    private static void fixStaleOpportunities(List<Id> recordIds) {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create Tasks.');
        }

        List<Task> tasks = new List<Task>();
        for (Id oppId : recordIds) {
            tasks.add(new Task(
                Subject = 'Follow up on stale opportunity',
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(2),
                WhatId = oppId,
                OwnerId = UserInfo.getUserId(),
                Description = 'This opportunity has been inactive. Please review and update the stage or close it.'
            ));
        }

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, tasks);
        insert decision.getRecords();
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
            data.recentLogs = getRecentLogs();

            return data;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load dashboard data: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Behavior_Log__c> getRecentLogs() {
        try {
            return [
                SELECT Id, Action_Name__c, User__r.Name, CreatedDate, Object_API_Name__c 
                FROM Behavior_Log__c 
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC 
                LIMIT 10 
            ];
        } catch (Exception e) {
            return new List<Behavior_Log__c>();
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
            return null;
        }
    }
}