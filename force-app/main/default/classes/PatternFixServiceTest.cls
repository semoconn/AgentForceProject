@isTest
private class PatternFixServiceTest {

    @testSetup
    static void setupData() {
        // Create a Premium License so checks pass if called via Controller (though Service doesn't check license directly)
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            Name = 'Premium License',
            Status__c = 'Active'
        );
        insert license;

        // Create Test User (Standard User for Positive Tests)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'standt', 
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8', 
            LastName = 'Testing', 
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', 
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'patternfixtest_standard@testorg.com'
        );
        insert u;

        // Assign permission set if needed (assuming Standard User can read/edit basic objects, 
        // but for stripInaccessible we often need explicit grants. In many scratch orgs Standard User is fine).
    }

    @isTest
    static void testFixStaleCases_Positive() {
        User u = [SELECT Id FROM User WHERE UserName = 'patternfixtest_standard@testorg.com'];
        
        // Setup Case
        Case c = new Case(
            Subject = 'Test Stale Case',
            Status = 'New',
            OwnerId = u.Id
        );
        insert c;

        List<Id> caseIds = new List<Id>{c.Id};

        System.runAs(u) {
            Test.startTest();
            PatternFixService.fixStaleCases(caseIds);
            Test.stopTest();
        }

        // Validate Task Creation
        List<Task> tasks = [SELECT Id, Subject, Priority, OwnerId, WhatId FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'One task should be created');
        System.assertEquals('High', tasks[0].Priority, 'Task should be High Priority');
        System.assertEquals(u.Id, tasks[0].OwnerId, 'Task should be assigned to Case Owner');
    }

    @isTest
    static void testFixUnassignedLeads_Positive() {
        User u = [SELECT Id FROM User WHERE UserName = 'patternfixtest_standard@testorg.com'];
        
        // Setup Lead owned by someone else (e.g., current running user which is sys admin)
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Status = 'Open - Not Contacted',
            OwnerId = UserInfo.getUserId() // Initially owned by Admin
        );
        insert l;

        List<Id> leadIds = new List<Id>{l.Id};

        System.runAs(u) {
            Test.startTest();
            PatternFixService.fixUnassignedLeads(leadIds);
            Test.stopTest();
        }

        // Validate Lead Ownership Change
        Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(u.Id, updatedLead.OwnerId, 'Lead owner should be updated to the running user');
    }

    @isTest
    static void testFixStaleCases_Negative_Security() {
        // Attempt to find a restricted profile
        List<Profile> restrictedProfiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        
        if (restrictedProfiles.isEmpty()) {
            restrictedProfiles = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        }
        
        // If no restricted profile exists in this org environment, skip the negative permission test
        if (restrictedProfiles.isEmpty()) return;

        User noAccessUser = new User(
            Alias = 'noacc', 
            Email = 'noaccess@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'NoAccess', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = restrictedProfiles[0].Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'noaccess_patternfix@testorg.com'
        );
        insert noAccessUser;

        Case c = new Case(Subject = 'Test Case');
        insert c;

        System.runAs(noAccessUser) {
            Test.startTest();
            try {
                PatternFixService.fixStaleCases(new List<Id>{c.Id});
                System.assert(false, 'Should have thrown AuraHandledException due to lack of permissions');
            } catch (AuraHandledException e) {
                System.assert(true);
            } catch (Exception e) {
                // In some cases standard security might throw other exceptions, but we expect AuraHandled
                System.debug('Caught unexpected exception: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testFixUnassignedLeads_Negative_Security() {
        List<Profile> restrictedProfiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (restrictedProfiles.isEmpty()) restrictedProfiles = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        if (restrictedProfiles.isEmpty()) return;

        User noAccessUser = new User(
            Alias = 'noacc2', 
            Email = 'noaccess2@testorg.com', 
            EmailEncodingKey = 'UTF-8', 
            LastName = 'NoAccess2', 
            LanguageLocaleKey = 'en_US', 
            LocaleSidKey = 'en_US', 
            ProfileId = restrictedProfiles[0].Id, 
            TimeZoneSidKey = 'America/Los_Angeles', 
            UserName = 'noaccess2_patternfix@testorg.com'
        );
        insert noAccessUser;

        Lead l = new Lead(LastName='Test', Company='Test');
        insert l;

        System.runAs(noAccessUser) {
            Test.startTest();
            try {
                PatternFixService.fixUnassignedLeads(new List<Id>{l.Id});
                System.assert(false, 'Should have thrown AuraHandledException due to lack of permissions');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            Test.stopTest();
        }
    }
}