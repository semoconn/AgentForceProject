@IsTest
private class LicenseServiceTest {

    @IsTest
    static void testDefaultIsFree() {
        // Ensure no settings exist
        delete [SELECT Id FROM BehaviorIQ_License__c];
        
        Boolean isPrem = LicenseService.isPremium();
        String status = LicenseService.getLicenseStatus();
        
        System.assertEquals(false, isPrem, 'Default should be Free');
        System.assertEquals('Free', status, 'Status string should be Free');
    }

    @IsTest
    static void testPremiumStatus() {
        BehaviorIQ_License__c setting = new BehaviorIQ_License__c(SetupOwnerId = UserInfo.getOrganizationId(), Status__c = 'Premium');
        insert setting;
        
        Boolean isPrem = LicenseService.isPremium();
        String status = LicenseService.getLicenseStatus();
        
        System.assertEquals(true, isPrem, 'Should detect Premium setting');
        System.assertEquals('Premium', status, 'Status string should be Premium');
    }
    
    @IsTest
    static void testEnforceGate() {
        // Ensure free
        delete [SELECT Id FROM BehaviorIQ_License__c];
        
        try {
            LicenseService.enforcePremiumGate();
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assert(true, 'Exception thrown as expected');
        }
    }
}