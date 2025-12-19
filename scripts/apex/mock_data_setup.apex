/**
 * @description Sprint 6 Mock Data Setup Script
 * Creates test data to trigger all 5 Premium pain point rules.
 *
 * Usage: sfdx force:apex:execute -f scripts/apex/mock_data_setup.apex
 *
 * IMPORTANT: Run this script in a Sandbox or Developer org only!
 * This script creates real data that will be detected by the PatternAnalysisService.
 */

System.debug('=== Sprint 6 Mock Data Setup ===');
System.debug('Creating test data for 5 Premium pain point rules...');

// =============================================================================
// STORY 1: High-Value Ghosting (Revenue Risk)
// Rule: Amount > $50,000, LastActivityDate > 14 days ago, Stage NOT Closed
// =============================================================================
System.debug('Story 1: Creating High-Value Ghosting opportunities...');

List<Opportunity> ghostingOpps = new List<Opportunity>();
for (Integer i = 1; i <= 3; i++) {
    ghostingOpps.add(new Opportunity(
        Name = 'High-Value Deal #' + i + ' (Ghost Test)',
        Amount = 75000 + (i * 10000), // $85K, $95K, $105K
        StageName = 'Negotiation/Review',
        CloseDate = Date.today().addDays(30),
        // LastActivityDate will be null (no activities) which triggers the rule
        Description = '[TEST DATA] Created by mock_data_setup.apex for High-Value Ghosting detection'
    ));
}
insert ghostingOpps;
System.debug('Created ' + ghostingOpps.size() + ' high-value opportunities with no recent activity.');

// =============================================================================
// STORY 2: Frequent Flyer (Churn Risk)
// Rule: Priority = 'High', Account.Rating = 'Hot', Status is Open
// =============================================================================
System.debug('Story 2: Creating Frequent Flyer cases with Hot accounts...');

// First, create or find a Hot account
Account hotAccount;
List<Account> existingHotAccounts = [SELECT Id, Name FROM Account WHERE Rating = 'Hot' LIMIT 1];
if (existingHotAccounts.isEmpty()) {
    hotAccount = new Account(
        Name = 'Hot Customer Corp (Churn Risk Test)',
        Rating = 'Hot',
        Industry = 'Technology',
        Description = '[TEST DATA] Created by mock_data_setup.apex for Frequent Flyer detection'
    );
    insert hotAccount;
    System.debug('Created new Hot account: ' + hotAccount.Name);
} else {
    hotAccount = existingHotAccounts[0];
    System.debug('Using existing Hot account: ' + hotAccount.Name);
}

// Create high-priority open cases for the hot account
List<Case> churnRiskCases = new List<Case>();
for (Integer i = 1; i <= 3; i++) {
    churnRiskCases.add(new Case(
        AccountId = hotAccount.Id,
        Subject = 'Critical Issue #' + i + ' - Needs Immediate Attention',
        Priority = 'High',
        Status = 'New',
        Origin = 'Phone',
        Description = '[TEST DATA] Created by mock_data_setup.apex for Frequent Flyer detection'
    ));
}
insert churnRiskCases;
System.debug('Created ' + churnRiskCases.size() + ' high-priority cases for Hot account.');

// =============================================================================
// STORY 3: Lead Hoarding (Operational Bottleneck)
// Rule: Owner is a User (not Queue), Status = 'Open - Not Contacted', CreatedDate > 5 days ago
// =============================================================================
System.debug('Story 3: Creating Lead Hoarding leads...');

// Get the current user to assign leads to (simulating hoarding)
Id currentUserId = UserInfo.getUserId();

List<Lead> hoardedLeads = new List<Lead>();
for (Integer i = 1; i <= 5; i++) {
    hoardedLeads.add(new Lead(
        FirstName = 'Hoarded',
        LastName = 'Lead ' + i,
        Company = 'Hoarding Test Company ' + i,
        Email = 'hoarded.lead' + i + '@test.com',
        Status = 'Open - Not Contacted',
        LeadSource = 'Web',
        OwnerId = currentUserId, // Assigned to a user, not a queue
        Description = '[TEST DATA] Created by mock_data_setup.apex for Lead Hoarding detection'
    ));
}
insert hoardedLeads;

