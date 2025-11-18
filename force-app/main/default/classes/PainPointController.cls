/**
 * @description Securely queries and manages Identified_Pain_Point__c records for the OrgPulse Dashboard.
 * @version 2.1 - Added missing methods for Dashboard analytics and dismissal logic
 */
public with sharing class PainPointController {

    /**
     * @description Queries and returns all Identified_Pain_Point__c records, prioritized by Impact Score.
     * @return List<Identified_Pain_Point__c> A list of pain point records.
     */
    @AuraEnabled(cacheable=true)
    public static List<Identified_Pain_Point__c> getPainPoints() {
        try {
            if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
                return new List<Identified_Pain_Point__c>();
            }
            
            return [
                SELECT Id, Name, Description__c, Object_API_Name__c, 
                       Impact_Score__c, Status__c, Last_Detected__c,
                       Example_Records__c, Unique_Key__c, Occurrences__c
                FROM Identified_Pain_Point__c
                WITH SECURITY_ENFORCED
                ORDER BY Impact_Score__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching pain points: ' + e.getMessage());
        }
    }

    /**
     * @description Returns only Pain Points that are NOT dismissed (New or Acknowledged).
     * @return List<Identified_Pain_Point__c>
     */
    @AuraEnabled(cacheable=true)
    public static List<Identified_Pain_Point__c> getOpenPainPoints() {
        try {
            if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
                throw new AuraHandledException('User does not have read access to Identified_Pain_Point__c');
            }
            
            return [
                SELECT Id, Name, Description__c, Object_API_Name__c, 
                       Impact_Score__c, Status__c, Last_Detected__c,
                       Example_Records__c, Unique_Key__c, Occurrences__c
                FROM Identified_Pain_Point__c
                WHERE Status__c != 'Dismissed'
                WITH SECURITY_ENFORCED
                ORDER BY Last_Detected__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Returns a count of Pain Points grouped by Status.
     * @return Map<String, Integer>
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getPainPointCounts() {
        Map<String, Integer> counts = new Map<String, Integer>{
            'New' => 0,
            'Acknowledged' => 0,
            'Dismissed' => 0
        };

        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            return counts; // Return empty counts if no access
        }

        try {
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
            System.debug(LoggingLevel.ERROR, 'Error aggregating counts: ' + e.getMessage());
        }
        return counts;
    }

    /**
     * @description Updates status to 'Dismissed' and creates a permanent dismissal record.
     * @param uniqueKey The unique key of the pain point to dismiss
     * @param reason The reason for dismissal
     */
    @AuraEnabled
    public static void dismissPainPoint(String uniqueKey, String reason) {
        // 1. Check permissions for Suggestion_Dismissal__c creation
        if (!Schema.sObjectType.Suggestion_Dismissal__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create dismissal records.');
        }
        
        // 2. Find the Pain Point
        List<Identified_Pain_Point__c> pps = [
            SELECT Id, Status__c FROM Identified_Pain_Point__c 
            WHERE Unique_Key__c = :uniqueKey 
            WITH SECURITY_ENFORCED 
            LIMIT 1
        ];

        if (pps.isEmpty()) return;

        // 3. Create Dismissal Record
        Suggestion_Dismissal__c dismissal = new Suggestion_Dismissal__c(
            Dismissal_Key__c = uniqueKey,
            Action_Name__c = reason,
            User__c = UserInfo.getUserId()
        );

        // 4. Update Pain Point Status
        if (!Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the status of this record.');
        }
        pps[0].Status__c = 'Dismissed';

        try {
            // Use Upsert on Dismissal Key to prevent duplicates
            upsert dismissal Dismissal_Key__c;
            update pps[0];
        } catch (Exception e) {
            throw new AuraHandledException('Error during dismissal: ' + e.getMessage());
        }
    }

    /**
     * @description Updates the status of a pain point record.
     */
    @AuraEnabled
    public static String updatePainPointStatus(Id painPointId, String status, String uniqueKey) {
        if (!Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the status of this record.');
        }

        try {
            Identified_Pain_Point__c pointToUpdate = new Identified_Pain_Point__c(
                Id = painPointId, 
                Status__c = status
            );
            update pointToUpdate;
            
            // If explicitly setting to Dismissed via this method, handle logic
            if (status == 'Dismissed') {
                dismissPainPoint(uniqueKey, 'Dismissed via Status Update');
            }
            
            return 'Status updated successfully.';
        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while updating the status: ' + e.getMessage());
        }
    }
}