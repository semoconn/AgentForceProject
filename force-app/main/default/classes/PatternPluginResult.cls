/**
 * @description Result object returned from PatternPlugin.fix() method.
 * Encapsulates fix operation outcomes including success/failure counts,
 * error messages, and audit log records for persistence.
 *
 * Plugins should populate this result to enable proper audit trail
 * and user feedback in the BehaviorIQ UI.
 */
global class PatternPluginResult {

    /**
     * @description Number of records successfully remediated.
     */
    @AuraEnabled
    global Integer successCount { get; set; }

    /**
     * @description Number of records that failed remediation.
     */
    @AuraEnabled
    global Integer failureCount { get; set; }

    /**
     * @description List of error messages for failed records.
     * Each message should include the record ID and failure reason.
     */
    @AuraEnabled
    global List<String> errorMessages { get; set; }

    /**
     * @description Audit log records to be inserted by PatternFixService.
     * Plugins should create Remediation_Log__c records for each action taken.
     * These will be bulk inserted after the fix operation completes.
     */
    @AuraEnabled
    global List<Remediation_Log__c> auditLogs { get; set; }

    /**
     * @description Default constructor initializing all fields.
     */
    global PatternPluginResult() {
        this.successCount = 0;
        this.failureCount = 0;
        this.errorMessages = new List<String>();
        this.auditLogs = new List<Remediation_Log__c>();
    }

    /**
     * @description Helper method to add a successful operation log.
     * @param recordId The ID of the affected record
     * @param actionTaken Description of the action (e.g., 'Field_Update', 'Task_Creation')
     * @param originalValue The original value before the fix (can be null)
     * @param newValue The new value after the fix (can be null)
     * @param ruleDeveloperName The DeveloperName of the rule for traceability
     */
    global void addSuccessLog(Id recordId, String actionTaken, String originalValue,
                               String newValue, String ruleDeveloperName) {
        this.successCount++;
        this.auditLogs.add(createLog(recordId, actionTaken, originalValue, newValue,
                                      'Success', null, ruleDeveloperName));
    }

    /**
     * @description Helper method to add a failed operation log.
     * @param recordId The ID of the affected record
     * @param actionTaken Description of the attempted action
     * @param errorMessage The error message describing the failure
     * @param ruleDeveloperName The DeveloperName of the rule for traceability
     */
    global void addFailureLog(Id recordId, String actionTaken, String errorMessage,
                               String ruleDeveloperName) {
        this.failureCount++;
        this.errorMessages.add(recordId + ': ' + errorMessage);
        this.auditLogs.add(createLog(recordId, actionTaken, null, null,
                                      'Failed', errorMessage, ruleDeveloperName));
    }

    /**
     * @description Helper method to add a log with full snapshot for undo capability.
     * @param recordId The ID of the affected record
     * @param actionTaken Description of the action
     * @param originalValue The original value before the fix
     * @param newValue The new value after the fix
     * @param snapshotJson Full JSON snapshot of the record before modification
     * @param ruleDeveloperName The DeveloperName of the rule for traceability
     */
    global void addSuccessLogWithSnapshot(Id recordId, String actionTaken, String originalValue,
                                           String newValue, String snapshotJson, String ruleDeveloperName) {
        this.successCount++;
        Remediation_Log__c log = createLog(recordId, actionTaken, originalValue, newValue,
                                            'Success', null, ruleDeveloperName);
        log.Snapshot_JSON__c = truncateValue(snapshotJson, 131072); // Long Text Area limit
        this.auditLogs.add(log);
    }

    /**
     * @description Creates a Remediation_Log__c record with standard fields populated.
     */
    private Remediation_Log__c createLog(Id recordId, String actionTaken, String originalValue,
                                          String newValue, String status, String errorMessage,
                                          String ruleDeveloperName) {
        return new Remediation_Log__c(
            Affected_Record_ID__c = String.valueOf(recordId),
            Action_Taken__c = actionTaken,
            Original_Value__c = truncateValue(originalValue, 255),
            New_Value__c = truncateValue(newValue, 255),
            Status__c = status,
            Error_Message__c = truncateValue(errorMessage, 255),
            Rule_Developer_Name__c = ruleDeveloperName,
            Executed_By__c = UserInfo.getUserId()
            // Note: CreatedDate is auto-populated by Salesforce
        );
    }

    /**
     * @description Safely truncates a string to the specified length.
     */
    private String truncateValue(String value, Integer maxLength) {
        if (value == null) return null;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }

    /**
     * @description Calculates the total number of records processed.
     * @return Sum of successCount and failureCount
     */
    global Integer getTotalProcessed() {
        return this.successCount + this.failureCount;
    }

    /**
     * @description Checks if all records were processed successfully.
     * @return True if failureCount is 0 and at least one record was processed
     */
    global Boolean isFullSuccess() {
        return this.failureCount == 0 && this.successCount > 0;
    }

    /**
     * @description Checks if any records failed.
     * @return True if failureCount is greater than 0
     */
    global Boolean hasFailures() {
        return this.failureCount > 0;
    }
}
