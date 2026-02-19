/**
 * BehaviorIQ E2E Permission & Security Test Queries
 * ===================================================
 *
 * This script contains verification queries and security test methods
 * for validating BehaviorIQ permission set configurations.
 *
 * HOW TO USE:
 * 1. Run specific sections based on the user context you're testing
 * 2. Compare actual results with expected results in the E2E doc
 * 3. Document any security gaps or unexpected access
 *
 * TEST USERS REQUIRED:
 * - Admin User: BehaviorIQ_Admin permission set assigned
 * - Unprivileged User: No BehaviorIQ permission sets
 */

System.debug('=== BehaviorIQ E2E Permission & Security Test Queries ===');
System.debug('Running user: ' + UserInfo.getName() + ' (' + UserInfo.getUserId() + ')');
System.debug('');

// ============================================================================
// SECTION 1: VERIFY CURRENT USER'S PERMISSION SETS
// ============================================================================
System.debug('--- Section 1: Current User Permission Sets ---');

List<PermissionSetAssignment> psaList = [
    SELECT PermissionSet.Name, PermissionSet.Label
    FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId()
    AND PermissionSet.Name LIKE 'BehaviorIQ%'
];

if (psaList.isEmpty()) {
    System.debug('  NO BehaviorIQ permission sets assigned to current user.');
    System.debug('  Expected behavior: User should have NO access to BehaviorIQ objects.');
} else {
    System.debug('  BehaviorIQ Permission Sets assigned:');
    for (PermissionSetAssignment psa : psaList) {
        System.debug('    - ' + psa.PermissionSet.Name + ' (' + psa.PermissionSet.Label + ')');
    }
}
System.debug('');

// ============================================================================
// SECTION 2: OBJECT ACCESS TESTS
// ============================================================================
System.debug('--- Section 2: Object Access Tests ---');

