/**
 * @description Service class for BehaviorIQ Premium "Auto-Fix" features.
 * Metadata-Driven: Uses Behavior_Pattern_Rule__mdt to determine remediation logic.
 */
public with sharing class PatternFixService {

    public void executeFix(List<Id> recordIds, String ruleDeveloperName) {
        if (recordIds == null || recordIds.isEmpty()) return;

        // 1. Fetch Rule
        Behavior_Pattern_Rule__mdt rule = [
            SELECT Fix_Type__c, Fix_Config__c, Is_Premium__c 
            FROM Behavior_Pattern_Rule__mdt 
            WHERE DeveloperName = :ruleDeveloperName 
            LIMIT 1
        ];

        // 2. Validate License
        if (rule.Is_Premium__c && !LicenseService.isPremium()) {
            throw new AuraHandledException('This is a Premium feature. Please upgrade to execute this fix.');
        }

        // 3. Parse Config
        Map<String, Object> config = new Map<String, Object>();
        if (String.isNotBlank(rule.Fix_Config__c)) {
            config = (Map<String, Object>)JSON.deserializeUntyped(rule.Fix_Config__c);
        }

        // 4. Route Execution
        switch on rule.Fix_Type__c {
            when 'Task_Creation' {
                createTasks(recordIds, config);
            }
            when 'Owner_Assignment' {
                assignOwner(recordIds, config);
            }
            when 'Field_Update' {
                updateFields(recordIds, config);
            }
            when else {
                throw new AuraHandledException('Unknown Fix Type: ' + rule.Fix_Type__c);
            }
        }
    }

    // --- FIX IMPLEMENTATIONS ---

    private void createTasks(List<Id> recordIds, Map<String, Object> config) {
        if (!Schema.sObjectType.Task.isCreateable()) throw new AuraHandledException('Insufficient permissions to create Tasks.');

        List<Task> tasks = new List<Task>();
        String subject = (String)config.get('subject');
        
        for (Id recId : recordIds) {
            tasks.add(new Task(
                Subject = (subject != null ? subject : 'Action Required'),
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(1),
                WhatId = recId,
                OwnerId = UserInfo.getUserId()
            ));
        }
        insert Security.stripInaccessible(AccessType.CREATABLE, tasks).getRecords();
    }

    private void updateFields(List<Id> recordIds, Map<String, Object> config) {
        String field = (String)config.get('field');
        String val = (String)config.get('value');
        if (String.isBlank(field)) return;

        List<SObject> records = new List<SObject>();
        Schema.SObjectType sType = recordIds[0].getSObjectType();

        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            obj.put(field, val);
            records.add(obj);
        }
        update Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();
    }

    private void assignOwner(List<Id> recordIds, Map<String, Object> config) {
        // Simple "Claim" logic for MVP
        List<SObject> records = new List<SObject>();
        Schema.SObjectType sType = recordIds[0].getSObjectType();
        
        for (Id recId : recordIds) {
            SObject obj = sType.newSObject(recId);
            obj.put('OwnerId', UserInfo.getUserId());
            records.add(obj);
        }
        update Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();
    }
}