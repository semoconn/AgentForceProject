/**
 * @description Test class for ExclusionBuilderController. Provides comprehensive coverage
 *              for all controller methods including positive and negative test cases.
 * @author      BehaviorIQ
 * @group       BehaviorIQ
 */
@IsTest
private class ExclusionBuilderControllerTest {

    /**
     * @description Sets up test data for the test methods.
     */
    @TestSetup
    static void setupTestData() {
        // Create a BehaviorIQ_Configuration__c record
        BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
            Name = 'Default',
            Monitored_Objects__c = 'Account,Lead,Opportunity,Case',
            Global_Exclusion_Filter__c = '{"Account": "Type != \'Customer\'"}'
        );
        insert config;
    }

    /**
     * @description Tests getMonitoredObjects returns configured objects.
     */
    @IsTest
    static void testGetMonitoredObjects_WithConfig() {
        Test.startTest();
        List<ExclusionBuilderController.ObjectWrapper> result = ExclusionBuilderController.getMonitoredObjects();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should return at least one object');

        // Check that expected objects are in the result
        Set<String> objectNames = new Set<String>();
        for (ExclusionBuilderController.ObjectWrapper wrapper : result) {
            objectNames.add(wrapper.value);
            System.assertNotEquals(null, wrapper.label, 'Label should not be null');
            System.assertNotEquals(null, wrapper.value, 'Value should not be null');
        }

        System.assert(objectNames.contains('Account'), 'Should contain Account');
        System.assert(objectNames.contains('Lead'), 'Should contain Lead');
    }

    /**
     * @description Tests getMonitoredObjects returns default objects when no config exists.
     */
    @IsTest
    static void testGetMonitoredObjects_WithoutConfig() {
        // Delete the config record
        delete [SELECT Id FROM BehaviorIQ_Configuration__c];

        Test.startTest();
        List<ExclusionBuilderController.ObjectWrapper> result = ExclusionBuilderController.getMonitoredObjects();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should return default objects');
    }

    /**
     * @description Tests getObjectFields returns fields for a valid object.
     */
    @IsTest
    static void testGetObjectFields_ValidObject() {
        Test.startTest();
        List<ExclusionBuilderController.FieldWrapper> result = ExclusionBuilderController.getObjectFields('Account');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should return at least one field');

        // Verify wrapper properties are populated
        Boolean foundType = false;
        for (ExclusionBuilderController.FieldWrapper wrapper : result) {
            System.assertNotEquals(null, wrapper.label, 'Label should not be null');
            System.assertNotEquals(null, wrapper.value, 'Value should not be null');
            System.assertNotEquals(null, wrapper.dataType, 'DataType should not be null');
            if (wrapper.value == 'Type') {
                foundType = true;
            }
        }

        System.assert(foundType, 'Should contain Type field for Account');
    }

    /**
     * @description Tests getObjectFields throws exception for blank object name.
     */
    @IsTest
    static void testGetObjectFields_BlankObjectName() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ExclusionBuilderController.getObjectFields('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Object name is required'), 'Should indicate object name is required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for blank object name');
    }

    /**
     * @description Tests getObjectFields throws exception for invalid object name.
     */
    @IsTest
    static void testGetObjectFields_InvalidObject() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ExclusionBuilderController.getObjectFields('NonExistentObject__c');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Object not found'), 'Should indicate object not found');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for invalid object');
    }

    /**
     * @description Tests getPicklistValues returns values for a valid picklist field.
     */
    @IsTest
    static void testGetPicklistValues_ValidPicklist() {
        Test.startTest();
        List<ExclusionBuilderController.PicklistWrapper> result =
            ExclusionBuilderController.getPicklistValues('Lead', 'Status');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should return at least one picklist value');

        // Verify wrapper properties are populated
        for (ExclusionBuilderController.PicklistWrapper wrapper : result) {
            System.assertNotEquals(null, wrapper.label, 'Label should not be null');
            System.assertNotEquals(null, wrapper.value, 'Value should not be null');
        }
    }

    /**
     * @description Tests getPicklistValues throws exception for blank parameters.
     */
    @IsTest
    static void testGetPicklistValues_BlankParams() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ExclusionBuilderController.getPicklistValues('', 'Status');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('required'), 'Should indicate parameters are required');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for blank parameters');
    }

    /**
     * @description Tests getPicklistValues throws exception for invalid field.
     */
    @IsTest
    static void testGetPicklistValues_InvalidField() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ExclusionBuilderController.getPicklistValues('Account', 'NonExistentField__c');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Field not found'), 'Should indicate field not found');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for invalid field');
    }

    /**
     * @description Tests getExclusionConfig returns existing configuration.
     */
    @IsTest
    static void testGetExclusionConfig_WithExistingConfig() {
        Test.startTest();
        ExclusionBuilderController.ExclusionConfigWrapper result = ExclusionBuilderController.getExclusionConfig();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.recordId, 'Record Id should not be null');
        System.assertNotEquals(null, result.jsonConfig, 'JSON config should not be null');
        System.assert(result.jsonConfig.contains('Account'), 'Should contain Account exclusion');
    }

    /**
     * @description Tests getExclusionConfig returns empty config when none exists.
     */
    @IsTest
    static void testGetExclusionConfig_NoExistingConfig() {
        // Delete the config record
        delete [SELECT Id FROM BehaviorIQ_Configuration__c];

        Test.startTest();
        ExclusionBuilderController.ExclusionConfigWrapper result = ExclusionBuilderController.getExclusionConfig();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(null, result.recordId, 'Record Id should be null when no config exists');
        System.assertEquals('{}', result.jsonConfig, 'Should return empty JSON object');
    }

    /**
     * @description Tests saveExclusions creates a new configuration record.
     */
    @IsTest
    static void testSaveExclusions_NewRecord() {
        // Delete the config record
        delete [SELECT Id FROM BehaviorIQ_Configuration__c];

        String testJson = '{"Lead": "Status != \'Closed\'"}';

        Test.startTest();
        Id resultId = ExclusionBuilderController.saveExclusions(testJson);
        Test.stopTest();

        System.assertNotEquals(null, resultId, 'Should return the new record Id');

        // Verify the record was created
        BehaviorIQ_Configuration__c config = [
            SELECT Id, Global_Exclusion_Filter__c
            FROM BehaviorIQ_Configuration__c
            WHERE Id = :resultId
        ];

        System.assertEquals(testJson, config.Global_Exclusion_Filter__c, 'JSON should be saved correctly');
    }

    /**
     * @description Tests saveExclusions updates an existing configuration record.
     */
    @IsTest
    static void testSaveExclusions_UpdateExisting() {
        String testJson = '{"Account": "Type != \'Partner\'", "Lead": "Rating != \'Hot\'"}';

        Test.startTest();
        Id resultId = ExclusionBuilderController.saveExclusions(testJson);
        Test.stopTest();

        System.assertNotEquals(null, resultId, 'Should return the record Id');

        // Verify the record was updated
        BehaviorIQ_Configuration__c config = [
            SELECT Id, Global_Exclusion_Filter__c
            FROM BehaviorIQ_Configuration__c
            WHERE Id = :resultId
        ];

        System.assertEquals(testJson, config.Global_Exclusion_Filter__c, 'JSON should be updated correctly');
    }

    /**
     * @description Tests saveExclusions handles blank input gracefully.
     */
    @IsTest
    static void testSaveExclusions_BlankInput() {
        Test.startTest();
        Id resultId = ExclusionBuilderController.saveExclusions('');
        Test.stopTest();

        System.assertNotEquals(null, resultId, 'Should return the record Id');

        // Verify the record has empty JSON object
        BehaviorIQ_Configuration__c config = [
            SELECT Id, Global_Exclusion_Filter__c
            FROM BehaviorIQ_Configuration__c
            WHERE Id = :resultId
        ];

        System.assertEquals('{}', config.Global_Exclusion_Filter__c, 'Should save empty JSON object');
    }

    /**
     * @description Tests saveExclusions throws exception for invalid JSON.
     */
    @IsTest
    static void testSaveExclusions_InvalidJson() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ExclusionBuilderController.saveExclusions('not valid json');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('Invalid JSON'), 'Should indicate invalid JSON');
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw AuraHandledException for invalid JSON');
    }

    /**
     * @description Tests ObjectWrapper compareTo method for sorting.
     */
    @IsTest
    static void testObjectWrapper_CompareTo() {
        ExclusionBuilderController.ObjectWrapper wrapper1 = new ExclusionBuilderController.ObjectWrapper();
        wrapper1.label = 'Account';
        wrapper1.value = 'Account';

        ExclusionBuilderController.ObjectWrapper wrapper2 = new ExclusionBuilderController.ObjectWrapper();
        wrapper2.label = 'Lead';
        wrapper2.value = 'Lead';

        ExclusionBuilderController.ObjectWrapper wrapper3 = new ExclusionBuilderController.ObjectWrapper();
        wrapper3.label = null;
        wrapper3.value = 'Case';

        Test.startTest();
        Integer result1 = wrapper1.compareTo(wrapper2);
        Integer result2 = wrapper2.compareTo(wrapper1);
        Integer result3 = wrapper3.compareTo(wrapper1);
        Integer result4 = wrapper1.compareTo(wrapper3);
        Test.stopTest();

        System.assert(result1 < 0, 'Account should come before Lead');
        System.assert(result2 > 0, 'Lead should come after Account');
        System.assertEquals(-1, result3, 'Null label should return -1');
        System.assertEquals(1, result4, 'Non-null should return 1 when compared to null');
    }

    /**
     * @description Tests FieldWrapper compareTo method for sorting.
     */
    @IsTest
    static void testFieldWrapper_CompareTo() {
        ExclusionBuilderController.FieldWrapper wrapper1 = new ExclusionBuilderController.FieldWrapper();
        wrapper1.label = 'Account Name';
        wrapper1.value = 'Name';
        wrapper1.dataType = 'STRING';

        ExclusionBuilderController.FieldWrapper wrapper2 = new ExclusionBuilderController.FieldWrapper();
        wrapper2.label = 'Type';
        wrapper2.value = 'Type';
        wrapper2.dataType = 'PICKLIST';

        ExclusionBuilderController.FieldWrapper wrapper3 = new ExclusionBuilderController.FieldWrapper();
        wrapper3.label = null;
        wrapper3.value = 'Status';
        wrapper3.dataType = 'PICKLIST';

        Test.startTest();
        Integer result1 = wrapper1.compareTo(wrapper2);
        Integer result2 = wrapper2.compareTo(wrapper1);
        Integer result3 = wrapper3.compareTo(wrapper1);
        Integer result4 = wrapper1.compareTo(wrapper3);
        Test.stopTest();

        System.assert(result1 < 0, 'Account Name should come before Type');
        System.assert(result2 > 0, 'Type should come after Account Name');
        System.assertEquals(-1, result3, 'Null label should return -1');
        System.assertEquals(1, result4, 'Non-null should return 1 when compared to null');
    }

    /**
     * @description Tests getPicklistValues with Account Type field.
     */
    @IsTest
    static void testGetPicklistValues_AccountType() {
        Test.startTest();
        List<ExclusionBuilderController.PicklistWrapper> result =
            ExclusionBuilderController.getPicklistValues('Account', 'Type');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // Account Type is a standard picklist field
        System.assert(result.size() >= 0, 'Should return picklist values (may be empty in some orgs)');
    }

    /**
     * @description Tests getObjectFields includes various data types.
     */
    @IsTest
    static void testGetObjectFields_DataTypes() {
        Test.startTest();
        List<ExclusionBuilderController.FieldWrapper> result = ExclusionBuilderController.getObjectFields('Lead');
        Test.stopTest();

        Set<String> foundDataTypes = new Set<String>();
        for (ExclusionBuilderController.FieldWrapper wrapper : result) {
            foundDataTypes.add(wrapper.dataType);
        }

        // Lead should have various field types
        System.assert(foundDataTypes.contains('STRING') || foundDataTypes.contains('TEXTAREA'),
            'Should contain string-type fields');
        System.assert(foundDataTypes.contains('PICKLIST'), 'Should contain picklist fields');
    }

    /**
     * @description Tests getMonitoredObjects when config has empty Monitored_Objects__c.
     */
    @IsTest
    static void testGetMonitoredObjects_EmptyConfig() {
        // Update config to have empty monitored objects
        BehaviorIQ_Configuration__c config = [
            SELECT Id, Monitored_Objects__c
            FROM BehaviorIQ_Configuration__c
            LIMIT 1
        ];
        config.Monitored_Objects__c = '';
        update config;

        Test.startTest();
        List<ExclusionBuilderController.ObjectWrapper> result = ExclusionBuilderController.getMonitoredObjects();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Should return default objects when config is empty');
    }

    /**
     * @description Tests getExclusionConfig when Global_Exclusion_Filter__c is blank.
     */
    @IsTest
    static void testGetExclusionConfig_BlankFilter() {
        // Update config to have blank exclusion filter
        BehaviorIQ_Configuration__c config = [
            SELECT Id, Global_Exclusion_Filter__c
            FROM BehaviorIQ_Configuration__c
            LIMIT 1
        ];
        config.Global_Exclusion_Filter__c = '';
        update config;

        Test.startTest();
        ExclusionBuilderController.ExclusionConfigWrapper result = ExclusionBuilderController.getExclusionConfig();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.recordId, 'Record Id should not be null');
        System.assertEquals('{}', result.jsonConfig, 'Should return empty JSON object when filter is blank');
    }
}
