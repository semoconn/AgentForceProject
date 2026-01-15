/**
 * Comprehensive Mock Data Setup Part 2 - BehaviorIQ Custom Objects
 * Run this AFTER comprehensive_mock_data.apex (Part 1)
 *
 * This script creates data for BehaviorIQ custom objects that have proper FLS permissions.
 */

System.debug('=== BehaviorIQ Custom Objects Mock Data Setup ===');

// ============================================================================
// Get references to standard objects created in Part 1
// ============================================================================
List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 15];
List<Opportunity> opportunities = [SELECT Id, Name FROM Opportunity WHERE StageName != 'Closed Won' AND StageName != 'Closed Lost' LIMIT 20];
List<Case> cases = [SELECT Id, Subject FROM Case LIMIT 15];
List<Lead> leads = [SELECT Id, Name FROM Lead LIMIT 15];
Id currentUserId = UserInfo.getUserId();

System.debug('Found ' + accounts.size() + ' accounts, ' + opportunities.size() + ' opportunities for custom object data');

// ============================================================================
// PART 1: BehaviorIQ_Configuration__c - System Configuration
// ============================================================================
System.debug('--- Creating BehaviorIQ Configuration ---');

List<BehaviorIQ_Configuration__c> existingConfigs = [SELECT Id FROM BehaviorIQ_Configuration__c LIMIT 1];
if (existingConfigs.isEmpty()) {
    BehaviorIQ_Configuration__c config = new BehaviorIQ_Configuration__c(
        Name = 'Default Configuration',
        Monitored_Objects__c = 'Opportunity;Case;Lead;Contract;Account',
        Stale_Case_Threshold__c = 14,
        Stale_Opportunity_Threshold__c = 30
    );
    insert config;
    System.debug('Created BehaviorIQ Configuration record.');
} else {
    System.debug('BehaviorIQ Configuration already exists.');
}

// ============================================================================
// PART 2: BehaviorIQ_License__c - License Management
// ============================================================================
System.debug('--- Creating BehaviorIQ License ---');

List<BehaviorIQ_License__c> existingLicenses = [SELECT Id FROM BehaviorIQ_License__c LIMIT 1];
if (existingLicenses.isEmpty()) {
    BehaviorIQ_License__c license = new BehaviorIQ_License__c(
        Name = 'Free License',
        Status__c = 'Free'
    );
    insert license;
    System.debug('Created BehaviorIQ License record (Free Tier).');
} else {
    System.debug('BehaviorIQ License already exists.');
}

// ============================================================================
// PART 3: Identified_Pain_Point__c - Pain Points (detected patterns)
// ============================================================================
System.debug('--- Creating Identified Pain Points ---');

List<Identified_Pain_Point__c> painPoints = new List<Identified_Pain_Point__c>();

// High-Value Ghosting pain points (Unique_Key matches metadata DeveloperName: High_Value_Ghosting)
// Impact_Score__c = cumulative value at risk (simulated: 5 opps * ~$75K avg = $375,000)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'High-Value Ghosting - Revenue Risk',
    Description__c = 'Multiple high-value opportunities ($50K+) have gone silent with no activity in the past 14+ days.',
    Object_API_Name__c = 'Opportunity',
    Impact_Score__c = 375000,
    Occurrences__c = 5,
    Status__c = 'New',
    Last_Detected__c = DateTime.now(),
    Unique_Key__c = 'High_Value_Ghosting',
    Example_Records__c = opportunities.size() > 0 ? opportunities[0].Id : null
));

// Frequent Flyer pain points (matches metadata: Frequent_Flyer_Churn)
// Impact_Score__c = 12 cases * $75/case = $900
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Frequent Flyer - Churn Risk',
    Description__c = 'Hot-rated accounts are generating multiple high-priority support cases.',
    Object_API_Name__c = 'Case',
    Impact_Score__c = 900,
    Occurrences__c = 12,
    Status__c = 'New',
    Last_Detected__c = DateTime.now(),
    Unique_Key__c = 'Frequent_Flyer_Churn',
    Example_Records__c = cases.size() > 0 ? cases[0].Id : null
));

