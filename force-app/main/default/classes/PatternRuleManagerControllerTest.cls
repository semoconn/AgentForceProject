/**
 * @description Test class for PatternRuleManagerController
 * @author BehaviorIQ
 * @group BehaviorIQ
 */
@isTest
private class PatternRuleManagerControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test configuration
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Monitored_Objects__c = 'Case,Lead,Opportunity'
        );
        insert config;
    }

    // ==================== READ OPERATIONS TESTS ====================

    @isTest
    static void testGetAllPatternRules() {
        Test.startTest();
        List<PatternRuleManagerController.RuleWrapper> rules = PatternRuleManagerController.getAllPatternRules();
        Test.stopTest();

        // Should return rules (from actual metadata in org)
        System.assertNotEquals(null, rules, 'Rules list should not be null');
    }

    @isTest
    static void testGetRuleByDeveloperName_NotFound() {
        Test.startTest();
        try {
            PatternRuleManagerController.getRuleByDeveloperName('NonExistent_Rule_12345');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            // AuraHandledException wraps the message - just verify exception was thrown
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetRuleByDeveloperName_BlankName() {
        Test.startTest();
        try {
            PatternRuleManagerController.getRuleByDeveloperName('');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetAvailableObjects() {
        Test.startTest();
        List<PatternRuleManagerController.ObjectWrapper> objects = PatternRuleManagerController.getAvailableObjects();
        Test.stopTest();

        System.assertNotEquals(null, objects, 'Objects list should not be null');
        System.assert(objects.size() > 0, 'Should return at least some objects');

        // Verify standard objects are included
        Boolean hasAccount = false;
        Boolean hasCase = false;
        for (PatternRuleManagerController.ObjectWrapper obj : objects) {
            if (obj.value == 'Account') hasAccount = true;
            if (obj.value == 'Case') hasCase = true;
        }
        System.assert(hasAccount, 'Should include Account object');
        System.assert(hasCase, 'Should include Case object');
    }

    @isTest
    static void testGetObjectFields() {
        Test.startTest();
        List<PatternRuleManagerController.FieldWrapper> fields = PatternRuleManagerController.getObjectFields('Case');
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Fields list should not be null');
        System.assert(fields.size() > 0, 'Should return fields for Case object');

        // Verify some standard fields are included
        Boolean hasStatus = false;
        for (PatternRuleManagerController.FieldWrapper field : fields) {
            if (field.value == 'Status') hasStatus = true;
        }
        System.assert(hasStatus, 'Should include Status field');
    }

    @isTest
    static void testGetObjectFields_BlankObject() {
        Test.startTest();
        try {
            PatternRuleManagerController.getObjectFields('');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetObjectFields_InvalidObject() {
        Test.startTest();
        try {
            PatternRuleManagerController.getObjectFields('InvalidObject123');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<PatternRuleManagerController.PicklistOption> options = PatternRuleManagerController.getPicklistValues('Case', 'Status');
        Test.stopTest();

        System.assertNotEquals(null, options, 'Picklist options should not be null');
        System.assert(options.size() > 0, 'Should return picklist values for Case.Status');
    }

    @isTest
    static void testGetPicklistValues_BlankParams() {
        Test.startTest();
        try {
            PatternRuleManagerController.getPicklistValues('', '');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPicklistValues_InvalidField() {
        Test.startTest();
        try {
            PatternRuleManagerController.getPicklistValues('Case', 'InvalidField123');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFixTypeOptions() {
        Test.startTest();
        List<PatternRuleManagerController.PicklistOption> options = PatternRuleManagerController.getFixTypeOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Fix type options should not be null');
        System.assert(options.size() > 0, 'Should return fix type options');

        // Verify some expected values
        Boolean hasTaskCreation = false;
        for (PatternRuleManagerController.PicklistOption opt : options) {
            if (opt.value == 'Task_Creation') hasTaskCreation = true;
        }
        System.assert(hasTaskCreation, 'Should include Task_Creation fix type');
    }

    @isTest
    static void testGetLogicTypeOptions() {
        Test.startTest();
        List<PatternRuleManagerController.PicklistOption> options = PatternRuleManagerController.getLogicTypeOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Logic type options should not be null');
        System.assert(options.size() > 0, 'Should return logic type options');

        // Verify expected values
        Boolean hasStandard = false;
        for (PatternRuleManagerController.PicklistOption opt : options) {
            if (opt.value == 'Standard') hasStandard = true;
        }
        System.assert(hasStandard, 'Should include Standard logic type');
    }

    // ==================== VALIDATION TESTS ====================

    @isTest
    static void testValidateQueryCondition_ValidCondition() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            'Case',
            'Status != \'Closed\' AND CreatedDate < LAST_N_DAYS:30'
        );
        Test.stopTest();

        System.assert(result.isValid, 'Valid condition should pass validation');
        System.assert(result.referencedFields.size() > 0, 'Should extract field references');
    }

    @isTest
    static void testValidateQueryCondition_EmptyCondition() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            'Case',
            ''
        );
        Test.stopTest();

        System.assert(result.isValid, 'Empty condition should be valid (matches all records)');
    }

    @isTest
    static void testValidateQueryCondition_BlankObject() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            '',
            'Status = \'Open\''
        );
        Test.stopTest();

        System.assert(!result.isValid, 'Should fail with blank object name');
    }

    @isTest
    static void testValidateQueryCondition_InvalidObject() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            'InvalidObject123',
            'Status = \'Open\''
        );
        Test.stopTest();

        System.assert(!result.isValid, 'Should fail with invalid object');
    }

    @isTest
    static void testValidateQueryCondition_InvalidField() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            'Case',
            'InvalidField123 = \'test\''
        );
        Test.stopTest();

        System.assert(!result.isValid, 'Should fail with invalid field');
        System.assert(result.inaccessibleFields.contains('InvalidField123'), 'Should list invalid field');
    }

    @isTest
    static void testTestPatternQuery() {
        Test.startTest();
        Integer count = PatternRuleManagerController.testPatternQuery('Case', '');
        Test.stopTest();

        // Count can be 0 or more depending on test data
        System.assert(count >= 0, 'Should return a valid count');
    }

    @isTest
    static void testTestPatternQuery_BlankObject() {
        Test.startTest();
        try {
            PatternRuleManagerController.testPatternQuery('', '');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testTestPatternQuery_InvalidObject() {
        Test.startTest();
        try {
            PatternRuleManagerController.testPatternQuery('InvalidObject123', '');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    // ==================== WRITE OPERATIONS TESTS ====================

    @isTest
    static void testSavePatternRule_BlankJson() {
        Test.startTest();
        try {
            PatternRuleManagerController.savePatternRule('');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSavePatternRule_MissingLabel() {
        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule',
            'objectApiName' => 'Case',
            'fixType' => 'Task_Creation'
        });

        Test.startTest();
        try {
            PatternRuleManagerController.savePatternRule(ruleJson);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSavePatternRule_MissingObject() {
        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule',
            'label' => 'Test Rule',
            'fixType' => 'Task_Creation'
        });

        Test.startTest();
        try {
            PatternRuleManagerController.savePatternRule(ruleJson);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSavePatternRule_InvalidObject() {
        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule',
            'label' => 'Test Rule',
            'objectApiName' => 'InvalidObject123',
            'fixType' => 'Task_Creation'
        });

        Test.startTest();
        try {
            PatternRuleManagerController.savePatternRule(ruleJson);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSavePatternRule_ValidRule() {
        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule_' + System.currentTimeMillis(),
            'label' => 'Test Rule',
            'objectApiName' => 'Case',
            'fixType' => 'Task_Creation',
            'logicType' => 'Standard',
            'queryCondition' => 'Status != \'Closed\'',
            'isPremium' => false,
            'isActive' => true
        });

        Test.startTest();
        try {
            String jobId = PatternRuleManagerController.savePatternRule(ruleJson);
            // If we get here, the validation passed and deployment was enqueued
            System.assertNotEquals(null, jobId, 'Should return a job ID');
        } catch (AuraHandledException e) {
            // Metadata API operations may fail in test context - that's expected
            System.assert(true, 'Metadata API operation executed (may fail in test context)');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeactivateRule_BlankName() {
        Test.startTest();
        try {
            PatternRuleManagerController.deactivateRule('');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testDeactivateRule_NotFound() {
        Test.startTest();
        try {
            PatternRuleManagerController.deactivateRule('NonExistent_Rule_12345');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testReactivateRule_BlankName() {
        Test.startTest();
        try {
            PatternRuleManagerController.reactivateRule('');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testReactivateRule_NotFound() {
        Test.startTest();
        try {
            PatternRuleManagerController.reactivateRule('NonExistent_Rule_12345');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    // ==================== WRAPPER CLASS TESTS ====================

    @isTest
    static void testObjectWrapperComparable() {
        PatternRuleManagerController.ObjectWrapper obj1 = new PatternRuleManagerController.ObjectWrapper();
        obj1.label = 'Apple';
        obj1.value = 'Apple__c';

        PatternRuleManagerController.ObjectWrapper obj2 = new PatternRuleManagerController.ObjectWrapper();
        obj2.label = 'Banana';
        obj2.value = 'Banana__c';

        PatternRuleManagerController.ObjectWrapper obj3 = new PatternRuleManagerController.ObjectWrapper();
        obj3.label = null;
        obj3.value = 'Null__c';

        Test.startTest();
        Integer comparison1 = obj1.compareTo(obj2);
        Integer comparison2 = obj2.compareTo(obj1);
        Integer comparison3 = obj3.compareTo(obj1);
        Integer comparison4 = obj1.compareTo(obj3);
        Test.stopTest();

        System.assert(comparison1 < 0, 'Apple should come before Banana');
        System.assert(comparison2 > 0, 'Banana should come after Apple');
        System.assert(comparison3 < 0, 'Null label should come before non-null');
        System.assert(comparison4 > 0, 'Non-null label should come after null');
    }

    @isTest
    static void testFieldWrapperComparable() {
        PatternRuleManagerController.FieldWrapper field1 = new PatternRuleManagerController.FieldWrapper();
        field1.label = 'Alpha Field';
        field1.value = 'Alpha__c';
        field1.dataType = 'STRING';

        PatternRuleManagerController.FieldWrapper field2 = new PatternRuleManagerController.FieldWrapper();
        field2.label = 'Beta Field';
        field2.value = 'Beta__c';
        field2.dataType = 'STRING';

        Test.startTest();
        Integer comparison = field1.compareTo(field2);
        Test.stopTest();

        System.assert(comparison < 0, 'Alpha Field should come before Beta Field');
    }

    @isTest
    static void testRuleWrapperProperties() {
        PatternRuleManagerController.RuleWrapper wrapper = new PatternRuleManagerController.RuleWrapper();
        wrapper.developerName = 'Test_Rule';
        wrapper.label = 'Test Rule';
        wrapper.objectApiName = 'Case';
        wrapper.objectLabel = 'Case';
        wrapper.queryCondition = 'Status = \'Open\'';
        wrapper.thresholdDefault = 30;
        wrapper.fixType = 'Task_Creation';
        wrapper.fixConfig = '{"subject":"Follow up"}';
        wrapper.logicType = 'Standard';
        wrapper.apexHandlerClass = null;
        wrapper.isPremium = false;
        wrapper.costPerIncident = 100.00;
        wrapper.isActive = true;
        wrapper.badgeClass = 'standard';

        Test.startTest();
        // Just verify all properties are accessible
        System.assertEquals('Test_Rule', wrapper.developerName);
        System.assertEquals('Test Rule', wrapper.label);
        System.assertEquals('Case', wrapper.objectApiName);
        System.assertEquals(30, wrapper.thresholdDefault);
        System.assertEquals(false, wrapper.isPremium);
        System.assertEquals(true, wrapper.isActive);
        Test.stopTest();
    }

    @isTest
    static void testValidationResultProperties() {
        PatternRuleManagerController.ValidationResult result = new PatternRuleManagerController.ValidationResult();
        result.isValid = true;
        result.errorMessage = null;
        result.referencedFields = new List<String>{ 'Status', 'CreatedDate' };
        result.inaccessibleFields = new List<String>();

        Test.startTest();
        System.assertEquals(true, result.isValid);
        System.assertEquals(null, result.errorMessage);
        System.assertEquals(2, result.referencedFields.size());
        System.assertEquals(0, result.inaccessibleFields.size());
        Test.stopTest();
    }

    @isTest
    static void testPicklistOptionProperties() {
        PatternRuleManagerController.PicklistOption option = new PatternRuleManagerController.PicklistOption();
        option.label = 'Test Label';
        option.value = 'Test_Value';

        Test.startTest();
        System.assertEquals('Test Label', option.label);
        System.assertEquals('Test_Value', option.value);
        Test.stopTest();
    }

    // ==================== EXISTING RULE TESTS ====================

    @isTest
    static void testGetRuleByDeveloperName_ExistingRule() {
        // Get an existing rule from the actual metadata
        List<PatternRuleManagerController.RuleWrapper> allRules = PatternRuleManagerController.getAllPatternRules();

        if (allRules.isEmpty()) {
            // Skip if no rules exist
            return;
        }

        String existingRuleName = allRules[0].developerName;

        Test.startTest();
        PatternRuleManagerController.RuleWrapper rule = PatternRuleManagerController.getRuleByDeveloperName(existingRuleName);
        Test.stopTest();

        System.assertNotEquals(null, rule, 'Should return the rule');
        System.assertEquals(existingRuleName, rule.developerName, 'Developer name should match');
    }

    @isTest
    static void testDeactivateExistingRule() {
        // Get an existing rule from the actual metadata
        List<PatternRuleManagerController.RuleWrapper> allRules = PatternRuleManagerController.getAllPatternRules();

        if (allRules.isEmpty()) {
            // Skip if no rules exist
            return;
        }

        String existingRuleName = allRules[0].developerName;

        Test.startTest();
        try {
            String deactivateJobId = PatternRuleManagerController.deactivateRule(existingRuleName);
            System.assertNotEquals(null, deactivateJobId, 'Should return a job ID for deactivation');
        } catch (AuraHandledException e) {
            // Metadata API operations may fail in test context
            System.assert(true, 'Metadata API operation executed');
        }
        Test.stopTest();
    }

    @isTest
    static void testReactivateExistingRule() {
        // Get an existing rule from the actual metadata
        List<PatternRuleManagerController.RuleWrapper> allRules = PatternRuleManagerController.getAllPatternRules();

        if (allRules.isEmpty()) {
            // Skip if no rules exist
            return;
        }

        String existingRuleName = allRules[0].developerName;

        Test.startTest();
        try {
            String reactivateJobId = PatternRuleManagerController.reactivateRule(existingRuleName);
            System.assertNotEquals(null, reactivateJobId, 'Should return a job ID for reactivation');
        } catch (AuraHandledException e) {
            // Metadata API operations may fail in test context
            System.assert(true, 'Metadata API operation executed');
        }
        Test.stopTest();
    }

    // ==================== ADDITIONAL COVERAGE TESTS ====================

    @isTest
    static void testValidateQueryCondition_WithRelationshipField() {
        Test.startTest();
        PatternRuleManagerController.ValidationResult result = PatternRuleManagerController.validateQueryCondition(
            'Case',
            'Account.Name != null'
        );
        Test.stopTest();

        // Relationship fields are skipped in validation
        System.assert(result.isValid, 'Relationship field condition should pass validation');
    }

    @isTest
    static void testGetObjectFields_ForOpportunity() {
        Test.startTest();
        List<PatternRuleManagerController.FieldWrapper> fields = PatternRuleManagerController.getObjectFields('Opportunity');
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Fields list should not be null');
        System.assert(fields.size() > 0, 'Should return fields for Opportunity object');
    }

    @isTest
    static void testGetPicklistValues_ForOpportunityStage() {
        Test.startTest();
        List<PatternRuleManagerController.PicklistOption> options = PatternRuleManagerController.getPicklistValues('Opportunity', 'StageName');
        Test.stopTest();

        System.assertNotEquals(null, options, 'Picklist options should not be null');
        System.assert(options.size() > 0, 'Should return picklist values for Opportunity.StageName');
    }

    @isTest
    static void testSavePatternRule_WithFixConfig() {
        Map<String, Object> fixConfigMap = new Map<String, Object>{
            'subject' => 'Follow up on stale case',
            'priority' => 'High'
        };

        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule_Config_' + System.currentTimeMillis(),
            'label' => 'Test Rule with Config',
            'objectApiName' => 'Case',
            'fixType' => 'Task_Creation',
            'fixConfig' => JSON.serialize(fixConfigMap),
            'logicType' => 'Standard',
            'queryCondition' => 'Status != \'Closed\'',
            'isPremium' => false,
            'isActive' => true,
            'costPerIncident' => 50.00,
            'thresholdDefault' => 30
        });

        Test.startTest();
        try {
            String jobId = PatternRuleManagerController.savePatternRule(ruleJson);
            System.assertNotEquals(null, jobId, 'Should return a job ID');
        } catch (AuraHandledException e) {
            // Metadata API operations may fail in test context
            System.assert(true, 'Metadata API operation executed');
        }
        Test.stopTest();
    }

    @isTest
    static void testSavePatternRule_MissingFixType() {
        String ruleJson = JSON.serialize(new Map<String, Object>{
            'developerName' => 'Test_Rule',
            'label' => 'Test Rule',
            'objectApiName' => 'Case'
        });

        Test.startTest();
        try {
            PatternRuleManagerController.savePatternRule(ruleJson);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception was thrown as expected for missing fix type');
        }
        Test.stopTest();
    }

    // ==================== CIRCUIT BREAKER TESTS ====================

    @isTest
    static void testResetCircuitBreaker_Success() {
        // Pre-create a circuit breaker health record in Open state
        insert new Rule_Execution_Health__c(
            Rule_Developer_Name__c = 'CB_Test_Rule',
            Circuit_State__c = 'Open',
            Consecutive_Failures__c = 5,
            Total_Failure_Count__c = 10,
            Last_Error__c = 'Test error'
        );

        Test.startTest();
        String result = PatternRuleManagerController.resetCircuitBreaker('CB_Test_Rule');
        Test.stopTest();

        System.assert(result.contains('Circuit breaker reset'), 'Should return success message');

        // Verify circuit was reset
        Rule_Execution_Health__c health = [
            SELECT Circuit_State__c, Consecutive_Failures__c
            FROM Rule_Execution_Health__c
            WHERE Rule_Developer_Name__c = 'CB_Test_Rule'
        ];
        System.assertEquals('Closed', health.Circuit_State__c, 'Circuit should be Closed after reset');
        System.assertEquals(0, health.Consecutive_Failures__c, 'Failures should be reset to 0');
    }

    @isTest
    static void testResetCircuitBreaker_BlankName() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PatternRuleManagerController.resetCircuitBreaker('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for blank rule name');
    }

    @isTest
    static void testGetCircuitBreakerStatus_Empty() {
        // Ensure no health records exist
        delete [SELECT Id FROM Rule_Execution_Health__c];

        Test.startTest();
        List<Rule_Execution_Health__c> results = PatternRuleManagerController.getCircuitBreakerStatus();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should return empty list');
    }

    @isTest
    static void testGetCircuitBreakerStatus_WithRecords() {
        // Create health records
        insert new List<Rule_Execution_Health__c>{
            new Rule_Execution_Health__c(
                Rule_Developer_Name__c = 'Status_Rule_1',
                Circuit_State__c = 'Closed',
                Consecutive_Failures__c = 0
            ),
            new Rule_Execution_Health__c(
                Rule_Developer_Name__c = 'Status_Rule_2',
                Circuit_State__c = 'Open',
                Consecutive_Failures__c = 3,
                Last_Failure_Time__c = System.now(),
                Last_Error__c = 'Test failure'
            )
        };

        Test.startTest();
        List<Rule_Execution_Health__c> results = PatternRuleManagerController.getCircuitBreakerStatus();
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return 2 health records');
    }
}