// Backdate the CreatedDate using a workaround (note: may not work in all orgs)
// In production, these leads would naturally age past 5 days
System.debug('Created ' + hoardedLeads.size() + ' leads assigned to current user.');
System.debug('NOTE: These leads will trigger the rule after 5 days, or manually backdate CreatedDate in Data Loader.');

// =============================================================================
// STORY 4: Contract Expiry Red Zone (Renewal Risk)
// Rule: EndDate within next 30 days, Status != 'Activated' and != 'In Approval Process'
// =============================================================================
System.debug('Story 4: Creating Contract Expiry Red Zone contracts...');

// Create an account for the contracts if needed
Account contractAccount;
List<Account> existingAccounts = [SELECT Id, Name FROM Account WHERE Name LIKE '%Contract Test%' LIMIT 1];
if (existingAccounts.isEmpty()) {
    contractAccount = new Account(
        Name = 'Contract Test Customer',
        Industry = 'Financial Services',
        Description = '[TEST DATA] Created by mock_data_setup.apex for Contract Expiry detection'
    );
    insert contractAccount;
} else {
    contractAccount = existingAccounts[0];
}

List<Contract> expiringContracts = new List<Contract>();
for (Integer i = 1; i <= 3; i++) {
    expiringContracts.add(new Contract(
        AccountId = contractAccount.Id,
        Status = 'Draft', // Not Activated - will trigger the rule
        StartDate = Date.today().addMonths(-11), // Started almost a year ago
        ContractTerm = 12, // 12 month contract
        Description = '[TEST DATA] Contract expiring soon - mock_data_setup.apex'
    ));
}
insert expiringContracts;
System.debug('Created ' + expiringContracts.size() + ' contracts expiring within 30 days.');

// =============================================================================
// STORY 5: Zombie Projects (Resource Waste)
// Rule: Status = 'Active', LastModifiedDate > 60 days ago (Custom Object Project__c)
// =============================================================================
System.debug('Story 5: Creating Zombie Projects...');

// Check if Project__c object exists before trying to create records
Boolean projectObjectExists = false;
try {
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    projectObjectExists = globalDescribe.containsKey('Project__c');
} catch (Exception e) {
    System.debug('Could not check for Project__c object: ' + e.getMessage());
}

if (projectObjectExists) {
    List<SObject> zombieProjects = new List<SObject>();
    Schema.SObjectType projectType = Schema.getGlobalDescribe().get('Project__c');

    for (Integer i = 1; i <= 3; i++) {
        SObject proj = projectType.newSObject();
        proj.put('Name', 'Abandoned Project #' + i);
        proj.put('Status__c', 'Active');
        proj.put('Description__c', '[TEST DATA] Created by mock_data_setup.apex for Zombie Projects detection');
        zombieProjects.add(proj);
    }
    insert zombieProjects;
    System.debug('Created ' + zombieProjects.size() + ' zombie projects (will trigger after 60 days of no modification).');
    System.debug('NOTE: To test immediately, manually backdate LastModifiedDate via Data Loader.');
} else {
    System.debug('WARNING: Project__c object does not exist. Deploy the Project__c object first.');
    System.debug('Run: sfdx force:source:deploy -p force-app/main/default/objects/Project__c');
}

// =============================================================================
// SUMMARY
// =============================================================================
System.debug('');
System.debug('=== Mock Data Setup Complete ===');
System.debug('');
System.debug('Created test data for:');
System.debug('  1. High-Value Ghosting: ' + ghostingOpps.size() + ' opportunities (triggers immediately if no activities exist)');
System.debug('  2. Frequent Flyer: ' + churnRiskCases.size() + ' high-priority cases for Hot account');
System.debug('  3. Lead Hoarding: ' + hoardedLeads.size() + ' leads (triggers after 5 days)');
System.debug('  4. Contract Expiry: ' + expiringContracts.size() + ' contracts expiring within 30 days');
System.debug('  5. Zombie Projects: Check above for Project__c creation status');
System.debug('');
System.debug('To run the detection engine:');
System.debug('  1. Enable Premium license: BehaviorIQ_License__c settings');
System.debug('  2. Run: Database.executeBatch(new PatternAnalysisService(), 50);');
System.debug('  3. Check Identified_Pain_Point__c records for detected patterns');
