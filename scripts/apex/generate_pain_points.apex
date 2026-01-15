// BehaviorIQ Mock Pain Points Generator - Queries REAL records
// Run this in Anonymous Apex to create pain points with actual record IDs

// First, delete existing pain points to start fresh
delete [SELECT Id FROM Identified_Pain_Point__c];

List<Identified_Pain_Point__c> painPoints = new List<Identified_Pain_Point__c>();

// 1. High Value Ghosting - Opportunities over $50K with no recent activity
List<Opportunity> ghostingOpps = [
    SELECT Id, Amount FROM Opportunity
    WHERE Amount > 50000 AND (LastActivityDate < LAST_N_DAYS:14 OR LastActivityDate = null)
    AND IsClosed = false LIMIT 50
];
if (!ghostingOpps.isEmpty()) {
    List<String> oppIds = new List<String>();
    Decimal totalAmount = 0;
    for (Opportunity o : ghostingOpps) {
        oppIds.add(o.Id);
        totalAmount += o.Amount != null ? o.Amount : 0;
    }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'High-Value Opportunities Going Dark',
        Object_API_Name__c = 'Opportunity',
        Status__c = 'New',
        Description__c = 'Opportunities over $50K with no activity in 14+ days are at risk of being lost.',
        Occurrences__c = ghostingOpps.size(),
        Impact_Score__c = totalAmount > 0 ? totalAmount : ghostingOpps.size() * 50000,
        Example_Records__c = JSON.serialize(oppIds),
        Unique_Key__c = 'High_Value_Ghosting',
        Cost_Per_Incident__c = 2500
    ));
}

// 2. Stale Support Cases (14 days) - Cases with no updates
List<Case> staleCases14 = [
    SELECT Id FROM Case WHERE Status != 'Closed'
    AND LastModifiedDate < LAST_N_DAYS:14 LIMIT 50
];
if (!staleCases14.isEmpty()) {
    List<String> caseIds = new List<String>();
    for (Case c : staleCases14) { caseIds.add(c.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Stale Support Cases',
        Object_API_Name__c = 'Case',
        Status__c = 'New',
        Description__c = 'Open cases with no updates in 14+ days are causing customer dissatisfaction.',
        Occurrences__c = staleCases14.size(),
        Impact_Score__c = staleCases14.size() * 500,
        Example_Records__c = JSON.serialize(caseIds),
        Unique_Key__c = 'Stale_Case_14',
        Cost_Per_Incident__c = 500
    ));
}

// 3. Escalation Storm - Cases escalated without proper triage
List<Case> escalatedCases = [
    SELECT Id FROM Case WHERE IsEscalated = true
    AND Priority != 'High' AND Status != 'Closed' LIMIT 50
];
if (!escalatedCases.isEmpty()) {
    List<String> caseIds = new List<String>();
    for (Case c : escalatedCases) { caseIds.add(c.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Escalation Storm',
        Object_API_Name__c = 'Case',
        Status__c = 'New',
        Description__c = 'Cases escalated to management without proper tier-1 troubleshooting.',
        Occurrences__c = escalatedCases.size(),
        Impact_Score__c = escalatedCases.size() * 1000,
        Example_Records__c = JSON.serialize(caseIds),
        Unique_Key__c = 'Premature_Escalation',
        Cost_Per_Incident__c = 1000
    ));
}

// 4. Missing Contact Info - Contacts without email or phone
List<Contact> contactsWithGaps = [
    SELECT Id FROM Contact WHERE (Email = null OR Phone = null)
    AND OwnerId != null LIMIT 100
];
if (!contactsWithGaps.isEmpty()) {
    List<String> contactIds = new List<String>();
    for (Contact c : contactsWithGaps) { contactIds.add(c.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Missing Contact Info',
        Object_API_Name__c = 'Contact',
        Status__c = 'New',
        Description__c = 'Key contacts missing email or phone, blocking outreach campaigns.',
        Occurrences__c = contactsWithGaps.size(),
        Impact_Score__c = contactsWithGaps.size() * 50,
        Example_Records__c = JSON.serialize(contactIds),
        Unique_Key__c = 'Contact_Data_Gap',
        Cost_Per_Incident__c = 50
    ));
}

// 5. Lead Hoarding - Unworked leads sitting too long
List<Lead> hoardedLeads = [
    SELECT Id FROM Lead WHERE Status = 'Open - Not Contacted'
    AND CreatedDate < LAST_N_DAYS:5 AND IsConverted = false LIMIT 100
];
if (!hoardedLeads.isEmpty()) {
    List<String> leadIds = new List<String>();
    for (Lead l : hoardedLeads) { leadIds.add(l.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Lead Hoarding Detected',
        Object_API_Name__c = 'Lead',
        Status__c = 'New',
        Description__c = 'Sales reps holding unworked leads are bottlenecking the pipeline.',
        Occurrences__c = hoardedLeads.size(),
        Impact_Score__c = hoardedLeads.size() * 100,
        Example_Records__c = JSON.serialize(leadIds),
        Unique_Key__c = 'Lead_Hoarding',
        Cost_Per_Incident__c = 100
    ));
}

