/**
 * @description Test class for PatternAnalysisService.
 * @version 7.2 - Final version. All tests passing with corrected permission setup for test users.
 */
@isTest
private class PatternAnalysisServiceTest {

    @TestSetup
    static void setupData() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        String uniqueifier = String.valueOf(System.currentTimeMillis());

        // 1. Create unique users to prevent test collisions
        List<User> usersToInsert = new List<User>{
            new User(
                Alias = 'testpas', Email='testpas' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8',
                LastName='Testing', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
                ProfileId = p.Id, TimeZoneSidKey='America/Los_Angeles',
                UserName='testpas' + uniqueifier + '@testorg.com'
            ),
            new User(
                Alias = 'nodelete', Email='nodelete' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8',
                LastName='NoDelete', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
                ProfileId = p.Id, TimeZoneSidKey='America/Los_Angeles',
                UserName='nodelete' + uniqueifier + '@testorg.com'
            ),
            new User(
                Alias = 'nocreate', Email='nocreate' + uniqueifier + '@testorg.com', EmailEncodingKey='UTF-8',
                LastName='NoCreate', LanguageLocaleKey='en_US', LocaleSidKey='en_US',
                ProfileId = p.Id, TimeZoneSidKey='America/Los_Angeles',
                UserName='nocreate' + uniqueifier + '@testorg.com'
            )
        };
        insert usersToInsert;

