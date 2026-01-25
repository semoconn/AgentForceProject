/**
 * @description Apex plugin that detects Leads with missing or invalid email addresses.
 * Target Object: Lead
 */
global class LeadDataQualityPlugin implements PatternPlugin {

    /**
     * @description Finds Leads with blank email addresses.
     */
    global List<Id> analyze(PatternPluginContext context) {
        List<Lead> leadsWithNoEmail = [
            SELECT Id
            FROM Lead
            WHERE Email = null
            AND IsConverted = false
            WITH USER_MODE
            LIMIT 100
        ];

        List<Id> matchingIds = new List<Id>();
        for (Lead ld : leadsWithNoEmail) {
            matchingIds.add(ld.Id);
        }
        return matchingIds;
    }

    /**
     * @description Creates a task to update lead contact info.
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        PatternPluginResult result = new PatternPluginResult();
        String ruleName = config != null ? (String) config.get('ruleDeveloperName') : 'Lead_Data_Quality';

        List<Task> tasksToInsert = new List<Task>();

        for (Id recordId : recordIds) {
            tasksToInsert.add(new Task(
                WhoId = recordId,
                Subject = 'Update Lead Email Address',
                Description = 'This lead is missing an email address. Please update their contact information.',
                ActivityDate = Date.today().addDays(3),
                Priority = 'High',
                Status = 'Not Started'
            ));
        }

        try {
            insert tasksToInsert;
            for (Id recordId : recordIds) {
                result.addSuccessLog(recordId, 'Task_Creation', null, 'Task created', ruleName);
            }
        } catch (Exception e) {
            for (Id recordId : recordIds) {
                result.addFailureLog(recordId, 'Task_Creation', e.getMessage(), ruleName);
            }
        }

        return result;
    }
}
