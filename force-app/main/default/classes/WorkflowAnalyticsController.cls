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
        @AuraEnabled public String FixedRecordIds; // Cumulative list of fixed record IDs
        @AuraEnabled public Datetime LastModifiedDate; // Timestamp for when records were fixed

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
            this.FixedRecordIds = pp.Fixed_Record_Ids__c;
            this.LastModifiedDate = pp.LastModifiedDate;

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
            // Check premium status once for filtering
            Boolean userIsPremium = LicenseService.isPremium();

            // Build set of premium rule names for filtering (only needed for free users)
            // CMDT queries don't support WITH USER_MODE
            Set<String> premiumRuleNames = new Set<String>();
            if (!userIsPremium) {
                for (Behavior_Pattern_Rule__mdt rule : [  // NOPMD - ApexCRUDViolation: CMDT doesn't support USER_MODE
                    SELECT DeveloperName FROM Behavior_Pattern_Rule__mdt WHERE Is_Premium__c = true
                ]) {
                    premiumRuleNames.add(rule.DeveloperName);
                }
            }

            // Return ALL statuses so LWC can filter by Active/Dismissed tabs
            // Using USER_MODE for sharing/FLS enforcement
            List<Identified_Pain_Point__c> points = [
                SELECT Id, Name, Object_API_Name__c, Impact_Score__c, Status__c, Description__c,
                       Occurrences__c, Example_Records__c, Unique_Key__c, Cost_Per_Incident__c,
                       Fixed_Record_Ids__c, LastModifiedDate
                FROM Identified_Pain_Point__c
                WITH USER_MODE
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
                // Extract base rule name for partial fix pain points with timestamped keys
                // e.g., "Lead_Hoarding_1767994173771" -> "Lead_Hoarding"
                String baseKey = extractBaseRuleName(pp.Unique_Key__c);

                // PREMIUM GATING: Skip premium pain points for free users
                // Check both the base key and original key (for timestamped partial fix records)
                if (!userIsPremium && (premiumRuleNames.contains(baseKey) || premiumRuleNames.contains(pp.Unique_Key__c))) {
                    continue; // Skip this premium pain point for free users
                }

                Decimal costPerIncident = ruleCostMap.get(baseKey);

                // Fallback: if still null, try the original key (in case it's not timestamped)
                if (costPerIncident == null && baseKey != pp.Unique_Key__c) {
                    costPerIncident = ruleCostMap.get(pp.Unique_Key__c);
                }

                // Final fallback: use stored Cost_Per_Incident__c from the pain point itself
                if (costPerIncident == null && pp.Cost_Per_Incident__c != null) {
                    costPerIncident = pp.Cost_Per_Incident__c;
                }

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

        // 1. Load defaults from metadata - CMDT doesn't support USER_MODE
        try {
            for (Behavior_Pattern_Rule__mdt rule : [  // NOPMD - ApexCRUDViolation
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
                    WITH USER_MODE
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
     * @description Extracts the base rule name from a potentially timestamped unique key.
     * Pain points created from partial fixes have keys like "Lead_Hoarding_1767994173771".
     * This method strips the timestamp to get "Lead_Hoarding" for metadata lookups.
     * @param uniqueKey The unique key from the pain point record
     * @return The base rule name suitable for metadata lookup
     */
    @TestVisible
    private static String extractBaseRuleName(String uniqueKey) {
        if (String.isBlank(uniqueKey)) {
            return uniqueKey;
        }

        // Match pattern: ruleName_timestamp (e.g., Lead_Hoarding_1767994173771)
        // Timestamps are 13+ digit numbers (milliseconds since epoch)
        Integer lastUnderscore = uniqueKey.lastIndexOf('_');
        if (lastUnderscore > 0 && lastUnderscore < uniqueKey.length() - 1) {
            String possibleTimestamp = uniqueKey.substring(lastUnderscore + 1);
            // Check if the suffix is a numeric timestamp (10+ digits for epoch milliseconds)
            if (possibleTimestamp.isNumeric() && possibleTimestamp.length() >= 10) {
                return uniqueKey.substring(0, lastUnderscore);
            }
        }
        return uniqueKey;
    }

    /**
     * @description Wrapper class for fix configuration to display in UI
     */
    public class FixConfigInfo {
        @AuraEnabled public String fixType;
        @AuraEnabled public String description;
        @AuraEnabled public String subject;
        @AuraEnabled public String priority;
        @AuraEnabled public String fieldName;
        @AuraEnabled public String fieldValue;
        @AuraEnabled public String queueName;
        @AuraEnabled public Boolean isPremium;

        public FixConfigInfo() {
            this.isPremium = false;
        }
    }

    /**
     * @description Gets the fix configuration for a pattern rule to display in the confirmation dialog.
     * This allows the UI to show users exactly what action will be taken before they confirm.
     * @param ruleDeveloperName The developer name of the pattern rule (may include timestamp suffix)
     * @return FixConfigInfo containing the fix details
     */
    @AuraEnabled(cacheable=true)
    public static FixConfigInfo getFixConfig(String ruleDeveloperName) {
        FixConfigInfo info = new FixConfigInfo();

        if (String.isBlank(ruleDeveloperName)) {
            return info;
        }

        try {
            // Extract base rule name in case it's a timestamped key from partial fix
            String baseRuleName = extractBaseRuleName(ruleDeveloperName);

            // Query the metadata for fix configuration - CMDT doesn't support USER_MODE
            List<Behavior_Pattern_Rule__mdt> rules = [  // NOPMD - ApexCRUDViolation
                SELECT DeveloperName, Label, Fix_Type__c, Fix_Config__c, Is_Premium__c
                FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :baseRuleName
                LIMIT 1
            ];

            if (rules.isEmpty()) {
                // Try with original name if base name didn't match
                rules = [  // NOPMD - ApexCRUDViolation
                    SELECT DeveloperName, Label, Fix_Type__c, Fix_Config__c, Is_Premium__c
                    FROM Behavior_Pattern_Rule__mdt
                    WHERE DeveloperName = :ruleDeveloperName
                    LIMIT 1
                ];
            }

            if (!rules.isEmpty()) {
                Behavior_Pattern_Rule__mdt rule = rules[0];
                info.fixType = rule.Fix_Type__c;
                info.isPremium = rule.Is_Premium__c;

                // Parse Fix_Config__c JSON to extract details
                if (String.isNotBlank(rule.Fix_Config__c)) {
                    Map<String, Object> config = (Map<String, Object>)JSON.deserializeUntyped(rule.Fix_Config__c);

                    // Extract common fields based on fix type
                    if (config.containsKey('description')) {
                        info.description = String.valueOf(config.get('description'));
                    }
                    if (config.containsKey('subject')) {
                        info.subject = String.valueOf(config.get('subject'));
                    }
                    if (config.containsKey('priority')) {
                        info.priority = String.valueOf(config.get('priority'));
                    }
                    if (config.containsKey('field')) {
                        info.fieldName = String.valueOf(config.get('field'));
                    }
                    if (config.containsKey('value')) {
                        info.fieldValue = String.valueOf(config.get('value'));
                    }
                    if (config.containsKey('queueName')) {
                        info.queueName = String.valueOf(config.get('queueName'));
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting fix config for rule ' + ruleDeveloperName + ': ' + e.getMessage());
        }

        return info;
    }

    /**
     * @description Retrieves records by their IDs for display in the remediation preview.
     * Used to load previously fixed records for cumulative display.
     * @param objectApiName The API name of the object to query
     * @param recordIds Comma-separated list of record IDs to retrieve
     * @return List of SObject records with display fields
     */
    @AuraEnabled
    public static List<SObject> getRecordsByIds(String objectApiName, String recordIds) {
        if (String.isBlank(objectApiName) || String.isBlank(recordIds)) {
            return new List<SObject>();
        }

        try {
            // Parse the record IDs (handle both comma-separated and JSON array format)
            List<String> idStrings = new List<String>();
            String trimmedIds = recordIds.trim();

            if (trimmedIds.startsWith('[')) {
                // JSON array format
                try {
                    idStrings = (List<String>)JSON.deserialize(trimmedIds, List<String>.class);
                } catch (Exception jsonEx) {
                    // Fallback: strip brackets and quotes, then split
                    trimmedIds = trimmedIds.replace('[', '').replace(']', '').replace('"', '');
                    idStrings = trimmedIds.split(',');
                }
            } else {
                // Comma-separated format
                idStrings = trimmedIds.split(',');
            }

            // Convert to Id list and validate
            List<Id> idList = new List<Id>();
            for (String idStr : idStrings) {
                String trimmedId = idStr.trim();
                if (String.isNotBlank(trimmedId)) {
                    try {
                        idList.add(Id.valueOf(trimmedId));
                    } catch (Exception idEx) {
                        System.debug(LoggingLevel.WARN, 'Invalid ID skipped: ' + trimmedId);
                    }
                }
            }

            if (idList.isEmpty()) {
                return new List<SObject>();
            }

            // Build dynamic query based on object type
            // queryFields are Schema-validated via getDisplayFieldsForObject
            String queryFields = getDisplayFieldsForObject(objectApiName);
            String query = 'SELECT ' + queryFields + ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                          ' WHERE Id IN :idList WITH SECURITY_ENFORCED LIMIT 200';

            return Database.query(query);  // NOPMD - ApexSOQLInjection: queryFields are Schema-validated

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getRecordsByIds Error: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve records: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the display fields for a given object type.
     * Used by getRecordsByIds to build dynamic queries.
     */
    private static String getDisplayFieldsForObject(String objectApiName) {
        String objName = objectApiName.toLowerCase();

        if (objName == 'case') {
            return 'Id, CaseNumber, Subject, Status, Priority, CreatedDate';
        } else if (objName == 'opportunity') {
            return 'Id, Name, StageName, Amount, CloseDate, Probability';
        } else if (objName == 'lead') {
            return 'Id, Name, Company, Status, Email, Phone';
        } else if (objName == 'account') {
            return 'Id, Name, Industry, Type, Phone, CreatedDate';
        } else if (objName == 'contact') {
            return 'Id, Name, Email, Phone, Title, CreatedDate';
        } else {
            // Default fields that most objects have
            return 'Id, Name, CreatedDate';
        }
    }

    /**
     * @description Calculates the total Amount for Opportunities with proper sharing enforcement.
     * Uses a two-step approach: first queries with USER_MODE to filter by sharing rules,
     * then aggregates only the accessible records. This prevents information disclosure
     * where users could see aggregate totals that include records they can't access.
     * @param opportunityIds List of Opportunity IDs to sum
     * @return Total amount from accessible Opportunities, or 0 if none accessible
     */
    private static Decimal getOpportunityAmountWithSharing(List<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return 0;
        }

        try {
            // Step 1: Query with USER_MODE to get only accessible Opportunity IDs
            // This respects both OWD settings and sharing rules
            List<Opportunity> accessibleOpps = [
                SELECT Id, Amount
                FROM Opportunity
                WHERE Id IN :opportunityIds
                WITH USER_MODE
            ];

            // Step 2: Sum the amounts from only the accessible records
            Decimal totalAmount = 0;
            for (Opportunity opp : accessibleOpps) {
                if (opp.Amount != null) {
                    totalAmount += opp.Amount;
                }
            }

            return totalAmount;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getOpportunityAmountWithSharing error: ' + e.getMessage());
            return 0;
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
            // Use PatternFixService for ALL fix types - it handles:
            // Task_Creation, Field_Update, Owner_Assignment, Escalation_Revert, Opportunity_Creation, No_Action
            // The fixType parameter should be the rule's DeveloperName (e.g., "Contact_Data_Gap", "Stale_Case_14")
            String ruleDeveloperName = (fixType != null) ? fixType.replace(' ', '_').trim() : '';

            System.debug('Executing PatternFixService for rule: ' + ruleDeveloperName);

            PatternFixService service = new PatternFixService();
            service.executeFix(idList, ruleDeveloperName);

            // Build success message based on the rule
            String successMessage = 'Auto-Fix completed for ' + idList.size() + ' record(s).';

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

    // --- PAIN POINT RESOLUTION METHODS ---

    /**
     * @description Marks a pain point as resolved after auto-fix. Supports partial fixes by
     * creating a new pain point for remaining records and marking the original as resolved.
     * @param painPointId The ID of the pain point being fixed
     * @param fixedCount Number of records successfully fixed
     * @param totalCount Total number of records that were affected
     * @param fixedRecordIds Comma-separated list of record IDs that were fixed
     */
    @AuraEnabled
    public static void markPainPointResolved(String painPointId, Integer fixedCount, Integer totalCount, String fixedRecordIds) {
        System.debug('markPainPointResolved called with: painPointId=' + painPointId + ', fixedCount=' + fixedCount + ', totalCount=' + totalCount);

        if (String.isBlank(painPointId)) {
            throw new AuraHandledException('Pain Point ID is required');
        }

        // Query the original pain point
        List<Identified_Pain_Point__c> painPoints = [
            SELECT Id, Name, Status__c, Object_API_Name__c, Description__c,
                   Occurrences__c, Impact_Score__c, Example_Records__c, Unique_Key__c,
                   Cost_Per_Incident__c, Fixed_Record_Ids__c
            FROM Identified_Pain_Point__c
            WHERE Id = :painPointId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (painPoints.isEmpty()) {
            throw new AuraHandledException('Pain Point not found: ' + painPointId);
        }

        Identified_Pain_Point__c original = painPoints[0];
        System.debug('Found pain point: ' + original.Name + ' with current status: ' + original.Status__c);

        // Parse fixed record IDs - handle both JSON array and comma-separated formats
        Set<String> fixedIdSet = new Set<String>();
        if (String.isNotBlank(fixedRecordIds)) {
            String trimmedFixedIds = fixedRecordIds.trim();
            if (trimmedFixedIds.startsWith('[')) {
                // JSON array format: ["id1","id2",...]
                try {
                    List<String> parsedIds = (List<String>)JSON.deserialize(trimmedFixedIds, List<String>.class);
                    for (String fid : parsedIds) {
                        fixedIdSet.add(fid.trim());
                    }
                } catch (Exception jsonEx) {
                    System.debug(LoggingLevel.WARN, 'Failed to parse fixedRecordIds as JSON, falling back to string split: ' + jsonEx.getMessage());
                    // Fallback: strip brackets and quotes, then split
                    trimmedFixedIds = trimmedFixedIds.replace('[', '').replace(']', '').replace('"', '');
                    for (String fid : trimmedFixedIds.split(',')) {
                        fixedIdSet.add(fid.trim());
                    }
                }
            } else {
                // Plain comma-separated format
                for (String fid : trimmedFixedIds.split(',')) {
                    fixedIdSet.add(fid.trim());
                }
            }
        }
        System.debug('Fixed IDs to remove: ' + fixedIdSet);

        // Parse Example_Records__c - it's stored as JSON array format: ["id1","id2",...]
        List<String> remaining = new List<String>();
        if (String.isNotBlank(original.Example_Records__c)) {
            String exampleRecords = original.Example_Records__c.trim();
            List<String> originalIds;

            // Handle JSON array format
            if (exampleRecords.startsWith('[')) {
                try {
                    originalIds = (List<String>)JSON.deserialize(exampleRecords, List<String>.class);
                } catch (Exception jsonEx) {
                    System.debug(LoggingLevel.WARN, 'Failed to parse JSON array, falling back to string split: ' + jsonEx.getMessage());
                    // Fallback: strip brackets and quotes, then split
                    exampleRecords = exampleRecords.replace('[', '').replace(']', '').replace('"', '');
                    originalIds = exampleRecords.split(',');
                }
            } else {
                // Plain comma-separated format
                originalIds = exampleRecords.split(',');
            }

            System.debug('Original IDs from Example_Records__c: ' + originalIds);

            for (String recId : originalIds) {
                String trimmedId = recId.trim();
                if (String.isNotBlank(trimmedId) && !fixedIdSet.contains(trimmedId)) {
                    remaining.add(trimmedId);
                }
            }
        }

        // IMPORTANT: Use the totalCount from the LWC (from actual pattern query) to calculate
        // remaining records, NOT the size of Example_Records__c which is just a sample.
        // The LWC sends totalCount = fixedCount + remainingCount, so:
        Integer actualRemainingCount = (totalCount != null && totalCount > 0) ? (totalCount - fixedCount) : remaining.size();
        System.debug('Calculated remaining count: totalCount=' + totalCount + ', fixedCount=' + fixedCount +
                     ', actualRemainingCount=' + actualRemainingCount + ', sample remaining=' + remaining.size());

        Decimal costPerIncident = original.Cost_Per_Incident__c != null ? original.Cost_Per_Incident__c : 0;
        String objName = original.Object_API_Name__c != null ? original.Object_API_Name__c.toLowerCase() : '';

        // Build cumulative fixed record IDs: any previously fixed + newly fixed
        String cumulativeFixedIds = '';
        if (String.isNotBlank(original.Fixed_Record_Ids__c)) {
            cumulativeFixedIds = original.Fixed_Record_Ids__c;
            if (String.isNotBlank(fixedRecordIds)) {
                cumulativeFixedIds += ',' + fixedRecordIds;
            }
        } else {
            cumulativeFixedIds = fixedRecordIds;
        }

        // Check if this is a partial fix (remaining records exist)
        if (actualRemainingCount > 0) {
            // PARTIAL FIX: Two-part update:
            // 1. Update the SAME pain point with remaining records (stays in Active)
            // 2. Create a NEW Completed record for the fixed records (shows in Completed)
            System.debug('Partial fix: ' + fixedCount + ' fixed, ' + actualRemainingCount + ' remaining');

            // Calculate new impact score for remaining records
            Decimal remainingImpactScore = 0;
            Decimal fixedImpactScore = fixedCount * costPerIncident;

            if (objName == 'opportunity') {
                // Query remaining Opportunity records to sum actual Amount values
                if (!remaining.isEmpty()) {
                    try {
                        List<Id> remainingIds = new List<Id>();
                        for (String idStr : remaining) {
                            String trimmed = idStr.trim();
                            if (String.isNotBlank(trimmed)) {
                                remainingIds.add(Id.valueOf(trimmed));
                            }
                        }

                        if (!remainingIds.isEmpty()) {
                            // Use sharing-aware helper to ensure we only aggregate accessible records
                            remainingImpactScore = getOpportunityAmountWithSharing(remainingIds);
                        }
                    } catch (Exception oppEx) {
                        System.debug(LoggingLevel.WARN, 'Failed to query Opportunity amounts for remaining impact: ' + oppEx.getMessage());
                        remainingImpactScore = actualRemainingCount * costPerIncident;
                    }
                }

                // Query fixed Opportunity records to sum their Amount values
                if (!fixedIdSet.isEmpty()) {
                    try {
                        List<Id> fixedIds = new List<Id>();
                        for (String idStr : fixedIdSet) {
                            if (String.isNotBlank(idStr)) {
                                fixedIds.add(Id.valueOf(idStr.trim()));
                            }
                        }

                        if (!fixedIds.isEmpty()) {
                            // Use sharing-aware helper to ensure we only aggregate accessible records
                            fixedImpactScore = getOpportunityAmountWithSharing(fixedIds);
                        }
                    } catch (Exception fixedEx) {
                        System.debug(LoggingLevel.WARN, 'Failed to query fixed Opportunity amounts: ' + fixedEx.getMessage());
                    }
                }
            } else {
                remainingImpactScore = actualRemainingCount * costPerIncident;
            }

            // 1. Update the SAME pain point in place for remaining records
            original.Occurrences__c = actualRemainingCount;
            original.Impact_Score__c = remainingImpactScore;
            original.Example_Records__c = JSON.serialize(remaining);
            // ALSO update Fixed_Record_Ids__c on active record so preview can exclude already-fixed records
            original.Fixed_Record_Ids__c = cumulativeFixedIds;
            // Status stays as 'New' - still active with remaining records

            System.debug('Updating pain point in place: ' + actualRemainingCount + ' remaining, $' + remainingImpactScore + ' at risk');
            System.debug('Cumulative fixed IDs for filtering: ' + cumulativeFixedIds);

            // 2. Create a NEW Completed record for the fixed records
            if (Schema.sObjectType.Identified_Pain_Point__c.isCreateable()) {
                List<String> fixedIdsList = new List<String>(fixedIdSet);
                Identified_Pain_Point__c completedRecord = new Identified_Pain_Point__c(
                    Name = original.Name + ' (Partial Fix)',
                    Object_API_Name__c = original.Object_API_Name__c,
                    Status__c = 'Resolved',
                    Description__c = original.Description__c,
                    Occurrences__c = fixedCount,
                    Impact_Score__c = fixedImpactScore,
                    Example_Records__c = '[]', // Empty - all these records are fixed
                    Fixed_Record_Ids__c = JSON.serialize(fixedIdsList),
                    Unique_Key__c = original.Unique_Key__c + '_' + String.valueOf(System.currentTimeMillis()),
                    Cost_Per_Incident__c = costPerIncident
                );
                insert completedRecord;
                System.debug('Created Completed record for partial fix: ' + completedRecord.Id + ' with ' + fixedCount + ' fixed records');
            }

        } else {
            // FULL FIX: All records remediated - mark as Resolved
            System.debug('Full fix: All ' + fixedCount + ' records remediated');

            original.Status__c = 'Resolved';
            original.Occurrences__c = fixedCount;
            original.Example_Records__c = '[]'; // Clear - all records fixed
            original.Fixed_Record_Ids__c = cumulativeFixedIds;

            // Calculate impact score for resolved records (for ROI reporting)
            if (objName == 'opportunity' && String.isNotBlank(fixedRecordIds)) {
                try {
                    List<Id> resolvedIds = new List<Id>();
                    for (String idStr : fixedRecordIds.split(',')) {
                        String trimmed = idStr.trim();
                        if (String.isNotBlank(trimmed)) {
                            resolvedIds.add(Id.valueOf(trimmed));
                        }
                    }

                    if (!resolvedIds.isEmpty()) {
                        // Use sharing-aware helper to ensure we only aggregate accessible records
                        Decimal resolvedAmount = getOpportunityAmountWithSharing(resolvedIds);
                        if (resolvedAmount > 0) {
                            original.Impact_Score__c = resolvedAmount;
                        }
                    }
                } catch (Exception resolvedEx) {
                    System.debug(LoggingLevel.WARN, 'Failed to query fixed Opportunity amounts: ' + resolvedEx.getMessage());
                    original.Impact_Score__c = fixedCount * costPerIncident;
                }
            } else {
                original.Impact_Score__c = fixedCount * costPerIncident;
            }
        }

        if (!Schema.sObjectType.Identified_Pain_Point__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Pain Points');
        }
        update original;
        System.debug('Successfully updated pain point ' + original.Id + ': Status=' + original.Status__c + ', Occurrences=' + original.Occurrences__c);
    }

    /**
     * @description Extracts the base rule developer name from a Unique_Key__c value.
     * Pain points created from partial fixes may have timestamped keys like "High_Value_Ghosting_1767994173771".
     * This method returns the original rule key ("High_Value_Ghosting") that matches the metadata.
     * @param uniqueKey The Unique_Key__c value from a pain point
     * @return The base rule developer name without any timestamp suffix
     */
    private static String getBaseRuleKey(String uniqueKey) {
        if (String.isBlank(uniqueKey)) {
            return uniqueKey;
        }

        // Check if this key exists as a rule directly - CMDT doesn't support USER_MODE
        List<Behavior_Pattern_Rule__mdt> directMatch = [  // NOPMD - ApexCRUDViolation
            SELECT DeveloperName FROM Behavior_Pattern_Rule__mdt
            WHERE DeveloperName = :uniqueKey LIMIT 1
        ];
        if (!directMatch.isEmpty()) {
            return uniqueKey; // It's already a valid rule name
        }

        // Try to find the base rule by progressively removing underscore-suffixed segments
        // e.g., "High_Value_Ghosting_1767994173771" -> try "High_Value_Ghosting"
        String testKey = uniqueKey;
        while (testKey.contains('_')) {
            // Remove the last underscore segment
            Integer lastUnderscore = testKey.lastIndexOf('_');
            testKey = testKey.substring(0, lastUnderscore);

            List<Behavior_Pattern_Rule__mdt> match = [  // NOPMD - ApexCRUDViolation
                SELECT DeveloperName FROM Behavior_Pattern_Rule__mdt
                WHERE DeveloperName = :testKey LIMIT 1
            ];
            if (!match.isEmpty()) {
                return testKey;
            }
        }

        // No match found - return original (will likely fail but at least it's clear why)
        return uniqueKey;
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
     * @description Undoes a completed fix, restoring the pain point to Active status.
     * This is used when an admin wants to revert a fix that was applied via Auto-Fix.
     * Note: This only changes the pain point status - it does NOT revert the actual
     * data changes (e.g., task creation, lead reassignment). Those changes remain.
     * @param painPointId The Id of the resolved pain point to undo
     * @return Success message string
     */
    @AuraEnabled
    public static String undoPainPointFix(Id painPointId) {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isUpdateable() ||
            !Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to update Pain Points.');
        }

        try {
            // Verify the pain point exists and is in Resolved status
            List<Identified_Pain_Point__c> points = [
                SELECT Id, Status__c, Name
                FROM Identified_Pain_Point__c
                WHERE Id = :painPointId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (points.isEmpty()) {
                throw new AuraHandledException('Pain Point not found.');
            }

            if (points[0].Status__c != 'Resolved') {
                throw new AuraHandledException('Only resolved pain points can be undone.');
            }

            Identified_Pain_Point__c point = new Identified_Pain_Point__c(
                Id = painPointId,
                Status__c = 'New'
            );

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<Identified_Pain_Point__c>{point});
            update decision.getRecords();

            return 'Fix undone - "' + points[0].Name + '" restored to active.';
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error undoing fix: ' + e.getMessage());
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

        // Aggregate from Identified_Pain_Point__c with sharing-aware approach
        // Query records first with USER_MODE to respect sharing rules, then aggregate in Apex
        try {
            // Step 1: Query accessible pain points with USER_MODE
            List<Identified_Pain_Point__c> accessiblePainPoints = [
                SELECT Id, Status__c
                FROM Identified_Pain_Point__c
                WITH USER_MODE
                LIMIT 10000
            ];

            // Step 2: Aggregate counts by status in Apex
            Integer activeCount = 0;
            Integer dismissedCount = 0;
            for (Identified_Pain_Point__c pp : accessiblePainPoints) {
                if (pp.Status__c == 'New' || pp.Status__c == 'Active') {
                    activeCount++;
                } else if (pp.Status__c == 'Dismissed') {
                    dismissedCount++;
                }
            }

            if (activeCount > 0) {
                metrics.add(new MetricWrapper('Active Anomalies', activeCount, '+2%', 'alert', 'active_anomalies'));
            }
            if (dismissedCount > 0) {
                metrics.add(new MetricWrapper('Dismissed', dismissedCount, '0%', 'success', 'dismissed_anomalies'));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Metric Aggregation Error: ' + e.getMessage());
        }

        // If no data, add a placeholder or default metric
        if (metrics.isEmpty()) {
             Integer staleOppCount = 0;
             try {
                if (Schema.sObjectType.Opportunity.isAccessible()) {
                    // Query with USER_MODE to respect sharing rules, then count accessible records
                    List<Opportunity> staleOpps = [
                        SELECT Id
                        FROM Opportunity
                        WHERE LastStageChangeDate < LAST_N_DAYS:30 AND IsClosed = false
                        WITH USER_MODE
                        LIMIT 10000
                    ];
                    staleOppCount = staleOpps.size();
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
            // Query with USER_MODE to respect sharing rules, then aggregate in Apex
            // This prevents information disclosure where aggregate counts include inaccessible records
            List<Behavior_Log__c> accessibleLogs = [
                SELECT Id, User__c, Object_API_Name__c
                FROM Behavior_Log__c
                WITH USER_MODE
                LIMIT 50000
            ];

            // Count total accessible logs
            stats.put('totalLogs', accessibleLogs.size());

            // Count unique users from accessible logs
            Set<Id> uniqueUsers = new Set<Id>();
            Set<String> uniqueObjects = new Set<String>();
            for (Behavior_Log__c log : accessibleLogs) {
                if (log.User__c != null) {
                    uniqueUsers.add(log.User__c);
                }
                if (String.isNotBlank(log.Object_API_Name__c)) {
                    uniqueObjects.add(log.Object_API_Name__c);
                }
            }

            stats.put('uniqueUsers', uniqueUsers.size());
            stats.put('objectsTracked', uniqueObjects.size());
        } catch (Exception e) {
            throw new AuraHandledException('Unable to calculate stats.');
        }

        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<TopAction> getTopActions() {
        List<TopAction> actions = new List<TopAction>();

        try {
            // Query with USER_MODE to respect sharing rules, then aggregate in Apex
            // This prevents information disclosure where aggregate counts include inaccessible records
            List<Behavior_Log__c> accessibleLogs = [
                SELECT Id, Action_Name__c, Object_API_Name__c
                FROM Behavior_Log__c
                WHERE CreatedDate = LAST_N_DAYS:30
                WITH USER_MODE
                LIMIT 50000
            ];

            // Aggregate counts by action+object combination in Apex
            Map<String, TopAction> actionMap = new Map<String, TopAction>();
            for (Behavior_Log__c log : accessibleLogs) {
                String key = (log.Action_Name__c != null ? log.Action_Name__c : '') +
                             (log.Object_API_Name__c != null ? log.Object_API_Name__c : '');

                if (!actionMap.containsKey(key)) {
                    TopAction ta = new TopAction();
                    ta.actionName = log.Action_Name__c;
                    ta.objectName = log.Object_API_Name__c;
                    ta.count = 0;
                    ta.id = key;
                    actionMap.put(key, ta);
                }
                actionMap.get(key).count++;
            }

            // Sort by count descending and take top 10
            List<TopAction> allActions = actionMap.values();
            allActions.sort(new TopActionComparator());

            for (Integer i = 0; i < Math.min(10, allActions.size()); i++) {
                actions.add(allActions[i]);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching top actions.');
        }
        return actions;
    }

    /**
     * @description Comparator for sorting TopAction by count descending.
     */
    private class TopActionComparator implements Comparator<TopAction> {
        public Integer compare(TopAction a, TopAction b) {
            // Sort descending by count
            return b.count - a.count;
        }
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
     * @description Returns enhanced system health data with fallback to Behavior_Log__c.
     * If no System_Health_Log__c exists, falls back to the most recent Behavior_Log__c.
     * This ensures consistent "Last Scan" time across dashboard and system health panel.
     */
    @AuraEnabled(cacheable=true)
    public static SystemHealthWrapper getEnhancedSystemHealth() {
        SystemHealthWrapper wrapper = new SystemHealthWrapper();

        try {
            // First, try to get from System_Health_Log__c
            List<System_Health_Log__c> healthLogs = [
                SELECT Id, Job_Name__c, Status__c, CreatedDate
                FROM System_Health_Log__c
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!healthLogs.isEmpty()) {
                wrapper.lastRunTime = healthLogs[0].CreatedDate;
                wrapper.status = healthLogs[0].Status__c;
                wrapper.jobName = healthLogs[0].Job_Name__c;
                wrapper.source = 'System_Health_Log__c';
                wrapper.hasData = true;
                return wrapper;
            }

            // Fallback: Check Behavior_Log__c for most recent activity
            if (Schema.sObjectType.Behavior_Log__c.isAccessible()) {
                List<Behavior_Log__c> behaviorLogs = [
                    SELECT Id, CreatedDate
                    FROM Behavior_Log__c
                    WITH SECURITY_ENFORCED
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (!behaviorLogs.isEmpty()) {
                    wrapper.lastRunTime = behaviorLogs[0].CreatedDate;
                    wrapper.status = 'Success';
                    wrapper.jobName = 'Behavior Tracking';
                    wrapper.source = 'Behavior_Log__c';
                    wrapper.hasData = true;
                    return wrapper;
                }
            }

            // No data available
            wrapper.hasData = false;
            wrapper.status = 'No Data';

        } catch (Exception e) {
            wrapper.hasData = false;
            wrapper.status = 'Error';
            wrapper.errorMessage = e.getMessage();
        }

        return wrapper;
    }

    /**
     * Wrapper class for enhanced system health data
     */
    public class SystemHealthWrapper {
        @AuraEnabled public Datetime lastRunTime;
        @AuraEnabled public String status;
        @AuraEnabled public String jobName;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean hasData;
        @AuraEnabled public String errorMessage;
    }

    /**
     * @description Manually triggers the pattern analysis batch job.
     * Allows admins to run analysis on-demand instead of waiting for the scheduled 2 AM run.
     * Checks if a job is already running to prevent duplicate executions.
     * @return String message indicating success or if a job is already in progress
     */
    @AuraEnabled
    public static String runAnalysisNow() {
        try {
            // Check if there's already a batch running
            // Note: AsyncApexJob is a setup object and requires specific permissions
            List<AsyncApexJob> runningJobs = [
                SELECT Id, Status, CreatedDate
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'PatternAnalysisService'
                AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
                WITH USER_MODE
                LIMIT 1
            ];

            if (!runningJobs.isEmpty()) {
                return 'Analysis job is already running. Please wait for it to complete.';
            }

            // Start the batch job
            Database.executeBatch(new PatternAnalysisService(), 50);

            return 'Analysis job started successfully. Results will appear shortly.';

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'runAnalysisNow Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to start analysis: ' + e.getMessage());
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

    /**
     * @description Returns the count of monitored objects from BehaviorIQ configuration.
     * Used by the dashboard to display accurate "Objects Monitored" metric.
     * @return Integer count of configured monitored objects
     */
    @AuraEnabled(cacheable=true)
    public static Integer getMonitoredObjectsCount() {
        try {
            if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isAccessible()) {
                return 0;
            }
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Monitored_Objects__c
                FROM BehaviorIQ_Configuration__c
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (configs.isEmpty() || String.isBlank(configs[0].Monitored_Objects__c)) {
                return 0;
            }
            // Count comma-separated values
            return configs[0].Monitored_Objects__c.split(',').size();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getMonitoredObjectsCount error: ' + e.getMessage());
            return 0;
        }
    }

    /**
     * @description Returns the count of active standard users in the org.
     * Used by the dashboard to display accurate "Active Users" metric.
     * Filters to UserType='Standard' to exclude system users (Integration User,
     * Automated Process, Security User, etc.)
     * @return Integer count of active standard users, or 0 if no access or on error
     */
    @AuraEnabled(cacheable=true)
    public static Integer getActiveUsersCount() {
        try {
            if (!Schema.sObjectType.User.isAccessible()) {
                return 0;
            }
            // Filter to Standard users only - excludes system users like:
            // - Integration User, Automated Process, Security User, Platform Integration, etc.
            return [SELECT COUNT() FROM User WHERE IsActive = true AND UserType = 'Standard' WITH SECURITY_ENFORCED];
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getActiveUsersCount error: ' + e.getMessage());
            return 0;
        }
    }

    // --- NEW: Trend Data for Charts ---

    // Constants for trend data retrieval - documented rationale:
    // MAX_DAYS_BACK: 90 days provides sufficient historical context while limiting query scope
    // MAX_TREND_ROWS: 2000 rows accommodates ~20 metrics * 90 days with buffer
    // MAX_AGG_POINTS: 90 points = max 1 per day for 90 days
    private static final Integer MAX_DAYS_BACK = 90;
    private static final Integer DEFAULT_DAYS_BACK = 30;
    private static final Integer MAX_TREND_ROWS = 2000;
    private static final Integer MAX_AGG_POINTS = 90;

    // Date formatting cache to reduce CPU overhead
    private static Map<Date, String> dateFormatCache = new Map<Date, String>();

    /**
     * @description Wrapper for trend data point used in the trend chart visualization.
     * Each data point represents a snapshot in time with associated metrics.
     */
    public class TrendDataPoint {
        @AuraEnabled public Date snapshotDate { get; set; }
        @AuraEnabled public String metricName { get; set; }
        @AuraEnabled public Integer recordCount { get; set; }
        @AuraEnabled public Decimal impactScore { get; set; }
        @AuraEnabled public String formattedDate { get; set; }

        public TrendDataPoint(Behavior_Snapshot__c snapshot) {
            this.snapshotDate = snapshot.Snapshot_Date__c;
            this.metricName = snapshot.Metric_Name__c;
            this.recordCount = snapshot.Record_Count__c != null ? snapshot.Record_Count__c.intValue() : 0;
            this.impactScore = snapshot.Impact_Score__c != null ? snapshot.Impact_Score__c : 0;
            // Use cached date formatting to reduce CPU overhead
            this.formattedDate = formatDateCached(snapshot.Snapshot_Date__c);
        }
    }

    /**
     * @description Formats a date with caching to reduce CPU overhead at scale.
     * Uses GMT formatting for consistent output across user timezones.
     * @param d The date to format
     * @return Formatted string like "Jan 15"
     */
    private static String formatDateCached(Date d) {
        if (d == null) {
            return '';
        }
        if (dateFormatCache.containsKey(d)) {
            return dateFormatCache.get(d);
        }
        Datetime dt = Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0));
        String formatted = dt.formatGmt('MMM d');
        dateFormatCache.put(d, formatted);
        return formatted;
    }

    /**
     * @description Wrapper for aggregated trend data grouped by metric/pattern.
     * Contains multiple data points for charting trends over time.
     */
    public class TrendSeries {
        @AuraEnabled public String metricName { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public List<TrendDataPoint> dataPoints { get; set; }
        @AuraEnabled public String color { get; set; }

        public TrendSeries(String metricName) {
            this.metricName = metricName;
            this.displayName = WorkflowAnalyticsController.formatMetricDisplayName(metricName);
            this.dataPoints = new List<TrendDataPoint>();
            this.color = WorkflowAnalyticsController.getColorForMetric(metricName);
        }
    }

    /**
     * @description Converts snake_case metric name to space-separated display name.
     * Example: "High_Value_Ghosting" -> "High Value Ghosting"
     */
    private static String formatMetricDisplayName(String metricName) {
        if (String.isBlank(metricName)) return 'Unknown';
        return metricName.replace('_', ' ');
    }

    /**
     * @description Assigns a consistent color based on metric name hash.
     * Null-safe: treats blank/null as 'Other' for consistent coloring.
     */
    private static String getColorForMetric(String metricName) {
        List<String> colors = new List<String>{
            '#0176d3', // Salesforce blue
            '#ff5d2d', // Orange
            '#4bca81', // Green
            '#9050e9', // Purple
            '#ffb75d', // Yellow
            '#ff538a', // Pink
            '#1589ee', // Light blue
            '#c23934'  // Red
        };
        // Null-safe: use 'Other' for blank metric names
        String safeName = String.isBlank(metricName) ? 'Other' : metricName;
        Integer hash = Math.abs(safeName.hashCode());
        return colors[Math.mod(hash, colors.size())];
    }

    /**
     * @description Wrapper for trend data response including truncation metadata.
     */
    public class TrendDataResponse {
        @AuraEnabled public List<TrendSeries> series { get; set; }
        @AuraEnabled public Boolean isTruncated { get; set; }
        @AuraEnabled public Integer totalRecordsQueried { get; set; }

        public TrendDataResponse() {
            this.series = new List<TrendSeries>();
            this.isTruncated = false;
            this.totalRecordsQueried = 0;
        }
    }

    /**
     * @description Retrieves trend data from Behavior_Snapshot__c for the trend chart.
     * Returns data grouped by metric/pattern name over the specified time period.
     * Results are sorted alphabetically by metric name for deterministic ordering.
     * @param daysBack Number of days to look back (default 30, max 90)
     * @return TrendDataResponse containing sorted TrendSeries and truncation metadata
     */
    @AuraEnabled(cacheable=true)
    public static TrendDataResponse getTrendData(Integer daysBack) {
        TrendDataResponse response = new TrendDataResponse();

        if (!Schema.sObjectType.Behavior_Snapshot__c.isAccessible()) {
            return response;
        }

        try {
            // Validate and constrain daysBack parameter
            if (daysBack == null || daysBack <= 0) {
                daysBack = DEFAULT_DAYS_BACK;
            }
            daysBack = Math.min(daysBack, MAX_DAYS_BACK);

            Date startDate = Date.today().addDays(-daysBack);

            // Query snapshots - ordered by metric and date for efficient grouping
            List<Behavior_Snapshot__c> snapshots = [
                SELECT Id, Snapshot_Date__c, Metric_Name__c, Record_Count__c, Impact_Score__c
                FROM Behavior_Snapshot__c
                WHERE Snapshot_Date__c >= :startDate
                WITH SECURITY_ENFORCED
                ORDER BY Metric_Name__c ASC, Snapshot_Date__c ASC
                LIMIT :MAX_TREND_ROWS
            ];

            response.totalRecordsQueried = snapshots.size();
            response.isTruncated = snapshots.size() >= MAX_TREND_ROWS;

            // Group by metric name using ordered map for deterministic output
            Map<String, TrendSeries> seriesMap = new Map<String, TrendSeries>();

            for (Behavior_Snapshot__c snapshot : snapshots) {
                String metricName = snapshot.Metric_Name__c;
                if (String.isBlank(metricName)) {
                    metricName = 'Other';
                }

                if (!seriesMap.containsKey(metricName)) {
                    seriesMap.put(metricName, new TrendSeries(metricName));
                }

                seriesMap.get(metricName).dataPoints.add(new TrendDataPoint(snapshot));
            }

            // Sort series alphabetically for deterministic ordering
            List<String> sortedMetricNames = new List<String>(seriesMap.keySet());
            sortedMetricNames.sort();

            for (String metricName : sortedMetricNames) {
                response.series.add(seriesMap.get(metricName));
            }

            return response;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getTrendData Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
            // Throw user-friendly exception rather than silently returning empty data
            throw new AuraHandledException('Unable to load trend data. Please try again or contact your administrator.');
        }
    }

    /**
     * @description Gets aggregated trend data showing total issues over time.
     * Useful for showing overall org health trend on the dashboard.
     * @param daysBack Number of days to look back (default 30, max 90)
     * @return List of aggregated data points with total counts per date, ordered by date
     */
    @AuraEnabled(cacheable=true)
    public static List<TrendDataPoint> getAggregatedTrendData(Integer daysBack) {
        if (!Schema.sObjectType.Behavior_Snapshot__c.isAccessible()) {
            return new List<TrendDataPoint>();
        }

        try {
            // Validate and constrain daysBack parameter
            if (daysBack == null || daysBack <= 0) {
                daysBack = DEFAULT_DAYS_BACK;
            }
            daysBack = Math.min(daysBack, MAX_DAYS_BACK);

            Date startDate = Date.today().addDays(-daysBack);

            // Aggregate by date - MAX_AGG_POINTS accommodates 1 point per day for max days
            List<AggregateResult> results = [
                SELECT Snapshot_Date__c snapDate,
                       SUM(Record_Count__c) totalRecords,
                       SUM(Impact_Score__c) totalImpact
                FROM Behavior_Snapshot__c
                WHERE Snapshot_Date__c >= :startDate
                WITH SECURITY_ENFORCED
                GROUP BY Snapshot_Date__c
                ORDER BY Snapshot_Date__c ASC
                LIMIT :MAX_AGG_POINTS
            ];

            List<TrendDataPoint> dataPoints = new List<TrendDataPoint>();
            for (AggregateResult ar : results) {
                TrendDataPoint point = new TrendDataPoint(new Behavior_Snapshot__c(
                    Snapshot_Date__c = (Date)ar.get('snapDate'),
                    Metric_Name__c = 'Total Issues',
                    Record_Count__c = (Decimal)ar.get('totalRecords'),
                    Impact_Score__c = (Decimal)ar.get('totalImpact')
                ));
                dataPoints.add(point);
            }

            return dataPoints;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getAggregatedTrendData Error: ' + e.getMessage() + ' | Stack: ' + e.getStackTraceString());
            // Throw user-friendly exception rather than silently returning empty data
            throw new AuraHandledException('Unable to load aggregated trend data. Please try again or contact your administrator.');
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