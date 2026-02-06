/**
 * @description Generic batch class for deleting records older than a cutoff date.
 * Uses Schema tokens for injection-proof query construction.
 * Uses inherited sharing to respect the sharing context of the calling code.
 *
 * Security:
 * - Object/field names derived from Schema.SObjectType and Schema.SObjectField tokens (no string injection)
 * - Queries use WITH SECURITY_ENFORCED for FLS enforcement
 * - Object-level isDeletable() check before DELETE DML
 */
public virtual inherited sharing class DeleteRecordsBatch implements Database.Batchable<sObject> {

    private final String query;

    /**
     * @description Constructs a deletion batch for records older than a Date cutoff.
     * Uses Schema tokens so object/field names cannot be injected.
     * @param sObjectType The SObject type token (e.g., Behavior_Log_Summary__c.SObjectType)
     * @param dateField The Date field token to filter on (e.g., Behavior_Log_Summary__c.Log_Date__c)
     * @param cutoffDate Records with this field value before this date will be deleted
     */
    public DeleteRecordsBatch(Schema.SObjectType sObjectType, Schema.SObjectField dateField, Date cutoffDate) {
        String objectName = sObjectType.getDescribe().getName();
        String fieldName = dateField.getDescribe().getName();
        // String.valueOf(Date) produces SOQL-safe YYYY-MM-DD format
        this.query = 'SELECT Id FROM ' + objectName +
                     ' WHERE ' + fieldName + ' < ' + String.valueOf(cutoffDate) +
                     ' WITH SECURITY_ENFORCED';
    }

    /**
     * @description Constructs a deletion batch for records older than a DateTime cutoff.
     * Uses Schema tokens so object/field names cannot be injected.
     * @param sObjectType The SObject type token (e.g., Behavior_Log__c.SObjectType)
     * @param dateTimeField The DateTime field token to filter on (e.g., Schema.SObjectType.Behavior_Log__c.fields.CreatedDate)
     * @param cutoffDateTime Records with this field value before this datetime will be deleted
     */
    public DeleteRecordsBatch(Schema.SObjectType sObjectType, Schema.SObjectField dateTimeField, DateTime cutoffDateTime) {
        String objectName = sObjectType.getDescribe().getName();
        String fieldName = dateTimeField.getDescribe().getName();
        String isoDate = cutoffDateTime.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        this.query = 'SELECT Id FROM ' + objectName +
                     ' WHERE ' + fieldName + ' < ' + isoDate +
                     ' WITH SECURITY_ENFORCED';
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('[DeleteRecordsBatch.start] Query: ' + query);
        return Database.getQueryLocator(query);
    }

    public virtual void execute(Database.BatchableContext bc, List<sObject> scope) {
        // Object-level permission check: isDeletable() is the correct enforcement for DELETE.
        // Note: Security.stripInaccessible does not support AccessType.DELETABLE —
        // object-level isDeletable() is the Salesforce-prescribed check for delete DML.
        if (!scope.isEmpty() && scope[0].getSObjectType().getDescribe().isDeletable()) {
             try {
                delete scope;
                System.debug('[DeleteRecordsBatch.execute] Successfully deleted ' + scope.size() + ' records.');
            } catch (DmlException e) {
                System.debug(LoggingLevel.ERROR, '[DeleteRecordsBatch.execute] Error deleting records in batch: ' + e.getMessage());
            }
        } else {
            System.debug('[DeleteRecordsBatch.execute] Scope is empty or sObject is not deletable (skipping deletion).');
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('[DeleteRecordsBatch.finish] Batch finished. Job ID: ' + bc.getJobId());
    }
}
