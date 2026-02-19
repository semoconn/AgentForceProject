/**
 * BehaviorIQ E2E Security Test Data Setup
 * ==========================================
 *
 * This script creates production-quality test data from a NEW CUSTOMER perspective.
 * It simulates realistic CRM data with common data quality issues that BehaviorIQ detects.
 *
 * PREREQUISITES:
 * 1. Complete the Setup Wizard first (as Admin)
 * 2. Run this script after Setup Wizard completion
 * 3. Then run PatternAnalysisBatch to detect pain points
 *
 * DATA CREATED:
 * - 50 Accounts (including duplicates, various ratings)
 * - 100 Contacts (orphans, missing data, duplicates)
 * - 75 Leads (duplicates, various statuses)
 * - 60 Opportunities (high-value ghosted, orphans)
 * - 80 Cases (orphans, escalated, churn patterns)
 * - 20 Contracts (expiring, active)
 *
 * PATTERN COVERAGE:
 * - Contact_Data_Gap (FREE)
 * - High_Value_Ghosting (PREMIUM)
 * - Duplicate_Leads (PREMIUM)
 * - Duplicate_Contacts (PREMIUM)
 * - Duplicate_Accounts (PREMIUM)
 * - Orphan_Contact (PREMIUM)
 * - Orphan_Opportunity (PREMIUM)
 * - Orphan_Case (PREMIUM)
 * - Frequent_Flyer_Churn (PREMIUM)
 * - Premature_Escalation (PREMIUM)
 * - Contract_Expiry_Red_Zone (PREMIUM)
 */

System.debug('=== BehaviorIQ E2E Security Test Data Setup ===');
System.debug('Creating production-quality test data for new customer experience...');
System.debug('');

// Track created record IDs for verification
Map<String, List<Id>> createdRecords = new Map<String, List<Id>>();

// ============================================================================
// PART 1: ACCOUNTS (50 total)
// ============================================================================
System.debug('--- Creating Accounts (50 total) ---');

List<Account> accounts = new List<Account>();

// 5 Hot accounts for Frequent Flyer Churn testing
for (Integer i = 1; i <= 5; i++) {
    accounts.add(new Account(
        Name = 'Enterprise Customer ' + i,
        Rating = 'Hot',
        Industry = 'Technology',
        Type = 'Customer - Direct',
        AnnualRevenue = 5000000 + (i * 1000000),
        NumberOfEmployees = 500 + (i * 100),
        Website = 'https://enterprise' + i + '.example.com',
        Description = 'High-value enterprise customer - Hot rating for churn testing'
    ));
}

// 10 Warm accounts - standard customers
for (Integer i = 1; i <= 10; i++) {
    accounts.add(new Account(
        Name = 'Growing Business ' + i,
        Rating = 'Warm',
        Industry = 'Financial Services',
        Type = 'Customer - Channel',
        AnnualRevenue = 1000000 + (i * 200000),
        NumberOfEmployees = 50 + (i * 25)
    ));
}

// 15 Cold accounts - prospects
for (Integer i = 1; i <= 15; i++) {
    accounts.add(new Account(
        Name = 'Prospect Company ' + i,
        Rating = 'Cold',
        Industry = 'Healthcare',
        Type = 'Prospect',
        AnnualRevenue = 500000 + (i * 100000)
    ));
}

// 8 Duplicate accounts (4 pairs) - for Duplicate_Accounts pattern
String[] dupAccountNames = new String[]{'Duplicate Company Alpha', 'Duplicate Company Beta', 'Duplicate Company Gamma', 'Duplicate Company Delta'};
for (String dupName : dupAccountNames) {
    // First occurrence
    accounts.add(new Account(
        Name = dupName,
        Rating = 'Warm',
        Industry = 'Technology',
        Type = 'Prospect',
        Description = 'Intentional duplicate for testing'
    ));
    // Second occurrence (duplicate)
    accounts.add(new Account(
        Name = dupName,
        Rating = 'Cold',
        Industry = 'Manufacturing',
        Type = 'Customer - Direct',
        Description = 'Intentional duplicate for testing'
    ));
}

// 12 Standard accounts without issues
for (Integer i = 1; i <= 12; i++) {
    accounts.add(new Account(
        Name = 'Standard Corp ' + i,
        Rating = Math.mod(i, 3) == 0 ? 'Hot' : (Math.mod(i, 3) == 1 ? 'Warm' : 'Cold'),
        Industry = 'Retail',
        Type = 'Customer - Direct'
    ));
}

