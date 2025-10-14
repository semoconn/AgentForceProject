/**
 * @description       : Apex controller to support the OrgPulse setup wizard LWC.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-13-2025
 * @last modified by  : Gemini
**/
public with sharing class SetupWizardController {

    private static final String SCHEDULE_JOB_NAME = 'OrgPulse Nightly Analysis';

    /**
     * @description Wrapper class to return SObject information to the LWC.
     */
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

    /**
     * @description Returns a list of SObjects that have triggers and can be monitored by OrgPulse.
    **/
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

    /**
     * @description Schedules the PatternAnalysisService to run every night at 2 AM.
     * @return      : String The Job ID of the scheduled job.
    **/
    @AuraEnabled
    public static String scheduleAnalysisJob() {
        // Prevent duplicate jobs from being scheduled
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
            // Schedule to run every day at 2 AM
            String chronExpression = '0 0 2 * * ?';
            return System.schedule(SCHEDULE_JOB_NAME, chronExpression, service);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to schedule the analysis job: ' + e.getMessage());
        }
    }

    /**
     * @description Saves the list of monitored objects to a protected custom setting.
     * @param monitoredObjects : A list of SObject API names to monitor.
    **/
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
}

