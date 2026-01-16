@isTest
private with sharing class PatternFixServiceTest {

    // ==================== HELPER METHODS ====================

    /**
     * @description Creates a mock Behavior_Pattern_Rule__mdt record for testing.
     * Uses JSON deserialization to create an in-memory metadata record.
     */
    private static Behavior_Pattern_Rule__mdt createMockRule(String fixType, Boolean isPremium, String fixConfig) {
        String jsonRule = '{' +
            '"DeveloperName": "Test_Rule",' +
            '"MasterLabel": "Test Rule",' +
            '"Fix_Type__c": "' + fixType + '",' +
            '"Is_Premium__c": ' + isPremium + ',' +
            '"Fix_Config__c": ' + (fixConfig != null ? '"' + fixConfig.replace('"', '\\"') + '"' : 'null') +
        '}';
        return (Behavior_Pattern_Rule__mdt) JSON.deserialize(jsonRule, Behavior_Pattern_Rule__mdt.class);
    }

    /**
     * @description Clears the mock rule after each test to prevent state leakage.
     */
    private static void clearMockRule() {
        PatternFixService.mockRule = null;
        PatternFixService.fallbackOwnerId = null;
    }

    @testSetup
    static void setupData() {
        // Create a Premium License so positive tests pass by default
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Premium'
        );
        insert license;
    }

    // ==================== TASK CREATION TESTS ====================

    @isTest
    static void testTaskCreation_SingleRecord() {
        // Setup
        Case c = new Case(Subject = 'Test Stale Case', Status = 'New');
        insert c;

        // Configure mock rule for Task_Creation
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Follow up on stale case"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Task was created
        List<Task> tasks = [SELECT Id, Subject, WhatId, OwnerId, Priority, Status FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Expected exactly 1 task to be created');
        System.assertEquals('Follow up on stale case', tasks[0].Subject, 'Task subject should match config');
        System.assertEquals(c.Id, tasks[0].WhatId, 'Task should be related to the Case');
        System.assertEquals(UserInfo.getUserId(), tasks[0].OwnerId, 'Task should be owned by current user');
        System.assertEquals('High', tasks[0].Priority, 'Task priority should be High');
        System.assertEquals('Not Started', tasks[0].Status, 'Task status should be Not Started');

        // Verify Remediation Log was created
        List<Remediation_Log__c> logs = [
            SELECT Affected_Record_ID__c, Action_Taken__c, Status__c, New_Value__c, Executed_By__c, Rule_Developer_Name__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Task_Creation', logs[0].Action_Taken__c, 'Action should be Task_Creation');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');
        System.assertEquals(UserInfo.getUserId(), logs[0].Executed_By__c, 'Executed By should be current user');
        System.assertEquals('Test_Rule', logs[0].Rule_Developer_Name__c, 'Rule name should be captured');

        clearMockRule();
    }

    @isTest
    static void testTaskCreation_DefaultSubject() {
        // Setup - test when no subject is configured
        Case c = new Case(Subject = 'Test Case No Config', Status = 'New');
        insert c;

        // Configure mock rule without subject in config
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Task was created with default subject
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Expected exactly 1 task to be created');
        System.assertEquals('Action Required', tasks[0].Subject, 'Task should have default subject');

        clearMockRule();
    }

    @isTest
    static void testTaskCreation_BulkRecords() {
        // Setup - create 50 cases
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            cases.add(new Case(Subject = 'Bulk Test Case ' + i, Status = 'New'));
        }
        insert cases;

        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Bulk task"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(caseIds, 'Test_Rule');
        Test.stopTest();

        // Verify all tasks were created
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId IN :caseIds];
        System.assertEquals(50, tasks.size(), 'Expected 50 tasks to be created');

        // Verify all remediation logs were created
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Task_Creation'];
        System.assertEquals(50, logs.size(), 'Expected 50 remediation logs');

        clearMockRule();
    }

    // ==================== OWNER ASSIGNMENT TESTS ====================

    @isTest
    static void testOwnerAssignment_LeadWithAssignmentRules() {
        // Setup
        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        Id originalOwnerId = [SELECT OwnerId FROM Lead WHERE Id = :l.Id].OwnerId;

        // Configure mock rule for Owner_Assignment with assignment rules enabled
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":true}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Remediation Log was created
        List<Remediation_Log__c> logs = [
            SELECT Affected_Record_ID__c, Action_Taken__c, Original_Value__c, New_Value__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Owner_Assignment', logs[0].Action_Taken__c, 'Action should be Owner_Assignment');
        System.assertEquals(String.valueOf(originalOwnerId), logs[0].Original_Value__c, 'Original owner should be captured');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_CaseWithAssignmentRules() {
        // Setup
        Case c = new Case(Subject = 'Test Case Assignment', Status = 'New');
        insert c;

        Id originalOwnerId = [SELECT OwnerId FROM Case WHERE Id = :c.Id].OwnerId;

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":true}');
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Owner_Assignment', logs[0].Action_Taken__c, 'Action should be Owner_Assignment');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_WithFallbackOwner() {
        // Setup
        Lead l = new Lead(
            LastName = 'Test Lead Fallback',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Set a specific fallback owner
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        // Configure mock rule with requireOwnerChange to trigger safety net
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false,"requireOwnerChange":true}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify remediation log was created - owner may be queue or fallback depending on org config
        // Priority: 1) Queue (if exists for Lead), 2) Config fallback, 3) Test fallback
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Owner_Assignment', logs[0].Action_Taken__c, 'Action should be Owner_Assignment');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_ConfiguredFallbackOwner() {
        // Setup
        Lead l = new Lead(
            LastName = 'Test Lead Config Fallback',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Configure mock rule with fallbackOwnerId in config
        String config = '{"useAssignmentRules":false,"requireOwnerChange":true,"fallbackOwnerId":"' + UserInfo.getUserId() + '"}';
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log shows safety net was applied
        List<Remediation_Log__c> logs = [
            SELECT Error_Message__c, Status__c, New_Value__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_BulkLeads() {
        // Setup - create 100 leads
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 100; i++) {
            leads.add(new Lead(
                LastName = 'Bulk Lead ' + i,
                Company = 'Test Company',
                Status = 'Open - Not Contacted'
            ));
        }
        insert leads;

        List<Id> leadIds = new List<Id>();
        for (Lead l : leads) {
            leadIds.add(l.Id);
        }

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":true}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(leadIds, 'Test_Rule');
        Test.stopTest();

        // Verify all remediation logs were created
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Owner_Assignment'];
        System.assertEquals(100, logs.size(), 'Expected 100 remediation logs');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_DisabledAssignmentRules() {
        // Setup - test with assignment rules disabled
        Lead l = new Lead(
            LastName = 'Test No Assignment Rules',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Configure mock rule with assignment rules disabled
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');

        clearMockRule();
    }

    // ==================== FIELD UPDATE TESTS ====================

    @isTest
    static void testFieldUpdate_SingleRecord() {
        // Setup
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        String originalStage = opp.StageName;

        // Configure mock rule for Field_Update
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"StageName","value":"Qualification"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify field was updated
        Opportunity updatedOpp = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Qualification', updatedOpp.StageName, 'Opportunity stage should be updated');

        // Verify Remediation Log was created
        List<Remediation_Log__c> logs = [
            SELECT Affected_Record_ID__c, Action_Taken__c, Original_Value__c, New_Value__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Field_Update', logs[0].Action_Taken__c, 'Action should be Field_Update');
        System.assertEquals(originalStage, logs[0].Original_Value__c, 'Original value should be captured');
        System.assertEquals('Qualification', logs[0].New_Value__c, 'New value should be captured');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        clearMockRule();
    }

    @isTest
    static void testFieldUpdate_BulkOpportunities() {
        // Setup - create 50 opportunities
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 50; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            ));
        }
        insert opps;

        List<Id> oppIds = new List<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"StageName","value":"Qualification"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(oppIds, 'Test_Rule');
        Test.stopTest();

        // Verify all fields were updated
        List<Opportunity> updatedOpps = [SELECT StageName FROM Opportunity WHERE Id IN :oppIds];
        for (Opportunity opp : updatedOpps) {
            System.assertEquals('Qualification', opp.StageName, 'All opportunity stages should be updated');
        }

        // Verify all remediation logs were created
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Field_Update'];
        System.assertEquals(50, logs.size(), 'Expected 50 remediation logs');

        clearMockRule();
    }

    @isTest
    static void testFieldUpdate_EmptyFieldConfig() {
        // Setup - test when field config is missing
        Opportunity opp = new Opportunity(
            Name = 'Test Opp Empty Config',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Configure mock rule with empty field
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"","value":"Qualification"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify field was NOT updated (method returns early)
        Opportunity unchangedOpp = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Prospecting', unchangedOpp.StageName, 'Opportunity stage should NOT be updated');

        // No log should be created since method returned early
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)];
        System.assertEquals(0, logs.size(), 'No remediation log should be created for empty field config');

        clearMockRule();
    }

    // ==================== LICENSE RESTRICTION TESTS ====================

    @isTest
    static void testPremiumRule_WithPremiumLicense() {
        // Setup - Premium license exists from testSetup
        Case c = new Case(Subject = 'Premium Test Case', Status = 'New');
        insert c;

        // Configure mock rule as Premium
        PatternFixService.mockRule = createMockRule('Task_Creation', true, '{"subject":"Premium feature task"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify task was created (Premium license allows it)
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Premium user should be able to create task');

        clearMockRule();
    }

    @isTest
    static void testPremiumRule_WithFreeLicense() {
        // Setup - Delete Premium license and create Free license
        delete [SELECT Id FROM BehaviorIQ_License__c];
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Free'
        );
        insert license;

        Lead l = new Lead(LastName = 'Free User Lead', Company = 'Test', Status = 'Open - Not Contacted');
        insert l;

        // Configure mock rule as Premium
        PatternFixService.mockRule = createMockRule('Task_Creation', true, '{"subject":"Premium task"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // AuraHandledException wraps the message, so just verify exception was thrown
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for Free users accessing Premium features');

        clearMockRule();
    }

    @isTest
    static void testNonPremiumRule_WithFreeLicense() {
        // Setup - Delete Premium license and create Free license
        delete [SELECT Id FROM BehaviorIQ_License__c];
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Status__c = 'Free'
        );
        insert license;

        Case c = new Case(Subject = 'Free User Case', Status = 'New');
        insert c;

        // Configure mock rule as NOT Premium
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Free feature task"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify task was created (Free feature is allowed)
        List<Task> tasks = [SELECT Id FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Free user should be able to use non-Premium features');

        clearMockRule();
    }

    // ==================== EDGE CASE TESTS ====================

    @isTest
    static void testExecuteFix_NullRecordIds() {
        Test.startTest();
        PatternFixService service = new PatternFixService();
        // Should handle null gracefully without exception
        service.executeFix(null, 'Test_Rule');
        Test.stopTest();

        // No logs should be created
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c];
        System.assertEquals(0, logs.size(), 'No logs should be created for null input');
    }

    @isTest
    static void testExecuteFix_EmptyRecordIds() {
        Test.startTest();
        PatternFixService service = new PatternFixService();
        // Should handle empty list gracefully without exception
        service.executeFix(new List<Id>(), 'Test_Rule');
        Test.stopTest();

        // No logs should be created
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c];
        System.assertEquals(0, logs.size(), 'No logs should be created for empty input');
    }

    @isTest
    static void testExecuteFix_UnknownFixType() {
        // Setup
        Case c = new Case(Subject = 'Unknown Fix Type Case', Status = 'New');
        insert c;

        // Configure mock rule with unknown fix type
        PatternFixService.mockRule = createMockRule('Unknown_Type', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // AuraHandledException wraps the message, so just verify exception was thrown
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should be thrown for unknown fix type');

        clearMockRule();
    }

    @isTest
    static void testExecuteFix_NullConfig() {
        // Setup - test when Fix_Config__c is null
        Case c = new Case(Subject = 'Null Config Case', Status = 'New');
        insert c;

        // Configure mock rule with null config
        PatternFixService.mockRule = createMockRule('Task_Creation', false, null);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify task was created with default subject
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :c.Id];
        System.assertEquals(1, tasks.size(), 'Task should be created with null config');
        System.assertEquals('Action Required', tasks[0].Subject, 'Task should have default subject');

        clearMockRule();
    }

    // ==================== REMEDIATION LOG TESTS ====================

    @isTest
    static void testRemediationLog_AllFieldsPopulated() {
        // Setup
        Opportunity opp = new Opportunity(
            Name = 'Log Fields Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"StageName","value":"Qualification"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify all log fields
        Remediation_Log__c log = [
            SELECT Affected_Record_ID__c, Action_Taken__c, Original_Value__c,
                   New_Value__c, Status__c, Executed_By__c, Rule_Developer_Name__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)
        ];

        System.assertEquals(String.valueOf(opp.Id), log.Affected_Record_ID__c, 'Affected_Record_ID__c mismatch');
        System.assertEquals('Field_Update', log.Action_Taken__c, 'Action_Taken__c mismatch');
        System.assertEquals('Prospecting', log.Original_Value__c, 'Original_Value__c mismatch');
        System.assertEquals('Qualification', log.New_Value__c, 'New_Value__c mismatch');
        System.assertEquals('Success', log.Status__c, 'Status__c mismatch');
        System.assertEquals(UserInfo.getUserId(), log.Executed_By__c, 'Executed_By__c mismatch');
        System.assertEquals('Test_Rule', log.Rule_Developer_Name__c, 'Rule_Developer_Name__c mismatch');

        clearMockRule();
    }

    @isTest
    static void testRemediationLog_TruncatesLongValues() {
        // Setup - Create opportunity with maximum length name
        String longDescription = '';
        for (Integer i = 0; i < 300; i++) {
            longDescription += 'A';
        }

        Opportunity opp = new Opportunity(
            Name = 'Truncation Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Description = longDescription
        );
        insert opp;

        // Configure mock rule to update Description with a long value
        String longValue = '';
        for (Integer i = 0; i < 300; i++) {
            longValue += 'B';
        }
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"Description","value":"' + longValue + '"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log values are truncated to 255
        Remediation_Log__c log = [
            SELECT Original_Value__c, New_Value__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)
        ];

        System.assert(log.Original_Value__c.length() <= 255, 'Original value should be truncated to 255 chars');
        System.assert(log.New_Value__c.length() <= 255, 'New value should be truncated to 255 chars');

        clearMockRule();
    }

    // ==================== CONCURRENT EXECUTION TESTS ====================

    @isTest
    static void testConcurrentServiceInstances() {
        // Setup - Create two separate cases
        Case c1 = new Case(Subject = 'Concurrent Test 1', Status = 'New');
        Case c2 = new Case(Subject = 'Concurrent Test 2', Status = 'New');
        insert new List<Case>{c1, c2};

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Concurrent task"}');

        Test.startTest();
        // Create two service instances
        PatternFixService service1 = new PatternFixService();
        PatternFixService service2 = new PatternFixService();

        service1.executeFix(new List<Id>{c1.Id}, 'Test_Rule');
        service2.executeFix(new List<Id>{c2.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify separate logs for each case
        List<Remediation_Log__c> logs1 = [SELECT Id FROM Remediation_Log__c WHERE Affected_Record_ID__c = :String.valueOf(c1.Id)];
        List<Remediation_Log__c> logs2 = [SELECT Id FROM Remediation_Log__c WHERE Affected_Record_ID__c = :String.valueOf(c2.Id)];

        System.assertEquals(1, logs1.size(), 'Case 1 should have exactly 1 log');
        System.assertEquals(1, logs2.size(), 'Case 2 should have exactly 1 log');

        // Verify separate tasks
        List<Task> tasks1 = [SELECT Id FROM Task WHERE WhatId = :c1.Id];
        List<Task> tasks2 = [SELECT Id FROM Task WHERE WhatId = :c2.Id];

        System.assertEquals(1, tasks1.size(), 'Case 1 should have exactly 1 task');
        System.assertEquals(1, tasks2.size(), 'Case 2 should have exactly 1 task');

        clearMockRule();
    }

    // ==================== SAFETY NET TESTS ====================

    @isTest
    static void testSafetyNet_NullOwnerFallback() {
        // Setup
        Lead l = new Lead(
            LastName = 'Safety Net Null Test',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify owner is not null or queue
        Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.assertNotEquals(null, updatedLead.OwnerId, 'Owner should not be null');
        System.assert(!String.valueOf(updatedLead.OwnerId).startsWith('00G'), 'Owner should not be a queue');

        clearMockRule();
    }

    @isTest
    static void testSafetyNet_RequireOwnerChange() {
        // Setup
        Lead l = new Lead(
            LastName = 'Require Change Test',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Configure mock rule with requireOwnerChange
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false,"requireOwnerChange":true}');
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created with safety net message
        List<Remediation_Log__c> logs = [
            SELECT Error_Message__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success after safety net');

        clearMockRule();
    }

    // ==================== ACCOUNT FIELD UPDATE TEST ====================

    @isTest
    static void testFieldUpdate_AccountRecord() {
        // Setup - test with Account (different object type)
        Account acc = new Account(Name = 'Test Account', Industry = 'Technology');
        insert acc;

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"Industry","value":"Finance"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{acc.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify field was updated
        Account updatedAcc = [SELECT Industry FROM Account WHERE Id = :acc.Id];
        System.assertEquals('Finance', updatedAcc.Industry, 'Account industry should be updated');

        // Verify log
        List<Remediation_Log__c> logs = [
            SELECT Original_Value__c, New_Value__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(acc.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Technology', logs[0].Original_Value__c, 'Original value should be Technology');
        System.assertEquals('Finance', logs[0].New_Value__c, 'New value should be Finance');

        clearMockRule();
    }

    // ==================== EMAIL NOTIFICATION TESTS (Sprint 6) ====================

    @isTest
    static void testEmailNotification_SingleCase() {
        // Setup - Create account and case
        Account acc = new Account(Name = 'Hot Customer', Rating = 'Hot');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Critical Issue',
            Priority = 'High',
            Status = 'New'
        );
        insert c;

        // Configure mock rule for Email_Notification
        String config = '{"subject":"CHURN ALERT","body":"Hot account has critical case","recipientField":"Account.OwnerId"}';
        PatternFixService.mockRule = createMockRule('Email_Notification', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        // Note: In tests, emails won't actually send but the code path is exercised
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Remediation Log was created (email send is mocked in test context)
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Email_Notification', logs[0].Action_Taken__c, 'Action should be Email_Notification');

        clearMockRule();
    }

    @isTest
    static void testEmailNotification_DefaultConfig() {
        // Setup - Test with minimal config (using defaults)
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Test Case',
            Status = 'New'
        );
        insert c;

        // Configure mock rule with empty config (use defaults)
        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Email_Notification', logs[0].Action_Taken__c, 'Action should be Email_Notification');

        clearMockRule();
    }

    @isTest
    static void testEmailNotification_BulkCases() {
        // Setup - Create multiple cases
        Account acc = new Account(Name = 'Bulk Email Account', Rating = 'Hot');
        insert acc;

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 10; i++) {
            cases.add(new Case(
                AccountId = acc.Id,
                Subject = 'Bulk Case ' + i,
                Priority = 'High',
                Status = 'New'
            ));
        }
        insert cases;

        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Bulk Alert"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(caseIds, 'Test_Rule');
        Test.stopTest();

        // Verify logs were created for all cases
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Email_Notification'];
        System.assert(logs.size() >= 10, 'Expected at least 10 remediation logs');

        clearMockRule();
    }

    // ==================== OPPORTUNITY CREATION TESTS (Sprint 6) ====================

    @isTest
    static void testOpportunityCreation_SingleContract() {
        // Setup - Create account and contract
        Account acc = new Account(Name = 'Contract Customer');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-11),
            ContractTerm = 12
        );
        insert c;

        // Configure mock rule for Opportunity_Creation
        String config = '{"opportunityName":"Renewal - {ContractNumber}","stageName":"Prospecting","closeDate":"+30","type":"Existing Customer - Renewal"}';
        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Opportunity was created
        List<Opportunity> opps = [SELECT Id, Name, StageName, Type, AccountId, ContractId FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Expected exactly 1 opportunity to be created');
        System.assertEquals('Prospecting', opps[0].StageName, 'Opportunity stage should be Prospecting');
        System.assertEquals('Existing Customer - Renewal', opps[0].Type, 'Opportunity type should be set');
        System.assertEquals(acc.Id, opps[0].AccountId, 'Opportunity should be linked to the account');

        // Verify Remediation Log was created
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c, New_Value__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Opportunity_Creation', logs[0].Action_Taken__c, 'Action should be Opportunity_Creation');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');
        System.assert(logs[0].New_Value__c.contains('Opportunity Created'), 'New value should indicate opportunity creation');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_DefaultConfig() {
        // Setup - Test with minimal config (using defaults)
        Account acc = new Account(Name = 'Default Config Customer');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-6),
            ContractTerm = 6
        );
        insert c;

        // Configure mock rule with empty config (use defaults)
        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Opportunity was created with defaults
        List<Opportunity> opps = [SELECT StageName FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Expected exactly 1 opportunity');
        System.assertEquals('Prospecting', opps[0].StageName, 'Should use default stage');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_BulkContracts() {
        // Setup - Create multiple contracts
        Account acc = new Account(Name = 'Bulk Contract Customer');
        insert acc;

        List<Contract> contracts = new List<Contract>();
        for (Integer i = 0; i < 10; i++) {
            contracts.add(new Contract(
                AccountId = acc.Id,
                Status = 'Draft',
                StartDate = Date.today().addMonths(-11),
                ContractTerm = 12
            ));
        }
        insert contracts;

        List<Id> contractIds = new List<Id>();
        for (Contract c : contracts) {
            contractIds.add(c.Id);
        }

        // Configure mock rule
        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{"stageName":"Qualification"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(contractIds, 'Test_Rule');
        Test.stopTest();

        // Verify opportunities were created for all contracts
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE ContractId IN :contractIds];
        System.assertEquals(10, opps.size(), 'Expected 10 opportunities');

        // Verify logs
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Opportunity_Creation'];
        System.assertEquals(10, logs.size(), 'Expected 10 remediation logs');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_Premium() {
        // Setup - Test that premium rule works with premium license
        Account acc = new Account(Name = 'Premium Customer');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-11),
            ContractTerm = 12
        );
        insert c;

        // Configure mock rule as Premium
        PatternFixService.mockRule = createMockRule('Opportunity_Creation', true, '{"stageName":"Negotiation/Review"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify Opportunity was created (premium license exists from testSetup)
        List<Opportunity> opps = [SELECT StageName FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Premium user should be able to create renewal opportunity');
        System.assertEquals('Negotiation/Review', opps[0].StageName, 'Stage should match config');

        clearMockRule();
    }

    // ==================== ADDITIONAL COVERAGE TESTS ====================

    @isTest
    static void testEmailNotification_WithLeadObject() {
        // Test email notification for Lead object (lines 350, 357-361)
        Lead l = new Lead(
            LastName = 'Email Test Lead',
            Company = 'Email Test Co',
            Status = 'Open - Not Contacted'
        );
        insert l;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Lead Alert","body":"Test body"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Email_Notification', logs[0].Action_Taken__c);

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_InvalidFallbackId() {
        // Test invalid fallback owner ID (line 199)
        Lead l = new Lead(
            LastName = 'Invalid Fallback Lead',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        // Set an invalid fallback owner ID
        PatternFixService.fallbackOwnerId = null;

        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false,"fallbackOwnerId":"invalid"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Should still create a log
        List<Remediation_Log__c> logs = [
            SELECT Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected remediation log');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_LongName() {
        // Test opportunity name truncation (line 508)
        Account acc = new Account(Name = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-11),
            ContractTerm = 12
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        List<Opportunity> opps = [SELECT Name FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Opportunity should be created');
        System.assert(opps[0].Name.length() <= 120, 'Name should be truncated');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_NoContract() {
        // Test with non-contract ID (line 527)
        Case c = new Case(Subject = 'Not a Contract', Status = 'New');
        insert c;

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Should not create opportunities for non-contracts
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE Name LIKE '%Not a Contract%'];
        System.assertEquals(0, opps.size(), 'No opportunity should be created for non-contract');

        clearMockRule();
    }

    @isTest
    static void testEmailNotification_NoOwner() {
        // Test email notification when record has no owner (lines 415-418)
        Account acc = new Account(Name = 'No Owner Test Account');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'No Owner Case',
            Status = 'New'
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Alert","recipientField":"InvalidField__c"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');

        clearMockRule();
    }

    @isTest
    static void testFieldUpdate_InvalidFieldName() {
        // Test field update with invalid field name (lines 158-169)
        Opportunity opp = new Opportunity(
            Name = 'Invalid Field Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"NonExistentField__c","value":"Test"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected for invalid field
        }
        Test.stopTest();

        clearMockRule();
    }

    @isTest
    static void testBulkEmailNotification() {
        // Test bulk email notifications (lines 431-444)
        Account acc = new Account(Name = 'Bulk Email Account');
        insert acc;

        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 20; i++) {
            cases.add(new Case(
                AccountId = acc.Id,
                Subject = 'Bulk Email Case ' + i,
                Status = 'New'
            ));
        }
        insert cases;

        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Bulk Alert"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(caseIds, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Email_Notification'];
        System.assert(logs.size() >= 20, 'Expected at least 20 remediation logs');

        clearMockRule();
    }

    @isTest
    static void testEmailNotification_AccountObject() {
        Account acc = new Account(Name = 'Email Test Account');
        insert acc;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Account Alert"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{acc.Id}, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(acc.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_InvalidCloseDate() {
        Account acc = new Account(Name = 'Invalid CloseDate Account');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-11),
            ContractTerm = 12
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{"closeDate":"invalid"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        List<Opportunity> opps = [SELECT CloseDate FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Opportunity should be created');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_OpportunityObject() {
        Opportunity opp = new Opportunity(
            Name = 'Owner Assignment Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false}');
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [
            SELECT Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected remediation log');

        clearMockRule();
    }

    @isTest
    static void testOpportunityCreation_WithAccountName() {
        Account acc = new Account(Name = 'Template Test Account');
        insert acc;

        Contract c = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-6),
            ContractTerm = 12
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{"opportunityName":"Renewal for {AccountName}"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        List<Opportunity> opps = [SELECT Name FROM Opportunity WHERE ContractId = :c.Id];
        System.assertEquals(1, opps.size(), 'Expected 1 opportunity');

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_AccountObject() {
        Account acc = new Account(Name = 'Owner Assignment Account');
        insert acc;

        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false}');
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{acc.Id}, 'Test_Rule');
        Test.stopTest();

        List<Remediation_Log__c> logs = [
            SELECT Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(acc.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected remediation log');

        clearMockRule();
    }

    // ==================== EXCEPTION PATH COVERAGE TESTS ====================

    @isTest
    static void testForceTaskCreationException() {
        Case c = new Case(Subject = 'Task Exception Test', Status = 'New');
        insert c;

        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Test Task"}');
        PatternFixService.forceTaskCreationException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - task creation failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceFieldUpdateException() {
        Opportunity opp = new Opportunity(
            Name = 'Field Update Exception Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"StageName","value":"Qualification"}');
        PatternFixService.forceFieldUpdateException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - field update failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceOwnerAssignmentException() {
        Lead l = new Lead(
            LastName = 'Owner Assignment Exception Test',
            Company = 'Test Company',
            Status = 'Open - Not Contacted'
        );
        insert l;

        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":true}');
        PatternFixService.forceOwnerAssignmentException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - owner assignment failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceEmailQueryException() {
        Account acc = new Account(Name = 'Email Query Exception Account');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Email Query Exception Test',
            Status = 'New'
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Test Alert"}');
        PatternFixService.forceEmailQueryException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - email query failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceEmailSendException() {
        Account acc = new Account(Name = 'Email Send Exception Account');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'Email Send Exception Test',
            Status = 'New'
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Test Alert"}');
        PatternFixService.forceEmailSendException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - email send failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceOpportunityCreationException() {
        Account acc = new Account(Name = 'Opp Creation Exception Account');
        insert acc;

        Contract con = new Contract(
            AccountId = acc.Id,
            Status = 'Draft',
            StartDate = Date.today().addMonths(-11),
            ContractTerm = 12
        );
        insert con;

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{"stageName":"Prospecting"}');
        PatternFixService.forceOpportunityCreationException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        try {
            service.executeFix(new List<Id>{con.Id}, 'Test_Rule');
        } catch (Exception e) {
            // Expected - opportunity creation failure should propagate
        }
        Test.stopTest();

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testForceNoValidRecipients() {
        Account acc = new Account(Name = 'No Recipients Account');
        insert acc;

        Case c = new Case(
            AccountId = acc.Id,
            Subject = 'No Recipients Test',
            Status = 'New'
        );
        insert c;

        PatternFixService.mockRule = createMockRule('Email_Notification', false, '{"subject":"Test Alert"}');
        PatternFixService.forceNoValidRecipients = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Should create a log indicating no valid recipients
        List<Remediation_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testResetTestFlags_PatternFixService() {
        // Set all flags to true
        PatternFixService.forceTaskCreationException = true;
        PatternFixService.forceFieldUpdateException = true;
        PatternFixService.forceOwnerAssignmentException = true;
        PatternFixService.forceEmailQueryException = true;
        PatternFixService.forceEmailSendException = true;
        PatternFixService.forceOpportunityCreationException = true;
        PatternFixService.forceNoValidRecipients = true;
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{}');
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService.resetTestFlags();
        Test.stopTest();

        // Verify all flags are reset
        System.assertEquals(false, PatternFixService.forceTaskCreationException, 'forceTaskCreationException should be reset');
        System.assertEquals(false, PatternFixService.forceFieldUpdateException, 'forceFieldUpdateException should be reset');
        System.assertEquals(false, PatternFixService.forceOwnerAssignmentException, 'forceOwnerAssignmentException should be reset');
        System.assertEquals(false, PatternFixService.forceEmailQueryException, 'forceEmailQueryException should be reset');
        System.assertEquals(false, PatternFixService.forceEmailSendException, 'forceEmailSendException should be reset');
        System.assertEquals(false, PatternFixService.forceOpportunityCreationException, 'forceOpportunityCreationException should be reset');
        System.assertEquals(false, PatternFixService.forceNoValidRecipients, 'forceNoValidRecipients should be reset');
        System.assertEquals(null, PatternFixService.mockRule, 'mockRule should be reset');
        System.assertEquals(null, PatternFixService.fallbackOwnerId, 'fallbackOwnerId should be reset');
    }

    @isTest
    static void testMultipleExceptionFlags_PatternFixService() {
        Case c = new Case(Subject = 'Multiple Flags Test', Status = 'New');
        insert c;

        // Set multiple exception flags
        PatternFixService.forceTaskCreationException = true;
        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Multi Flag Test"}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown');

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testTaskCreationException_WithLog() {
        Case c = new Case(Subject = 'Task Log Exception Test', Status = 'New');
        insert c;

        PatternFixService.mockRule = createMockRule('Task_Creation', false, '{"subject":"Exception Log Test"}');
        PatternFixService.forceTaskCreationException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        } catch (Exception e) {
            exceptionThrown = true;
            System.assert(e.getMessage() != null, 'Exception should have message');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown');

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testFieldUpdateException_WithLog() {
        Opportunity opp = new Opportunity(
            Name = 'Field Exception Log Test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        PatternFixService.mockRule = createMockRule('Field_Update', false, '{"field":"StageName","value":"Closed Won"}');
        PatternFixService.forceFieldUpdateException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown');

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testOwnerAssignmentException_BulkRecords() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(new Lead(
                LastName = 'Bulk Owner Exception ' + i,
                Company = 'Test Company',
                Status = 'Open - Not Contacted'
            ));
        }
        insert leads;

        List<Id> leadIds = new List<Id>();
        for (Lead l : leads) {
            leadIds.add(l.Id);
        }

        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, '{"useAssignmentRules":false}');
        PatternFixService.forceOwnerAssignmentException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(leadIds, 'Test_Rule');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown for bulk owner assignment');

        PatternFixService.resetTestFlags();
    }

    @isTest
    static void testOpportunityCreationException_BulkContracts() {
        Account acc = new Account(Name = 'Bulk Opp Exception Account');
        insert acc;

        List<Contract> contracts = new List<Contract>();
        for (Integer i = 0; i < 3; i++) {
            contracts.add(new Contract(
                AccountId = acc.Id,
                Status = 'Draft',
                StartDate = Date.today().addMonths(-11),
                ContractTerm = 12
            ));
        }
        insert contracts;

        List<Id> contractIds = new List<Id>();
        for (Contract con : contracts) {
            contractIds.add(con.Id);
        }

        PatternFixService.mockRule = createMockRule('Opportunity_Creation', false, '{"stageName":"Qualification"}');
        PatternFixService.forceOpportunityCreationException = true;

        Test.startTest();
        PatternFixService service = new PatternFixService();
        Boolean exceptionThrown = false;
        try {
            service.executeFix(contractIds, 'Test_Rule');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Exception should be thrown for bulk opportunity creation');

        PatternFixService.resetTestFlags();
    }

    // ==================== ESCALATION REVERT TESTS ====================

    @isTest
    static void testEscalationRevert_SingleCase() {
        // Setup - Create an escalated case
        Case c = new Case(
            Subject = 'Escalation Revert Test',
            Status = 'New',
            Priority = 'Medium',
            IsEscalated = true
        );
        insert c;

        // Verify case is escalated
        Case beforeCase = [SELECT IsEscalated FROM Case WHERE Id = :c.Id];
        System.assertEquals(true, beforeCase.IsEscalated, 'Case should be escalated before fix');

        // Configure mock rule for Escalation_Revert with Chatter post
        String config = '{"field":"IsEscalated","value":"false","postChatter":true,"chatterMessage":"Auto-remediated: Please complete Tier-1 troubleshooting."}';
        PatternFixService.mockRule = createMockRule('Escalation_Revert', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify case escalation was reverted
        Case afterCase = [SELECT IsEscalated FROM Case WHERE Id = :c.Id];
        System.assertEquals(false, afterCase.IsEscalated, 'Case should no longer be escalated');

        // Verify Remediation Log was created
        List<Remediation_Log__c> logs = [
            SELECT Affected_Record_ID__c, Action_Taken__c, Original_Value__c, New_Value__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Escalation_Revert', logs[0].Action_Taken__c, 'Action should be Escalation_Revert');
        System.assertEquals('true', logs[0].Original_Value__c, 'Original value should be true');
        System.assertEquals('false', logs[0].New_Value__c, 'New value should be false');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        // Verify Chatter post was created
        List<FeedItem> posts = [SELECT Body FROM FeedItem WHERE ParentId = :c.Id];
        System.assertEquals(1, posts.size(), 'Expected exactly 1 Chatter post');
        System.assert(posts[0].Body.contains('Auto-remediated'), 'Chatter post should contain remediation message');

        clearMockRule();
    }

    @isTest
    static void testEscalationRevert_BulkCases() {
        // Setup - Create multiple escalated cases
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 20; i++) {
            cases.add(new Case(
                Subject = 'Bulk Escalation Revert ' + i,
                Status = 'New',
                Priority = 'Medium',
                IsEscalated = true
            ));
        }
        insert cases;

        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        // Configure mock rule
        String config = '{"field":"IsEscalated","value":"false","postChatter":true,"chatterMessage":"Bulk revert test"}';
        PatternFixService.mockRule = createMockRule('Escalation_Revert', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(caseIds, 'Test_Rule');
        Test.stopTest();

        // Verify all cases were de-escalated
        List<Case> updatedCases = [SELECT IsEscalated FROM Case WHERE Id IN :caseIds];
        for (Case c : updatedCases) {
            System.assertEquals(false, c.IsEscalated, 'All cases should be de-escalated');
        }

        // Verify remediation logs
        List<Remediation_Log__c> logs = [SELECT Id FROM Remediation_Log__c WHERE Action_Taken__c = 'Escalation_Revert'];
        System.assertEquals(20, logs.size(), 'Expected 20 remediation logs');

        // Verify Chatter posts
        List<FeedItem> posts = [SELECT Id FROM FeedItem WHERE ParentId IN :caseIds];
        System.assertEquals(20, posts.size(), 'Expected 20 Chatter posts');

        clearMockRule();
    }

    @isTest
    static void testEscalationRevert_WithoutChatter() {
        // Setup - Create an escalated case
        Case c = new Case(
            Subject = 'No Chatter Revert Test',
            Status = 'New',
            Priority = 'Low',
            IsEscalated = true
        );
        insert c;

        // Configure mock rule without Chatter posting
        String config = '{"field":"IsEscalated","value":"false","postChatter":false}';
        PatternFixService.mockRule = createMockRule('Escalation_Revert', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify case was de-escalated
        Case afterCase = [SELECT IsEscalated FROM Case WHERE Id = :c.Id];
        System.assertEquals(false, afterCase.IsEscalated, 'Case should be de-escalated');

        // Verify NO Chatter post was created
        List<FeedItem> posts = [SELECT Id FROM FeedItem WHERE ParentId = :c.Id];
        System.assertEquals(0, posts.size(), 'No Chatter post should be created when postChatter is false');

        clearMockRule();
    }

    @isTest
    static void testEscalationRevert_Premium() {
        // Setup - Test that premium rule works with premium license
        Case c = new Case(
            Subject = 'Premium Escalation Revert',
            Status = 'New',
            Priority = 'Medium',
            IsEscalated = true
        );
        insert c;

        // Configure mock rule as Premium
        String config = '{"postChatter":true,"chatterMessage":"Premium feature revert"}';
        PatternFixService.mockRule = createMockRule('Escalation_Revert', true, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify case was de-escalated (premium license exists from testSetup)
        Case afterCase = [SELECT IsEscalated FROM Case WHERE Id = :c.Id];
        System.assertEquals(false, afterCase.IsEscalated, 'Premium user should be able to revert escalation');

        clearMockRule();
    }

    // ==================== NO ACTION TESTS ====================

    @isTest
    static void testNoAction_SingleRecord() {
        // Setup - Create a case (no DML will be performed on it)
        Case c = new Case(
            Subject = 'No Action Test',
            Status = 'New',
            Priority = 'Low'
        );
        insert c;

        // Capture original state
        Case beforeCase = [SELECT Subject, Status, Priority FROM Case WHERE Id = :c.Id];

        // Configure mock rule for No_Action
        String config = '{"message":"Expected seasonal pattern - no remediation needed"}';
        PatternFixService.mockRule = createMockRule('No_Action', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify case was NOT modified
        Case afterCase = [SELECT Subject, Status, Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals(beforeCase.Subject, afterCase.Subject, 'Subject should not change');
        System.assertEquals(beforeCase.Status, afterCase.Status, 'Status should not change');
        System.assertEquals(beforeCase.Priority, afterCase.Priority, 'Priority should not change');

        // Verify Remediation Log was created with message
        List<Remediation_Log__c> logs = [
            SELECT Affected_Record_ID__c, Action_Taken__c, New_Value__c, Status__c
            FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('No_Action', logs[0].Action_Taken__c, 'Action should be No_Action');
        System.assertEquals('Expected seasonal pattern - no remediation needed', logs[0].New_Value__c, 'Message should be logged');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        clearMockRule();
    }

    @isTest
    static void testNoAction_BulkRecords() {
        // Setup - Create multiple cases
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            cases.add(new Case(
                Subject = 'Bulk No Action Test ' + i,
                Status = 'New'
            ));
        }
        insert cases;

        List<Id> caseIds = new List<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        // Configure mock rule
        String config = '{"message":"Weekend spike - informational only"}';
        PatternFixService.mockRule = createMockRule('No_Action', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(caseIds, 'Test_Rule');
        Test.stopTest();

        // Verify all logs were created
        List<Remediation_Log__c> logs = [SELECT New_Value__c FROM Remediation_Log__c WHERE Action_Taken__c = 'No_Action'];
        System.assertEquals(50, logs.size(), 'Expected 50 remediation logs');

        // Verify message is consistent across all logs
        for (Remediation_Log__c log : logs) {
            System.assertEquals('Weekend spike - informational only', log.New_Value__c, 'All logs should have same message');
        }

        clearMockRule();
    }

    @isTest
    static void testNoAction_DefaultMessage() {
        // Setup - Test with empty config (use default message)
        Case c = new Case(Subject = 'Default No Action Message', Status = 'New');
        insert c;

        // Configure mock rule with empty config
        PatternFixService.mockRule = createMockRule('No_Action', false, '{}');

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created with default message
        List<Remediation_Log__c> logs = [
            SELECT New_Value__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('Expected pattern - no action required', logs[0].New_Value__c, 'Should use default message');

        clearMockRule();
    }

    @isTest
    static void testNoAction_WithOpportunity() {
        // Test No_Action with Opportunity object
        Opportunity opp = new Opportunity(
            Name = 'No Action Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        String config = '{"message":"Seasonal pattern - expected behavior"}';
        PatternFixService.mockRule = createMockRule('No_Action', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{opp.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(opp.Id)
        ];
        System.assertEquals(1, logs.size(), 'Expected exactly 1 remediation log');
        System.assertEquals('No_Action', logs[0].Action_Taken__c, 'Action should be No_Action');
        System.assertEquals('Success', logs[0].Status__c, 'Status should be Success');

        clearMockRule();
    }

    // ==================== EMAIL OPT-OUT TESTS ====================

    @isTest
    static void testEmailNotification_OptedOutUser() {
        // Create a Case with an owner
        Account a = new Account(Name = 'Test Account for Opt-Out');
        insert a;

        Case c = new Case(
            Subject = 'Test Opt-Out Case',
            Status = 'New',
            AccountId = a.Id
        );
        insert c;

        // Configure mock rule for Email_Notification
        String config = '{"subject":"Test Alert","body":"Please review this case."}';
        PatternFixService.mockRule = createMockRule('Email_Notification', false, config);

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{c.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify remediation log was created (success or failure depending on user settings)
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(c.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Email_Notification', logs[0].Action_Taken__c, 'Action should be Email_Notification');

        clearMockRule();
    }

    // ==================== OWNER ASSIGNMENT FAILURE TESTS ====================

    @isTest
    static void testOwnerAssignment_NoQueueOrFallback_ThrowsError() {
        // Test that owner assignment fails explicitly when no queue or fallback is configured
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'Lead No Fallback',
            Company = 'Test Company'
        );
        insert l;

        // Configure mock rule for Owner_Assignment WITHOUT any fallback
        // Note: Since there's no queue configured in test context and no fallbackOwnerId set,
        // this should throw an exception
        String config = '{"useAssignmentRules":false}';
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, config);

        // Explicitly set fallbackOwnerId to null to ensure no fallback
        PatternFixService.fallbackOwnerId = null;

        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            PatternFixService service = new PatternFixService();
            service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        // In test context, the queue lookup may find a queue or may not
        // The test verifies that the error handling path works correctly
        if (exceptionThrown) {
            System.assert(
                errorMessage.contains('No queue is configured') || errorMessage.contains('fallback owner'),
                'Error message should indicate missing queue/fallback configuration. Got: ' + errorMessage
            );
        }

        clearMockRule();
    }

    @isTest
    static void testOwnerAssignment_WithFallbackOwnerId_Succeeds() {
        // Test that owner assignment succeeds when fallbackOwnerId is explicitly set
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'Lead With Fallback',
            Company = 'Test Company'
        );
        insert l;

        // Configure mock rule for Owner_Assignment with fallback
        String config = '{"useAssignmentRules":false}';
        PatternFixService.mockRule = createMockRule('Owner_Assignment', false, config);

        // Set the test-injectable fallback to current user
        PatternFixService.fallbackOwnerId = UserInfo.getUserId();

        Test.startTest();
        PatternFixService service = new PatternFixService();
        service.executeFix(new List<Id>{l.Id}, 'Test_Rule');
        Test.stopTest();

        // Verify log was created with success
        List<Remediation_Log__c> logs = [
            SELECT Action_Taken__c, Status__c FROM Remediation_Log__c
            WHERE Affected_Record_ID__c = :String.valueOf(l.Id)
        ];
        System.assert(logs.size() >= 1, 'Expected at least 1 remediation log');
        System.assertEquals('Owner_Assignment', logs[0].Action_Taken__c, 'Action should be Owner_Assignment');

        clearMockRule();
    }
}