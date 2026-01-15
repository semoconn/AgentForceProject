/**
 * Comprehensive Mock Data Setup for BehaviorIQ Managed Package Testing
 * Creates extensive test data across all BehaviorIQ custom objects and standard objects
 */

System.debug('=== BehaviorIQ Comprehensive Mock Data Setup ===');
System.debug('Creating extensive test data for end-to-end package testing...');

// ============================================================================
// PART 1: ACCOUNTS - Various ratings and industries for testing
// ============================================================================
System.debug('--- Creating Accounts ---');

List<Account> accounts = new List<Account>();

// Hot accounts (churn risk testing)
for (Integer i = 1; i <= 5; i++) {
    accounts.add(new Account(
        Name = 'Enterprise Hot Customer ' + i,
        Rating = 'Hot',
        Industry = 'Technology',
        Type = 'Customer - Direct',
        AnnualRevenue = 5000000 + (i * 1000000),
        NumberOfEmployees = 500 + (i * 100),
        Website = 'https://hotcustomer' + i + '.example.com',
        Description = 'High-value enterprise customer for BehaviorIQ testing'
    ));
}

// Warm accounts
for (Integer i = 1; i <= 5; i++) {
    accounts.add(new Account(
        Name = 'Growing Business ' + i,
        Rating = 'Warm',
        Industry = 'Financial Services',
        Type = 'Customer - Channel',
        AnnualRevenue = 1000000 + (i * 500000),
        NumberOfEmployees = 100 + (i * 50)
    ));
}

// Cold accounts (prospects)
for (Integer i = 1; i <= 5; i++) {
    accounts.add(new Account(
        Name = 'Prospect Company ' + i,
        Rating = 'Cold',
        Industry = 'Healthcare',
        Type = 'Prospect'
    ));
}

insert accounts;
System.debug('Created ' + accounts.size() + ' accounts across Hot/Warm/Cold ratings.');

// ============================================================================
// PART 2: CONTACTS - Multiple contacts per account
// ============================================================================
System.debug('--- Creating Contacts ---');

List<Contact> contacts = new List<Contact>();
Integer contactNum = 1;
for (Account acc : accounts) {
    // Create 2-3 contacts per account
    Integer numContacts = Math.mod(contactNum, 2) + 2;
    for (Integer i = 1; i <= numContacts; i++) {
        String emailDomain = acc.Name.replaceAll('[^a-zA-Z0-9]', '').toLowerCase().left(15);
        contacts.add(new Contact(
            AccountId = acc.Id,
            FirstName = 'Contact' + i,
            LastName = 'Person ' + contactNum,
            Email = 'contact' + contactNum + '@' + emailDomain + '.test',
            Title = i == 1 ? 'VP Sales' : (i == 2 ? 'Director' : 'Manager'),
            Phone = '555-' + String.valueOf(1000 + contactNum)
        ));
        contactNum++;
    }
}
insert contacts;
System.debug('Created ' + contacts.size() + ' contacts.');

// ============================================================================
// PART 3: OPPORTUNITIES - Various stages and amounts
// ============================================================================
System.debug('--- Creating Opportunities ---');

List<Opportunity> opportunities = new List<Opportunity>();
List<String> stages = new List<String>{'Prospecting', 'Qualification', 'Needs Analysis', 'Value Proposition', 'Proposal/Price Quote', 'Negotiation/Review'};

Integer oppCounter = 0;
for (Account acc : accounts) {
    // High-value opportunities for ghosting detection
    if (acc.Rating == 'Hot') {
        opportunities.add(new Opportunity(
            Name = 'Enterprise Deal - ' + acc.Name.left(30),
            AccountId = acc.Id,
            Amount = 150000 + (oppCounter * 25000),
            StageName = 'Negotiation/Review',
            CloseDate = Date.today().addDays(45),
            Probability = 70,
            Description = 'High-value deal for ghosting detection testing'
        ));
        oppCounter++;
    }

    // Medium-value opportunities
    opportunities.add(new Opportunity(
        Name = 'Standard Deal - ' + acc.Name.left(30),
        AccountId = acc.Id,
        Amount = 25000 + (oppCounter * 5000),
        StageName = stages[Math.mod(oppCounter, stages.size())],
        CloseDate = Date.today().addDays(30 + Math.mod(oppCounter * 7, 60)),
        Probability = 40
    ));
    oppCounter++;

    // Small opportunities
    opportunities.add(new Opportunity(
        Name = 'Quick Win - ' + acc.Name.left(30),
        AccountId = acc.Id,
        Amount = 5000 + (oppCounter * 1000),
        StageName = stages[Math.mod(oppCounter, stages.size())],
        CloseDate = Date.today().addDays(14 + Math.mod(oppCounter * 3, 30)),
        Probability = 60
    ));
    oppCounter++;
}

