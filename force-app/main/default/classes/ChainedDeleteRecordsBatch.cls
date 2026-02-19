/**
 * @description Extension of DeleteRecordsBatch that chains the next batch job
 * upon completion. Prevents hitting the 5-concurrent-batch governor limit by
 * running retention cleanup jobs sequentially instead of in parallel.
 *
 * Usage: Construct with the same arguments as DeleteRecordsBatch, then call
 * setNextBatch() to specify what runs after this batch completes.
 *
 * Security:
 * - Inherits all security from DeleteRecordsBatch (Schema tokens, SECURITY_ENFORCED, isDeletable)
 * - Batch chaining uses try/catch to prevent chain failures from propagating
 */
public inherited sharing class ChainedDeleteRecordsBatch extends DeleteRecordsBatch {

    private DeleteRecordsBatch nextBatch;
    private Integer nextBatchSize;

    /**
     * @description Constructs a chained deletion batch using a Date cutoff.
     * @param sObjectType The SObject type token
     * @param dateField The Date field token to filter on
     * @param cutoffDate Records with this field value before this date will be deleted
     */
    public ChainedDeleteRecordsBatch(Schema.SObjectType sObjectType, Schema.SObjectField dateField, Date cutoffDate) {
        super(sObjectType, dateField, cutoffDate);
    }

    /**
     * @description Constructs a chained deletion batch using a DateTime cutoff.
     * @param sObjectType The SObject type token
     * @param dateTimeField The DateTime field token to filter on
     * @param cutoffDateTime Records with this field value before this datetime will be deleted
     */
    public ChainedDeleteRecordsBatch(Schema.SObjectType sObjectType, Schema.SObjectField dateTimeField, DateTime cutoffDateTime) {
        super(sObjectType, dateTimeField, cutoffDateTime);
    }

    /**
     * @description Sets the next batch to execute when this one completes.
     * @param next The next DeleteRecordsBatch (or ChainedDeleteRecordsBatch) to run
     * @param batchSize The batch size for the next job
     * @return This instance for fluent chaining
     */
    public ChainedDeleteRecordsBatch setNextBatch(DeleteRecordsBatch next, Integer batchSize) {
        this.nextBatch = next;
        this.nextBatchSize = batchSize;
        return this;
    }

    /**
     * @description Overrides finish to chain the next batch job after this one completes.
     * Wraps Database.executeBatch in try/catch so chain failures don't propagate.
     * Logs failures to System_Health_Log__c for admin visibility.
     */
    public override void finish(Database.BatchableContext bc) {
        super.finish(bc);
        if (nextBatch != null) {
            try {
                Database.executeBatch(nextBatch, nextBatchSize);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    '[ChainedDeleteRecordsBatch.finish] Failed to chain next batch: ' + e.getMessage());
                logChainFailure(bc.getJobId(), e.getMessage());
            }
        }
    }

    /**
     * @description Persists batch chain failure to System_Health_Log__c so admins
     * can see it in the UI rather than only in debug logs.
     */
    private void logChainFailure(Id jobId, String errorMessage) {
        if (!Schema.sObjectType.System_Health_Log__c.isCreateable()) {
            return;
        }
        try {
            System_Health_Log__c log = new System_Health_Log__c(
                Job_Name__c = 'ChainedDeleteRecordsBatch',
                Job_ID__c = String.valueOf(jobId),
                Status__c = 'Failed',
                Error_Count__c = 1,
                Error_Details__c = 'Batch chain failed: ' + (errorMessage != null ? errorMessage.left(255) : 'Unknown error')
            );
            insert log;
        } catch (Exception ex) {
            // Last-resort fallback: if health log insert also fails, debug only
            System.debug(LoggingLevel.ERROR,
                '[ChainedDeleteRecordsBatch] Could not log chain failure: ' + ex.getMessage());
        }
    }
}
