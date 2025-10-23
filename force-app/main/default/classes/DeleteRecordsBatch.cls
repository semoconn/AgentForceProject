/**
 * @description Batch class to delete records based on a SOQL query.
 */
public class DeleteRecordsBatch implements Database.Batchable<sObject>, Database.Stateful {
    private String query;
    private Integer recordsDeleted = 0;
    private String firstError = null;

    public DeleteRecordsBatch(String q) {
        query = q;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<sObject> scope) {
        try {
            if(!scope.isEmpty()){
                 Database.DeleteResult[] results = Database.delete(scope, false); // Allow partial success
                 for(Database.DeleteResult dr : results){
                     if(dr.isSuccess()){
                         recordsDeleted++;
                     } else if (firstError == null) {
                         // Capture the first error encountered
                         Database.Error err = dr.getErrors()[0];
                         firstError = 'Failed to delete record ID ' + dr.getId() + '. Status code: ' + err.getStatusCode() + '. Message: ' + err.getMessage();
                     }
                 }
            }
        } catch (Exception e) {
             if(firstError == null){
                 firstError = 'Exception during delete execute: ' + e.getMessage();
             }
             System.debug(LoggingLevel.ERROR, 'Exception in DeleteRecordsBatch execute: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
         System.debug('DeleteRecordsBatch finished. Total records deleted successfully: ' + recordsDeleted);
         if(firstError != null){
              System.debug(LoggingLevel.ERROR, 'DeleteRecordsBatch encountered errors. First error: ' + firstError);
         }
    }
}