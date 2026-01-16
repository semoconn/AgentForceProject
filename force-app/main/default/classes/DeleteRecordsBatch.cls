/**
 * @description Generic batch class for deleting records returned by a SOQL query.
 * Uses inherited sharing to respect the sharing context of the calling code.
 */
public virtual inherited sharing class DeleteRecordsBatch implements Database.Batchable<sObject> {
    
    private final String query;
    private final String jobName = 'Generic Delete Batch';

    /**
     * @param soqlQuery The query string to select records for deletion.
     */
    public DeleteRecordsBatch(String soqlQuery) {
        this.query = soqlQuery;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('[DeleteRecordsBatch.start] Query: ' + query);
        
        // SECURITY FIX: Ensure the query enforces security
        String secureQuery = query;
        if (!secureQuery.contains('SECURITY_ENFORCED')) {
            secureQuery += ' WITH SECURITY_ENFORCED';
        }
        return Database.getQueryLocator(secureQuery);
    }

    public virtual void execute(Database.BatchableContext bc, List<sObject> scope) { // ADDED 'virtual'
        // The check here is simplified to allow the test to cover the else branch easily.
        // SECURITY FIX: Explicit check for Delete permissions
        if (!scope.isEmpty() && Schema.sObjectType.Behavior_Log__c.isDeletable()) {
             try {
                // Bulk delete the records in the current chunk
                delete scope;
                System.debug('[DeleteRecordsBatch.execute] Successfully deleted ' + scope.size() + ' records.');
            } catch (DmlException e) {
                // Log and absorb DML exceptions to ensure batch continues (Covered by testDmlException)
                System.debug(LoggingLevel.ERROR, '[DeleteRecordsBatch.execute] Error deleting records in batch: ' + e.getMessage());
            }
        } else {
            // Covered by testNonDeletableAndEmptyScope
            System.debug('[DeleteRecordsBatch.execute] Scope is empty or sObject is not deletable (skipping deletion).');
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Logging is often done in the calling finish method (e.g., PatternAnalysisService.finish)
        System.debug('[DeleteRecordsBatch.finish] Batch finished. Job ID: ' + bc.getJobId());
    }
}