// Add some closed-won/lost for historical data
for (Integer i = 1; i <= 10; i++) {
    opportunities.add(new Opportunity(
        Name = 'Historical Deal Q' + Math.mod(i, 4) + ' - ' + i,
        AccountId = accounts[Math.mod(i, accounts.size())].Id,
        Amount = 30000 + (i * 8000),
        StageName = Math.mod(i, 3) == 0 ? 'Closed Lost' : 'Closed Won',
        CloseDate = Date.today().addDays(-30 - (i * 15))
    ));
}

insert opportunities;
System.debug('Created ' + opportunities.size() + ' opportunities.');

// ============================================================================
// PART 4: CASES - Various priorities and statuses
// ============================================================================
System.debug('--- Creating Cases ---');

List<Case> cases = new List<Case>();
List<String> caseOrigins = new List<String>{'Phone', 'Email', 'Web'};
List<String> casePriorities = new List<String>{'High', 'Medium', 'Low'};
List<String> caseStatuses = new List<String>{'New', 'Working', 'Escalated'};

Integer caseCounter = 0;
for (Account acc : accounts) {
    // More cases for Hot accounts (frequent flyer testing)
    Integer numCases = acc.Rating == 'Hot' ? 5 : 2;

    for (Integer i = 1; i <= numCases; i++) {
        cases.add(new Case(
            AccountId = acc.Id,
            Subject = 'Support Request ' + caseCounter + ' - ' + acc.Name.left(20),
            Priority = acc.Rating == 'Hot' ? 'High' : casePriorities[Math.mod(caseCounter, 3)],
            Status = caseStatuses[Math.mod(caseCounter, 3)],
            Origin = caseOrigins[Math.mod(caseCounter, 3)],
            Description = 'Test case for BehaviorIQ pattern detection'
        ));
        caseCounter++;
    }
}

insert cases;
System.debug('Created ' + cases.size() + ' cases.');

// ============================================================================
// PART 5: LEADS - For lead hoarding detection
// ============================================================================
System.debug('--- Creating Leads ---');

List<Lead> leads = new List<Lead>();
List<String> leadSources = new List<String>{'Web', 'Phone Inquiry', 'Partner Referral', 'Purchased List', 'Other'};
List<String> industries = new List<String>{'Technology', 'Healthcare', 'Finance', 'Manufacturing', 'Retail'};

Id currentUserId = UserInfo.getUserId();

// Leads assigned to current user (hoarding test)
for (Integer i = 1; i <= 15; i++) {
    leads.add(new Lead(
        FirstName = 'Prospect',
        LastName = 'Lead ' + i,
        Company = 'Prospective Company ' + i,
        Email = 'prospect.lead' + i + '@testcompany.example',
        Phone = '555-' + String.valueOf(2000 + i),
        Status = 'Open - Not Contacted',
        LeadSource = leadSources[Math.mod(i, 5)],
        Industry = industries[Math.mod(i, 5)],
        Rating = Math.mod(i, 3) == 0 ? 'Hot' : (Math.mod(i, 3) == 1 ? 'Warm' : 'Cold'),
        OwnerId = currentUserId,
        Description = 'Test lead for lead hoarding detection'
    ));
}

// Additional leads in various statuses
for (Integer i = 16; i <= 30; i++) {
    leads.add(new Lead(
        FirstName = 'Marketing',
        LastName = 'Lead ' + i,
        Company = 'Marketing Source Company ' + i,
        Email = 'marketing.lead' + i + '@testcompany.example',
        Status = Math.mod(i, 4) == 0 ? 'Working - Contacted' : 'Open - Not Contacted',
        LeadSource = leadSources[Math.mod(i, 5)],
        Industry = industries[Math.mod(i, 5)]
    ));
}

insert leads;
System.debug('Created ' + leads.size() + ' leads.');

// ============================================================================
// PART 6: CONTRACTS - For expiry detection
// ============================================================================
System.debug('--- Creating Contracts ---');

List<Contract> contracts = new List<Contract>();

// Expiring contracts (within 30 days)
for (Integer i = 1; i <= 5; i++) {
    contracts.add(new Contract(
        AccountId = accounts[Math.mod(i, accounts.size())].Id,
        Status = 'Draft',
        StartDate = Date.today().addMonths(-11).addDays(-i * 5),
        ContractTerm = 12,
        Description = 'Expiring contract for red zone detection'
    ));
}

// Active contracts
for (Integer i = 6; i <= 10; i++) {
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

System.debug('=== Standard Object Data Complete ===');
System.debug('Total Records Created:');
System.debug('  Accounts: ' + accounts.size());
System.debug('  Contacts: ' + contacts.size());
System.debug('  Opportunities: ' + opportunities.size());
System.debug('  Cases: ' + cases.size());
System.debug('  Leads: ' + leads.size());
System.debug('  Contracts: ' + contracts.size());
