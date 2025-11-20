/**
 * @description Centralized service for managing BehaviorIQ application licensing and feature gating.
 * Uses Protected Hierarchy Custom Settings (BehaviorIQ_License__c) to distinguish Free vs. Premium tenants.
 */
public with sharing class LicenseService {

    public static final String STATUS_FREE = 'Free';
    public static final String STATUS_PREMIUM = 'Premium';

    /**
     * @description Determines if the current user/org has access to Premium features.
     * Uses getInstance() to checks User > Profile > Org defaults hierarchy.
     * Defaults to FALSE (Free) if no setting exists (Security by Default).
     * @return Boolean - True if Premium, False if Free.
     */
    public static Boolean isPremium() {
        BehaviorIQ_License__c license = BehaviorIQ_License__c.getInstance();
        
        if (license == null || license.Status__c == null) {
            return false;
        }
        
        return license.Status__c == STATUS_PREMIUM;
    }

    /**
     * @description Security Gate. Call this at the very top of any @AuraEnabled write operation.
     * @throws AuraHandledException if the user is not Premium.
     */
    public static void enforcePremiumGate() {
        if (!isPremium()) {
            String msg = 'Access Denied: This feature requires a BehaviorIQ Premium license.';
            // PATTERN FIX: Create exception, set message, then throw. 
            // This ensures the message is passed to the client/tests correctly.
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }
    }

    /**
     * @description Helper to get the current specific status string for UI badges.
     */
    public static String getLicenseStatus() {
        return isPremium() ? STATUS_PREMIUM : STATUS_FREE;
    }
}