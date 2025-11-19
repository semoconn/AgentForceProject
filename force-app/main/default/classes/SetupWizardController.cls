/**
 * @description       : Apex controller to support the BehaviorIQ setup wizard LWC.
 * @author            : Gemini
 * @group             : BehaviorIQ
 * @last modified on  : 11-18-2025
 * @last modified by  : Gemini (Rebranding Refactor)
**/
public with sharing class SetupWizardController {

    // REBRAND UPDATE: Updated Job Name
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

        // Logic preserved: Dynamically find objects with BehaviorTriggers
        for (ApexTrigger t : [
            SELECT TableEnumOrId
            FROM ApexTrigger 
            WHERE Name LIKE '%BehaviorTrigger' AND TableEnumOrId != NULL
            WITH SECURITY_ENFORCED
        ]) {
            supportedObjects.add(t.TableEnumOrId);
        }

        if (supportedObjects.isEmpty()) {
            supportedObjects.addAll(new List<String>{'Account', 'Contact', 'Lead', 'Opportunity', 'Case'});
        }

        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        for (String objApiName : supportedObjects) {
            if (schemaMap.containsKey(objApiName)) {
                Schema.DescribeSObjectResult describeResult = schemaMap.get(objApiName).getDescribe();
                objects.add(new TrackableObject(describeResult.getLabel(), describeResult.getName()));
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

        List<CronTrigger> existingJobs = [
            SELECT Id 
            FROM CronTrigger 
            WHERE CronJobDetail.Name = :SCHEDULE_JOB_NAME
        ];
        if (!existingJobs.isEmpty()) {
            throw new AuraHandledException('The analysis job is already scheduled.');
        }

        try {
            PatternAnalysisService service = new PatternAnalysisService();
            String cronExpression = '0 0 2 * * ?';
            return System.schedule(SCHEDULE_JOB_NAME, cronExpression, service);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to schedule the analysis job: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveMonitoringSettings(List<String> monitoredObjects) {
        try {
            // REFACTOR: Switched from Custom Setting (.getOrgDefaults) to Custom Object (SOQL)
            BehaviorIQ_Configuration__c settings;
            
            List<BehaviorIQ_Configuration__c> configs = [
                SELECT Id, Monitored_Objects__c 
                FROM BehaviorIQ_Configuration__c 
                LIMIT 1
            ];

            if (configs.isEmpty()) {
                // Create new if none exists
                settings = new BehaviorIQ_Configuration__c(Name = 'Default Configuration');
            } else {
                settings = configs[0];
            }

            settings.Monitored_Objects__c = String.join(monitoredObjects, ',');
            upsert settings;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Checks if the BehaviorIQ initial setup has been completed.
     * @return      Boolean true if the configuration record exists, false otherwise.
    **/
    @AuraEnabled(cacheable=true)
    public static Boolean isSetupComplete() {
        // REFACTOR: Switched from Custom Setting (.getOrgDefaults) to Custom Object (SOQL)
        List<BehaviorIQ_Configuration__c> configs = [
            SELECT Monitored_Objects__c 
            FROM BehaviorIQ_Configuration__c 
            LIMIT 1
        ];
        
        if (configs.isEmpty()) {
            return false;
        }
        
        return String.isNotBlank(configs[0].Monitored_Objects__c);
    }
}