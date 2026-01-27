/**
 * @description Utility class for safely instantiating and invoking PatternPlugin implementations.
 * Provides secure Type.forName() wrapper with interface validation, error handling,
 * and comprehensive logging for plugin invocations.
 *
 * Security Features:
 * - Validates class exists before instantiation
 * - Verifies class implements PatternPlugin interface
 * - Catches and logs all exceptions from plugin code
 * - Provides descriptive error messages for debugging
 *
 * @example
 * PatternPluginContext ctx = new PatternPluginContext('Opportunity', 'Amount > 50000', configMap, 'Rule_Name');
 * List<Id> matches = PluginInvoker.invokeAnalyze('MyCustomPlugin', ctx);
 */
public with sharing class PluginInvoker {

    // CPU time monitoring threshold (in milliseconds)
    // Plugins exceeding this threshold trigger a warning log
    // 5000ms (5 seconds) allows reasonable processing while catching runaway plugins
    private static final Integer CPU_TIME_WARNING_THRESHOLD_MS = 5000;

    // Test visibility flags for exception coverage
    @TestVisible private static Boolean forceTypeNotFound = false;
    @TestVisible private static Boolean forceInterfaceValidationFailure = false;
    @TestVisible private static Boolean forceInstantiationException = false;
    @TestVisible private static Boolean forceAnalyzeException = false;
    @TestVisible private static Boolean forceFixException = false;
    @TestVisible private static Boolean forceCpuTimeWarning = false;

    /**
     * @description Resets all test flags. Call in test cleanup.
     */
    @TestVisible
    private static void resetTestFlags() {
        forceTypeNotFound = false;
        forceInterfaceValidationFailure = false;
        forceInstantiationException = false;
        forceAnalyzeException = false;
        forceFixException = false;
        forceCpuTimeWarning = false;
    }

    /**
     * @description Exception class for plugin-related errors.
     */
    public class PluginException extends Exception {}

    /**
     * @description Instantiates a PatternPlugin implementation by class name.
     * Validates the class exists and implements the PatternPlugin interface.
     *
     * @param className Fully qualified class name (e.g., 'MyNamespace.MyPlugin' or 'MyPlugin')
     * @return Instance of PatternPlugin
     * @throws PluginException if class not found, doesn't implement interface, or instantiation fails
     */
    public static PatternPlugin instantiate(String className) {
        // Validate input
        if (String.isBlank(className)) {
            throw new PluginException('Plugin class name cannot be blank.');
        }

        // Get Type for the class
        Type pluginType;
        try {
            if (Test.isRunningTest() && forceTypeNotFound) {
                pluginType = null;
            } else {
                pluginType = Type.forName(className);
            }
        } catch (Exception e) {
            throw new PluginException('Error resolving plugin class "' + className + '": ' + e.getMessage());
        }

        if (pluginType == null) {
            throw new PluginException('Plugin class "' + className + '" not found. Ensure the class exists and is accessible.');
        }

        // Instantiate the class
        Object instance;
        try {
            if (Test.isRunningTest() && forceInstantiationException) {
                throw new TypeException('Forced instantiation exception for testing');
            }
            instance = pluginType.newInstance();
        } catch (Exception e) {
            throw new PluginException('Error instantiating plugin class "' + className + '": ' + e.getMessage());
        }

        // Validate interface implementation
        if (Test.isRunningTest() && forceInterfaceValidationFailure) {
            throw new PluginException('Class "' + className + '" does not implement the PatternPlugin interface.');
        }

        if (!(instance instanceof PatternPlugin)) {
            throw new PluginException('Class "' + className + '" does not implement the PatternPlugin interface. ' +
                                      'Ensure your class declares: global class ' + className + ' implements PatternPlugin');
        }

        return (PatternPlugin) instance;
    }

    /**
     * @description Invokes the analyze() method on the specified plugin.
     * Catches and wraps any exceptions from plugin code.
     * Monitors CPU time consumption and logs warnings for expensive plugins.
     *
     * @param className The plugin class name
     * @param context PatternPluginContext with analysis parameters
     * @return List of record IDs matching the pattern, or empty list on error
     * @throws PluginException if plugin cannot be instantiated or analyze() fails
     */
    public static List<Id> invokeAnalyze(String className, PatternPluginContext context) {
        PatternPlugin plugin = instantiate(className);

        // Capture CPU time before plugin execution for monitoring
        Integer cpuTimeBefore = Limits.getCpuTime();

        try {
            if (Test.isRunningTest() && forceAnalyzeException) {
                throw new QueryException('Forced analyze exception for testing');
            }

            List<Id> results = plugin.analyze(context);

            // Check CPU time consumption and log warning if excessive
            Integer cpuTimeConsumed = Limits.getCpuTime() - cpuTimeBefore;
            if (cpuTimeConsumed > CPU_TIME_WARNING_THRESHOLD_MS || (Test.isRunningTest() && forceCpuTimeWarning)) {
                System.debug(LoggingLevel.WARN, 'PluginInvoker: Plugin "' + className + '" analyze() consumed ' +
                            cpuTimeConsumed + 'ms CPU time (threshold: ' + CPU_TIME_WARNING_THRESHOLD_MS + 'ms). ' +
                            'Consider optimizing this plugin to prevent governor limit issues.');
            }

            return results != null ? results : new List<Id>();
        } catch (PluginException pe) {
            throw pe; // Re-throw our own exceptions
        } catch (Exception e) {
            throw new PluginException('Error in plugin analyze() for class "' + className + '": ' +
                                      e.getMessage() + ' [' + e.getTypeName() + ']');
        }
    }

    /**
     * @description Invokes the fix() method on the specified plugin.
     * Catches and wraps any exceptions from plugin code.
     * Monitors CPU time consumption and logs warnings for expensive plugins.
     *
     * @param className The plugin class name
     * @param recordIds List of record IDs to fix
     * @param config Configuration map from Fix_Config__c
     * @return PatternPluginResult with success/failure counts and audit logs
     * @throws PluginException if plugin cannot be instantiated or fix() fails
     */
    public static PatternPluginResult invokeFix(String className, List<Id> recordIds, Map<String, Object> config) {
        PatternPlugin plugin = instantiate(className);

        // Capture CPU time before plugin execution for monitoring
        Integer cpuTimeBefore = Limits.getCpuTime();

        try {
            if (Test.isRunningTest() && forceFixException) {
                throw new DmlException('Forced fix exception for testing');
            }

            PatternPluginResult result = plugin.fix(recordIds, config);

            // Check CPU time consumption and log warning if excessive
            Integer cpuTimeConsumed = Limits.getCpuTime() - cpuTimeBefore;
            if (cpuTimeConsumed > CPU_TIME_WARNING_THRESHOLD_MS || (Test.isRunningTest() && forceCpuTimeWarning)) {
                System.debug(LoggingLevel.WARN, 'PluginInvoker: Plugin "' + className + '" fix() consumed ' +
                            cpuTimeConsumed + 'ms CPU time (threshold: ' + CPU_TIME_WARNING_THRESHOLD_MS + 'ms). ' +
                            'Consider optimizing this plugin to prevent governor limit issues.');
            }

            return result != null ? result : new PatternPluginResult();
        } catch (PluginException pe) {
            throw pe; // Re-throw our own exceptions
        } catch (Exception e) {
            throw new PluginException('Error in plugin fix() for class "' + className + '": ' +
                                      e.getMessage() + ' [' + e.getTypeName() + ']');
        }
    }

    /**
     * @description Validates that a class name is a valid plugin without executing it.
     * Useful for validation in setup UI before saving metadata.
     *
     * @param className The class name to validate
     * @return True if class exists and implements PatternPlugin
     */
    public static Boolean isValidPlugin(String className) {
        try {
            instantiate(className);
            return true;
        } catch (PluginException e) {
            return false;
        }
    }

    /**
     * @description Gets a validation error message for a class name, or null if valid.
     * Useful for setup UI error display.
     *
     * @param className The class name to validate
     * @return Error message string, or null if valid
     */
    public static String getValidationError(String className) {
        try {
            instantiate(className);
            return null;
        } catch (PluginException e) {
            return e.getMessage();
        }
    }
}
