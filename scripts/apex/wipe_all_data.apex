/**
 * Wipe All BehaviorIQ and Test Data
 * ==================================
 * This script deletes all test data and resets BehaviorIQ to a clean state.
 */

System.debug('=== WIPING ALL DATA ===');

// Delete BehaviorIQ custom object records first
System.debug('--- Deleting BehaviorIQ Records ---');

// Identified Pain Points
List<Identified_Pain_Point__c> painPoints = [SELECT Id FROM Identified_Pain_Point__c LIMIT 10000];
if (!painPoints.isEmpty()) {
    delete painPoints;
    System.debug('Deleted ' + painPoints.size() + ' Identified_Pain_Point__c records');
}

// Remediation Logs
List<Remediation_Log__c> remLogs = [SELECT Id FROM Remediation_Log__c LIMIT 10000];
if (!remLogs.isEmpty()) {
    delete remLogs;
    System.debug('Deleted ' + remLogs.size() + ' Remediation_Log__c records');
}

// Behavior Logs
List<Behavior_Log__c> behaviorLogs = [SELECT Id FROM Behavior_Log__c LIMIT 10000];
if (!behaviorLogs.isEmpty()) {
    delete behaviorLogs;
    System.debug('Deleted ' + behaviorLogs.size() + ' Behavior_Log__c records');
}

// Behavior Snapshots
List<Behavior_Snapshot__c> snapshots = [SELECT Id FROM Behavior_Snapshot__c LIMIT 10000];
if (!snapshots.isEmpty()) {
    delete snapshots;
    System.debug('Deleted ' + snapshots.size() + ' Behavior_Snapshot__c records');
}

// Suggestion Dismissals
List<Suggestion_Dismissal__c> dismissals = [SELECT Id FROM Suggestion_Dismissal__c LIMIT 10000];
if (!dismissals.isEmpty()) {
    delete dismissals;
    System.debug('Deleted ' + dismissals.size() + ' Suggestion_Dismissal__c records');
}

// System Health Logs
List<System_Health_Log__c> healthLogs = [SELECT Id FROM System_Health_Log__c LIMIT 10000];
if (!healthLogs.isEmpty()) {
    delete healthLogs;
    System.debug('Deleted ' + healthLogs.size() + ' System_Health_Log__c records');
}

// BehaviorIQ Configuration
List<BehaviorIQ_Configuration__c> configs = [SELECT Id FROM BehaviorIQ_Configuration__c LIMIT 100];
if (!configs.isEmpty()) {
    delete configs;
    System.debug('Deleted ' + configs.size() + ' BehaviorIQ_Configuration__c records');
}

System.debug('');
System.debug('--- Deleting Standard Object Test Data ---');

// Delete Entitlements first (they block Account deletion)
List<Entitlement> entitlements = [SELECT Id FROM Entitlement LIMIT 10000];
if (!entitlements.isEmpty()) {
    delete entitlements;
    System.debug('Deleted ' + entitlements.size() + ' Entitlements');
}

// Delete Contracts (no dependencies)
List<Contract> contracts = [SELECT Id FROM Contract LIMIT 10000];
if (!contracts.isEmpty()) {
    delete contracts;
    System.debug('Deleted ' + contracts.size() + ' Contracts');
}

// Delete Cases
List<Case> cases = [SELECT Id FROM Case LIMIT 10000];
if (!cases.isEmpty()) {
    delete cases;
    System.debug('Deleted ' + cases.size() + ' Cases');
}

// Delete Opportunities
List<Opportunity> opps = [SELECT Id FROM Opportunity LIMIT 10000];
if (!opps.isEmpty()) {
    delete opps;
    System.debug('Deleted ' + opps.size() + ' Opportunities');
}

// Delete Leads
List<Lead> leads = [SELECT Id FROM Lead LIMIT 10000];
if (!leads.isEmpty()) {
    delete leads;
    System.debug('Deleted ' + leads.size() + ' Leads');
}

// Delete Contacts
List<Contact> contacts = [SELECT Id FROM Contact LIMIT 10000];
if (!contacts.isEmpty()) {
    delete contacts;
    System.debug('Deleted ' + contacts.size() + ' Contacts');
}

// Delete Accounts
List<Account> accounts = [SELECT Id FROM Account LIMIT 10000];
if (!accounts.isEmpty()) {
    delete accounts;
    System.debug('Deleted ' + accounts.size() + ' Accounts');
}

// Delete Tasks created by fixes
List<Task> tasks = [SELECT Id FROM Task LIMIT 10000];
if (!tasks.isEmpty()) {
    delete tasks;
    System.debug('Deleted ' + tasks.size() + ' Tasks');
}

System.debug('');
System.debug('--- Aborting Any Scheduled Jobs ---');

// Abort any BehaviorIQ scheduled jobs
List<CronTrigger> cronJobs = [
    SELECT Id, CronJobDetail.Name
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE '%BehaviorIQ%'
    OR CronJobDetail.Name LIKE '%Pattern%'
];

for (CronTrigger ct : cronJobs) {
    try {
        System.abortJob(ct.Id);
        System.debug('Aborted scheduled job: ' + ct.CronJobDetail.Name);
    } catch (Exception e) {
        System.debug('Could not abort job: ' + e.getMessage());
    }
}

System.debug('');
System.debug('=== WIPE COMPLETE ===');
System.debug('The org is now clean. You can:');
System.debug('1. Go through the Setup Wizard again');
System.debug('2. Run the test data script');
System.debug('3. Run the pattern analysis batch');
