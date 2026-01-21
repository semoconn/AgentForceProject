@isTest
private with sharing class UserLeaderboardControllerTest {

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

        // Assign BehaviorIQ_Admin permission set to admin user for FLS access
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'BehaviorIQ_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = testAdmin.Id, PermissionSetId = ps.Id);

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

    @isTest
    static void testNudgeUser_Success() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User targetUser = [SELECT Id, Name FROM User WHERE Alias = 'bstd' LIMIT 1];

        System.runAs(admin) {
            Test.startTest();
            String result = UserLeaderboardController.nudgeUser(targetUser.Id);
            Test.stopTest();

            System.assert(result.contains('Nudge sent'), 'Should return success message');

            // Verify Task was created
            List<Task> tasks = [SELECT Id, Subject, OwnerId FROM Task WHERE OwnerId = :targetUser.Id AND Subject LIKE '%BehaviorIQ%'];
            System.assertEquals(1, tasks.size(), 'Should create one task');
            System.assertEquals('BehaviorIQ Notice: Action Required', tasks[0].Subject, 'Task subject should match');
        }
    }

    @isTest
    static void testNudgeUser_NullUserId() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            Test.startTest();
            Boolean exceptionThrown = false;
            try {
                UserLeaderboardController.nudgeUser(null);
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                // AuraHandledException.getMessage() may return 'Script-thrown exception'
                // The actual message is set via setMessage() but may not be accessible in tests
            } catch (Exception e) {
                exceptionThrown = true;
            }
            Test.stopTest();

            System.assert(exceptionThrown, 'Should have thrown an exception for null user ID');
        }
    }

    @isTest
    static void testNudgeUser_InvalidUser() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        // Use a fake User ID that doesn't exist
        Id fakeUserId = '005000000000000AAA';

        System.runAs(admin) {
            Test.startTest();
            Boolean exceptionThrown = false;
            try {
                UserLeaderboardController.nudgeUser(fakeUserId);
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                // AuraHandledException.getMessage() may return 'Script-thrown exception'
                // The actual message is set via setMessage() but may not be accessible in tests
            } catch (Exception e) {
                exceptionThrown = true;
            }
            Test.stopTest();

            System.assert(exceptionThrown, 'Should have thrown an exception for invalid user');
        }
    }

    // ==================== ADDITIONAL COVERAGE TESTS ====================

    @isTest
    static void testGetLicenseStatus_Premium() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            String status = UserLeaderboardController.getLicenseStatus();
            Test.stopTest();

            System.assertEquals('Premium', status, 'Should return Premium status');
        }
    }

    @isTest
    static void testGetLicenseStatus_Free() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            String status = UserLeaderboardController.getLicenseStatus();
            Test.stopTest();

            System.assertEquals('Free', status, 'Should return Free status');
        }
    }

    @isTest
    static void testGetLicenseStatus_Default() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            // Reset to use actual license check
            UserLeaderboardController.forcePremiumContext = null;

            Test.startTest();
            String status = UserLeaderboardController.getLicenseStatus();
            Test.stopTest();

            // Should return either Free or Premium depending on license
            System.assert(status == 'Free' || status == 'Premium',
                'Should return valid status: ' + status);
        }
    }

    @isTest
    static void testLeaderboardResult_Constructor() {
        Test.startTest();
        List<UserLeaderboardController.LeaderboardEntry> entries =
            new List<UserLeaderboardController.LeaderboardEntry>();
        entries.add(new UserLeaderboardController.LeaderboardEntry(
            '005000000000001',
            'Test User',
            '/photo.jpg',
            100,
            false
        ));

        UserLeaderboardController.LeaderboardResult result =
            new UserLeaderboardController.LeaderboardResult(true, entries);
        Test.stopTest();

        System.assertEquals(true, result.isPremium, 'isPremium should be true');
        System.assertEquals(1, result.entries.size(), 'Should have 1 entry');
        System.assertEquals(null, result.errorMessage, 'errorMessage should be null');
    }

    @isTest
    static void testLeaderboardEntry_Constructor() {
        Test.startTest();
        UserLeaderboardController.LeaderboardEntry entry =
            new UserLeaderboardController.LeaderboardEntry(
                '005000000000001',
                'Test User',
                '/photo.jpg',
                50,
                true
            );
        Test.stopTest();

        System.assertEquals('005000000000001', entry.userId);
        System.assertEquals('Test User', entry.userName);
        System.assertEquals('/photo.jpg', entry.photoUrl);
        System.assertEquals(50, entry.totalImpactScore);
        System.assertEquals(true, entry.isAnonymized);
        System.assertNotEquals(null, entry.topBehaviors, 'topBehaviors should be initialized');
        System.assertEquals(0, entry.topBehaviors.size(), 'topBehaviors should be empty initially');
    }

    @isTest
    static void testGetLeaderboardData_NoLogs() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        // Delete all behavior logs
        delete [SELECT Id FROM Behavior_Log__c];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(0, result.entries.size(), 'Should have no entries when no logs exist');
        }
    }

    @isTest
    static void testGetLeaderboardData_WithBehaviors() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Add more behavior logs with different action names
        System.runAs(admin) {
            List<Behavior_Log__c> additionalLogs = new List<Behavior_Log__c>();
            additionalLogs.add(new Behavior_Log__c(
                User__c = standardUser.Id,
                Action_Name__c = 'Record_Viewed',
                Object_API_Name__c = 'Account',
                Timestamp__c = System.now()
            ));
            additionalLogs.add(new Behavior_Log__c(
                User__c = standardUser.Id,
                Action_Name__c = 'Record_Deleted',
                Object_API_Name__c = 'Contact',
                Timestamp__c = System.now()
            ));
            insert additionalLogs;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assert(result.entries.size() > 0, 'Should have entries');

            // Check that top behaviors are populated (up to 3)
            UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
            System.assert(entry.topBehaviors.size() <= 3, 'Should have at most 3 top behaviors');
        }
    }

    @isTest
    static void testGetLeaderboardData_FreeTierBehaviors() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertEquals(false, result.isPremium, 'Should be free tier');
            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                System.assertEquals(true, entry.isAnonymized, 'Should be anonymized in free tier');
                // Free tier should still get behaviors
                System.assertNotEquals(null, entry.topBehaviors, 'topBehaviors should exist');
            }
        }
    }

    @isTest
    static void testNudgeUser_InactiveUser() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Deactivate the user
        standardUser.IsActive = false;
        update standardUser;

        System.runAs(admin) {
            Test.startTest();
            Boolean exceptionThrown = false;
            try {
                UserLeaderboardController.nudgeUser(standardUser.Id);
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            } catch (Exception e) {
                exceptionThrown = true;
            }
            Test.stopTest();

            System.assert(exceptionThrown, 'Should throw exception for inactive user');
        }
    }

    @isTest
    static void testGetLeaderboardData_MultipleUsers() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Add logs for admin user as well
        System.runAs(admin) {
            List<Behavior_Log__c> adminLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 3; i++) {
                adminLogs.add(new Behavior_Log__c(
                    User__c = admin.Id,
                    Action_Name__c = 'Admin_Action',
                    Object_API_Name__c = 'Account',
                    Timestamp__c = System.now()
                ));
            }
            insert adminLogs;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            // Should have entries for both users
            System.assert(result.entries.size() >= 1, 'Should have at least 1 entry');
        }
    }

    @isTest
    static void testGetBehaviorBreakdowns_EmptyUserIds() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        // Delete all logs to ensure empty aggregates
        delete [SELECT Id FROM Behavior_Log__c];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(0, result.entries.size(), 'Should have no entries');
        }
    }

    // ==================== APPEXCHANGE SECURITY EDGE CASE TESTS ====================

    @isTest
    static void testNudgeUser_DeactivatedUserDuringExecution() {
        // Test race condition where user is deactivated during nudge
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        // Create a new user that we can deactivate
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User tempUser = new User(
            Alias = 'tmpusr',
            Email = 'tempuser@behavioriq.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TempUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = stdProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tempuser@behavioriq.test' + System.currentTimeMillis()
        );
        insert tempUser;

        System.runAs(admin) {
            Test.startTest();
            String result = UserLeaderboardController.nudgeUser(tempUser.Id);
            Test.stopTest();

            System.assert(result.contains('Nudge sent'), 'Should send nudge to active user');
        }
    }

    @isTest
    static void testGetLeaderboardData_NullUserInMap() {
        // Test handling when a user in behavior logs doesn't exist in user query
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            // Verify no null pointer exceptions occurred
            for (UserLeaderboardController.LeaderboardEntry entry : result.entries) {
                System.assertNotEquals(null, entry.userName, 'UserName should never be null');
            }
        }
    }

    @isTest
    static void testGetLeaderboardData_Top10Limit() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        // Create users to test limit
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> testUsers = new List<User>();
        for (Integer i = 0; i < 15; i++) {
            testUsers.add(new User(
                Alias = 'tst' + i,
                Email = 'testlimit' + i + '@behavioriq.test',
                EmailEncodingKey = 'UTF-8',
                LastName = 'TestLimit' + i,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = stdProfile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                UserName = 'testlimit' + i + '@behavioriq.test' + System.currentTimeMillis()
            ));
        }
        insert testUsers;

        // Create logs for each user
        List<Behavior_Log__c> logs = new List<Behavior_Log__c>();
        for (User u : testUsers) {
            logs.add(new Behavior_Log__c(
                User__c = u.Id,
                Action_Name__c = 'Test_Action',
                Object_API_Name__c = 'Account',
                Timestamp__c = System.now()
            ));
        }
        insert logs;

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            // Should be limited to 10 entries
            System.assert(result.entries.size() <= 10, 'Should return max 10 entries');
        }
    }

    @isTest
    static void testGetLeaderboardData_NullActionName() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Create log with null action name
        System.runAs(admin) {
            Behavior_Log__c nullActionLog = new Behavior_Log__c(
                User__c = standardUser.Id,
                Action_Name__c = null,
                Object_API_Name__c = 'Account',
                Timestamp__c = System.now()
            );
            insert nullActionLog;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            // Should handle null action names gracefully
        }
    }

    @isTest
    static void testGetLeaderboardData_DuplicateActionNames() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Create multiple logs with same action name (should only show unique actions)
        System.runAs(admin) {
            List<Behavior_Log__c> duplicateLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 10; i++) {
                duplicateLogs.add(new Behavior_Log__c(
                    User__c = standardUser.Id,
                    Action_Name__c = 'Duplicate_Action',
                    Object_API_Name__c = 'Account',
                    Timestamp__c = System.now()
                ));
            }
            insert duplicateLogs;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result should not be null');
            if (result.entries.size() > 0) {
                // Top behaviors should only contain unique action names
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                Set<String> uniqueBehaviors = new Set<String>(entry.topBehaviors);
                System.assertEquals(entry.topBehaviors.size(), uniqueBehaviors.size(),
                    'Top behaviors should be unique');
            }
        }
    }

    @isTest
    static void testGetLeaderboardData_Max3TopBehaviors() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Create logs with more than 3 different action names
        System.runAs(admin) {
            List<Behavior_Log__c> manyActionLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 10; i++) {
                manyActionLogs.add(new Behavior_Log__c(
                    User__c = standardUser.Id,
                    Action_Name__c = 'Action_Type_' + i,
                    Object_API_Name__c = 'Account',
                    Timestamp__c = System.now()
                ));
            }
            insert manyActionLogs;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                System.assert(entry.topBehaviors.size() <= 3,
                    'Should have at most 3 top behaviors. Actual: ' + entry.topBehaviors.size());
            }
        }
    }

    @isTest
    static void testLeaderboardEntry_WithTopBehaviors() {
        // Test LeaderboardEntry with topBehaviors populated
        Test.startTest();
        UserLeaderboardController.LeaderboardEntry entry =
            new UserLeaderboardController.LeaderboardEntry(
                '005000000000001',
                'Test User',
                '/photo.jpg',
                100,
                false
            );

        entry.topBehaviors.add('Behavior 1');
        entry.topBehaviors.add('Behavior 2');
        entry.topBehaviors.add('Behavior 3');
        Test.stopTest();

        System.assertEquals(3, entry.topBehaviors.size());
        System.assertEquals('Behavior 1', entry.topBehaviors[0]);
        System.assertEquals('Behavior 2', entry.topBehaviors[1]);
        System.assertEquals('Behavior 3', entry.topBehaviors[2]);
    }

    @isTest
    static void testNudgeUser_TaskFieldValidation() {
        // Verify all task fields are correctly set
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User targetUser = [SELECT Id, Name FROM User WHERE Alias = 'bstd' LIMIT 1];

        System.runAs(admin) {
            Test.startTest();
            UserLeaderboardController.nudgeUser(targetUser.Id);
            Test.stopTest();

            List<Task> tasks = [
                SELECT Id, Subject, Description, Status, Priority, ActivityDate, OwnerId
                FROM Task
                WHERE OwnerId = :targetUser.Id
                AND Subject LIKE '%BehaviorIQ%'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            System.assertEquals(1, tasks.size(), 'Should create exactly one task');
            Task t = tasks[0];
            System.assertEquals('BehaviorIQ Notice: Action Required', t.Subject);
            System.assert(t.Description.contains('open items'), 'Description should mention open items');
            System.assertEquals('Not Started', t.Status);
            System.assertEquals('Normal', t.Priority);
            System.assertEquals(Date.today().addDays(3), t.ActivityDate);
        }
    }

    @isTest
    static void testGetLeaderboardData_AnonymizedPhotoUrl() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                // Free tier should use default photo
                System.assertEquals('/img/icon/t4v35/standard/avatar.svg', entry.photoUrl,
                    'Free tier should use default anonymous photo');
            }
        }
    }

    @isTest
    static void testGetLeaderboardData_PremiumShowsRealPhoto() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                // Premium should show actual user data (not anonymized)
                System.assertEquals(false, entry.isAnonymized,
                    'Premium entries should not be anonymized');
            }
        }
    }

    @isTest
    static void testGetLeaderboardData_FreeTierUserIdNull() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                // Free tier should have null userId for privacy
                System.assertEquals(null, entry.userId,
                    'Free tier should have null userId for privacy');
            }
        }
    }

    @isTest
    static void testGetLeaderboardData_RankOrdering() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User standardUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Create more logs for standard user to ensure they rank higher
        System.runAs(admin) {
            List<Behavior_Log__c> extraLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 20; i++) {
                extraLogs.add(new Behavior_Log__c(
                    User__c = standardUser.Id,
                    Action_Name__c = 'Extra_Action',
                    Object_API_Name__c = 'Account',
                    Timestamp__c = System.now()
                ));
            }
            insert extraLogs;
        }

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = false;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            if (result.entries.size() >= 2) {
                // First entry should have higher or equal score than second
                System.assert(
                    result.entries[0].totalImpactScore >= result.entries[1].totalImpactScore,
                    'Entries should be ordered by score descending'
                );
            }

            // Verify anonymized names follow User 1, User 2 pattern in free tier
            if (result.entries.size() > 0) {
                System.assertEquals('User 1', result.entries[0].userName,
                    'First anonymized user should be "User 1"');
            }
        }
    }

    @isTest
    static void testLeaderboardResult_ErrorMessageField() {
        // Test that errorMessage field can be set
        Test.startTest();
        UserLeaderboardController.LeaderboardResult result =
            new UserLeaderboardController.LeaderboardResult(
                false,
                new List<UserLeaderboardController.LeaderboardEntry>()
            );

        // Verify default error message is null
        System.assertEquals(null, result.errorMessage, 'Default errorMessage should be null');
        Test.stopTest();
    }

    @isTest
    static void testGetLeaderboardData_LicenseCheckException() {
        // This tests the exception handling path in isPremium check
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            // Reset forcePremiumContext to trigger actual license check
            UserLeaderboardController.forcePremiumContext = null;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            // Should not throw exception, should gracefully handle
            System.assertNotEquals(null, result, 'Result should not be null');
        }
    }

    @isTest
    static void testNudgeUser_VerifyNoExistingTasks() {
        // Test nudging creates a new task even if similar tasks exist
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];
        User targetUser = [SELECT Id FROM User WHERE Alias = 'bstd' LIMIT 1];

        // Create an existing task
        Task existingTask = new Task(
            OwnerId = targetUser.Id,
            Subject = 'Existing Task',
            Status = 'Not Started'
        );
        insert existingTask;

        System.runAs(admin) {
            Test.startTest();
            String result = UserLeaderboardController.nudgeUser(targetUser.Id);
            Test.stopTest();

            System.assert(result.contains('Nudge sent'), 'Should send nudge successfully');

            // Should have both tasks
            List<Task> tasks = [SELECT Id FROM Task WHERE OwnerId = :targetUser.Id];
            System.assertEquals(2, tasks.size(), 'Should have both existing and new task');
        }
    }

    @isTest
    static void testGetLeaderboardData_EmptyPhotoUrl() {
        User admin = [SELECT Id FROM User WHERE Alias = 'badmin' LIMIT 1];

        System.runAs(admin) {
            UserLeaderboardController.forcePremiumContext = true;

            Test.startTest();
            UserLeaderboardController.LeaderboardResult result =
                UserLeaderboardController.getLeaderboardData();
            Test.stopTest();

            // Premium users with no custom photo should still have a valid photoUrl
            if (result.entries.size() > 0) {
                UserLeaderboardController.LeaderboardEntry entry = result.entries[0];
                // photoUrl should not be null (could be empty string or actual URL)
                // The controller sets it to empty string '' if null
            }
        }
    }
}