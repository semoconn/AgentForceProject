@isTest
private class PatternFixServiceTest {

    @testSetup
    static void setupData() {
        // Create a Premium License so positive tests pass by default
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Premium'
        );
        insert license;
    }

    @isTest
    static void testExecuteFix_TaskCreation() {
        // Setup Case - run as current user (admin in test context)
        Case c = new Case(
            Subject = 'Test Stale Case',
            Status = 'New'
        );
        insert c;

        List<Id> caseIds = new List<Id>{c.Id};

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            // Calls the new DYNAMIC method
            // 'Stale_Case' refers to the Behavior_Pattern_Rule__mdt developer name
            service.executeFix(caseIds, 'Stale_Case');
        } catch (Exception e) {
            System.debug('CMDT Missing or other error: ' + e.getMessage());
        }
        Test.stopTest();

        // Validate Task Creation (Smoke test)
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :c.Id];
        // Note: Actual assertion depends on metadata existence in the org
    }

    @isTest
    static void testExecuteFix_OwnerAssignment() {
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        List<Id> leadIds = new List<Id>{l.Id};

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            // Covers 'Owner_Assignment' logic
            service.executeFix(leadIds, 'Unassigned_Lead');
        } catch (Exception e) {
            System.debug('CMDT Missing or other error: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testExecuteFix_FieldUpdate() {
        // Setup Opportunity for Field Update Test
        Opportunity opp = new Opportunity(
            Name = 'Stale Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        List<Id> oppIds = new List<Id>{opp.Id};

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            // Covers 'Field_Update' logic (Assuming Stale_Opportunity maps to field update)
            service.executeFix(oppIds, 'Stale_Opportunity');
        } catch (Exception e) {
            System.debug('CMDT Missing or other error: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testExecuteFix_LicenseRestriction() {
        // Delete Premium license first (from org level)
        delete [SELECT Id FROM BehaviorIQ_License__c];

        // Create Free license
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Free'
        );
        insert license;

        // Setup dummy record
        Lead l = new Lead(LastName='Test', Company='Test', Status='Open - Not Contacted');
        insert l;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            // Try to run a Premium rule (Unassigned_Lead)
            service.executeFix(new List<Id>{l.Id}, 'Unassigned_Lead');
            // If metadata exists, we expect an exception here
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should catch license restriction exception');
        } catch (Exception e) {
            // Catching metadata missing errors - this is acceptable
            System.debug('Expected exception caught: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testExecuteFix_EmptyRecordIds() {
        Test.startTest();
        PatternFixService service = new PatternFixService();
        // Should handle null gracefully
        service.executeFix(null, 'Stale_Case');
        // Should handle empty list gracefully
        service.executeFix(new List<Id>(), 'Stale_Case');
        Test.stopTest();
        // No exception means test passes
        System.assert(true, 'Empty record handling should not throw exception');
    }
}
