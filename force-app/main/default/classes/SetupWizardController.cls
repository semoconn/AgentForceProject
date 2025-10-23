/**
 * @description       : Apex controller to support the OrgPulse setup wizard LWC.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-15-2025
 * @last modified by  : Gemini (Final Sprint 4 Feature)
**/
public with sharing class SetupWizardController {

    private static final String SCHEDULE_JOB_NAME = 'OrgPulse Nightly Analysis';
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
            OrgPulse_Configuration__c settings = OrgPulse_Configuration__c.getOrgDefaults();
            if (settings == null) {
                settings = new OrgPulse_Configuration__c();
            }
            settings.Monitored_Objects__c = String.join(monitoredObjects, ',');
            upsert settings;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save settings: ' + e.getMessage());
        }
    }
    
    /**
     * @description Checks if the OrgPulse initial setup has been completed.
     * @return      Boolean true if the configuration setting exists, false otherwise.
    **/
    @AuraEnabled(cacheable=true)
    public static Boolean isSetupComplete() {
        // The existence of the org-level custom setting is our flag for setup completion.
        OrgPulse_Configuration__c settings = OrgPulse_Configuration__c.getOrgDefaults();
        return (settings != null && String.isNotBlank(settings.Monitored_Objects__c));
    }
}