// Test 2.1: Identified_Pain_Point__c Access
System.debug('  2.1 Identified_Pain_Point__c:');
try {
    Integer count = [SELECT COUNT() FROM Identified_Pain_Point__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.2: Remediation_Log__c Access
System.debug('  2.2 Remediation_Log__c:');
try {
    Integer count = [SELECT COUNT() FROM Remediation_Log__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.3: BehaviorIQ_Configuration__c Access
System.debug('  2.3 BehaviorIQ_Configuration__c:');
try {
    Integer count = [SELECT COUNT() FROM BehaviorIQ_Configuration__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.4: Behavior_Log__c Access
System.debug('  2.4 Behavior_Log__c:');
try {
    Integer count = [SELECT COUNT() FROM Behavior_Log__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.5: Suggestion_Dismissal__c Access
System.debug('  2.5 Suggestion_Dismissal__c:');
try {
    Integer count = [SELECT COUNT() FROM Suggestion_Dismissal__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.6: System_Health_Log__c Access
System.debug('  2.6 System_Health_Log__c:');
try {
    Integer count = [SELECT COUNT() FROM System_Health_Log__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.7: BehaviorIQ_License__c Access (Custom Setting)
System.debug('  2.7 BehaviorIQ_License__c (Custom Setting):');
try {
    BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
    if (license != null && license.Status__c != null) {
        System.debug('    READ: SUCCESS (Status = ' + license.Status__c + ')');
    } else {
        System.debug('    READ: SUCCESS (No org defaults set)');
    }
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

// Test 2.8: Behavior_Snapshot__c Access
System.debug('  2.8 Behavior_Snapshot__c:');
try {
    Integer count = [SELECT COUNT() FROM Behavior_Snapshot__c];
    System.debug('    READ: SUCCESS (' + count + ' records)');
} catch (Exception e) {
    System.debug('    READ: BLOCKED - ' + e.getMessage().left(100));
}

System.debug('');

// ============================================================================
// SECTION 3: CONTROLLER ACCESS TESTS
// ============================================================================
System.debug('--- Section 3: Controller Access Tests ---');

// Test 3.1: PainPointController.getOpenPainPoints()
System.debug('  3.1 PainPointController.getOpenPainPoints():');
try {
    List<Identified_Pain_Point__c> painPoints = PainPointController.getOpenPainPoints();
    System.debug('    SUCCESS - Returned ' + painPoints.size() + ' pain points');
} catch (Exception e) {
    System.debug('    BLOCKED - ' + e.getMessage().left(100));
}

// Test 3.2: PainPointController.getPainPointCounts()
System.debug('  3.2 PainPointController.getPainPointCounts():');
try {
    Map<String, Integer> counts = PainPointController.getPainPointCounts();
    System.debug('    SUCCESS - Status counts: ' + JSON.serialize(counts));
} catch (Exception e) {
    System.debug('    BLOCKED - ' + e.getMessage().left(100));
}

// Test 3.3: LicenseService.isPremium()
System.debug('  3.3 LicenseService.isPremium():');
try {
    Boolean isPremium = LicenseService.isPremium();
    System.debug('    SUCCESS - isPremium = ' + isPremium);
} catch (Exception e) {
    System.debug('    BLOCKED - ' + e.getMessage().left(100));
}

// Test 3.4: BehaviorSettingsController.getConfigSettings()
System.debug('  3.4 BehaviorSettingsController.getConfigSettings():');
try {
    Map<String, Object> settings = BehaviorSettingsController.getConfigSettings();
    System.debug('    SUCCESS - Settings retrieved');
} catch (Exception e) {
    System.debug('    BLOCKED - ' + e.getMessage().left(100));
}

System.debug('');

// ============================================================================
// SECTION 4: DML PERMISSION TESTS
// ============================================================================
System.debug('--- Section 4: DML Permission Tests ---');

// Test 4.1: Create Identified_Pain_Point__c
System.debug('  4.1 CREATE Identified_Pain_Point__c:');
try {
    Identified_Pain_Point__c testPP = new Identified_Pain_Point__c(
        Name = 'TEST_PERMISSION_CHECK',
        Unique_Key__c = 'TEST_PERMISSION_CHECK_' + DateTime.now().getTime(),
        Object_API_Name__c = 'Test',
        Status__c = 'New',
        Occurrences__c = 1
    );
    insert testPP;
    System.debug('    CREATE: SUCCESS (Id = ' + testPP.Id + ')');
    // Cleanup
    delete testPP;
    System.debug('    DELETE: SUCCESS (cleanup)');
} catch (Exception e) {
    System.debug('    CREATE/DELETE: BLOCKED - ' + e.getMessage().left(100));
}

// Test 4.2: Update BehaviorIQ_License__c (should require admin)
System.debug('  4.2 UPDATE BehaviorIQ_License__c:');
try {
    BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
    String originalStatus = license.Status__c;
    license.Status__c = 'Test';
    upsert license;
    System.debug('    UPDATE: SUCCESS (SECURITY GAP - non-admin modified license!)');
    // Revert
    license.Status__c = originalStatus;
    upsert license;
} catch (Exception e) {
    System.debug('    UPDATE: BLOCKED (Expected for non-admin) - ' + e.getMessage().left(80));
}

System.debug('');

// ============================================================================
// SECTION 5: SECURITY BYPASS TESTS
// ============================================================================
System.debug('--- Section 5: Security Bypass Tests ---');

// Test 5.1: Query with SECURITY_ENFORCED
System.debug('  5.1 Query with SECURITY_ENFORCED:');
try {
    List<Identified_Pain_Point__c> results = [
        SELECT Id, Name, Unique_Key__c, Occurrences__c
        FROM Identified_Pain_Point__c
        WITH SECURITY_ENFORCED
        LIMIT 5
    ];
    System.debug('    SUCCESS - ' + results.size() + ' records (WITH SECURITY_ENFORCED passed)');
} catch (System.QueryException e) {
    System.debug('    BLOCKED - Query blocked by SECURITY_ENFORCED: ' + e.getMessage().left(80));
}

// Test 5.2: Query with USER_MODE
System.debug('  5.2 Query with USER_MODE:');
try {
    List<Identified_Pain_Point__c> results = [
        SELECT Id, Name, Unique_Key__c
        FROM Identified_Pain_Point__c
        WITH USER_MODE
        LIMIT 5
    ];
    System.debug('    SUCCESS - ' + results.size() + ' records (WITH USER_MODE passed)');
} catch (System.QueryException e) {
    System.debug('    BLOCKED - Query blocked by USER_MODE: ' + e.getMessage().left(80));
}

// Test 5.3: stripInaccessible test
System.debug('  5.3 stripInaccessible test:');
try {
    List<Identified_Pain_Point__c> rawResults = [
        SELECT Id, Name, Unique_Key__c, Occurrences__c, Impact_Score__c, Description__c
        FROM Identified_Pain_Point__c
        LIMIT 5
    ];
    SObjectAccessDecision decision = Security.stripInaccessible(AccessType.READABLE, rawResults);
    Set<String> removedFields = decision.getRemovedFields().get('Identified_Pain_Point__c');
    if (removedFields != null && !removedFields.isEmpty()) {
        System.debug('    Fields stripped due to FLS: ' + removedFields);
    } else {
        System.debug('    SUCCESS - All fields accessible');
    }
} catch (Exception e) {
    System.debug('    BLOCKED - ' + e.getMessage().left(100));
}

System.debug('');

// ============================================================================
// SECTION 6: PAIN POINT VERIFICATION QUERIES
// ============================================================================
System.debug('--- Section 6: Pain Point Verification Queries ---');

try {
    // Count all pain points
    System.debug('  All Pain Points:');
    for (AggregateResult ar : [
        SELECT Unique_Key__c, Occurrences__c, Status__c
        FROM Identified_Pain_Point__c
        GROUP BY Unique_Key__c, Occurrences__c, Status__c
        ORDER BY Unique_Key__c
    ]) {
        System.debug('    ' + ar.get('Unique_Key__c') + ': ' + ar.get('Occurrences__c') + ' occurrences (' + ar.get('Status__c') + ')');
    }
} catch (Exception e) {
    System.debug('  BLOCKED - Cannot query pain points: ' + e.getMessage().left(80));
}

System.debug('');

// ============================================================================
// SECTION 7: MOCK DATA VERIFICATION QUERIES
// ============================================================================
System.debug('--- Section 7: Mock Data Verification Queries ---');

System.debug('  Contacts missing data (Contact_Data_Gap):');
try {
    Integer count = [SELECT COUNT() FROM Contact WHERE Email = null OR Phone = null];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Orphan contacts (Orphan_Contact):');
try {
    Integer count = [SELECT COUNT() FROM Contact WHERE AccountId = null];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  High-value opportunities (High_Value_Ghosting):');
try {
    Integer count = [SELECT COUNT() FROM Opportunity WHERE Amount > 50000 AND IsClosed = false AND LastActivityDate = null];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Orphan opportunities (Orphan_Opportunity):');
try {
    Integer count = [SELECT COUNT() FROM Opportunity WHERE AccountId = null];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Orphan cases (Orphan_Case):');
try {
    Integer count = [SELECT COUNT() FROM Case WHERE AccountId = null AND ContactId = null];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Duplicate leads:');
try {
    Integer dupCount = 0;
    for (AggregateResult ar : [
        SELECT Email, COUNT(Id) cnt
        FROM Lead
        WHERE Email != null
        GROUP BY Email
        HAVING COUNT(Id) > 1
    ]) {
        dupCount += (Integer)ar.get('cnt');
    }
    System.debug('    Total duplicates: ' + dupCount);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Duplicate contacts:');
try {
    Integer dupCount = 0;
    for (AggregateResult ar : [
        SELECT Email, COUNT(Id) cnt
        FROM Contact
        WHERE Email != null
        GROUP BY Email
        HAVING COUNT(Id) > 1
    ]) {
        dupCount += (Integer)ar.get('cnt');
    }
    System.debug('    Total duplicates: ' + dupCount);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Duplicate accounts:');
try {
    Integer dupCount = 0;
    for (AggregateResult ar : [
        SELECT Name, COUNT(Id) cnt
        FROM Account
        WHERE Name != null
        GROUP BY Name
        HAVING COUNT(Id) > 1
    ]) {
        dupCount += (Integer)ar.get('cnt');
    }
    System.debug('    Total duplicates: ' + dupCount);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('  Premature escalations:');
try {
    Integer count = [SELECT COUNT() FROM Case WHERE IsEscalated = true AND Priority != 'High'];
    System.debug('    Count: ' + count);
} catch (Exception e) {
    System.debug('    Error: ' + e.getMessage().left(80));
}

System.debug('');

// ============================================================================
// SUMMARY
// ============================================================================
System.debug('=== PERMISSION TEST QUERIES COMPLETE ===');
System.debug('');
System.debug('Review the output above and compare with expected results in:');
System.debug('  docs/E2E_TEST_CASES_PATTERN_BEHAVIOR.md');
System.debug('');
System.debug('EXPECTED RESULTS BY USER TYPE:');
System.debug('  Admin (BehaviorIQ_Admin): All queries should succeed');
System.debug('  Unprivileged: All BehaviorIQ queries should FAIL');
System.debug('');