insert accounts;
System.debug('Created ' + accounts.size() + ' accounts.');
System.debug('  - 5 Hot accounts (for Frequent Flyer Churn)');
System.debug('  - 8 Duplicate accounts (4 pairs)');

// Store account IDs for reference
createdRecords.put('Account', new List<Id>());
for (Account a : accounts) {
    createdRecords.get('Account').add(a.Id);
}

// ============================================================================
// PART 2: CONTACTS (100 total)
// ============================================================================
System.debug('');
System.debug('--- Creating Contacts (100 total) ---');

List<Contact> contacts = new List<Contact>();

// Get Hot accounts for churn testing relationships
List<Account> hotAccounts = [SELECT Id, Name FROM Account WHERE Rating = 'Hot' AND Id IN :createdRecords.get('Account')];

// 15 Contacts with missing Email OR Phone - for Contact_Data_Gap pattern
// 10 with null Email
for (Integer i = 1; i <= 10; i++) {
    contacts.add(new Contact(
        AccountId = accounts[Math.mod(i, 20)].Id,
        FirstName = 'NoEmail',
        LastName = 'Person ' + i,
        Email = null,
        Phone = '555-' + String.valueOf(1000 + i).rightPad(4, '0'),
        Title = 'Manager'
    ));
}

// 5 with null Phone
for (Integer i = 1; i <= 5; i++) {
    contacts.add(new Contact(
        AccountId = accounts[Math.mod(i, 20)].Id,
        FirstName = 'NoPhone',
        LastName = 'Person ' + i,
        Email = 'nophone' + i + '@example.com',
        Phone = null,
        Title = 'Director'
    ));
}

// 10 Orphan contacts (no AccountId) - for Orphan_Contact pattern
for (Integer i = 1; i <= 10; i++) {
    contacts.add(new Contact(
        AccountId = null,
        FirstName = 'Orphan',
        LastName = 'Contact ' + i,
        Email = 'orphan.contact' + i + '@example.com',
        Phone = '555-' + String.valueOf(2000 + i).rightPad(4, '0'),
        Title = 'Consultant',
        Description = 'Contact without account association'
    ));
}

// 10 Duplicate contacts (5 pairs same email) - for Duplicate_Contacts pattern
String[] dupContactEmails = new String[]{'dup.contact1@example.com', 'dup.contact2@example.com', 'dup.contact3@example.com', 'dup.contact4@example.com', 'dup.contact5@example.com'};
Integer dupContactIdx = 0;
for (String dupEmail : dupContactEmails) {
    dupContactIdx++;
    // First contact with email
    contacts.add(new Contact(
        AccountId = accounts[Math.mod(dupContactIdx, 15)].Id,
        FirstName = 'Duplicate',
        LastName = 'ContactA ' + dupContactIdx,
        Email = dupEmail,
        Phone = '555-300' + dupContactIdx,
        Title = 'Sales Rep'
    ));
    // Second contact with same email (duplicate)
    contacts.add(new Contact(
        AccountId = accounts[Math.mod(dupContactIdx + 5, 15)].Id,
        FirstName = 'Duplicate',
        LastName = 'ContactB ' + dupContactIdx,
        Email = dupEmail,
        Phone = '555-400' + dupContactIdx,
        Title = 'Account Manager'
    ));
}

// 55 Standard contacts (no issues) - distributed across accounts
Integer contactNum = 1;
for (Integer i = 0; i < 30; i++) {
    Account acc = accounts[Math.mod(i, accounts.size())];
    contacts.add(new Contact(
        AccountId = acc.Id,
        FirstName = 'Standard',
        LastName = 'Contact ' + contactNum,
        Email = 'standard.contact' + contactNum + '@' + acc.Name.replaceAll('[^a-zA-Z0-9]', '').toLowerCase().left(10) + '.test',
        Phone = '555-' + String.valueOf(5000 + contactNum).rightPad(4, '0'),
        Title = Math.mod(contactNum, 3) == 0 ? 'VP Sales' : (Math.mod(contactNum, 3) == 1 ? 'Director' : 'Manager')
    ));
    contactNum++;
}

// Add more contacts to hot accounts for churn pattern
for (Account hotAcc : hotAccounts) {
    for (Integer i = 1; i <= 5; i++) {
        contacts.add(new Contact(
            AccountId = hotAcc.Id,
            FirstName = 'Hot',
            LastName = 'Contact ' + contactNum,
            Email = 'hot.contact' + contactNum + '@example.com',
            Phone = '555-' + String.valueOf(6000 + contactNum).rightPad(4, '0'),
            Title = 'Customer Success'
        ));
        contactNum++;
    }
}

