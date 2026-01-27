/**
 * @description Controller for the User Leaderboard LWC.
 * Updates: Switched helper query to use Security.stripInaccessible for graceful handling of partial permissions.
 * Uses "Aggregate-Query-Enrich" pattern to handle non-groupable fields like SmallPhotoUrl.
 */
public with sharing class UserLeaderboardController {

    @TestVisible private static Boolean forcePremiumContext = null;

    // Org-agnostic default avatar - uses standard Salesforce asset that works across all orgs
    private static final String DEFAULT_ANONYMOUS_AVATAR = '/img/icon/t4v35/standard/avatar.svg';

    // Response Wrapper to carry state + data
    public class LeaderboardResult {
        @AuraEnabled public Boolean isPremium;
        @AuraEnabled public List<LeaderboardEntry> entries;
        @AuraEnabled public String errorMessage; 
        
        public LeaderboardResult(Boolean isPremium, List<LeaderboardEntry> entries) {
            this.isPremium = isPremium;
            this.entries = entries;
            this.errorMessage = null;
        }
    }

    public class LeaderboardEntry {
        @AuraEnabled public String userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String photoUrl;
        @AuraEnabled public Integer totalImpactScore;
        @AuraEnabled public List<String> topBehaviors;
        @AuraEnabled public Boolean isAnonymized;

        public LeaderboardEntry(String userId, String userName, String photoUrl, Integer score, Boolean isAnonymized) {
            this.userId = userId;
            this.userName = userName;
            this.photoUrl = photoUrl;
            this.totalImpactScore = score;
            this.topBehaviors = new List<String>();
            this.isAnonymized = isAnonymized;
        }
    }

    /**
     * @description Simple accessor for LWC to check license status directly.
     * FIX: This method is required by the Dashboard LWC.
     */
    @AuraEnabled(cacheable=true)
    public static String getLicenseStatus() {
        try {
            return isPremiumUser() ? 'Premium' : 'Free';
        } catch (Exception e) {
            return 'Free';
        }
    }

    @AuraEnabled(cacheable=true)
    public static LeaderboardResult getLeaderboardData() {
        Boolean isPremium = false;
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();

        // 1. Safe License Check
        try {
            isPremium = isPremiumUser();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BehaviorIQ License Check Failed: ' + e.getMessage());
            isPremium = false;
        }

        // 2. Safe Data Query with sharing-aware approach
        // Query records first with USER_MODE to respect sharing rules, then aggregate in Apex
        // This prevents information disclosure where aggregate counts include inaccessible records
        try {
            // STEP A: Query accessible logs with USER_MODE to respect sharing rules
            List<Behavior_Log__c> accessibleLogs = [
                SELECT Id, User__c
                FROM Behavior_Log__c
                WHERE User__c != null
                WITH USER_MODE
                LIMIT 50000
            ];

            // STEP B: Aggregate counts by User__c in Apex (sharing-aware)
            Map<Id, Integer> userEventCounts = new Map<Id, Integer>();
            for (Behavior_Log__c log : accessibleLogs) {
                if (!userEventCounts.containsKey(log.User__c)) {
                    userEventCounts.put(log.User__c, 0);
                }
                userEventCounts.put(log.User__c, userEventCounts.get(log.User__c) + 1);
            }

            // STEP C: Sort by count descending and take top 10
            List<UserEventCount> sortedUsers = new List<UserEventCount>();
            for (Id userId : userEventCounts.keySet()) {
                sortedUsers.add(new UserEventCount(userId, userEventCounts.get(userId)));
            }
            sortedUsers.sort();

            // STEP D: Collect top 10 User Ids
            Set<Id> userIds = new Set<Id>();
            List<UserEventCount> topUsers = new List<UserEventCount>();
            for (Integer i = 0; i < Math.min(10, sortedUsers.size()); i++) {
                userIds.add(sortedUsers[i].userId);
                topUsers.add(sortedUsers[i]);
            }

            // STEP E: Enrich with User Details (Name, Photo)
            Map<Id, User> userMap = new Map<Id, User>();
            if (!userIds.isEmpty()) {
                userMap = new Map<Id, User>([
                    SELECT Id, Name, SmallPhotoUrl
                    FROM User
                    WHERE Id IN :userIds
                    WITH USER_MODE
                ]);
            }

            // STEP F: Get Behavior Breakdowns
            Map<Id, List<String>> behaviorMap = getBehaviorBreakdowns(userIds);

            // STEP G: Build Wrappers
            Integer rankCounter = 1;
            for (UserEventCount uec : topUsers) {
                Id userId = uec.userId;
                Integer score = uec.eventCount;

                // Get User details from our map
                User u = userMap.get(userId);
                String realName = (u != null) ? u.Name : 'Unknown User';
                String realPhoto = (u != null) ? u.SmallPhotoUrl : '';

                LeaderboardEntry entry;

                if (isPremium) {
                    // PREMIUM: Show actual data
                    entry = new LeaderboardEntry((String)userId, realName, realPhoto, score, false);
                    if (behaviorMap.containsKey(userId)) {
                        entry.topBehaviors = behaviorMap.get(userId);
                    }
                } else {
                    // FREE: Anonymize data
                    String anonName = 'User ' + rankCounter;
                    entry = new LeaderboardEntry(null, anonName, DEFAULT_ANONYMOUS_AVATAR, score, true);

                    if (behaviorMap.containsKey(userId)) {
                        entry.topBehaviors = behaviorMap.get(userId);
                    }
                }

                entries.add(entry);
                rankCounter++;
            }

        } catch (System.QueryException qe) {
            System.debug(LoggingLevel.INFO, 'BehaviorIQ: User lacks permission to Behavior_Log__c or User fields.');
            return new LeaderboardResult(isPremium, new List<LeaderboardEntry>());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BehaviorIQ Leaderboard Error: ' + e.getMessage() + ' ' + e.getStackTraceString());
            return new LeaderboardResult(isPremium, new List<LeaderboardEntry>());
        }

        return new LeaderboardResult(isPremium, entries);
    }

    /**
     * @description Helper class for sorting users by event count descending.
     */
    private class UserEventCount implements Comparable {
        public Id userId;
        public Integer eventCount;

        public UserEventCount(Id userId, Integer eventCount) {
            this.userId = userId;
            this.eventCount = eventCount;
        }

        public Integer compareTo(Object other) {
            UserEventCount otherUec = (UserEventCount) other;
            // Sort descending by event count
            return otherUec.eventCount - this.eventCount;
        }
    }

    private static Map<Id, List<String>> getBehaviorBreakdowns(Set<Id> userIds) {
        Map<Id, List<String>> resultMap = new Map<Id, List<String>>();
        if (userIds.isEmpty()) return resultMap;

        try {
            // Query with USER_MODE for sharing/FLS enforcement, then stripInaccessible for additional protection
            List<Behavior_Log__c> logs = [
                SELECT User__c, Action_Name__c
                FROM Behavior_Log__c
                WHERE User__c IN :userIds
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 500
            ];

            // Apply security stripping for additional field-level protection
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.READABLE, logs);
            
            for (SObject obj : securityDecision.getRecords()) {
                Behavior_Log__c log = (Behavior_Log__c)obj;
                
                if (!resultMap.containsKey(log.User__c)) {
                    resultMap.put(log.User__c, new List<String>());
                }
                
                // Only add if Action Name is visible/populated
                if (log.Action_Name__c != null) {
                    List<String> userBehaviors = resultMap.get(log.User__c);
                    if (!userBehaviors.contains(log.Action_Name__c) && userBehaviors.size() < 3) {
                        userBehaviors.add(log.Action_Name__c);
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'BehaviorIQ Breakdown Query Error: ' + e.getMessage());
        }
        return resultMap;
    }

    private static Boolean isPremiumUser() {
        if (forcePremiumContext != null) {
            return forcePremiumContext;
        }
        return LicenseService.isPremium();
    }

    /**
     * @description Sends a nudge notification to a user via Task creation.
     * Creates a Task assigned to the user with a reminder about open items.
     * @param userId The Id of the user to nudge
     * @return String - Success or error message
     */
    @AuraEnabled
    public static String nudgeUser(Id userId) {
        try {
            // Validate input
            if (userId == null) {
                throw new AuraHandledException('User ID is required.');
            }

            // Verify the user exists with USER_MODE for security
            List<User> users = [SELECT Id, Name FROM User WHERE Id = :userId AND IsActive = true WITH USER_MODE LIMIT 1];
            if (users.isEmpty()) {
                throw new AuraHandledException('User not found or inactive.');
            }

            // CRUD check before creating Task
            if (!Schema.sObjectType.Task.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create Tasks.');
            }

            // Create a Task for the user
            Task nudgeTask = new Task(
                OwnerId = userId,
                Subject = 'BehaviorIQ Notice: Action Required',
                Description = 'BehaviorIQ Notice: You have open items requiring attention. Please check your dashboard.',
                Status = 'Not Started',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(3)
            );

            // Use Security.stripInaccessible for FLS enforcement, and 'as user' for CRUD/sharing
            List<SObject> secureTasks = Security.stripInaccessible(AccessType.CREATABLE, new List<Task>{nudgeTask}).getRecords();
            insert as user secureTasks;

            return 'Nudge sent to ' + users[0].Name;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            String msg = 'Failed to create nudge task: ' + e.getDmlMessage(0);
            AuraHandledException ahe = new AuraHandledException(msg);
            ahe.setMessage(msg);
            throw ahe;
        } catch (Exception e) {
            String msg = 'An error occurred while sending the nudge: ' + e.getMessage();
            AuraHandledException ahe = new AuraHandledException(msg);
            ahe.setMessage(msg);
            throw ahe;
        }
    }
}