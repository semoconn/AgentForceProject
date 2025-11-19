@isTest
private class PatternAnalysisServiceTest {

    @TestSetup
    static void setupUsersAndPermissions() {
        Profile pStd = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        
        Profile pMin = pStd;
        List<Profile> minProfiles = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        if (!minProfiles.isEmpty()) {
            pMin = minProfiles[0];
        } else {
            List<Profile> roProfiles = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
            if (!roProfiles.isEmpty()) pMin = roProfiles[0];
        }

        String uniqueifier = String.valueOf(System.currentTimeMillis());

        List<User> usersToInsert = new List<User>{
            new User(Alias = 'testpas', Email='testpas' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', LocaleSidKey='en_US', ProfileId = pStd.Id, TimeZoneSidKey='America/Los_Angeles', UserName='testpas' + uniqueifier + '@testorg.com'),
            new User(Alias = 'nodelete', Email='nodelete' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8', LastName='NoDelete', LanguageLocaleKey='en_US', LocaleSidKey='en_US', ProfileId = pStd.Id, TimeZoneSidKey='America/Los_Angeles', UserName='nodelete' + uniqueifier + '@testorg.com'),
            new User(Alias = 'nocreate', Email='nocreate' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8', LastName='NoCreate', LanguageLocaleKey='en_US', LocaleSidKey='en_US', ProfileId = pMin.Id, TimeZoneSidKey='America/Los_Angeles', UserName='nocreate' + uniqueifier + '@testorg.com')
        };
        insert usersToInsert;

        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];
        User noDeleteUser = [SELECT Id FROM User WHERE Alias = 'nodelete' LIMIT 1];
        User noCreateUser = [SELECT Id FROM User WHERE Alias = 'nocreate' LIMIT 1];

        // Mock Admin Set
        PermissionSet psMockAdmin = new PermissionSet(Name = 'Mock_Admin_' + uniqueifier, Label = 'Mock Admin');
        insert psMockAdmin;
        
        insert new ObjectPermissions(ParentId = psMockAdmin.Id, SObjectType = 'Behavior_Log__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new ObjectPermissions(ParentId = psMockAdmin.Id, SObjectType = 'System_Health_Log__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
                                     
        insert new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psMockAdmin.Id);
        insert new PermissionSetAssignment(AssigneeId = noDeleteUser.Id, PermissionSetId = psMockAdmin.Id);

        // Batch Runner Set (No Health Log Create)
        PermissionSet psBatchRunner = new PermissionSet(Name = 'Batch_Runner_' + uniqueifier, Label = 'Batch Runner');
        insert psBatchRunner;
        insert new ObjectPermissions(ParentId = psBatchRunner.Id, SObjectType = 'Behavior_Log__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new PermissionSetAssignment(AssigneeId = noCreateUser.Id, PermissionSetId = psBatchRunner.Id);

        // Analyzer Access Set
        PermissionSet psAnalyzerAccess = new PermissionSet(Name = 'Analyzer_Access_' + uniqueifier, Label = 'Analyzer Access');
        insert psAnalyzerAccess;

        insert new ObjectPermissions(ParentId = psAnalyzerAccess.Id, SObjectType = 'Opportunity', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new ObjectPermissions(ParentId = psAnalyzerAccess.Id, SObjectType = 'Case', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new ObjectPermissions(ParentId = psAnalyzerAccess.Id, SObjectType = 'Lead', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new ObjectPermissions(ParentId = psAnalyzerAccess.Id, SObjectType = 'Identified_Pain_Point__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true);

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psAnalyzerAccess.Id),
            new PermissionSetAssignment(AssigneeId = noDeleteUser.Id, PermissionSetId = psAnalyzerAccess.Id),
            new PermissionSetAssignment(AssigneeId = noCreateUser.Id, PermissionSetId = psAnalyzerAccess.Id)
        };
        
        // Remove admin set from nodelete user to ensure block works
        delete [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :noDeleteUser.Id AND PermissionSetId = :psMockAdmin.Id];
        
        // Read Only Set - Grant Behavior Log Access (No Delete) AND Health Log Access (Create OK)
        PermissionSet psReadOnly = new PermissionSet(Name = 'ReadOnly_' + uniqueifier, Label = 'Read Only');
        insert psReadOnly;
        
        List<ObjectPermissions> roPerms = new List<ObjectPermissions>();
        // Behavior Log: NO DELETE
        roPerms.add(new ObjectPermissions(ParentId = psReadOnly.Id, SObjectType = 'Behavior_Log__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = false));
        // Health Log: YES CREATE (so the test assertion passes)
        roPerms.add(new ObjectPermissions(ParentId = psReadOnly.Id, SObjectType = 'System_Health_Log__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true));
        
        insert roPerms;
        insert new PermissionSetAssignment(AssigneeId = noDeleteUser.Id, PermissionSetId = psReadOnly.Id);
    }

    private static void createPatternData(User testUser) {
        Id queueId;
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Group> existingQueues = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Unassigned Leads Queue' LIMIT 1];
            if (existingQueues.isEmpty()) {
                Group queueGroup = new Group(Name = 'Unassigned Leads Queue', Type = 'Queue');
                insert queueGroup;
                QueueSObject qso = new QueueSObject(QueueId = queueGroup.Id, SobjectType = 'Lead');
                insert qso;
                queueId = queueGroup.Id;
            } else {
                queueId = existingQueues[0].Id;
            }
        }

        System.runAs(testUser) {
            List<Opportunity> tempOpps = new List<Opportunity>();
            for (Integer i = 0; i < 5; i++) {
                tempOpps.add(new Opportunity(Name = 'Deal ' + i, Amount = 150000, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1)));
            }
            insert tempOpps;

            List<Case> tempCases = new List<Case>();
            for (Integer i = 0; i < 4; i++) {
                tempCases.add(new Case(Subject = 'Case ' + i, Priority = 'High', Status = 'New'));
            }
            insert tempCases;

            for (Integer i = 0; i < 7; i++) {
                Contact c = new Contact(LastName = 'Seq ' + i);
                insert c;
                Task t = new Task(Subject = 'Follow Up', WhoId = c.Id);
                insert t;
            }

            List<Lead> unassignedLeads = new List<Lead>();
            for (Integer i = 0; i < 8; i++) {
                unassignedLeads.add(new Lead(LastName = 'Unassigned ' + i, Company = 'Co', OwnerId = queueId));
            }
            insert unassignedLeads;
            
            Test.getEventBus().deliver(); 
        }
    }

    @isTest
    static void testAllPatterns_And_HealthLogging() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];
        
        // INJECT MOCK METADATA
        // We set values to 0 so that 'today's' data is considered stale/old enough to trigger the patterns
        PatternAnalysisService.mockSettings = new Behavior_Setting__mdt(
            DeveloperName = 'Default',
            Unassigned_Lead_Age_Hours__c = 0,
            Stale_Opportunity_Days__c = 0,
            Sequential_Action_Threshold__c = 5
        );
        
        // Keep static override for the property not yet in MDT
        PatternAnalysisService.STALE_CASE_DAYS = 0;

        createPatternData(testUser);

        Test.startTest();
        System.runAs(testUser) {
            Database.executeBatch(new PatternAnalysisService());
        }
        Test.stopTest();

        List<Identified_Pain_Point__c> finalPainPoints = [SELECT Unique_Key__c FROM Identified_Pain_Point__c];
        // Expect 4: Sequential, Stale Opps, Unassigned Leads, Stale Cases
        System.assertEquals(4, finalPainPoints.size(), 'Should find 4 pain points using mock metadata settings.');
        
        System.assertEquals(1, [SELECT COUNT() FROM System_Health_Log__c WHERE Status__c = 'Success'], 'Health log should be success.');
    }

    @isTest
    static void testDataRetention_DeletesOldLogs() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];
        
        System.runAs(testUser) {
            List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
            for (Integer i = 0; i < 5; i++) oldLogs.add(new Behavior_Log__c(Action_Name__c = 'Old', User__c = testUser.Id));
            insert oldLogs;
            for(Behavior_Log__c l : oldLogs) Test.setCreatedDate(l.Id, Date.today().addDays(-100));
            update oldLogs;
        }

        Test.startTest();
        System.runAs(testUser) {
            Date cutoffDate = Date.today().addDays(-PatternAnalysisService.DEFAULT_RETENTION_DAYS);
            String isoDate = Datetime.newInstanceGmt(cutoffDate.year(), cutoffDate.month(), cutoffDate.day()).format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String query = 'SELECT Id FROM Behavior_Log__c WHERE CreatedDate < ' + isoDate;
            Database.executeBatch(new DeleteRecordsBatch(query)); 
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'Old'], 'Old logs should have been deleted.');
    }

    @isTest
    static void testFinishMethod_HandlesLogDeletionError() {
        User noDeleteUser = [SELECT Id FROM User WHERE Alias = 'nodelete' LIMIT 1];
        
        System.runAs(noDeleteUser) {
            Behavior_Log__c log = new Behavior_Log__c(Action_Name__c = 'NoDelete', User__c = noDeleteUser.Id);
            insert log;
        }

        Test.startTest();
        System.runAs(noDeleteUser) {
            Database.executeBatch(new PatternAnalysisService());
        }
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'NoDelete'], 'Log should NOT be deleted due to lack of permission.');
        System.assertEquals(1, [SELECT COUNT() FROM System_Health_Log__c WHERE Status__c = 'Success'], 'Health log should still be Success.');
    }

    @isTest
    static void testFinishMethod_HandlesHealthLogError() {
        User noCreateUser = [SELECT Id FROM User WHERE Alias = 'nocreate' LIMIT 1];
        
        System.runAs(noCreateUser) {
             Behavior_Log__c log = new Behavior_Log__c(Action_Name__c = 'Test', User__c = noCreateUser.Id);
             insert log;
        }

        Test.startTest();
        System.runAs(noCreateUser) {
            Database.executeBatch(new PatternAnalysisService());
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM System_Health_Log__c WHERE CreatedDate = TODAY], 'Should be 0 if user lacks Create permission.');
    }
}