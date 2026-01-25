/**
 * @description Test class for MissingAttachmentPlugin.
 * Tests detection of records missing required file attachments.
 * Validates CRUD/FLS security enforcement and proper task creation.
 *
 * @group BehaviorIQ Tests
 * @since 2025-01
 */
@isTest
private with sharing class MissingAttachmentPluginTest {

    @TestSetup
    static void setupData() {
        // Create admin user for tests
        Profile pAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        String uniqueifier = String.valueOf(System.currentTimeMillis());

        User testUser = new User(
            Alias = 'atttest',
            Email = 'atttest' + uniqueifier + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AttachmentTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = pAdmin.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'atttest' + uniqueifier + '@testorg.com'
        );
        insert testUser;

        // Assign BehaviorIQ_Admin permission set
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'BehaviorIQ_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = ps.Id);
    }

    // ==================== OPPORTUNITY TESTS ====================

    @isTest
    static void testAnalyze_ClosedWonOppsWithoutAttachments_FindsMissing() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create closed won opportunities
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Opp With Attachment',
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today().addDays(-10)
            ),
            new Opportunity(
                Name = 'Opp Without Attachment 1',
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today().addDays(-5)
            ),
            new Opportunity(
                Name = 'Opp Without Attachment 2',
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today().addDays(-3)
            )
        };
        insert opps;

        // Add attachment to the first opportunity
        ContentVersion cv = new ContentVersion(
            Title = 'Test Contract',
            PathOnClient = 'contract.pdf',
            VersionData = Blob.valueOf('Test contract content')
        );
        insert cv;

        ContentVersion insertedCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = opps[0].Id,
            ContentDocumentId = insertedCv.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.queryCondition = 'StageName = \'Closed Won\'';
            context.config = new Map<String, Object>{
                'filterCondition' => 'StageName = \'Closed Won\''
            };

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        // Should find 2 opportunities without attachments
        System.assertEquals(2, missingAttachmentIds.size(), 'Should find 2 opportunities without attachments');

        Set<Id> missingSet = new Set<Id>(missingAttachmentIds);
        System.assert(!missingSet.contains(opps[0].Id), 'Opportunity with attachment should not be found');
        System.assert(missingSet.contains(opps[1].Id), 'Opportunity without attachment should be found');
        System.assert(missingSet.contains(opps[2].Id), 'Opportunity without attachment should be found');
    }

    @isTest
    static void testAnalyze_AllOppsHaveAttachments_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create closed won opportunity
        Opportunity opp = new Opportunity(
            Name = 'Opp With Attachment',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert opp;

        // Add attachment
        ContentVersion cv = new ContentVersion(
            Title = 'Test Contract',
            PathOnClient = 'contract.pdf',
            VersionData = Blob.valueOf('Test content')
        );
        insert cv;

        ContentVersion insertedCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = opp.Id,
            ContentDocumentId = insertedCv.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.config = new Map<String, Object>{
                'filterCondition' => 'StageName = \'Closed Won\''
            };

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, missingAttachmentIds.size(), 'Should find no missing attachments');
    }

    // ==================== CASE TESTS ====================

    @isTest
    static void testAnalyze_ClosedCasesWithoutAttachments_FindsMissing() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Create closed cases
        List<Case> cases = new List<Case>{
            new Case(Subject = 'Case With Attachment', Status = 'Closed'),
            new Case(Subject = 'Case Without Attachment', Status = 'Closed')
        };
        insert cases;

        // Add attachment to first case
        ContentVersion cv = new ContentVersion(
            Title = 'Resolution Document',
            PathOnClient = 'resolution.pdf',
            VersionData = Blob.valueOf('Resolution content')
        );
        insert cv;

        ContentVersion insertedCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = cases[0].Id,
            ContentDocumentId = insertedCv.ContentDocumentId,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Case';
            context.config = new Map<String, Object>{
                'filterCondition' => 'Status = \'Closed\''
            };

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(1, missingAttachmentIds.size(), 'Should find 1 case without attachment');
        System.assertEquals(cases[1].Id, missingAttachmentIds[0], 'Should find the correct case');
    }

    // ==================== FIX METHOD TESTS ====================

    @isTest
    static void testFix_CreatesTasks_ForRecordsMissingAttachments() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create opportunities without attachments
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Opp 1',
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today()
            ),
            new Opportunity(
                Name = 'Opp 2',
                AccountId = acc.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today()
            )
        };
        insert opps;

        List<Id> oppIds = new List<Id>{ opps[0].Id, opps[1].Id };

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            Map<String, Object> config = new Map<String, Object>{
                'ruleDeveloperName' => 'Missing_Attachment_Closed_Won',
                'taskSubject' => 'Add contract documentation'
            };

            result = plugin.fix(oppIds, config);
        }
        Test.stopTest();

        // Verify success
        System.assertEquals(2, result.successCount, 'Should have 2 successful fixes');
        System.assertEquals(0, result.failureCount, 'Should have no failures');
        System.assertEquals(2, result.auditLogs.size(), 'Should have 2 audit logs');

        // Verify tasks were created
        List<Task> createdTasks = [
            SELECT Id, Subject, WhatId
            FROM Task
            WHERE WhatId IN :oppIds
        ];
        System.assertEquals(2, createdTasks.size(), 'Should create 2 tasks');
        System.assertEquals('Add contract documentation', createdTasks[0].Subject, 'Task subject should match config');
    }

    @isTest
    static void testFix_EmptyRecordList_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(new List<Id>(), new Map<String, Object>());
        }
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Empty list should result in 0 successes');
        System.assertEquals(0, result.failureCount, 'Empty list should result in 0 failures');
    }

    @isTest
    static void testFix_NullRecordList_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(null, new Map<String, Object>());
        }
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Null list should result in 0 successes');
        System.assertEquals(0, result.failureCount, 'Null list should result in 0 failures');
    }

    // ==================== ERROR HANDLING TESTS ====================

    @isTest
    static void testAnalyze_MissingFilterCondition_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.config = new Map<String, Object>(); // No filterCondition

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, missingAttachmentIds.size(), 'Missing filter condition should return empty list');
    }

    @isTest
    static void testAnalyze_InvalidObject_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'NonExistentObject__c';
            context.config = new Map<String, Object>{
                'filterCondition' => 'Status = \'Closed\''
            };

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, missingAttachmentIds.size(), 'Invalid object should return empty list');
    }

    @isTest
    static void testAnalyze_NoMatchingRecords_ReturnsEmpty() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Don't create any matching records

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.config = new Map<String, Object>{
                'filterCondition' => 'StageName = \'Closed Won\' AND Name = \'NonExistent\''
            };

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, missingAttachmentIds.size(), 'No matching records should return empty list');
    }

    @isTest
    static void testAnalyze_UsesQueryConditionAsFallback() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        // Create test account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert opp;

        Test.startTest();
        List<Id> missingAttachmentIds;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.queryCondition = 'StageName = \'Closed Won\''; // Use queryCondition instead of config
            context.config = new Map<String, Object>(); // Empty config

            missingAttachmentIds = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(1, missingAttachmentIds.size(), 'Should use queryCondition as fallback');
        System.assertEquals(opp.Id, missingAttachmentIds[0], 'Should find the correct opportunity');
    }

    // ==================== FIX METHOD EDGE CASES ====================

    /**
     * @description Tests fix with Contact records - should use WhoId instead of WhatId.
     */
    @isTest
    static void testFix_WithContactRecord_UsesWhoId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = acc.Id
        );
        insert con;

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(
                new List<Id>{ con.Id },
                new Map<String, Object>{
                    'ruleDeveloperName' => 'Missing_Attachment_Contact',
                    'taskSubject' => 'Add contact documentation'
                }
            );
        }
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed for Contact');

        // Verify task was created with WhoId
        List<Task> tasks = [SELECT WhoId, WhatId FROM Task WHERE WhoId = :con.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created');
        System.assertEquals(con.Id, tasks[0].WhoId, 'Task WhoId should be Contact Id');
        System.assertEquals(null, tasks[0].WhatId, 'Task WhatId should be null for Contact');
    }

    /**
     * @description Tests fix with Lead records - should use WhoId instead of WhatId.
     */
    @isTest
    static void testFix_WithLeadRecord_UsesWhoId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Lead ld = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company'
        );
        insert ld;

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(
                new List<Id>{ ld.Id },
                new Map<String, Object>{
                    'ruleDeveloperName' => 'Missing_Attachment_Lead',
                    'taskSubject' => 'Add lead documentation'
                }
            );
        }
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed for Lead');

        // Verify task was created with WhoId
        List<Task> tasks = [SELECT WhoId, WhatId FROM Task WHERE WhoId = :ld.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created for Lead');
        System.assertEquals(ld.Id, tasks[0].WhoId, 'Task WhoId should be Lead Id');
    }

    /**
     * @description Tests fix with null config - should use default values.
     */
    @isTest
    static void testFix_NullConfig_UsesDefaults() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );
        insert opp;

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(new List<Id>{ opp.Id }, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed with null config');

        // Verify default task subject was used
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :opp.Id];
        System.assertEquals('Add required documentation', tasks[0].Subject, 'Should use default subject');
    }

    /**
     * @description Tests fix with Case records - should use WhatId.
     */
    @isTest
    static void testFix_WithCaseRecord_UsesWhatId() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Case c = new Case(Subject = 'Test Case', Status = 'Closed');
        insert c;

        Test.startTest();
        PatternPluginResult result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();
            result = plugin.fix(
                new List<Id>{ c.Id },
                new Map<String, Object>{
                    'ruleDeveloperName' => 'Missing_Attachment_Case'
                }
            );
        }
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed for Case');

        // Verify task was created with WhatId
        List<Task> tasks = [SELECT WhatId FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created with WhatId');
    }

    /**
     * @description Tests analyze with invalid filter condition - should handle exception.
     */
    @isTest
    static void testAnalyze_InvalidFilterCondition_HandlesException() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'atttest' LIMIT 1];

        Test.startTest();
        List<Id> result;
        System.runAs(testUser) {
            MissingAttachmentPlugin plugin = new MissingAttachmentPlugin();

            PatternPluginContext context = new PatternPluginContext();
            context.objectApiName = 'Opportunity';
            context.config = new Map<String, Object>{
                'filterCondition' => 'InvalidField = \'Test\''
            };

            result = plugin.analyze(context);
        }
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Invalid filter should return empty list');
    }
}
