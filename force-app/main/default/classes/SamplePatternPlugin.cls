/**
 * @description Sample pattern plugin for E2E testing TC-5.1.
 * Detects Accounts with Rating = 'Cold' and creates follow-up tasks.
 */
global class SamplePatternPlugin implements PatternPlugin {

    /**
     * @description Finds records matching custom pattern logic.
     * Returns Accounts with Rating = 'Cold'.
     */
    global List<Id> analyze(PatternPluginContext context) {
        List<Account> coldAccounts = [
            SELECT Id
            FROM Account
            WHERE Rating = 'Cold'
            WITH USER_MODE
            LIMIT 100
        ];

        List<Id> matchingIds = new List<Id>();
        for (Account acc : coldAccounts) {
            matchingIds.add(acc.Id);
        }
        return matchingIds;
    }

    /**
     * @description Applies remediation to identified records.
     * Creates a follow-up task for each account.
     */
    global PatternPluginResult fix(List<Id> recordIds, Map<String, Object> config) {
        PatternPluginResult result = new PatternPluginResult();
        String ruleName = config != null ? (String) config.get('ruleDeveloperName') : 'Sample_Plugin_Pattern';

        List<Task> tasksToInsert = new List<Task>();

        for (Id recordId : recordIds) {
            tasksToInsert.add(new Task(
                WhatId = recordId,
                Subject = 'Follow up on cold account',
                ActivityDate = Date.today().addDays(7),
                Priority = 'Normal',
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
