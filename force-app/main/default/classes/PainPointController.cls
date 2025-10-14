/**
 * @description       : Securely queries Identified_Pain_Point__c records for the OrgPulse Dashboard.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-13-2025
 * @last modified by  : Gemini
**/
public with sharing class PainPointController {

    /**
     * @description Queries and returns all Identified_Pain_Point__c records, prioritized by Impact Score.
     * This method respects Field-Level Security (FLS) for the current user.
     * @return        : List<Identified_Pain_Point__c> A list of pain point records.
     * @throws        : AuraHandledException if the user does not have read access to the object or fields.
    **/
    @AuraEnabled(cacheable=true)
    public static List<Identified_Pain_Point__c> getPainPoints() {
        try {
            return [
                SELECT 
                    Id, 
                    Name, 
                    Description__c, 
                    Object_API_Name__c, 
                    Impact_Score__c, 
                    Status__c, 
                    Last_Detected__c 
                FROM Identified_Pain_Point__c
                WITH SECURITY_ENFORCED
                ORDER BY Impact_Score__c DESC
            ];
        } catch (Exception e) {
            // Surface exceptions to the LWC in a user-friendly way
            throw new AuraHandledException('An error occurred while fetching pain points: ' + e.getMessage());
        }
    }
}