// Lead Hoarding pain points (matches metadata: Lead_Hoarding)
// Impact_Score__c = 15 leads * $100/lead = $1,500
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Lead Hoarding - Operational Bottleneck',
    Description__c = 'Leads are being hoarded by sales reps without follow-up.',
    Object_API_Name__c = 'Lead',
    Impact_Score__c = 1500,
    Occurrences__c = 15,
    Status__c = 'New',
    Last_Detected__c = DateTime.now(),
    Unique_Key__c = 'Lead_Hoarding',
    Example_Records__c = leads.size() > 0 ? leads[0].Id : null
));

// Contract Expiry pain points (matches metadata: Contract_Expiry_Red_Zone)
// Impact_Score__c = cumulative contract value at risk (simulated: 5 contracts * ~$50K avg = $250,000)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Contract Expiry Red Zone',
    Description__c = 'Contracts are expiring within 30 days without renewal activity.',
    Object_API_Name__c = 'Contract',
    Impact_Score__c = 250000,
    Occurrences__c = 5,
    Status__c = 'New',
    Last_Detected__c = DateTime.now(),
    Unique_Key__c = 'Contract_Expiry_Red_Zone'
));

// Some resolved pain points for historical data (matches metadata: Stale_Opp_90)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Resolved - Stale Pipeline Q3',
    Description__c = 'Previously identified stale opportunities have been addressed.',
    Object_API_Name__c = 'Opportunity',
    Impact_Score__c = 180000,
    Occurrences__c = 8,
    Status__c = 'Resolved',
    Last_Detected__c = DateTime.now().addDays(-30),
    Unique_Key__c = 'Stale_Opp_90'
));

// Resolved case backlog (matches metadata: Stale_Case_30)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Resolved - Case Backlog October',
    Description__c = 'Case backlog from October has been cleared.',
    Object_API_Name__c = 'Case',
    Impact_Score__c = 1875,
    Occurrences__c = 25,
    Status__c = 'Resolved',
    Last_Detected__c = DateTime.now().addDays(-45),
    Unique_Key__c = 'Stale_Case_30'
));

// Additional stale opportunities (matches metadata: Stale_Opp_90)
// Impact_Score__c = cumulative opportunity amount at risk (9 opps * ~$45K avg = $405,000)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Stale Opportunities - Q4 Pipeline',
    Description__c = 'Several Q4 opportunities have not been updated in over 30 days.',
    Object_API_Name__c = 'Opportunity',
    Impact_Score__c = 405000,
    Occurrences__c = 9,
    Status__c = 'New',
    Last_Detected__c = DateTime.now().addDays(-3),
    Unique_Key__c = 'Stale_Opp_90'
));

// Unassigned leads (matches metadata: Unassigned_Lead_48)
// Impact_Score__c = 22 leads * $100/lead = $2,200
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Unqualified Lead Backlog',
    Description__c = 'Large number of leads have not been qualified within SLA.',
    Object_API_Name__c = 'Lead',
    Impact_Score__c = 2200,
    Occurrences__c = 22,
    Status__c = 'New',
    Last_Detected__c = DateTime.now().addDays(-1),
    Unique_Key__c = 'Unassigned_Lead_48'
));

insert painPoints;
System.debug('Created ' + painPoints.size() + ' Identified Pain Points.');

// ============================================================================
// PART 4: Behavior_Log__c - User Behavior Logs
// ============================================================================
System.debug('--- Creating Behavior Logs ---');

List<Behavior_Log__c> behaviorLogs = new List<Behavior_Log__c>();
List<String> actions = new List<String>{'View', 'Edit', 'Create', 'Delete', 'Clone', 'Share'};
List<String> objects = new List<String>{'Opportunity', 'Case', 'Lead', 'Account', 'Contact'};

