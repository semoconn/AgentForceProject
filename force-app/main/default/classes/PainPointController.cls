/**
 * @description Controller for the BehaviorIQ Dashboard LWC.
 * Bridges the "Insight" layer (Identified Pain Points) to the UI.
 * @version 3.1 - Phase 3 Metadata Support + Robust Security (stripInaccessible)
 */
public with sharing class PainPointController {

    /**
     * @description Fetches active pain points. Uses stripInaccessible to ensure partial results 
     * return even if user lacks FLS on specific non-critical fields.
     * @return List of Identified_Pain_Point__c records.
     */
    @AuraEnabled
    public static List<Identified_Pain_Point__c> getOpenPainPoints() {
        try {
            // Raw query without WITH SECURITY_ENFORCED to prevent all-or-nothing crashes
            List<Identified_Pain_Point__c> rawResults = [
                SELECT Id, Name, Description__c, Impact_Score__c, Status__c, 
                       Occurrences__c, Last_Detected__c, 
                       Unique_Key__c, Example_Records__c, Object_API_Name__c
                FROM Identified_Pain_Point__c
                WHERE Status__c != 'Dismissed'
                ORDER BY Impact_Score__c DESC, Last_Detected__c DESC
                LIMIT 50
            ];

            // Gracefully strip fields the user cannot see
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.READABLE, rawResults);
            return (List<Identified_Pain_Point__c>)securityDecision.getRecords();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Dashboard Query Error: ' + e.getMessage());
            throw new AuraHandledException('Unable to load findings: ' + e.getMessage());
        }
    }

    /**
     * @description Provides a breakdown of findings by Status for the metrics bar.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getPainPointCounts() {
        Map<String, Integer> counts = new Map<String, Integer>{
            'New' => 0, 'Acknowledged' => 0, 'Dismissed' => 0
        };

        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            return counts;
        }

        try {
            // Aggregate queries require WITH SECURITY_ENFORCED as stripInaccessible doesn't work on Aggregates
            for (AggregateResult ar : [
                SELECT Status__c, COUNT(Id) cnt 
                FROM Identified_Pain_Point__c 
                WITH SECURITY_ENFORCED 
                GROUP BY Status__c
            ]) {
                String status = (String)ar.get('Status__c');
                Integer count = (Integer)ar.get('cnt');
                if (counts.containsKey(status)) {
                    counts.put(status, count);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching counts: ' + e.getMessage());
        }
        return counts;
    }

    /**
     * @description Dismisses a finding and logs the dismissal to preventing re-alerting.
     */
    @AuraEnabled
    public static void dismissPainPoint(String uniqueKey, String reason) {
        if (String.isBlank(uniqueKey)) return;

        // Strict Create Check for Audit Log
        if (!Schema.sObjectType.Suggestion_Dismissal__c.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create dismissal records.');
        }

        try {
            List<Identified_Pain_Point__c> points = [
                SELECT Id, Status__c, Object_API_Name__c 
                FROM Identified_Pain_Point__c 
                WHERE Unique_Key__c = :uniqueKey 
                LIMIT 1
            ];

            if (!points.isEmpty()) {
                // Prepare Dismissal Log
                Suggestion_Dismissal__c dismissal = new Suggestion_Dismissal__c(
                    Dismissal_Key__c = uniqueKey,
                    Action_Name__c = String.isNotBlank(reason) ? reason : 'Dismissed via Dashboard',
                    User__c = UserInfo.getUserId(),
                    Object_API_Name__c = points[0].Object_API_Name__c
                );

                // Prepare Update
                points[0].Status__c = 'Dismissed';

                // Secure Execution
                SObjectAccessDecision logDecision = Security.stripInaccessible(AccessType.UPSERTABLE, new List<Suggestion_Dismissal__c>{dismissal});
                SObjectAccessDecision ppDecision = Security.stripInaccessible(AccessType.UPDATABLE, points);

                upsert (List<Suggestion_Dismissal__c>)logDecision.getRecords() Dismissal_Key__c;
                update ppDecision.getRecords();
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error handling dismissal: ' + e.getMessage());
        }
    }
}