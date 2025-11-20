public with sharing class LicenseService {
    
    // Define our tiers
    public static final String TIER_FREE = 'Free';
    public static final String TIER_PREMIUM = 'Premium';
    
    /**
     * @description Checks if the current org has a Premium license.
     * Uses a Protected Custom Setting that is hidden from the subscriber.
     */
    public static Boolean isPremium() {
        // If running in a Scratch Org or Sandbox during dev, default to Premium for testing
        // Remove '|| Test.isRunningTest()' before final security review if strictly testing gating logic
        if (isDevEnvironment()) {
            return true; 
        }

        BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
        
        // Default to Free if no setting exists
        if (license == null || String.isBlank(license.Status__c)) {
            return false;
        }
        
        return license.Status__c == TIER_PREMIUM;
    }
    
    /**
     * @description Throws an exception if the user tries to access a Premium feature without a license.
     * Use this at the top of any @AuraEnabled method that performs a write operation (Auto-Fix).
     */
    public static void enforcePremiumGate() {
        if (!isPremium()) {
            throw new AuraHandledException('This feature is available in BehaviorIQ Premium only. Please upgrade to access Auto-Fix capabilities.');
        }
    }

    /**
     * @description Helper to return the current status string for the UI
     */
    public static String getLicenseStatus() {
        if (isPremium()) {
            return TIER_PREMIUM;
        }
        return TIER_FREE;
    }

    // Internal helper to detect dev environments so you don't lock yourself out during dev
    private static Boolean isDevEnvironment() {
        Organization org = [SELECT IsSandbox, TrialExpirationDate FROM Organization LIMIT 1];
        // Logic can be adjusted: Assume Sandbox is Premium for testing, or strictly use the Custom Setting
        // For now, we return false to force you to create the Custom Setting record to test the flow.
        return false; 
    }
}