insert contacts;
System.debug('Created ' + contacts.size() + ' contacts.');
System.debug('  - 15 with missing Email/Phone (Contact_Data_Gap)');
System.debug('  - 10 orphan contacts (Orphan_Contact)');
System.debug('  - 10 duplicate contacts (Duplicate_Contacts)');

createdRecords.put('Contact', new List<Id>());
for (Contact c : contacts) {
    createdRecords.get('Contact').add(c.Id);
}

// ============================================================================
// PART 3: LEADS (75 total)
// ============================================================================
System.debug('');
System.debug('--- Creating Leads (75 total) ---');

List<Lead> leads = new List<Lead>();
List<String> leadSources = new List<String>{'Web', 'Phone Inquiry', 'Partner Referral', 'Purchased List', 'Other'};
List<String> industries = new List<String>{'Technology', 'Healthcare', 'Finance', 'Manufacturing', 'Retail'};

// 12 Duplicate leads (6 pairs same email) - for Duplicate_Leads pattern
String[] dupLeadEmails = new String[]{'dup.lead1@test.com', 'dup.lead2@test.com', 'dup.lead3@test.com', 'dup.lead4@test.com', 'dup.lead5@test.com', 'dup.lead6@test.com'};
Integer dupLeadIdx = 0;
for (String dupEmail : dupLeadEmails) {
    dupLeadIdx++;
    // First lead with email
    leads.add(new Lead(
        FirstName = 'Duplicate',
        LastName = 'LeadA ' + dupLeadIdx,
        Company = 'Duplicate Lead Company A' + dupLeadIdx,
        Email = dupEmail,
        Phone = '555-700' + dupLeadIdx,
        Status = 'Open - Not Contacted',
        LeadSource = 'Web',
        Industry = 'Technology',
        Description = 'Intentional duplicate for testing'
    ));
    // Second lead with same email (duplicate)
    leads.add(new Lead(
        FirstName = 'Duplicate',
        LastName = 'LeadB ' + dupLeadIdx,
        Company = 'Duplicate Lead Company B' + dupLeadIdx,
        Email = dupEmail,
        Phone = '555-800' + dupLeadIdx,
        Status = 'Working - Contacted',
        LeadSource = 'Phone Inquiry',
        Industry = 'Healthcare',
        Description = 'Intentional duplicate for testing'
    ));
}

// 63 Standard leads (no issues)
for (Integer i = 1; i <= 63; i++) {
    leads.add(new Lead(
        FirstName = 'Prospect',
        LastName = 'Lead ' + i,
        Company = 'Prospective Company ' + i,
        Email = 'prospect.lead' + i + '@testcompany.example',
        Phone = '555-' + String.valueOf(9000 + i).rightPad(4, '0'),
        Status = Math.mod(i, 3) == 0 ? 'Working - Contacted' : 'Open - Not Contacted',
        LeadSource = leadSources[Math.mod(i, 5)],
        Industry = industries[Math.mod(i, 5)],
        Rating = Math.mod(i, 4) == 0 ? 'Hot' : (Math.mod(i, 4) == 1 ? 'Warm' : 'Cold')
    ));
}

insert leads;
System.debug('Created ' + leads.size() + ' leads.');
System.debug('  - 12 duplicate leads (Duplicate_Leads)');

createdRecords.put('Lead', new List<Id>());
for (Lead l : leads) {
    createdRecords.get('Lead').add(l.Id);
}

// ============================================================================
// PART 4: OPPORTUNITIES (60 total)
// ============================================================================
System.debug('');
System.debug('--- Creating Opportunities (60 total) ---');

List<Opportunity> opportunities = new List<Opportunity>();
List<String> stages = new List<String>{'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition', 'Proposal/Price Quote', 'Negotiation/Review'};

