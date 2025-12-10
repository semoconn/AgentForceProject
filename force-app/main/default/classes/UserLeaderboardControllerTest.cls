@isTest
private class UserLeaderboardControllerTest {

    private static User testAdmin;
    private static User testStandardUser;

    @testSetup
    static void setupData() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        testAdmin = new User(
            Alias = 'badmin', Email='admin@behavioriq.test', 
            EmailEncodingKey='UTF-8', LastName='Admin', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = adminProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='admin@behavioriq.test' + System.currentTimeMillis()
        );
        insert testAdmin;

        testStandardUser = new User(
            Alias = 'bstd', Email='user@behavioriq.test', 
            EmailEncodingKey='UTF-8', LastName='Standard', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = stdProfile.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='user@behavioriq.test' + System.currentTimeMillis()
        );
        insert testStandardUser;

        System.runAs(testAdmin) {
            List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
            for(Integer i=0; i<5; i++) {
                logs.add(new Behavior_Log__c(
                    User__c = testStandardUser.Id,
                    Action_Name__c = 'Stale Opportunity',
                    Object_API_Name__c = 'Opportunity',
                    Behavior_Data__c = '{"daysOpen": 45}',
                    Timestamp__c = System.now()
                ));
            }
            logs.add(new Behavior_Log__c(
                User__c = testStandardUser.Id,
                Action_Name__c = 'Unassigned Lead',
                Object_API_Name__c = 'Lead',
                Timestamp__c = System.now()
            ));
            insert logs;
        }
    }

    @isTest
    static void testGetLeaderboardData_Premium() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        
        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result = UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertEquals(true, result.isPremium, 'Should be premium');
            System.assertNotEquals(0, result.entries.size(), 'Should return rows');
            
            UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
            System.assertEquals(false, entry.isAnonymized, 'Premium should not be anonymized');
            System.assertEquals('Standard', entry.userName, 'Premium should return real Name');
        }
    }

    @isTest
    static void testGetLeaderboardData_Free() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        
        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result = UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertEquals(false, result.isPremium, 'Should be free');
            System.assertNotEquals(0, result.entries.size(), 'Should return rows');
            
            UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
            System.assertEquals(true, entry.isAnonymized, 'Free tier should be anonymized');
            System.assert(entry.userName.startsWith('User'), 'Name should be masked');
        }
    }

    @isTest
    static void testSecurityEnforcement_NoAccess() {
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];
        
        System.runAs(standardUser) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            // With the new "bulletproof" controller, this should return empty list instead of throwing
            UserLeaderboardController.LeaderboardResult result = UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            // Depending on org permissions, isPremium might be true or false, but entries should be empty
            // because standard user likely has no access to behavior logs
            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(0, result.entries.size(), 'Should return 0 entries due to lack of permission');
        }
    }
}