/**
 * @description Test class for DuplicateRecordPlugin.
 * Tests duplicate detection across Lead, Contact, and Account objects.
 * Validates CRUD/FLS security enforcement and proper task creation.
 *
 * @group BehaviorIQ Tests
 * @since 2025-01
 */
@isTest
private with sharing class DuplicateRecordPluginTest {

    @TestSetup
    static void setupData() {
        // Create admin user for tests
        Profile pAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        String uniqueifier = String.valueOf(System.currentTimeMillis());

        User testUser = new User(
            Alias = 'duptest',
            Email = 'duptest' + uniqueifier + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'DuplicateTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = pAdmin.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'duptest' + uniqueifier + '@testorg.com'
        );
        insert testUser;

        // Assign BehaviorIQ_Admin permission set
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Label = 'BehaviorIQ Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);
    }

    // ==================== LEAD DUPLICATE DETECTION TESTS ====================

    @isTest
    static void testAnalyze_DuplicateLeadsByEmail_FindsDuplicates() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create leads with duplicate emails
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'John', LastName = 'Doe', Company = 'Acme Corp', Email = 'duplicate@example.com'),
            new Lead(FirstName = 'Jane', LastName = 'Doe', Company = 'Beta Corp', Email = 'duplicate@example.com'),
            new Lead(FirstName = 'Bob', LastName = 'Smith', Company = 'Gamma Corp', Email = 'unique@example.com')
        };
        insert leads;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        // Should find exactly 2 leads with duplicate email
        System.assertEquals(2, duplicateIds.size(), 'Should find 2 leads with duplicate email');

        // Verify the correct leads were found
        Set<Id> duplicateIdSet = new Set<Id>(duplicateIds);
        System.assert(duplicateIdSet.contains(leads[0].Id), 'First duplicate lead should be found');
        System.assert(duplicateIdSet.contains(leads[1].Id), 'Second duplicate lead should be found');
        System.assert(!duplicateIdSet.contains(leads[2].Id), 'Unique lead should not be found');
    }

    @isTest
    static void testAnalyze_NoDuplicates_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create leads with unique emails
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'John', LastName = 'Doe', Company = 'Acme Corp', Email = 'john@example.com'),
            new Lead(FirstName = 'Jane', LastName = 'Doe', Company = 'Beta Corp', Email = 'jane@example.com')
        };
        insert leads;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Should find no duplicates when emails are unique');
    }

    @isTest
    static void testAnalyze_NullEmails_ExcludedByDefault() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create leads with null emails (should not count as duplicates)
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'John', LastName = 'Doe', Company = 'Acme Corp', Email = null),
            new Lead(FirstName = 'Jane', LastName = 'Doe', Company = 'Beta Corp', Email = null)
        };
        insert leads;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Null emails should not be considered duplicates');
    }

    // ==================== CONTACT DUPLICATE DETECTION TESTS ====================

    @isTest
    static void testAnalyze_DuplicateContactsByEmail_FindsDuplicates() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create contacts with duplicate emails
        List<Contact> contacts = new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Doe', Email = 'contact.dup@example.com'),
            new Contact(FirstName = 'Jane', LastName = 'Smith', Email = 'contact.dup@example.com'),
            new Contact(FirstName = 'Bob', LastName = 'Brown', Email = 'unique.contact@example.com')
        };
        insert contacts;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Contact';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(2, duplicateIds.size(), 'Should find 2 contacts with duplicate email');
    }

    // ==================== ACCOUNT DUPLICATE DETECTION TESTS ====================

    @isTest
    static void testAnalyze_DuplicateAccountsByName_FindsDuplicates() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create accounts with duplicate names
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Acme Corporation'),
            new Account(Name = 'Acme Corporation'),
            new Account(Name = 'Unique Company')
        };
        insert accounts;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Account';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Name',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(2, duplicateIds.size(), 'Should find 2 accounts with duplicate name');
    }

    // ==================== FIX METHOD TESTS ====================

    @isTest
    static void testFix_CreatesTasks_ForDuplicateRecords() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create duplicate leads
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName = 'John', LastName = 'Doe', Company = 'Acme Corp', Email = 'fix.test@example.com'),
            new Lead(FirstName = 'Jane', LastName = 'Doe', Company = 'Beta Corp', Email = 'fix.test@example.com')
        };
        insert leads;

        List<Id> leadIds = new List<Id>{ leads[0].Id, leads[1].Id };

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            Map<String, Object> config = new Map<String, Object>{
                'ruleDeveloperName' => 'Duplicate_Leads',
                'duplicateField' => 'Email',
                'taskSubject' => 'Review duplicate lead'
            };

            result = plugin.fix(leadIds, config);
        }
        Test.stopTest();

        // Verify success
        System.assertEquals(2, result.successCount, 'Should have 2 successful fixes');
        System.assertEquals(0, result.failureCount, 'Should have no failures');
        System.assertEquals(2, result.auditLogs.size(), 'Should have 2 audit logs');

        // Verify tasks were created
        List<Task> createdTasks = [
            SELECT Id, Subject, WhoId
            FROM Task
            WHERE WhoId IN :leadIds
        ];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks');
        System.assert(createdTasks[0].Subject.contains('Review duplicate lead'), 'Task subject should contain configured text');
    }

    @isTest
    static void testFix_WithAccountRecords_UsesWhatId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create duplicate accounts
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Test Account 1'),
            new Account(Name = 'Test Account 2')
        };
        insert accounts;

        List<Id> accountIds = new List<Id>{ accounts[0].Id, accounts[1].Id };

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            Map<String, Object> config = new Map<String, Object>{
                'ruleDeveloperName' => 'Duplicate_Accounts',
                'duplicateField' => 'Name',
                'taskSubject' => 'Review duplicate account'
            };

            result = plugin.fix(accountIds, config);
        }
        Test.stopTest();

        // Verify tasks were created with WhatId (not WhoId)
        List<Task> createdTasks = [
            SELECT Id, Subject, WhatId
            FROM Task
            WHERE WhatId IN :accountIds
        ];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks for accounts');
    }

    @isTest
    static void testFix_EmptyRecordList_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();
            result = plugin.fix(new List<Id>(), new Map<String, Object>());
        }
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Empty list should result in 0 successes');
        System.assertEquals(0, result.failureCount, 'Empty list should result in 0 failures');
    }

    @isTest
    static void testFix_NullRecordList_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();
            result = plugin.fix(null, new Map<String, Object>());
        }
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Null list should result in 0 successes');
        System.assertEquals(0, result.failureCount, 'Null list should result in 0 failures');
    }

    // ==================== ERROR HANDLING TESTS ====================

    @isTest
    static void testAnalyze_MissingDuplicateField_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>(); // No duplicateField

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Missing duplicateField config should return empty list');
    }

    @isTest
    static void testAnalyze_InvalidObject_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'NonExistentObject__c';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email'
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Invalid object should return empty list');
    }

    @isTest
    static void testAnalyze_InvalidField_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>{
                'duplicateField' => 'NonExistentField__c'
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Invalid field should return empty list');
    }

    @isTest
    static void testAnalyze_NullContext_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = null;

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Null config should return empty list');
    }

    // ==================== MULTIPLE DUPLICATE GROUPS TEST ====================

    @isTest
    static void testAnalyze_MultipleDuplicateGroups_FindsAll() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        // Create multiple groups of duplicates
        List<Lead> leads = new List<Lead>{
            // Group 1: duplicate@example.com
            new Lead(FirstName = 'John', LastName = 'Doe', Company = 'Acme', Email = 'groupone@example.com'),
            new Lead(FirstName = 'Jane', LastName = 'Doe', Company = 'Beta', Email = 'groupone@example.com'),
            // Group 2: another@example.com
            new Lead(FirstName = 'Bob', LastName = 'Smith', Company = 'Gamma', Email = 'grouptwo@example.com'),
            new Lead(FirstName = 'Alice', LastName = 'Smith', Company = 'Delta', Email = 'grouptwo@example.com'),
            new Lead(FirstName = 'Charlie', LastName = 'Smith', Company = 'Epsilon', Email = 'grouptwo@example.com'),
            // Unique
            new Lead(FirstName = 'Unique', LastName = 'Lead', Company = 'Zeta', Email = 'unique@example.com')
        };
        insert leads;

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Lead';
            context.config = new Map<String, Object>{
                'duplicateField' => 'Email',
                'excludeNulls' => true
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        // Should find 5 duplicates (2 from group1 + 3 from group2)
        System.assertEquals(5, duplicateIds.size(), 'Should find 5 leads across 2 duplicate groups');
    }

    // ==================== FIELD TYPE VALIDATION TESTS ====================

    @isTest
    static void testAnalyze_UnsupportedFieldType_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            // Amount is a Currency field - not supported for duplicate detection
            context.config = new Map<String, Object>{
                'duplicateField' => 'Amount'
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Unsupported field type (Currency) should return empty list');
    }

    @isTest
    static void testAnalyze_DateFieldType_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'duptest' LIMIT 1];

        Test.startTest();
        List<Id> duplicateIds;
        System.runAs(testUser) {
            DuplicateRecordPlugin plugin = new DuplicateRecordPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            // CloseDate is a Date field - not supported for duplicate detection
            context.config = new Map<String, Object>{
                'duplicateField' => 'CloseDate'
            };

            duplicateIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, duplicateIds.size(), 'Unsupported field type (Date) should return empty list');
    }
}