// 10 High-value opportunities with NO activity - for High_Value_Ghosting pattern
// Amount > $50K, LastActivityDate = null (no tasks/events), IsClosed = false
String[] ghostedNames = new String[]{'Enterprise Deal Alpha', 'Enterprise Deal Beta', 'Global Expansion', 'Healthcare Project', 'Mega Deal', 'Strategic Partnership', 'Digital Transformation', 'Cloud Migration', 'Platform Upgrade', 'Market Expansion'};
Decimal[] ghostedAmounts = new Decimal[]{75000, 125000, 250000, 175000, 500000, 95000, 150000, 200000, 85000, 300000};
Integer ghostIdx = 0;
for (String ghostName : ghostedNames) {
    opportunities.add(new Opportunity(
        Name = ghostName,
        AccountId = accounts[Math.mod(ghostIdx, 15)].Id,
        Amount = ghostedAmounts[ghostIdx],
        StageName = 'Negotiation/Review',
        CloseDate = Date.today().addDays(45 + ghostIdx * 5),
        Probability = 60,
        Description = 'High-value opportunity with no sales activity - GHOSTED'
        // LastActivityDate will be null because no Tasks/Events are created
    ));
    ghostIdx++;
}

// 6 Orphan opportunities (no AccountId) - for Orphan_Opportunity pattern
for (Integer i = 1; i <= 6; i++) {
    opportunities.add(new Opportunity(
        Name = 'Orphan Deal ' + i,
        AccountId = null,
        Amount = 25000 + (i * 5000),
        StageName = stages[Math.mod(i, 6)],
        CloseDate = Date.today().addDays(30 + i * 7),
        Probability = 40,
        Description = 'Opportunity without account association'
    ));
}

// 44 Standard opportunities (no issues)
Integer oppCounter = 0;
for (Integer i = 0; i < 44; i++) {
    oppCounter++;
    opportunities.add(new Opportunity(
        Name = 'Standard Deal ' + oppCounter + ' - ' + accounts[Math.mod(i, accounts.size())].Name.left(20),
        AccountId = accounts[Math.mod(i, accounts.size())].Id,
        Amount = 10000 + (oppCounter * 2500),
        StageName = stages[Math.mod(oppCounter, 6)],
        CloseDate = Date.today().addDays(14 + Math.mod(oppCounter * 3, 60)),
        Probability = 30 + Math.mod(oppCounter * 5, 40)
    ));
}

insert opportunities;
System.debug('Created ' + opportunities.size() + ' opportunities.');
System.debug('  - 10 high-value ghosted (High_Value_Ghosting)');
System.debug('  - 6 orphan opportunities (Orphan_Opportunity)');

createdRecords.put('Opportunity', new List<Id>());
for (Opportunity o : opportunities) {
    createdRecords.get('Opportunity').add(o.Id);
}

// ============================================================================
// PART 5: CASES (80 total)
// ============================================================================
System.debug('');
System.debug('--- Creating Cases (80 total) ---');

List<Case> cases = new List<Case>();
List<String> caseOrigins = new List<String>{'Phone', 'Email', 'Web'};
List<String> casePriorities = new List<String>{'High', 'Medium', 'Low'};
List<String> caseStatuses = new List<String>{'New', 'Working', 'Escalated'};

// 8 Orphan cases (no AccountId, no ContactId) - for Orphan_Case pattern
for (Integer i = 1; i <= 8; i++) {
    cases.add(new Case(
        AccountId = null,
        ContactId = null,
        Subject = 'Orphan Support Request ' + i,
        Priority = casePriorities[Math.mod(i, 3)],
        Status = 'New',
        Origin = caseOrigins[Math.mod(i, 3)],
        Description = 'Case without account or contact association'
    ));
}

// 5 Premature escalation cases - for Premature_Escalation pattern
// IsEscalated = true but Priority != 'High'
for (Integer i = 1; i <= 5; i++) {
    cases.add(new Case(
        AccountId = accounts[Math.mod(i, 20)].Id,
        Subject = 'Prematurely Escalated Case ' + i,
        Priority = Math.mod(i, 2) == 0 ? 'Medium' : 'Low',
        Status = 'Escalated',
        IsEscalated = true,
        Origin = 'Email',
        Description = 'Case escalated without High priority - testing Premature_Escalation'
    ));
}

// 50+ Cases for Hot accounts - for Frequent_Flyer_Churn pattern
// Each Hot account gets 10+ cases
for (Account hotAcc : hotAccounts) {
    for (Integer i = 1; i <= 12; i++) {
        cases.add(new Case(
            AccountId = hotAcc.Id,
            Subject = 'Support Request ' + i + ' for ' + hotAcc.Name.left(20),
            Priority = i <= 4 ? 'High' : (i <= 8 ? 'Medium' : 'Low'),
            Status = Math.mod(i, 3) == 0 ? 'Escalated' : (Math.mod(i, 3) == 1 ? 'Working' : 'New'),
            Origin = caseOrigins[Math.mod(i, 3)],
            Description = 'Multiple cases for Hot account - Frequent Flyer Churn testing'
        ));
    }
}

