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
        @AuraEnabled public Integer totalImpactScore;    // Actual $ impact from pain points they own
        @AuraEnabled public Integer activityCount;        // Number of tracked events
        @AuraEnabled public Integer issueCount;           // Number of pain point records they own
        @AuraEnabled public List<String> topBehaviors;
        @AuraEnabled public Boolean isAnonymized;
        @AuraEnabled public String impactTooltip;         // Explains how score is calculated

        public LeaderboardEntry(String userId, String userName, String photoUrl, Integer impactScore, Integer activityCount, Integer issueCount, Boolean isAnonymized) {
            this.userId = userId;
            this.userName = userName;
            this.photoUrl = photoUrl;
            this.totalImpactScore = impactScore;
            this.activityCount = activityCount;
            this.issueCount = issueCount;
            this.topBehaviors = new List<String>();
            this.isAnonymized = isAnonymized;
            // Build tooltip explaining the score
            this.impactTooltip = 'Impact Score: $' + (impactScore != null ? impactScore : 0) + ' at risk from ' +
                                 (issueCount != null ? issueCount : 0) + ' issue(s) on records you own. ' +
                                 'Activity: ' + (activityCount != null ? activityCount : 0) + ' tracked events.';
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
        try {
            // STEP A: Query accessible logs with USER_MODE to respect sharing rules
            List<Behavior_Log__c> accessibleLogs = [
                SELECT Id, User__c
                FROM Behavior_Log__c
                WHERE User__c != null
                WITH USER_MODE
                LIMIT 50000
            ];

            // STEP B: Aggregate activity counts by User__c in Apex (sharing-aware)
            Map<Id, Integer> userActivityCounts = new Map<Id, Integer>();
            for (Behavior_Log__c log : accessibleLogs) {
                if (!userActivityCounts.containsKey(log.User__c)) {
                    userActivityCounts.put(log.User__c, 0);
                }
                userActivityCounts.put(log.User__c, userActivityCounts.get(log.User__c) + 1);
            }

            // STEP C: Calculate REAL Impact from Pain Points
            // Impact = sum of Impact_Score__c from pain points where user owns the problematic records
            Map<Id, Decimal> userImpactScores = new Map<Id, Decimal>();
            Map<Id, Integer> userIssueCounts = new Map<Id, Integer>();
            calculateUserImpactFromPainPoints(userImpactScores, userIssueCounts);

            // STEP D: Merge activity users with impact users
            Set<Id> allUserIds = new Set<Id>();
            allUserIds.addAll(userActivityCounts.keySet());
            allUserIds.addAll(userImpactScores.keySet());

            // STEP E: Build sortable list prioritizing impact, then activity
            List<UserImpactData> sortedUsers = new List<UserImpactData>();
            for (Id userId : allUserIds) {
                Decimal impact = userImpactScores.containsKey(userId) ? userImpactScores.get(userId) : 0;
                Integer activity = userActivityCounts.containsKey(userId) ? userActivityCounts.get(userId) : 0;
                Integer issues = userIssueCounts.containsKey(userId) ? userIssueCounts.get(userId) : 0;
                sortedUsers.add(new UserImpactData(userId, impact, activity, issues));
            }
            sortedUsers.sort();

            // STEP F: Collect top 10 User Ids
            Set<Id> topUserIds = new Set<Id>();
            List<UserImpactData> topUsers = new List<UserImpactData>();
            for (Integer i = 0; i < Math.min(10, sortedUsers.size()); i++) {
                topUserIds.add(sortedUsers[i].userId);
                topUsers.add(sortedUsers[i]);
            }

            // STEP G: Enrich with User Details (Name, Photo)
            Map<Id, User> userMap = new Map<Id, User>();
            if (!topUserIds.isEmpty()) {
                userMap = new Map<Id, User>([
                    SELECT Id, Name, SmallPhotoUrl
                    FROM User
                    WHERE Id IN :topUserIds
                    WITH USER_MODE
                ]);
            }

            // STEP H: Get Behavior Breakdowns
            Map<Id, List<String>> behaviorMap = getBehaviorBreakdowns(topUserIds);

            // STEP I: Build Wrappers
            Integer rankCounter = 1;
            for (UserImpactData uid : topUsers) {
                Id userId = uid.userId;
                Integer impactScore = uid.impactScore.intValue();
                Integer activityCount = uid.activityCount;
                Integer issueCount = uid.issueCount;

                // Get User details from our map
                User u = userMap.get(userId);
                String realName = (u != null) ? u.Name : 'Unknown User';
                String realPhoto = (u != null) ? u.SmallPhotoUrl : '';

                LeaderboardEntry entry;

                if (isPremium) {
                    // PREMIUM: Show actual data
                    entry = new LeaderboardEntry((String)userId, realName, realPhoto, impactScore, activityCount, issueCount, false);
                    if (behaviorMap.containsKey(userId)) {
                        entry.topBehaviors = behaviorMap.get(userId);
                    }
                } else {
                    // FREE: Anonymize data
                    String anonName = 'User ' + rankCounter;
                    entry = new LeaderboardEntry(null, anonName, DEFAULT_ANONYMOUS_AVATAR, impactScore, activityCount, issueCount, true);

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
     * @description Helper class for sorting users by impact (primary) and activity (secondary).
     */
    private class UserImpactData implements Comparable {
        public Id userId;
        public Decimal impactScore;  // Dollar value at risk from pain points
        public Integer activityCount; // Number of tracked events
        public Integer issueCount;    // Number of pain point records owned

        public UserImpactData(Id userId, Decimal impactScore, Integer activityCount, Integer issueCount) {
            this.userId = userId;
            this.impactScore = impactScore != null ? impactScore : 0;
            this.activityCount = activityCount != null ? activityCount : 0;
            this.issueCount = issueCount != null ? issueCount : 0;
        }

        public Integer compareTo(Object other) {
            UserImpactData otherUid = (UserImpactData) other;
            // Primary sort: descending by impact score (users causing more $ risk at top)
            if (this.impactScore != otherUid.impactScore) {
                return this.impactScore > otherUid.impactScore ? -1 : 1;
            }
            // Secondary sort: descending by issue count
            if (this.issueCount != otherUid.issueCount) {
                return otherUid.issueCount - this.issueCount;
            }
            // Tertiary sort: descending by activity count
            return otherUid.activityCount - this.activityCount;
        }
    }

    /**
     * @description Calculates actual impact scores by finding record owners of pain point records.
     * Queries Identified_Pain_Point__c, parses Example_Records__c, and aggregates impact by owner.
     * @param userImpactScores Output map of User ID to total impact score ($ at risk)
     * @param userIssueCounts Output map of User ID to count of pain point records they own
     */
    private static void calculateUserImpactFromPainPoints(Map<Id, Decimal> userImpactScores, Map<Id, Integer> userIssueCounts) {
        if (!Schema.sObjectType.Identified_Pain_Point__c.isAccessible()) {
            return;
        }

        try {
            // Query active pain points with their impact scores
            // Note: Can't filter on Example_Records__c (Long Text Area) in SOQL, handle in Apex
            List<Identified_Pain_Point__c> painPoints = [
                SELECT Id, Object_API_Name__c, Impact_Score__c, Example_Records__c, Occurrences__c
                FROM Identified_Pain_Point__c
                WHERE (Status__c = 'New' OR Status__c = 'Active')
                WITH USER_MODE
                LIMIT 100
            ];

            if (painPoints.isEmpty()) {
                return;
            }

            // Group record IDs by object type for efficient batched queries
            Map<String, Set<Id>> recordIdsByObject = new Map<String, Set<Id>>();
            Map<Id, Decimal> recordImpactMap = new Map<Id, Decimal>(); // Record ID to its share of impact

            for (Identified_Pain_Point__c pp : painPoints) {
                String objType = pp.Object_API_Name__c;
                if (String.isBlank(objType) || String.isBlank(pp.Example_Records__c)) {
                    continue;
                }

                // Parse record IDs from Example_Records__c (JSON array or comma-separated)
                List<Id> recordIds = parseRecordIds(pp.Example_Records__c);
                if (recordIds.isEmpty()) {
                    continue;
                }

                // Calculate per-record impact (total impact / number of records)
                Decimal totalImpact = pp.Impact_Score__c != null ? pp.Impact_Score__c : 0;
                Decimal perRecordImpact = recordIds.size() > 0 ? totalImpact / recordIds.size() : 0;

                // Group by object type
                if (!recordIdsByObject.containsKey(objType)) {
                    recordIdsByObject.put(objType, new Set<Id>());
                }

                for (Id recId : recordIds) {
                    recordIdsByObject.get(objType).add(recId);
                    // Accumulate impact for records that appear in multiple pain points
                    if (!recordImpactMap.containsKey(recId)) {
                        recordImpactMap.put(recId, 0);
                    }
                    recordImpactMap.put(recId, recordImpactMap.get(recId) + perRecordImpact);
                }
            }

            // Query owners for each object type and aggregate impact
            for (String objType : recordIdsByObject.keySet()) {
                Set<Id> recordIds = recordIdsByObject.get(objType);
                if (recordIds.isEmpty()) {
                    continue;
                }

                // Query record owners using dynamic SOQL
                Map<Id, Id> recordOwners = getRecordOwners(objType, recordIds);

                // Aggregate impact by owner
                for (Id recordId : recordOwners.keySet()) {
                    Id ownerId = recordOwners.get(recordId);
                    Decimal impact = recordImpactMap.containsKey(recordId) ? recordImpactMap.get(recordId) : 0;

                    if (!userImpactScores.containsKey(ownerId)) {
                        userImpactScores.put(ownerId, 0);
                        userIssueCounts.put(ownerId, 0);
                    }
                    userImpactScores.put(ownerId, userImpactScores.get(ownerId) + impact);
                    userIssueCounts.put(ownerId, userIssueCounts.get(ownerId) + 1);
                }
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error calculating user impact from pain points: ' + e.getMessage());
        }
    }

    /**
     * @description Parses record IDs from Example_Records__c field (JSON array or comma-separated).
     */
    private static List<Id> parseRecordIds(String recordsStr) {
        List<Id> result = new List<Id>();
        if (String.isBlank(recordsStr)) {
            return result;
        }

        try {
            String trimmed = recordsStr.trim();
            List<String> idStrings;

            if (trimmed.startsWith('[')) {
                // JSON array format
                try {
                    idStrings = (List<String>)JSON.deserialize(trimmed, List<String>.class);
                } catch (Exception jsonEx) {
                    // Fallback: strip brackets and split
                    trimmed = trimmed.replace('[', '').replace(']', '').replace('"', '');
                    idStrings = trimmed.split(',');
                }
            } else {
                // Comma-separated format
                idStrings = trimmed.split(',');
            }

            for (String idStr : idStrings) {
                String cleanId = idStr.trim();
                if (String.isNotBlank(cleanId)) {
                    try {
                        result.add(Id.valueOf(cleanId));
                    } catch (Exception idEx) {
                        // Skip invalid IDs
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error parsing record IDs: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Queries record owners for a specific object type.
     * @param objectApiName The API name of the object (e.g., 'Case', 'Opportunity')
     * @param recordIds Set of record IDs to query
     * @return Map of Record ID to Owner ID
     */
    private static Map<Id, Id> getRecordOwners(String objectApiName, Set<Id> recordIds) {
        Map<Id, Id> ownerMap = new Map<Id, Id>();

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return ownerMap;
        }

        try {
            // Verify the object has OwnerId field
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) {
                return ownerMap;
            }

            Schema.DescribeSObjectResult describeResult = objType.getDescribe();
            if (!describeResult.isAccessible()) {
                return ownerMap;
            }

            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            if (!fieldMap.containsKey('OwnerId')) {
                return ownerMap;
            }

            // Build and execute dynamic query
            String query = 'SELECT Id, OwnerId FROM ' + String.escapeSingleQuotes(objectApiName) +
                          ' WHERE Id IN :recordIds WITH SECURITY_ENFORCED LIMIT 500';

            List<SObject> records = Database.query(query);  // NOPMD - ApexSOQLInjection: objectApiName validated via Schema

            for (SObject record : records) {
                Id ownerId = (Id)record.get('OwnerId');
                if (ownerId != null) {
                    ownerMap.put(record.Id, ownerId);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error querying owners for ' + objectApiName + ': ' + e.getMessage());
        }

        return ownerMap;
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