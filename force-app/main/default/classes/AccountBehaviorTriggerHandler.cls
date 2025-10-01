/**
 * Handler class for Account behavior tracking triggers
 * Follows trigger handler pattern for better maintainability and testing
 */
public with sharing class AccountBehaviorTriggerHandler {
    
    // Prevent recursion
    private static Boolean hasRun = false;
    
    /**
     * Main entry point for trigger execution
     */
    public static void run(TriggerOperation triggerEvent, List<Account> newRecords, List<Account> oldRecords, Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        
        // Prevent recursive execution
        if (hasRun) {
            return;
        }
        
        switch on triggerEvent {
            when BEFORE_INSERT {
                handleBeforeInsert(newRecords);
            }
            when AFTER_INSERT {
                handleAfterInsert(newRecords);
            }
            when BEFORE_UPDATE {
                handleBeforeUpdate(newRecords, oldRecords, newMap, oldMap);
            }
            when AFTER_UPDATE {
                handleAfterUpdate(newRecords, oldRecords, newMap, oldMap);
            }
            when BEFORE_DELETE {
                handleBeforeDelete(oldRecords);
            }
            when AFTER_DELETE {
                handleAfterDelete(oldRecords);
            }
            when AFTER_UNDELETE {
                handleAfterUndelete(newRecords);
            }
        }
    }
    
    /**
     * Handle before insert events
     */
    private static void handleBeforeInsert(List<Account> newAccounts) {
        System.debug('AccountBehaviorTriggerHandler: Before Insert executed for ' + newAccounts.size() + ' records');
        
        // Log record creation attempt - Note: Id is null in before insert
        for (Account acc : newAccounts) {
            logBehaviorEvent('Record_Creation_Started', 'Account', null, new Map<String, Object>{
                'accountName' => acc.Name,
                'createdBy' => UserInfo.getUserId()
            });
        }
    }
    
    /**
     * Handle after insert events
     */
    private static void handleAfterInsert(List<Account> newAccounts) {
        System.debug('AccountBehaviorTriggerHandler: After Insert executed for ' + newAccounts.size() + ' records');
        
        hasRun = true;
        
        try {
            // Log successful record creation
            for (Account acc : newAccounts) {
                logBehaviorEvent('Record_Created', 'Account', acc.Id, new Map<String, Object>{
                    'accountName' => acc.Name,
                    'industry' => acc.Industry,
                    'createdDate' => acc.CreatedDate,
                    'createdBy' => acc.CreatedById
                });
            }
            
            // Trigger pattern analysis for new account creation trends
            analyzeCreationPatterns(newAccounts);
            
        } finally {
            hasRun = false;
        }
    }
    
    /**
     * Handle before update events
     */
    private static void handleBeforeUpdate(List<Account> newAccounts, List<Account> oldAccounts, Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        System.debug('AccountBehaviorTriggerHandler: Before Update executed for ' + newAccounts.size() + ' records');
        
        // Track what fields are being changed
        for (Account newAcc : newAccounts) {
            Account oldAcc = oldMap.get(newAcc.Id);
            Map<String, Object> changedFields = getChangedFields(newAcc, oldAcc);
            
            if (!changedFields.isEmpty()) {
                logBehaviorEvent('Record_Update_Started', 'Account', newAcc.Id, new Map<String, Object>{
                    'changedFields' => changedFields,
                    'modifiedBy' => UserInfo.getUserId()
                });
            }
        }
    }
    
    /**
     * Handle after update events - This is where most of your behavior tracking will happen
     */
    private static void handleAfterUpdate(List<Account> newAccounts, List<Account> oldAccounts, Map<Id, Account> newMap, Map<Id, Account> oldMap) {
        System.debug('AccountBehaviorTriggerHandler: After Update executed for ' + newAccounts.size() + ' records');
        
        hasRun = true;
        
        try {
            for (Account newAcc : newAccounts) {
                Account oldAcc = oldMap.get(newAcc.Id);
                
                // Log the update event with detailed change information
                Map<String, Object> changeDetails = getDetailedChangeInfo(newAcc, oldAcc);
                
                logBehaviorEvent('Record_Updated', 'Account', newAcc.Id, changeDetails);
                
                // Check for specific business logic patterns
                checkBusinessPatterns(newAcc, oldAcc);
            }
            
            // Analyze update patterns across all records
            analyzeUpdatePatterns(newAccounts, oldAccounts);
            
        } finally {
            hasRun = false;
        }
    }
    
    /**
     * Handle before delete events
     */
    private static void handleBeforeDelete(List<Account> oldAccounts) {
        System.debug('AccountBehaviorTriggerHandler: Before Delete executed for ' + oldAccounts.size() + ' records');
        
        for (Account acc : oldAccounts) {
            logBehaviorEvent('Record_Deletion_Started', 'Account', acc.Id, new Map<String, Object>{
                'accountName' => acc.Name,
                'lastModifiedDate' => acc.LastModifiedDate,
                'deletedBy' => UserInfo.getUserId()
            });
        }
    }
    
    /**
     * Handle after delete events
     */
    private static void handleAfterDelete(List<Account> oldAccounts) {
        System.debug('AccountBehaviorTriggerHandler: After Delete executed for ' + oldAccounts.size() + ' records');
        
        for (Account acc : oldAccounts) {
            logBehaviorEvent('Record_Deleted', 'Account', acc.Id, new Map<String, Object>{
                'accountName' => acc.Name,
                'accountAge' => Date.today().daysBetween(acc.CreatedDate.date()),
                'deletedBy' => UserInfo.getUserId()
            });
        }
    }
    
    /**
     * Handle after undelete events
     */
    private static void handleAfterUndelete(List<Account> newAccounts) {
        System.debug('AccountBehaviorTriggerHandler: After Undelete executed for ' + newAccounts.size() + ' records');
        
        for (Account acc : newAccounts) {
            logBehaviorEvent('Record_Undeleted', 'Account', acc.Id, new Map<String, Object>{
                'accountName' => acc.Name,
                'undeletedBy' => UserInfo.getUserId()
            });
        }
    }
    
    /**
     * Helper method to get changed fields between old and new records
     */
    private static Map<String, Object> getChangedFields(Account newRecord, Account oldRecord) {
        Map<String, Object> changes = new Map<String, Object>();
        
        // Define fields to track - you can expand this list
        List<String> fieldsToTrack = new List<String>{
            'Name', 'Industry', 'Type', 'Phone', 'Website', 
            'BillingStreet', 'BillingCity', 'BillingState', 'BillingCountry',
            'AnnualRevenue', 'NumberOfEmployees', 'Description'
        };
        
        for (String fieldName : fieldsToTrack) {
            Object newValue = newRecord.get(fieldName);
            Object oldValue = oldRecord.get(fieldName);
            
            if (newValue != oldValue) {
                changes.put(fieldName, new Map<String, Object>{
                    'oldValue' => oldValue,
                    'newValue' => newValue
                });
            }
        }
        
        return changes;
    }
    
    /**
     * Get detailed change information for behavior analysis
     */
    private static Map<String, Object> getDetailedChangeInfo(Account newRecord, Account oldRecord) {
        Map<String, Object> details = new Map<String, Object>();
        Map<String, Object> changedFields = getChangedFields(newRecord, oldRecord);
        
        details.put('changedFields', changedFields);
        details.put('changeCount', changedFields.size());
        details.put('modifiedBy', newRecord.LastModifiedById);
        details.put('modifiedDate', newRecord.LastModifiedDate);
        details.put('accountName', newRecord.Name);
        
        // Calculate time since last modification
        if (oldRecord.LastModifiedDate != null) {
            Long timeDiff = newRecord.LastModifiedDate.getTime() - oldRecord.LastModifiedDate.getTime();
            details.put('timeSinceLastUpdate', timeDiff / (1000 * 60)); // minutes
        }
        
        return details;
    }
    
    /**
     * Check for specific business patterns that might indicate pain points
     */
    private static void checkBusinessPatterns(Account newRecord, Account oldRecord) {
        
        // Pattern 1: Frequent name changes (could indicate confusion)
        if (newRecord.Name != oldRecord.Name) {
            // Check if this account has had multiple name changes recently
            checkFrequentNameChanges(newRecord.Id);
        }
        
        // Pattern 2: Industry changes (could indicate classification issues)
        if (newRecord.Industry != oldRecord.Industry) {
            logBehaviorEvent('Industry_Changed', 'Account', newRecord.Id, new Map<String, Object>{
                'oldIndustry' => oldRecord.Industry,
                'newIndustry' => newRecord.Industry,
                'possibleClassificationIssue' => true
            });
        }
        
        // Pattern 3: Multiple field changes in single update (bulk correction?)
        Map<String, Object> changes = getChangedFields(newRecord, oldRecord);
        if (changes.size() >= 5) {
            logBehaviorEvent('Bulk_Field_Update', 'Account', newRecord.Id, new Map<String, Object>{
                'fieldCount' => changes.size(),
                'possibleDataCorrection' => true,
                'changes' => changes
            });
        }
    }
    
    /**
     * Check for frequent name changes pattern
     */
    private static void checkFrequentNameChanges(Id accountId) {
        // This would typically query your workflow log to see recent name changes
        // For now, we'll just log the pattern
        logBehaviorEvent('Frequent_Name_Changes_Pattern', 'Account', accountId, new Map<String, Object>{
            'patternType' => 'Data_Quality_Issue',
            'recommendation' => 'Consider adding validation rules or user training'
        });
    }
    
    /**
     * Analyze creation patterns across multiple records
     */
    private static void analyzeCreationPatterns(List<Account> newAccounts) {
        if (newAccounts.size() > 5) {
            // Bulk creation detected
            logBehaviorEvent('Bulk_Creation_Detected', 'Account', null, new Map<String, Object>{
                'recordCount' => newAccounts.size(),
                'createdBy' => UserInfo.getUserId(),
                'possibleDataImport' => true
            });
        }
    }
    
    /**
     * Analyze update patterns across multiple records
     */
    private static void analyzeUpdatePatterns(List<Account> newAccounts, List<Account> oldAccounts) {
        if (newAccounts.size() > 10) {
            // Mass update detected
            logBehaviorEvent('Mass_Update_Detected', 'Account', null, new Map<String, Object>{
                'recordCount' => newAccounts.size(),
                'modifiedBy' => UserInfo.getUserId(),
                'possibleBulkOperation' => true
            });
        }
    }
    
    /**
     * Central method to log behavior events
     * This calls your existing WorkflowSuggestionController.logWorkflowEvent method
     */
    private static void logBehaviorEvent(String actionName, String objectType, Id recordId, Map<String, Object> additionalData) {
        try {
            String behaviorData = JSON.serialize(new Map<String, Object>{
                'triggerContext' => true,
                'timestamp' => DateTime.now(),
                'userId' => UserInfo.getUserId(),
                'username' => UserInfo.getUserName(),
                'additionalData' => additionalData
            });
            
            // Call your existing logging method
            WorkflowSuggestionController.logWorkflowEvent(
                String.valueOf(recordId), 
                objectType, 
                actionName, 
                behaviorData
            );
            
        } catch (Exception e) {
            System.debug('Error logging behavior event: ' + e.getMessage());
            // Don't let logging errors break the main business logic
        }
    }
}