/**
 * @description Script to generate Mock Pain Points for UI testing.
 * Usage: sfdx force:apex:execute -f scripts/apex/generateMockData.apex
 */

List<Identified_Pain_Point__c> mockPoints = new List<Identified_Pain_Point__c>();

// Helper to generate unique keys for the mock data
String timestamp = String.valueOf(System.currentTimeMillis());

// 1. Stale Opportunity (High Impact)
mockPoints.add(new Identified_Pain_Point__c(
    Unique_Key__c = 'MOCK-OPP-' + timestamp,
    Object_API_Name__c = 'Opportunity',
    Description__c = 'Opportunity "Big Deal Q4" (ID: 006...) has been in "Negotiation" for 45 days without activity.',
    Impact_Score__c = 85,
    Occurrences__c = 1,
    Status__c = 'New',
    Last_Detected__c = Date.today()
));

// 2. Unassigned Leads (Medium Impact - Recurring)
mockPoints.add(new Identified_Pain_Point__c(
    Unique_Key__c = 'MOCK-LEAD-' + timestamp,
    Object_API_Name__c = 'Lead',
    Description__c = '5 Leads from "Web-to-Lead" source have remained unassigned for > 48 hours.',
    Impact_Score__c = 60,
    Occurrences__c = 5,
    Status__c = 'New',
    Last_Detected__c = Date.today()
));

// 3. Bot Detection (Critical)
mockPoints.add(new Identified_Pain_Point__c(
    Unique_Key__c = 'MOCK-TASK-' + timestamp,
    Object_API_Name__c = 'Task',
    Description__c = 'User "Integration User" created 150 Task records in under 1 minute. Suspected loop or automation error.',
    Impact_Score__c = 95,
    Occurrences__c = 150,
    Status__c = 'New',
    Last_Detected__c = Date.today().addDays(-1) // Yesterday
));

// 4. Stagnant Case (Low Impact - Dismissed Example)
mockPoints.add(new Identified_Pain_Point__c(
    Unique_Key__c = 'MOCK-CASE-' + timestamp,
    Object_API_Name__c = 'Case',
    Description__c = 'Case #10023 has been Open for 20 days.',
    Impact_Score__c = 30,
    Occurrences__c = 1,
    Status__c = 'Dismissed', // To test the filter
    Last_Detected__c = Date.today().addDays(-5)
));

insert mockPoints;
System.debug('Successfully created ' + mockPoints.size() + ' mock pain points.');