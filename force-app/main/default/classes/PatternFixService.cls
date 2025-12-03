/**
 * @description Service class for BehaviorIQ Premium "Auto-Fix" features.
 * Handles the remediation of identified behavioral patterns (e.g., Stale Cases, Unassigned Leads).
 * Strictly enforces CRUD/FLS and uses Security.stripInaccessible for all DML.
 */
public with sharing class PatternFixService {

    /**
     * @description Auto-Fix for Stale Cases: Creates a High Priority Task for the Case Owner.
     * @param caseIds List of Case Ids to apply the fix to.
     * @throws AuraHandledException if permissions are missing or DML fails.
     */
    public static void fixStaleCases(List<Id> caseIds) {
        // 1. Strict CRUD Check: Can the user create Tasks?
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions: You do not have permission to create Tasks.');
        }

        // 2. Strict CRUD/FLS Check: Can the user read Case OwnerId?
        if (!Schema.sObjectType.Case.isAccessible() || 
            !Schema.sObjectType.Case.fields.OwnerId.isAccessible()) {
            throw new AuraHandledException('Insufficient permissions: Unable to read Case Owner information.');
        }

        try {
            // 3. Query Target Records (Securely)
            // We need the OwnerId to assign the task correctly.
            // Using stripInaccessible on retrieval to ensure we only get data the user is allowed to see.
            List<Case> casesToFix = [SELECT Id, OwnerId, CaseNumber FROM Case WHERE Id IN :caseIds];
            SObjectAccessDecision readDecision = Security.stripInaccessible(AccessType.READABLE, casesToFix);
            casesToFix = (List<Case>)readDecision.getRecords();

            List<Task> tasksToInsert = new List<Task>();

            for (Case c : casesToFix) {
                Task t = new Task();
                t.Subject = 'Action Required: Stale Case detected by BehaviorIQ';
                t.Priority = 'High';
                t.Status = 'Not Started';
                t.ActivityDate = Date.today().addDays(1); // Due tomorrow
                t.WhatId = c.Id;
                t.OwnerId = c.OwnerId; // Assign to Case Owner
                t.Description = 'This case has been flagged as Stale. Please take action immediately.';
                tasksToInsert.add(t);
            }

            if (!tasksToInsert.isEmpty()) {
                // 4. Security.stripInaccessible before DML
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, tasksToInsert);
                
                // 5. Perform DML
                insert securityDecision.getRecords();
            }

        } catch (Exception e) {
            // Log exception internally if a logger exists, then throw user-friendly error
            throw new AuraHandledException('An error occurred while fixing Stale Cases. Please contact your administrator.');
        }
    }

    /**
     * @description Auto-Fix for Unassigned Leads: Updates the Owner to the current user.
     * @param leadIds List of Lead Ids to claim.
     * @throws AuraHandledException if permissions are missing or DML fails.
     */
    public static void fixUnassignedLeads(List<Id> leadIds) {
        // 1. Strict CRUD Check: Can the user update Leads?
        if (!Schema.sObjectType.Lead.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions: You do not have permission to update Leads.');
        }

        // 2. Strict FLS Check: Can the user update the OwnerId field?
        if (!Schema.sObjectType.Lead.fields.OwnerId.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions: You do not have permission to change Lead Ownership.');
        }

        try {
            List<Lead> leadsToUpdate = new List<Lead>();
            Id currentUserId = UserInfo.getUserId();

            for (Id leadId : leadIds) {
                Lead l = new Lead();
                l.Id = leadId;
                l.OwnerId = currentUserId; // "Claim" the lead
                leadsToUpdate.add(l);
            }

            if (!leadsToUpdate.isEmpty()) {
                // 3. Security.stripInaccessible before DML
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, leadsToUpdate);
                
                // 4. Perform DML
                update securityDecision.getRecords();
            }

        } catch (Exception e) {
            throw new AuraHandledException('An error occurred while claiming Unassigned Leads. Please contact your administrator.');
        }
    }
}