for (Integer i = 1; i <= 50; i++) {
    String objName = objects[Math.mod(i, objects.size())];
    String recordId = '';
    if (objName == 'Opportunity' && opportunities.size() > 0) {
        recordId = opportunities[Math.mod(i, opportunities.size())].Id;
    } else if (objName == 'Case' && cases.size() > 0) {
        recordId = cases[Math.mod(i, cases.size())].Id;
    } else if (objName == 'Lead' && leads.size() > 0) {
        recordId = leads[Math.mod(i, leads.size())].Id;
    } else if (objName == 'Account' && accounts.size() > 0) {
        recordId = accounts[Math.mod(i, accounts.size())].Id;
    }

    behaviorLogs.add(new Behavior_Log__c(
        Action_Name__c = actions[Math.mod(i, actions.size())],
        Object_API_Name__c = objName,
        Record_ID__c = recordId,
        User__c = currentUserId,
        Behavior_Data__c = '{"action":"' + actions[Math.mod(i, actions.size())] + '","index":' + i + '}',
        Timestamp__c = DateTime.now().addHours(-i)
    ));
}
insert behaviorLogs;
System.debug('Created ' + behaviorLogs.size() + ' Behavior Logs.');

// ============================================================================
// PART 5: Remediation_Log__c - Remediation Actions Taken
// ============================================================================
System.debug('--- Creating Remediation Logs ---');

List<Remediation_Log__c> remediationLogs = new List<Remediation_Log__c>();

List<String> remediationStatuses = new List<String>{'Success', 'Failed'};
List<String> actionsTaken = new List<String>{'Task_Creation', 'Owner_Assignment', 'Field_Update', 'Email_Notification', 'Opportunity_Creation'};

for (Integer i = 1; i <= 20; i++) {
    String affectedRecordId = '';
    if (Math.mod(i, 3) == 0 && opportunities.size() > 0) {
        affectedRecordId = opportunities[Math.mod(i, opportunities.size())].Id;
    } else if (Math.mod(i, 3) == 1 && cases.size() > 0) {
        affectedRecordId = cases[Math.mod(i, cases.size())].Id;
    } else if (leads.size() > 0) {
        affectedRecordId = leads[Math.mod(i, leads.size())].Id;
    }

    remediationLogs.add(new Remediation_Log__c(
        Affected_Record_ID__c = affectedRecordId,
        Action_Taken__c = actionsTaken[Math.mod(i, actionsTaken.size())],
        Status__c = remediationStatuses[Math.mod(i, remediationStatuses.size())],
        Original_Value__c = 'Old Value ' + i,
        New_Value__c = 'New Value ' + i,
        Executed_By__c = currentUserId,
        Error_Message__c = Math.mod(i, 4) == 2 ? 'Validation rule prevented update' : null,
        Rule_Developer_Name__c = 'RULE_' + String.valueOf(i).leftPad(3, '0')
    ));
}
insert remediationLogs;
System.debug('Created ' + remediationLogs.size() + ' Remediation Logs.');

// ============================================================================
// PART 6: Behavior_Snapshot__c - Historical Metrics
// ============================================================================
System.debug('--- Creating Behavior Snapshots ---');

List<Behavior_Snapshot__c> snapshots = new List<Behavior_Snapshot__c>();

