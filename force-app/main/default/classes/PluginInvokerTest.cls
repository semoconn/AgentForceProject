/**
 * @description Test class for PluginInvoker utility.
 * Tests plugin instantiation, interface validation, and method invocation.
 */
@IsTest
private class PluginInvokerTest {

    @TestSetup
    static void setupTestData() {
        // Create test account for plugin testing
        Account testAccount = new Account(Name = 'Plugin Test Account');
        insert testAccount;
    }

    @IsTest
    static void testInstantiateValidPlugin() {
        // Test: Valid plugin class instantiation
        Test.startTest();
        PatternPlugin plugin = PluginInvoker.instantiate('MockPatternPlugin');
        Test.stopTest();

        System.assertNotEquals(null, plugin, 'Should instantiate valid plugin');
    }

    @IsTest
    static void testInstantiateBlankClassName() {
        // Test: Blank class name throws exception
        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            PluginInvoker.instantiate('');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for blank class name');
        System.assert(errorMessage.contains('cannot be blank'), 'Error should mention blank class name');
    }

    @IsTest
    static void testInstantiateNullClassName() {
        // Test: Null class name throws exception
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.instantiate(null);
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for null class name');
    }

    @IsTest
    static void testInstantiateNonExistentClass() {
        // Test: Non-existent class throws exception
        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            PluginInvoker.instantiate('NonExistentPluginClass12345');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for non-existent class');
        System.assert(errorMessage.contains('not found'), 'Error should mention class not found');
    }

    @IsTest
    static void testInstantiateNonPluginClass() {
        // Test: Class that doesn't implement PatternPlugin
        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            // Account is a valid class but doesn't implement PatternPlugin
            PluginInvoker.instantiate('Account');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for non-plugin class');
        System.assert(errorMessage.contains('does not implement'), 'Error should mention interface not implemented');
    }

    @IsTest
    static void testInvokeAnalyzeSuccess() {
        // Test: Successful analyze invocation
        Account testAcc = [SELECT Id FROM Account LIMIT 1];
        MockPatternPlugin.reset();
        MockPatternPlugin.analyzeResult = new List<Id>{ testAcc.Id };

        PatternPluginContext ctx = new PatternPluginContext(
            'Account',
            'Name != null',
            new Map<String, Object>{ 'key' => 'value' },
            'Test_Rule'
        );

        Test.startTest();
        List<Id> results = PluginInvoker.invokeAnalyze('MockPatternPlugin', ctx);
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return configured result');
        System.assertEquals(testAcc.Id, results[0], 'Should return correct ID');
        System.assertEquals(1, MockPatternPlugin.analyzeCallCount, 'Should call analyze once');
        System.assertEquals('Account', MockPatternPlugin.lastAnalyzeContext.objectApiName, 'Should pass correct context');
    }

    @IsTest
    static void testInvokeAnalyzeReturnsEmptyForNull() {
        // Test: Null result from plugin returns empty list
        MockPatternPlugin.reset();
        MockPatternPlugin.analyzeResult = null;

        PatternPluginContext ctx = new PatternPluginContext();

        Test.startTest();
        List<Id> results = PluginInvoker.invokeAnalyze('MockPatternPlugin', ctx);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return empty list, not null');
        System.assertEquals(0, results.size(), 'Should return empty list');
    }

    @IsTest
    static void testInvokeAnalyzeThrowsException() {
        // Test: Plugin exception during analyze
        MockPatternPlugin.reset();
        MockPatternPlugin.throwOnAnalyze = true;
        MockPatternPlugin.analyzeExceptionMessage = 'Custom analyze error';

        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            PluginInvoker.invokeAnalyze('MockPatternPlugin', new PatternPluginContext());
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should propagate plugin exception');
        System.assert(errorMessage.contains('Custom analyze error'), 'Should include original error message');
    }

