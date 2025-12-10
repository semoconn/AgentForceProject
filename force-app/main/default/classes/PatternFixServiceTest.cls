@isTest
private class PatternFixServiceTest {

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

        // Verify Lead owner is set to fallback (current user)
        Lead updatedLead = [SELECT OwnerId FROM Lead WHERE Id = :l.Id];
        System.assertEquals(UserInfo.getUserId(), updatedLead.OwnerId, 'Lead should be owned by fallback owner');

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
}