        // Query users back for assignments
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];
        User noDeleteUser = [SELECT Id FROM User WHERE Alias = 'nodelete' LIMIT 1];
        User noCreateUser = [SELECT Id FROM User WHERE Alias = 'nocreate' LIMIT 1];

        // 2. Create Permission Set for BLOCKING Log Deletion
        PermissionSet psBlockDelete = new PermissionSet(Name = 'Block_Log_Delete_' + uniqueifier, Label = 'Block Log Delete');
        insert psBlockDelete;
        insert new ObjectPermissions(
            ParentId = psBlockDelete.Id, SObjectType = 'Behavior_Log__c',
            PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = false
        );
        insert new PermissionSetAssignment(AssigneeId = noDeleteUser.Id, PermissionSetId = psBlockDelete.Id);

        // 3. Create Permission Set for BLOCKING Health Log Creation
        PermissionSet psBlockCreate = new PermissionSet(Name = 'Block_Health_Create_' + uniqueifier, Label = 'Block Health Create');
        insert psBlockCreate;
        insert new ObjectPermissions(
            ParentId = psBlockCreate.Id, SObjectType = 'System_Health_Log__c',
            PermissionsRead = true, PermissionsCreate = false, PermissionsEdit = false, PermissionsDelete = false
        );
        insert new PermissionSetAssignment(AssigneeId = noCreateUser.Id, PermissionSetId = psBlockCreate.Id);
        
        // 4. Create Permission Set for ALLOWING Health Log Creation for the positive test paths
        PermissionSet psAllowHealth = new PermissionSet(Name = 'Allow_Health_Create_' + uniqueifier, Label = 'Allow Health Create');
        insert psAllowHealth;
        insert new ObjectPermissions(
            ParentId = psAllowHealth.Id, SObjectType = 'System_Health_Log__c',
            PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true
        );
        // Assign to the main test user AND the noDeleteUser, as both tests expect a health log to be created.
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(AssigneeId = testUser.Id, PermissionSetId = psAllowHealth.Id),
            new PermissionSetAssignment(AssigneeId = noDeleteUser.Id, PermissionSetId = psAllowHealth.Id)
        };

        // 5. Create the Queue
        if ([SELECT COUNT() FROM Group WHERE Type = 'Queue' AND Name = 'Unassigned Leads Queue'] == 0) {
            Group g = new Group(Name = 'Unassigned Leads Queue', Type = 'Queue');
            insert g;
            insert new QueueSObject(QueueID = g.Id, SobjectType = 'Lead');
        }
    }

    @isTest
    static void testAllPatterns_And_HealthLogging() {
        User testUser = [SELECT Id FROM User WHERE Alias = 'testpas' LIMIT 1];
        Id queueId = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Unassigned Leads Queue' LIMIT 1].Id;
        
        System.runAs(testUser) {
            List<Behavior_Log__c> logsToInsert = new List<Behavior_Log__c>();
            Datetime now = System.now();

            // Data for Pattern 1: Sequential Contact -> Task
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < 7; i++) { contacts.add(new Contact(LastName = 'Seq ' + i)); }
            insert contacts;
            List<Task> tasks = new List<Task>();
            for (Contact c : contacts) { tasks.add(new Task(Subject = 'Follow Up', WhoId = c.Id)); }
            insert tasks;
            for (Integer i = 0; i < contacts.size(); i++) {
                logsToInsert.add(new Behavior_Log__c(Action_Name__c = 'Record_Created', Object_API_Name__c = 'Contact', Record_ID__c = contacts[i].Id, User__c = testUser.Id));
                logsToInsert.add(new Behavior_Log__c(Action_Name__c = 'Record_Created', Object_API_Name__c = 'Task', Record_ID__c = tasks[i].Id, User__c = testUser.Id));
            }

            // Data for Pattern 2: Stale, High-Value Opportunities
            List<Opportunity> staleOpps = new List<Opportunity>();
            for (Integer i = 0; i < 5; i++) {
                staleOpps.add(new Opportunity(Name = 'Stale Deal ' + i, Amount = 150000, StageName = 'Proposal/Price Quote', CloseDate = Date.today().addMonths(1)));
            }
            insert staleOpps;
            for (Opportunity o : staleOpps) {
                Test.setCreatedDate(o.Id, Date.today().addDays(-40)); // Make them older than the 30-day threshold
                logsToInsert.add(new Behavior_Log__c(Action_Name__c = 'Record_Created', Object_API_Name__c = 'Opportunity', Record_ID__c = o.Id, User__c = testUser.Id));
            }

            // Data for Pattern 3: Unassigned Leads
            List<Lead> unassignedLeads = new List<Lead>();
            for (Integer i = 0; i < 8; i++) {
                unassignedLeads.add(new Lead(LastName = 'Unassigned ' + i, Company = 'New Prospect Inc.', OwnerId = queueId));
            }
            insert unassignedLeads;
            for (Lead l : unassignedLeads) {
                logsToInsert.add(new Behavior_Log__c(Action_Name__c = 'Record_Created', Object_API_Name__c = 'Lead', Record_ID__c = l.Id, User__c = testUser.Id));
            }
            
            insert logsToInsert;
            for(Behavior_Log__c log : logsToInsert) {
                Test.setCreatedDate(log.Id, now.addSeconds(-1));
            }

            Test.getEventBus().deliver();

            Test.startTest();
                Database.executeBatch(new PatternAnalysisService());
            Test.stopTest(); 

            System.assertEquals(3, [SELECT COUNT() FROM Identified_Pain_Point__c], 'Three pain point records should have been created.');
            System.assertEquals(1, [SELECT COUNT() FROM System_Health_Log__c], 'A health log should be created by the finish method.');
        }
    }

    @isTest
    static void testDataRetention_DeletesOldLogs() {
        List<Behavior_Log__c> oldLogs = new List<Behavior_Log__c>();
        for (Integer i = 0; i < 5; i++) { oldLogs.add(new Behavior_Log__c(Action_Name__c = 'Old_Action')); }
        insert oldLogs;
        for (Behavior_Log__c log : oldLogs) { Test.setCreatedDate(log.Id, Date.today().addDays(-100)); }

        Test.startTest();
            Database.executeBatch(new PatternAnalysisService());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Behavior_Log__c WHERE Action_Name__c = 'Old_Action'], 'Old logs should have been deleted by the finish method.');
    }

    @isTest
    static void testFinishMethod_HandlesLogDeletionError() {
        User noDeleteUser = [SELECT Id FROM User WHERE Alias = 'nodelete' LIMIT 1];
        System.runAs(noDeleteUser) {
            Behavior_Log__c oldLog = new Behavior_Log__c(Action_Name__c = 'Dummy Old Log');
            insert oldLog;
            Test.setCreatedDate(oldLog.Id, Date.today().addDays(-100));

            Test.startTest();
                PatternAnalysisService service = new PatternAnalysisService();
                service.finish(null); 
            Test.stopTest();

            System.assertEquals(1, [SELECT COUNT() FROM Behavior_Log__c WHERE Id = :oldLog.Id], 'The old log should NOT have been deleted.');
            System.assertEquals(1, [SELECT COUNT() FROM System_Health_Log__c], 'A health log should still be created even if deletion fails.');
        }
    }

    @isTest
    static void testFinishMethod_HandlesHealthLogError() {
        User noCreateUser = [SELECT Id FROM User WHERE Alias = 'nocreate' LIMIT 1];
        System.runAs(noCreateUser) {
            insert new Behavior_Log__c(Action_Name__c = 'Dummy Log');
            delete [SELECT Id FROM System_Health_Log__c];

            Test.startTest();
                PatternAnalysisService service = new PatternAnalysisService();
                service.finish(null);
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM System_Health_Log__c], 'No health log should have been created.');
        }
    }
}

