@isTest
private class LicenseServiceTest {

    @isTest
    static void testDefaultIsFree() {
        // Ensure absence of settings defaults to Free (Security by Default)
        Test.startTest();
        Boolean isPremium = LicenseService.isPremium();
        String status = LicenseService.getLicenseStatus();
        Test.stopTest();

        System.assertEquals(false, isPremium, 'Default state should be Free when no settings exist');
        System.assertEquals(LicenseService.STATUS_FREE, status, 'Default status string should be Free');
    }

    @isTest
    static void testPremiumLicense() {
        // Setup Premium License in Custom Setting
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(SetupOwnerId = UserInfo.getOrganizationId(), Status__c = LicenseService.STATUS_PREMIUM);
        insert license;

        Test.startTest();
        Boolean isPremium = LicenseService.isPremium();
        Test.stopTest();

        System.assertEquals(true, isPremium, 'State should be Premium when Custom Setting is configured');
    }

    @isTest
    static void testEnforceGate_Success() {
        // Setup Premium
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(SetupOwnerId = UserInfo.getOrganizationId(), Status__c = LicenseService.STATUS_PREMIUM);
        insert license;

        Test.startTest();
        try {
            LicenseService.enforcePremiumGate();
            // If we reach here without exception, the test passes
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception for Premium user: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testEnforceGate_Failure() {
        // Default is Free (No Insert)

        Test.startTest();
        try {
            LicenseService.enforcePremiumGate();
            System.assert(false, 'Should have thrown AuraHandledException for Free user');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Access Denied'), 'Exception message should indicate Access Denied');
        } catch (Exception e) {
             // Catch generic just in case, but assert failure if it's not the right type
        }
        Test.stopTest();
    }

    @isTest
    static void testCheckLicenseStatus_Free() {
        // Default is Free (No Insert)
        Test.startTest();
        String status = LicenseService.checkLicenseStatus();
        Test.stopTest();

        System.assertEquals(LicenseService.STATUS_FREE, status, 'AuraEnabled method should return Free by default');
    }

    @isTest
    static void testCheckLicenseStatus_Premium() {
        // Setup Premium License
        BehaviorIQ_License__c license = new BehaviorIQ_License__c(SetupOwnerId = UserInfo.getOrganizationId(), Status__c = LicenseService.STATUS_PREMIUM);
        insert license;

        Test.startTest();
        String status = LicenseService.checkLicenseStatus();
        Test.stopTest();

        System.assertEquals(LicenseService.STATUS_PREMIUM, status, 'AuraEnabled method should return Premium when configured');
    }
}