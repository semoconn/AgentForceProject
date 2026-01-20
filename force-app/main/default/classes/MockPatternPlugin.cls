/**
 * @description Mock implementation of PatternPlugin for testing purposes.
 * Provides configurable behavior for both analyze() and fix() methods.
 *
 * Usage in tests:
 *   MockPatternPlugin.analyzeResult = new List<Id>{ recordId1, recordId2 };
 *   MockPatternPlugin.fixResult = new PatternPluginResult();
 *   MockPatternPlugin.fixResult.successCount = 2;
 *
 * To simulate exceptions:
 *   MockPatternPlugin.throwOnAnalyze = true;
 *   MockPatternPlugin.throwOnFix = true;
 */
@IsTest
global class MockPatternPlugin implements PatternPlugin {

    // Static variables to control mock behavior
    public static List<Id> analyzeResult = new List<Id>();
    public static PatternPluginResult fixResult;
    public static Boolean throwOnAnalyze = false;
    public static Boolean throwOnFix = false;
    public static String analyzeExceptionMessage = 'Mock analyze exception';
    public static String fixExceptionMessage = 'Mock fix exception';

    // Tracking variables for verification
    public static PatternPluginContext lastAnalyzeContext;
    public static List<Id> lastFixRecordIds;
    public static Map<String, Object> lastFixConfig;
    public static Integer analyzeCallCount = 0;
    public static Integer fixCallCount = 0;

    /**
     * @description Resets all mock state. Call in test setup/cleanup.
     */
    public static void reset() {
        analyzeResult = new List<Id>();
        fixResult = null;
        throwOnAnalyze = false;
        throwOnFix = false;
        analyzeExceptionMessage = 'Mock analyze exception';
        fixExceptionMessage = 'Mock fix exception';
        lastAnalyzeContext = null;
        lastFixRecordIds = null;
        lastFixConfig = null;
        analyzeCallCount = 0;
        fixCallCount = 0;
    }

    /**
     * @description Mock analyze implementation.
     * Returns configured analyzeResult or throws if throwOnAnalyze is true.
     */
    global List<Id> analyze(PatternPluginContext context) {
        analyzeCallCount++;
        lastAnalyzeContext = context;

        if (throwOnAnalyze) {
            throw new PluginInvoker.PluginException(analyzeExceptionMessage);
        }

        return analyzeResult;
    }

    /**
     * @description Mock fix implementation.
     * Returns configured fixResult or throws if throwOnFix is true.
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        fixCallCount++;
        lastFixRecordIds = recordIds;
        lastFixConfig = config;

        if (throwOnFix) {
            throw new PluginInvoker.PluginException(fixExceptionMessage);
        }

        if (fixResult == null) {
            // Default success result
            fixResult = new PatternPluginResult();
            fixResult.successCount = recordIds.size();
        }

        return fixResult;
    }
}