    @IsTest
    static void testInvokeFixSuccess() {
        // Test: Successful fix invocation
        Account testAcc = [SELECT Id FROM Account LIMIT 1];
        MockPatternPlugin.reset();

        PatternPluginResult expectedResult = new PatternPluginResult();
        expectedResult.successCount = 1;
        MockPatternPlugin.fixResult = expectedResult;

        Map<String, Object> config = new Map<String, Object>{ 'action' => 'test' };

        Test.startTest();
        PatternPluginResult result = PluginInvoker.invokeFix('MockPatternPlugin', new List<Id>{ testAcc.Id }, config);
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should return configured result');
        System.assertEquals(1, MockPatternPlugin.fixCallCount, 'Should call fix once');
        System.assertEquals(testAcc.Id, MockPatternPlugin.lastFixRecordIds[0], 'Should pass correct IDs');
        System.assertEquals('test', MockPatternPlugin.lastFixConfig.get('action'), 'Should pass correct config');
    }

    @IsTest
    static void testInvokeFixThrowsException() {
        // Test: Plugin exception during fix
        MockPatternPlugin.reset();
        MockPatternPlugin.throwOnFix = true;
        MockPatternPlugin.fixExceptionMessage = 'Custom fix error';

        Boolean exceptionThrown = false;
        String errorMessage = '';

        Test.startTest();
        try {
            PluginInvoker.invokeFix('MockPatternPlugin', new List<Id>(), new Map<String, Object>());
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
            errorMessage = e.getMessage();
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should propagate plugin exception');
        System.assert(errorMessage.contains('Custom fix error'), 'Should include original error message');
    }

    @IsTest
    static void testIsValidPlugin() {
        // Test: Valid plugin validation
        Test.startTest();
        Boolean isValid = PluginInvoker.isValidPlugin('MockPatternPlugin');
        Boolean isInvalid = PluginInvoker.isValidPlugin('NonExistentClass');
        Boolean isNonPlugin = PluginInvoker.isValidPlugin('Account');
        Test.stopTest();

        System.assert(isValid, 'MockPatternPlugin should be valid');
        System.assert(!isInvalid, 'Non-existent class should be invalid');
        System.assert(!isNonPlugin, 'Non-plugin class should be invalid');
    }

    @IsTest
    static void testGetValidationError() {
        // Test: Validation error messages
        Test.startTest();
        String validError = PluginInvoker.getValidationError('MockPatternPlugin');
        String invalidError = PluginInvoker.getValidationError('NonExistentClass');
        Test.stopTest();

        System.assertEquals(null, validError, 'Valid plugin should have no error');
        System.assertNotEquals(null, invalidError, 'Invalid plugin should have error message');
        System.assert(invalidError.contains('not found'), 'Error should explain the issue');
    }

    @IsTest
    static void testForceTypeNotFound() {
        // Test: Test hook for type not found
        PluginInvoker.forceTypeNotFound = true;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.instantiate('MockPatternPlugin');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        PluginInvoker.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when type forced not found');
    }

    @IsTest
    static void testForceInterfaceValidationFailure() {
        // Test: Test hook for interface validation failure
        PluginInvoker.forceInterfaceValidationFailure = true;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.instantiate('MockPatternPlugin');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        PluginInvoker.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when interface validation forced to fail');
    }

    @IsTest
    static void testForceInstantiationException() {
        // Test: Test hook for instantiation exception
        PluginInvoker.forceInstantiationException = true;

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.instantiate('MockPatternPlugin');
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        PluginInvoker.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when instantiation forced to fail');
    }

    @IsTest
    static void testForceAnalyzeException() {
        // Test: Test hook for analyze exception
        PluginInvoker.forceAnalyzeException = true;
        MockPatternPlugin.reset();

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.invokeAnalyze('MockPatternPlugin', new PatternPluginContext());
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        PluginInvoker.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when analyze forced to fail');
    }

    @IsTest
    static void testForceFixException() {
        // Test: Test hook for fix exception
        PluginInvoker.forceFixException = true;
        MockPatternPlugin.reset();

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            PluginInvoker.invokeFix('MockPatternPlugin', new List<Id>(), new Map<String, Object>());
        } catch (PluginInvoker.PluginException e) {
            exceptionThrown = true;
        }
        PluginInvoker.resetTestFlags();
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when fix forced to fail');
    }
}