// 6. Pipeline Zombies - Opportunities stuck in same stage for 90+ days
List<Opportunity> staleOpps = [
    SELECT Id, Amount FROM Opportunity WHERE IsClosed = false
    AND LastStageChangeDate < LAST_N_DAYS:90 LIMIT 50
];
if (!staleOpps.isEmpty()) {
    List<String> oppIds = new List<String>();
    Decimal totalAmount = 0;
    for (Opportunity o : staleOpps) {
        oppIds.add(o.Id);
        totalAmount += o.Amount != null ? o.Amount : 0;
    }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Pipeline Zombies',
        Object_API_Name__c = 'Opportunity',
        Status__c = 'New',
        Description__c = 'Opportunities stuck in same stage for 90+ days are inflating pipeline forecasts.',
        Occurrences__c = staleOpps.size(),
        Impact_Score__c = totalAmount > 0 ? totalAmount : staleOpps.size() * 500,
        Example_Records__c = JSON.serialize(oppIds),
        Unique_Key__c = 'Stale_Opp_90',
        Cost_Per_Incident__c = 500
    ));
}

// 7. Unassigned Hot Leads - Leads without assignment for 48+ hours
List<Lead> unassignedLeads = [
    SELECT Id FROM Lead
    WHERE CreatedDate < LAST_N_DAYS:2
    AND Status = 'Open - Not Contacted'
    AND IsConverted = false
    LIMIT 50
];
if (!unassignedLeads.isEmpty()) {
    List<String> leadIds = new List<String>();
    for (Lead l : unassignedLeads) { leadIds.add(l.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Unassigned Hot Leads',
        Object_API_Name__c = 'Lead',
        Status__c = 'New',
        Description__c = 'New leads sitting in queue without assignment for 48+ hours.',
        Occurrences__c = unassignedLeads.size(),
        Impact_Score__c = unassignedLeads.size() * 300,
        Example_Records__c = JSON.serialize(leadIds),
        Unique_Key__c = 'Unassigned_Lead_48',
        Cost_Per_Incident__c = 300
    ));
}

// 8. Frequent Flyer Churn Risk - Hot accounts with high priority open cases
List<Case> frequentFlyerCases = [
    SELECT Id FROM Case
    WHERE Priority = 'High'
    AND IsClosed = false
    LIMIT 50
];
if (!frequentFlyerCases.isEmpty()) {
    List<String> caseIds = new List<String>();
    for (Case c : frequentFlyerCases) { caseIds.add(c.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Frequent Flyer (Churn Risk)',
        Object_API_Name__c = 'Case',
        Status__c = 'New',
        Description__c = 'Hot accounts with multiple high-priority cases indicate churn risk.',
        Occurrences__c = frequentFlyerCases.size(),
        Impact_Score__c = frequentFlyerCases.size() * 75,
        Example_Records__c = JSON.serialize(caseIds),
        Unique_Key__c = 'Frequent_Flyer_Churn',
        Cost_Per_Incident__c = 75
    ));
}

// 9. Weekend Cases Spike (Dismissed example - expected seasonal pattern)
List<Case> weekendCases = [
    SELECT Id FROM Case
    WHERE CreatedDate = LAST_WEEK
    AND Status != 'Closed'
    LIMIT 50
];
if (!weekendCases.isEmpty()) {
    List<String> caseIds = new List<String>();
    for (Case c : weekendCases) { caseIds.add(c.Id); }
    painPoints.add(new Identified_Pain_Point__c(
        Name = 'Weekend Cases Spike',
        Object_API_Name__c = 'Case',
        Status__c = 'Dismissed',
        Description__c = 'Weekend case volume increase - expected seasonal pattern, no action needed.',
        Occurrences__c = weekendCases.size(),
        Impact_Score__c = weekendCases.size() * 50,
        Example_Records__c = JSON.serialize(caseIds),
        Unique_Key__c = 'Weekend_Case_Spike',
        Cost_Per_Incident__c = 50
    ));
}

// Insert all pain points
if (!painPoints.isEmpty()) {
    insert painPoints;
    System.debug('Created ' + painPoints.size() + ' pain points with real record IDs');

    // Output summary
    for (Identified_Pain_Point__c pp : painPoints) {
        System.debug(pp.Name + ' | ' + pp.Object_API_Name__c + ' | ' + pp.Status__c + ' | Records: ' + pp.Occurrences__c + ' | $' + pp.Impact_Score__c);
    }
} else {
    System.debug('No matching records found in org. Ensure you have sample data for Cases, Opportunities, Leads, and Contacts.');
}
