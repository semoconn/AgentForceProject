/**
 * @description       : Securely queries and manages Identified_Pain_Point__c records for the OrgPulse Dashboard.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-20-2025
 * @last modified by  : Gemini
**/
public with sharing class PainPointController {

    /**
     * @description Queries and returns all Identified_Pain_Point__c records, prioritized by Impact Score.
     * @return        : List<Identified_Pain_Point__c> A list of pain point records.
     * @throws        : AuraHandledException if the user does not have read access to the object or fields.
    **/
    @AuraEnabled(cacheable=true)
    public static List<Identified_Pain_Point__c> getPainPoints() {
        try {
            return [
                SELECT 
                    Id, Name, Description__c, Object_API_Name__c, 
                    Impact_Score__c, Status__c, Last_Detected__c,
                    Example_Records__c, Unique_Key__c
                FROM Identified_Pain_Point__c
                WITH SECURITY_ENFORCED
                ORDER BY Impact_Score__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while fetching pain points: ' + e.getMessage());
        }
    }

    /**
     * @description Updates the status of a pain point record. Also handles dismissal logic.
     * @param  painPointId : The ID of the Identified_Pain_Point__c record to update.
     * @param  status      : The new status value (e.g., 'Acknowledged', 'Dismissed').
     * @param  uniqueKey   : The Unique_Key__c of the pain point, needed for dismissal tracking.
     * @return             : String confirmation message.
    **/
    @AuraEnabled
    public static String updatePainPointStatus(Id painPointId, String status, String uniqueKey) {
        // Security Check: Verify FLS for the Status field before performing DML.
        if (!Schema.sObjectType.Identified_Pain_Point__c.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update the status of this record.');
        }

        try {
            Identified_Pain_Point__c pointToUpdate = new Identified_Pain_Point__c(Id = painPointId, Status__c = status);
            update pointToUpdate;

            // If the pain point is being dismissed, create a dismissal record
            // to prevent it from being re-created by the analysis service.
            if (status == 'Dismissed') {
                Suggestion_Dismissal__c dismissal = new Suggestion_Dismissal__c(
                    // Create a unique key for the dismissal record itself
                    Dismissal_Key__c = UserInfo.getUserId() + ':' + uniqueKey,
                    User__c = UserInfo.getUserId()
                );
                // Use an upsert here to prevent duplicates if the user dismisses, re-activates, and dismisses again.
                upsert dismissal Dismissal_Key__c;
            }
            
            return 'Status updated successfully.';

        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while updating the status: ' + e.getMessage());
        }
    }
}