// Create 30 days of historical snapshot data
for (Integer day = 0; day < 30; day++) {
    Date snapshotDate = Date.today().addDays(-day);

    snapshots.add(new Behavior_Snapshot__c(
        Snapshot_Date__c = snapshotDate,
        Metric_Name__c = 'Stale Opportunities',
        Record_Count__c = 10 + Math.mod(day, 15),
        Impact_Score__c = 50 + Math.mod(day * 3, 40),
        Related_Pain_Point__c = painPoints.size() > 0 ? painPoints[0].Id : null
    ));

    snapshots.add(new Behavior_Snapshot__c(
        Snapshot_Date__c = snapshotDate,
        Metric_Name__c = 'High Priority Cases',
        Record_Count__c = 5 + Math.mod(day * 2, 10),
        Impact_Score__c = 40 + Math.mod(day * 2, 35),
        Related_Pain_Point__c = painPoints.size() > 1 ? painPoints[1].Id : null
    ));

    snapshots.add(new Behavior_Snapshot__c(
        Snapshot_Date__c = snapshotDate,
        Metric_Name__c = 'Uncontacted Leads',
        Record_Count__c = 15 + Math.mod(day, 20),
        Impact_Score__c = 30 + Math.mod(day, 25),
        Related_Pain_Point__c = painPoints.size() > 2 ? painPoints[2].Id : null
    ));
}
insert snapshots;
System.debug('Created ' + snapshots.size() + ' Behavior Snapshots (30 days of metrics).');

// ============================================================================
// PART 7: System_Health_Log__c - System Health Records
// ============================================================================
System.debug('--- Creating System Health Logs ---');

List<System_Health_Log__c> healthLogs = new List<System_Health_Log__c>();
List<String> healthStatuses = new List<String>{'Success', 'Success', 'Success', 'Success', 'Failed'};
List<String> jobNames = new List<String>{'PatternAnalysisBatch', 'MetricsCollectionJob', 'CleanupScheduledJob', 'NotificationService', 'DataSyncJob'};

for (Integer i = 1; i <= 25; i++) {
    healthLogs.add(new System_Health_Log__c(
        Job_Name__c = jobNames[Math.mod(i, jobNames.size())],
        Job_ID__c = 'JOB_' + String.valueOf(i).leftPad(8, '0'),
        Status__c = healthStatuses[Math.mod(i, healthStatuses.size())],
        Error_Count__c = healthStatuses[Math.mod(i, healthStatuses.size())] == 'Failed' ? Math.mod(i, 5) + 1 : 0
    ));
}
insert healthLogs;
System.debug('Created ' + healthLogs.size() + ' System Health Logs.');

// ============================================================================
// PART 8: Suggestion_Dismissal__c - User Dismissals
// ============================================================================
System.debug('--- Creating Suggestion Dismissals ---');

List<Suggestion_Dismissal__c> dismissals = new List<Suggestion_Dismissal__c>();
for (Integer i = 1; i <= 10; i++) {
    dismissals.add(new Suggestion_Dismissal__c(
        Action_Name__c = 'Dismiss_Suggestion_' + i,
        Object_API_Name__c = objects[Math.mod(i, objects.size())],
        User__c = currentUserId,
        Dismissal_Key__c = 'DISMISS_' + String.valueOf(i).leftPad(5, '0') + '_' + currentUserId
    ));
}
insert dismissals;
System.debug('Created ' + dismissals.size() + ' Suggestion Dismissals.');

// ============================================================================
// SUMMARY
// ============================================================================
System.debug('');
System.debug('=== BehaviorIQ Custom Object Mock Data Complete ===');
System.debug('');
System.debug('Custom Objects Created:');
System.debug('  BehaviorIQ_Configuration__c: 1');
System.debug('  BehaviorIQ_License__c: 1');
System.debug('  Identified_Pain_Point__c: ' + painPoints.size());
System.debug('  Behavior_Log__c: ' + behaviorLogs.size());
System.debug('  Remediation_Log__c: ' + remediationLogs.size());
System.debug('  Behavior_Snapshot__c: ' + snapshots.size());
System.debug('  System_Health_Log__c: ' + healthLogs.size());
System.debug('  Suggestion_Dismissal__c: ' + dismissals.size());
System.debug('');
System.debug('Ready for end-to-end testing of BehaviorIQ managed package!');
