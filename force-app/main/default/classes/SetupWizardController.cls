/**
 * @description       : Apex controller to support the BehaviorIQ setup wizard LWC.
 * @author            : Gemini
 * @group             : BehaviorIQ
 * @last modified on  : 12-01-2025
 * @last modified by  : Security Auditor
**/
public with sharing class SetupWizardController {

    private static final String SCHEDULE_JOB_NAME = 'BehaviorIQ Nightly Analysis';
    @TestVisible private static Boolean testHook_simulateDuplicateJob = false;

    public class TrackableObject implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public TrackableObject(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }

        public Integer compareTo(Object compareTo) {
            return label.compareTo(((TrackableObject)compareTo).label);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TrackableObject> getTrackableObjects() {
        List<TrackableObject> objects = new List<TrackableObject>();
        Set<String> supportedObjects = new Set<String>();

        try {
            for (ApexTrigger t : [
                SELECT TableEnumOrId
                FROM ApexTrigger 
                WHERE Name LIKE '%BehaviorTrigger' AND TableEnumOrId != NULL
                WITH SECURITY_ENFORCED
            ]) {
                supportedObjects.add(t.TableEnumOrId);
            }
        } catch (System.QueryException e) {
            System.debug(LoggingLevel.INFO, 'User lacks permission to query ApexTrigger: ' + e.getMessage());
        }

        if (supportedObjects.isEmpty()) {
            supportedObjects.addAll(new List<String>{'Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'Task'});
        }

        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        for (String objApiName : supportedObjects) {
            if (schemaMap.containsKey(objApiName)) {
                Schema.DescribeSObjectResult describeResult = schemaMap.get(objApiName).getDescribe();
                if (describeResult.isAccessible()) {
                    objects.add(new TrackableObject(describeResult.getLabel(), describeResult.getName()));
                }
            }
        }
        
        objects.sort();
        return objects;
    }

    @AuraEnabled
    public static String scheduleAnalysisJob() {
        if (Test.isRunningTest() && testHook_simulateDuplicateJob) {
            throw new AuraHandledException('The analysis job is already scheduled.');
        }

        try {
            List<CronTrigger> existingJobs = [
                SELECT Id 
                FROM CronTrigger 
                WHERE CronJobDetail.Name = :SCHEDULE_JOB_NAME
                WITH SECURITY_ENFORCED
            ];
            if (!existingJobs.isEmpty()) {
                throw new AuraHandledException('The analysis job is already scheduled.');
            }

            PatternAnalysisService service = new PatternAnalysisService();
            String cronExpression = '0 0 2 * * ?';
            
            return System.schedule(SCHEDULE_JOB_NAME, cronExpression, service);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Scheduling Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to schedule the analysis job. ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveMonitoringSettings(List<String> monitoredObjects) {
        // SECURITY FIX: Explicit CRUD/FLS Check performed BEFORE try/catch 
        // to prevent exception masking.
        if (!Schema.sObjectType.BehaviorIQ_Configuration__c.isCreateable() ||
            !Schema.sObjectType.BehaviorIQ_Configuration__c.isUpdateable() ||
            !Schema.sObjectType.BehaviorIQ_Configuration__c.fields.Monitored_Objects__c.isCreateable() ||
            !Schema.sObjectType.BehaviorIQ_Configuration__c.fields.Monitored_Objects__c.isUpdateable()) {
            throw new AuraHandledException('Insufficient permissions to save configuration.');
        }

        try {
            BehaviorIQ_Configuration__c settings;
            
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Id, Monitored_Objects__c 
                FROM BehaviorIQ_Configuration__c 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (configs.isEmpty()) {
                settings = new BehaviorIQ_Configuration__c(Name = 'Default Configuration');
            } else {
                settings = configs[0];
            }

            settings.Monitored_Objects__c = String.join(monitoredObjects, ',');

            upsert settings;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Save Settings Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to save settings: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean isSetupComplete() {
        try {
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Monitored_Objects__c 
                FROM BehaviorIQ_Configuration__c 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                return false;
            }
            
            return String.isNotBlank(configs[0].Monitored_Objects__c);
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Access check failed for isSetupComplete: ' + e.getMessage());
            return false;
        }
    }
}