// Fill remaining cases to reach ~80
Integer currentCaseCount = cases.size();
Integer remainingCases = 80 - currentCaseCount;
if (remainingCases > 0) {
    for (Integer i = 1; i <= remainingCases; i++) {
        cases.add(new Case(
            AccountId = accounts[Math.mod(i, accounts.size())].Id,
            Subject = 'Standard Support Request ' + i,
            Priority = casePriorities[Math.mod(i, 3)],
            Status = caseStatuses[Math.mod(i, 3)],
            Origin = caseOrigins[Math.mod(i, 3)],
            Description = 'Standard support case'
        ));
    }
}

insert cases;
System.debug('Created ' + cases.size() + ' cases.');
System.debug('  - 8 orphan cases (Orphan_Case)');
System.debug('  - 5 premature escalation cases (Premature_Escalation)');
System.debug('  - 60 cases for Hot accounts (Frequent_Flyer_Churn)');

createdRecords.put('Case', new List<Id>());
for (Case c : cases) {
    createdRecords.get('Case').add(c.Id);
}

// ============================================================================
// PART 6: CONTRACTS (20 total)
// ============================================================================
System.debug('');
System.debug('--- Creating Contracts (20 total) ---');

List<Contract> contracts = new List<Contract>();

// 8 Contracts expiring within 30 days - for Contract_Expiry_Red_Zone pattern
for (Integer i = 1; i <= 8; i++) {
    contracts.add(new Contract(
        AccountId = accounts[Math.mod(i, 15)].Id,
        Status = 'Draft',
        StartDate = Date.today().addMonths(-11).addDays(-i * 3),
        ContractTerm = 12,
        Description = 'Contract expiring within 30 days - Red Zone testing'
    ));
}

// 12 Active contracts (not expiring soon)
for (Integer i = 9; i <= 20; i++) {
    contracts.add(new Contract(
        AccountId = accounts[Math.mod(i, accounts.size())].Id,
        Status = 'Draft',
        StartDate = Date.today().addMonths(-6),
        ContractTerm = 24,
        Description = 'Active contract with time remaining'
    ));
}

insert contracts;
System.debug('Created ' + contracts.size() + ' contracts.');
System.debug('  - 8 expiring within 30 days (Contract_Expiry_Red_Zone)');

createdRecords.put('Contract', new List<Id>());
for (Contract ct : contracts) {
    createdRecords.get('Contract').add(ct.Id);
}

// ============================================================================
// SUMMARY
// ============================================================================
System.debug('');
System.debug('=== E2E SECURITY TEST DATA SETUP COMPLETE ===');
System.debug('');
System.debug('Total Records Created:');
System.debug('  Accounts:      ' + createdRecords.get('Account').size());
System.debug('  Contacts:      ' + createdRecords.get('Contact').size());
System.debug('  Leads:         ' + createdRecords.get('Lead').size());
System.debug('  Opportunities: ' + createdRecords.get('Opportunity').size());
System.debug('  Cases:         ' + createdRecords.get('Case').size());
System.debug('  Contracts:     ' + createdRecords.get('Contract').size());
System.debug('');
System.debug('PATTERN COVERAGE:');
System.debug('  Contact_Data_Gap:        15 contacts (FREE)');
System.debug('  Orphan_Contact:          10 contacts (PREMIUM)');
System.debug('  Duplicate_Contacts:      10 contacts (PREMIUM)');
System.debug('  Orphan_Opportunity:      6 opportunities (PREMIUM)');
System.debug('  High_Value_Ghosting:     10 opportunities (PREMIUM)');
System.debug('  Orphan_Case:             8 cases (PREMIUM)');
System.debug('  Premature_Escalation:    5 cases (PREMIUM)');
System.debug('  Frequent_Flyer_Churn:    ~60 cases on 5 Hot accounts (PREMIUM)');
System.debug('  Duplicate_Leads:         12 leads (PREMIUM)');
System.debug('  Duplicate_Accounts:      8 accounts (PREMIUM)');
System.debug('  Contract_Expiry_Red_Zone: 8 contracts (PREMIUM)');
System.debug('');
System.debug('NEXT STEPS:');
System.debug('1. Set license to FREE or PREMIUM as needed');
System.debug('2. Run: Database.executeBatch(new PatternAnalysisBatch(), 200);');
System.debug('3. Verify pain points created in Identified_Pain_Point__c');
System.debug('');
