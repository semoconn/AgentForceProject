// Verify pattern detection on FREE tier
// Expected: Only FREE tier patterns (Contact_Data_Gap, Stale_Case_14, Stale_Case_30, Weekend_Case_Spike)
// Premium patterns should NOT appear

// Get current license tier
String tier = LicenseService.getLicenseStatus();
Boolean isPremium = LicenseService.isPremium();
System.debug('Current License Tier: ' + tier + ' | isPremium: ' + isPremium);

// Count all pain points
List<Identified_Pain_Point__c> allPainPoints = [SELECT Id, Name, Unique_Key__c, Object_API_Name__c, Occurrences__c
                                                  FROM Identified_Pain_Point__c
                                                  ORDER BY Unique_Key__c];
System.debug('Total Pain Points Found: ' + allPainPoints.size());

// Group by pattern (using Unique_Key__c which contains the pattern name)
Map<String, Integer> patternCounts = new Map<String, Integer>();
for(Identified_Pain_Point__c pp : allPainPoints) {
    String pattern = pp.Unique_Key__c;
    if(!patternCounts.containsKey(pattern)) {
        patternCounts.put(pattern, 0);
    }
    patternCounts.put(pattern, patternCounts.get(pattern) + 1);
}

System.debug('=== PATTERNS DETECTED ===');
for(String pattern : patternCounts.keySet()) {
    System.debug('Pattern: ' + pattern + ' | Count: ' + patternCounts.get(pattern));
}

// Define FREE tier patterns (expected)
Set<String> freeTierPatterns = new Set<String>{
    'Contact_Data_Gap',
    'Stale_Case_14',
    'Stale_Case_30',
    'Weekend_Case_Spike'
};

// Define Premium patterns (should NOT be found on FREE tier)
Set<String> premiumPatterns = new Set<String>{
    'Lead_Hoarding',
    'Unassigned_Lead_48',
    'High_Value_Ghosting',
    'Orphan_Opportunity',
    'Stale_Opp_90',
    'Contract_Expiry_Red_Zone',
    'Orphan_Contact',
    'Orphan_Case',
    'Duplicate_Accounts'
};

System.debug('=== VERIFICATION ===');
System.debug('Expected FREE tier patterns: ' + freeTierPatterns);
System.debug('Premium patterns (should NOT appear): ' + premiumPatterns);

// Check for unexpected premium patterns
Boolean foundPremium = false;
for(String pattern : patternCounts.keySet()) {
    if(premiumPatterns.contains(pattern)) {
        System.debug('ERROR: Premium pattern found on FREE tier: ' + pattern);
        foundPremium = true;
    }
}

if(!foundPremium) {
    System.debug('SUCCESS: No Premium patterns detected on FREE tier!');
} else {
    System.debug('FAILURE: Premium patterns were detected on FREE tier - license gating issue!');
}
