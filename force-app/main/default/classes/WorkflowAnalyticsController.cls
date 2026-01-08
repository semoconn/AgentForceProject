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

    /**
     * @description Wrapper class for pain points with ROI data.
     * Uses the original SObject plus additional ROI fields for LWC binding.
     *
     * ROI Calculation Strategy:
     * - Opportunity/Contract: Use stored Impact_Score__c (cumulative value from actual record amounts)
     * - Other objects (Case, Lead, etc.): Calculate from Occurrences * CostPerIncident
     */
    public class PainPointWithROI {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String ObjectApiName;
        @AuraEnabled public Decimal ImpactScore;
        @AuraEnabled public String Status;
        @AuraEnabled public String Description;
        @AuraEnabled public Decimal Occurrences;
        @AuraEnabled public String ExampleRecords;
        @AuraEnabled public String UniqueKey;
        @AuraEnabled public Decimal EstimatedSavings;
        @AuraEnabled public Decimal CostPerIncident;

        public PainPointWithROI(Identified_Pain_Point__c pp, Decimal costPerIncident) {
            this.Id = pp.Id;
            this.Name = pp.Name;
            this.ObjectApiName = pp.Object_API_Name__c;
            this.ImpactScore = pp.Impact_Score__c;
            this.Status = pp.Status__c;
            this.Description = pp.Description__c;
            this.Occurrences = pp.Occurrences__c;
            this.ExampleRecords = pp.Example_Records__c;
            this.UniqueKey = pp.Unique_Key__c;
            this.CostPerIncident = costPerIncident != null ? costPerIncident : 0;

            // For Opportunity and Contract, Impact_Score__c holds the cumulative actual value at risk
            // For other objects, calculate from occurrences * cost per incident
            String objName = pp.Object_API_Name__c != null ? pp.Object_API_Name__c.toLowerCase() : '';
            if (objName == 'opportunity' || objName == 'contract') {
                // Use stored cumulative value (sum of actual Opportunity.Amount or Contract value)
                this.EstimatedSavings = pp.Impact_Score__c != null ? pp.Impact_Score__c : 0;
            } else {
                // Calculate: occurrences * cost per incident
                this.EstimatedSavings = (pp.Occurrences__c != null && costPerIncident != null)
                    ? pp.Occurrences__c * costPerIncident
                    : 0;
            }
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PainPointWithROI> getPainPoints() {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions to view Pain Points.');
        }

        try {
            // Return ALL statuses so LWC can filter by Active/Dismissed tabs
            List<Identified_Pain_Point__c> points = [
                SELECT Id, Name, Object_API_Name__c, Impact_Score__c, Status__c, Description__c, Occurrences__c, Example_Records__c, Unique_Key__c
                FROM Identified_Pain_Point__c
                ORDER BY Impact_Score__c DESC
                LIMIT 100
            ];

            // Enforce Security on the result set
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, points);
            List<Identified_Pain_Point__c> securedPoints = (List<Identified_Pain_Point__c>) decision.getRecords();

            // Build ROI data by fetching cost per incident from metadata and configuration
            Map<String, Decimal> ruleCostMap = getRuleCostMap();

            // Convert to wrapper with ROI data
            // For Opportunity and Contract objects, use stored Impact_Score (cumulative value)
            // For other objects, calculate from occurrences * cost per incident
            List<PainPointWithROI> results = new List<PainPointWithROI>();
            for (Identified_Pain_Point__c pp : securedPoints) {
                Decimal costPerIncident = ruleCostMap.get(pp.Unique_Key__c);
                results.add(new PainPointWithROI(pp, costPerIncident));
            }

            return results;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getPainPoints Error: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving analytics data. Please check logs.');
        }
    }

    /**
     * @description Builds a map of rule DeveloperName to Cost_Per_Incident value.
     * Prioritizes user overrides from BehaviorIQ_Configuration__c over metadata defaults.
     * @return Map of rule DeveloperName to cost value
     */
    private static Map<String, Decimal> getRuleCostMap() {
        Map<String, Decimal> costMap = new Map<String, Decimal>();

        // 1. Load defaults from metadata
        try {
            for (Behavior_Pattern_Rule__mdt rule : [
                SELECT DeveloperName, Cost_Per_Incident__c
                FROM Behavior_Pattern_Rule__mdt
            ]) {
                if (rule.Cost_Per_Incident__c != null) {
                    costMap.put(rule.DeveloperName, rule.Cost_Per_Incident__c);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to load rule costs from metadata: ' + e.getMessage());
        }

        // 2. Apply user overrides from configuration
        try {
            if (Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                List<BehaviorIQ_Configuration__c> configs = [
                    SELECT Cost_Override__c
                    FROM BehaviorIQ_Configuration__c
                    LIMIT 1
                ];

                if (!configs.isEmpty() && String.isNotBlank(configs[0].Cost_Override__c)) {
                    Map<String, Object> overrides = (Map<String, Object>)JSON.deserializeUntyped(configs[0].Cost_Override__c);
                    for (String ruleName : overrides.keySet()) {
                        Object value = overrides.get(ruleName);
                        if (value instanceof Decimal) {
                            costMap.put(ruleName, (Decimal)value);
                        } else if (value instanceof Integer) {
                            costMap.put(ruleName, Decimal.valueOf((Integer)value));
                        } else if (value instanceof Double) {
                            costMap.put(ruleName, Decimal.valueOf((Double)value));
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to load cost overrides from configuration: ' + e.getMessage());
        }

        return costMap;
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

    /**
     * @description Restores a dismissed pain point back to active status.
     * @param painPointId The Id of the pain point to restore.
     * @return Success message string.
     */
    @AuraEnabled
    public static String restoreSuggestion(Id painPointId) {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isUpdateable() ||
            !Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Pain Points.');
        }

        try {
            Identified_Pain_Point__c point = new Identified_Pain_Point__c(
                Id = painPointId,
                Status__c = 'New'
            );

            // Enforce Security on Update
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<Identified_Pain_Point__c>{point});
            update decision.getRecords();

            return 'Suggestion restored successfully.';
        } catch (Exception e) {
            throw new AuraHandledException('Error restoring suggestion.');
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

    /**
     * @description Returns the total count of Behavior_Log__c records analyzed.
     * Used by the dashboard to display dynamic "Events Analyzed" metric instead of hardcoded values.
     * @return Integer count of all behavior log records, or 0 if none exist or on error
     */
    @AuraEnabled(cacheable=true)
    public static Integer getTotalEventsAnalyzed() {
        try {
            if (!Schema.sObjectType.Behavior_Log__c.isAccessible()) {
                return 0;
            }
            return [SELECT COUNT() FROM Behavior_Log__c WITH SECURITY_ENFORCED];
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getTotalEventsAnalyzed error: ' + e.getMessage());
            return 0;
        }
    }

    // --- NEW: Org Health Score Gamification Engine ---

    /**
     * @description Wrapper for health score with status text and total at risk
     */
    public class HealthScoreResult {
        @AuraEnabled public Integer score { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer highCount { get; set; }
        @AuraEnabled public Integer mediumCount { get; set; }
        @AuraEnabled public Integer lowCount { get; set; }
        @AuraEnabled public Decimal totalAtRisk { get; set; }

        public HealthScoreResult(Integer score, String status, Integer highCount, Integer mediumCount, Integer lowCount, Decimal totalAtRisk) {
            this.score = score;
            this.status = status;
            this.highCount = highCount;
            this.mediumCount = mediumCount;
            this.lowCount = lowCount;
            this.totalAtRisk = totalAtRisk;
        }
    }

    /**
     * @description Calculates the Org Health Score based on active pain points.
     * Gamification scoring: Start at 100, deduct points based on actual dollar risk.
     *
     * Severity Classification (based on Impact_Score__c which stores actual $ at risk):
     * - High Severity (>= $50,000 at risk): -15 points each, cap at -45
     * - Medium Severity ($5,000 - $49,999 at risk): -8 points each, cap at -30
     * - Low Severity (< $5,000 at risk): -2 points each, cap at -20
     *
     * Floor: 0 (score cannot go negative)
     * @return HealthScoreResult containing score (0-100), status text, and breakdown counts
     */
    @AuraEnabled(cacheable=true)
    public static HealthScoreResult getHealthScore() {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            return new HealthScoreResult(100, 'Healthy', 0, 0, 0, 0);
        }

        try {
            Integer score = 100;
            Integer highCount = 0;
            Integer mediumCount = 0;
            Integer lowCount = 0;
            Decimal totalAtRisk = 0;

            // Build cost map from metadata (for fallback calculation)
            Map<String, Decimal> ruleCostMap = getRuleCostMap();

            // Get active pain points with Impact_Score__c for dollar-based severity
            List<Identified_Pain_Point__c> activePoints = [
                SELECT Id, Unique_Key__c, Occurrences__c, Object_API_Name__c, Impact_Score__c
                FROM Identified_Pain_Point__c
                WHERE Status__c = 'New' OR Status__c = 'Active'
                WITH SECURITY_ENFORCED
                LIMIT 100
            ];

            // Calculate deductions based on actual dollar risk
            Integer highDeduction = 0;
            Integer mediumDeduction = 0;
            Integer lowDeduction = 0;

            for (Identified_Pain_Point__c pp : activePoints) {
                String objName = pp.Object_API_Name__c != null ? pp.Object_API_Name__c.toLowerCase() : '';

                // Determine the dollar amount at risk
                Decimal dollarRisk = 0;
                if (objName == 'opportunity' || objName == 'contract') {
                    // For Opportunity/Contract, use stored Impact_Score (cumulative value)
                    dollarRisk = pp.Impact_Score__c != null ? pp.Impact_Score__c : 0;
                } else {
                    // For other objects, calculate from occurrences * cost per incident
                    Decimal costPerIncident = ruleCostMap.get(pp.Unique_Key__c);
                    if (costPerIncident != null && pp.Occurrences__c != null) {
                        dollarRisk = pp.Occurrences__c * costPerIncident;
                    }
                }

                // Add to total at risk
                totalAtRisk += dollarRisk;

                // Classify severity based on dollar amount at risk
                if (dollarRisk >= 50000) {
                    // High Severity: >= $50K at risk
                    highCount++;
                    highDeduction = Math.min(highDeduction + 15, 45);
                } else if (dollarRisk >= 5000) {
                    // Medium Severity: $5K - $50K at risk
                    mediumCount++;
                    mediumDeduction = Math.min(mediumDeduction + 8, 30);
                } else if (dollarRisk > 0) {
                    // Low Severity: < $5K at risk
                    lowCount++;
                    lowDeduction = Math.min(lowDeduction + 2, 20);
                }
                // Items with $0 risk don't affect score
            }

            // Apply deductions
            score = score - highDeduction - mediumDeduction - lowDeduction;

            // Floor at 0
            score = Math.max(score, 0);

            // Determine status text
            String status;
            if (score > 80) {
                status = 'Your Org is Healthy';
            } else if (score >= 50) {
                status = 'Needs Attention';
            } else {
                status = 'Critical Issues Found';
            }

            return new HealthScoreResult(score, status, highCount, mediumCount, lowCount, totalAtRisk);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getHealthScore Error: ' + e.getMessage());
            return new HealthScoreResult(100, 'Healthy', 0, 0, 0, 0);
        }
    }
}