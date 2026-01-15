// Reset Data Script for BehaviorIQ DevHub
// 1. Delete existing Pain Points
delete [SELECT Id FROM Identified_Pain_Point__c];

// 2. Create 10 Pain Points
List<Identified_Pain_Point__c> painPoints = new List<Identified_Pain_Point__c>();

// 1. High Value Ghosting - Opportunities (High severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'High-Value Opportunities Going Dark',
    Object_API_Name__c = 'Opportunity',
    Status__c = 'New',
    Description__c = 'Opportunities over $50K with no activity in 30+ days are at risk of being lost to competitors.',
    Occurrences__c = 8,
    Impact_Score__c = 425000,
    Unique_Key__c = 'High_Value_Ghosting'
));

// 2. Stale Cases - Cases (Medium severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Stale Support Cases',
    Object_API_Name__c = 'Case',
    Status__c = 'New',
    Description__c = 'Open cases with no updates in 14+ days are causing customer dissatisfaction.',
    Occurrences__c = 23,
    Impact_Score__c = 11500,
    Unique_Key__c = 'Stale_Case_14'
));

// 3. Lead Hoarding - Leads (Medium severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Lead Hoarding Detected',
    Object_API_Name__c = 'Lead',
    Status__c = 'New',
    Description__c = 'Sales reps holding 50+ unworked leads are bottlenecking the pipeline.',
    Occurrences__c = 156,
    Impact_Score__c = 31200,
    Unique_Key__c = 'Lead_Hoarding'
));

// 4. Frequent Flyer Churn Risk - Accounts (High severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Frequent Flyer Churn Risk',
    Object_API_Name__c = 'Account',
    Status__c = 'New',
    Description__c = 'High-value accounts showing declining engagement patterns indicating churn risk.',
    Occurrences__c = 5,
    Impact_Score__c = 275000,
    Unique_Key__c = 'Frequent_Flyer_Churn'
));

// 5. Unassigned Leads - Leads (Low severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Unassigned Hot Leads',
    Object_API_Name__c = 'Lead',
    Status__c = 'New',
    Description__c = 'New leads sitting in queue without assignment for 48+ hours.',
    Occurrences__c = 12,
    Impact_Score__c = 3600,
    Unique_Key__c = 'Unassigned_Lead_48'
));

// 6. Stale Opportunities 90 days - Opportunities (High severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Pipeline Zombies',
    Object_API_Name__c = 'Opportunity',
    Status__c = 'New',
    Description__c = 'Opportunities stuck in same stage for 90+ days are inflating pipeline forecasts.',
    Occurrences__c = 15,
    Impact_Score__c = 180000,
    Unique_Key__c = 'Stale_Opp_90'
));

// 7. Escalated Cases - Cases (Medium severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Escalation Storm',
    Object_API_Name__c = 'Case',
    Status__c = 'New',
    Description__c = 'Cases escalated to management without proper tier-1 troubleshooting.',
    Occurrences__c = 8,
    Impact_Score__c = 8000,
    Unique_Key__c = 'Premature_Escalation'
));

// 8. Contact Data Quality - Contacts (Low severity)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Missing Contact Info',
    Object_API_Name__c = 'Contact',
    Status__c = 'New',
    Description__c = 'Key contacts missing email or phone, blocking outreach campaigns.',
    Occurrences__c = 89,
    Impact_Score__c = 4450,
    Unique_Key__c = 'Contact_Data_Gap'
));

// 9. Already Resolved - Opportunities (for Completed tab testing)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Q4 Pipeline Cleanup',
    Object_API_Name__c = 'Opportunity',
    Status__c = 'Resolved',
    Description__c = 'Stale Q4 opportunities that were cleaned up during quarterly review.',
    Occurrences__c = 6,
    Impact_Score__c = 72000,
    Unique_Key__c = 'Q4_Cleanup_Resolved'
));

// 10. Dismissed Item - Cases (for Dismissed tab testing)
painPoints.add(new Identified_Pain_Point__c(
    Name = 'Weekend Cases Spike',
    Object_API_Name__c = 'Case',
    Status__c = 'Dismissed',
    Description__c = 'Weekend case volume increase - determined to be expected seasonal pattern.',
    Occurrences__c = 45,
    Impact_Score__c = 2250,
    Unique_Key__c = 'Weekend_Case_Spike'
));

insert painPoints;
System.debug('Reset 10 pain points.');

// 3. Ensure License is Premium
BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
if (license == null) {
    license = new BehaviorIQ_License__c();
}
license.Status__c = 'Premium';
upsert license;
System.debug('Ensured License is Premium.');
