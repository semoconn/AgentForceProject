// BehaviorIQ Partial Fix Simulation Test
// This script verifies that partial fixes correctly UPDATE the pain point instead of creating new ones

System.debug('=== PARTIAL FIX SIMULATION TEST ===');

// Step 1: Create a test pain point with 5 records
List<Case> testCases = [SELECT Id FROM Case WHERE IsClosed = false LIMIT 5];
if (testCases.size() < 5) {
    System.debug('ERROR: Need at least 5 open Cases for this test. Found: ' + testCases.size());
    return;
}

List<String> allCaseIds = new List<String>();
for (Case c : testCases) {
    allCaseIds.add(c.Id);
}

// Delete any existing test pain point
delete [SELECT Id FROM Identified_Pain_Point__c WHERE Unique_Key__c = 'Partial_Fix_Test'];

// Create fresh pain point
Identified_Pain_Point__c pp = new Identified_Pain_Point__c(
    Name = 'Partial Fix Test',
    Object_API_Name__c = 'Case',
    Status__c = 'New',
    Description__c = 'Testing partial fix behavior',
    Occurrences__c = 5,
    Impact_Score__c = 500,
    Example_Records__c = JSON.serialize(allCaseIds),
    Unique_Key__c = 'Partial_Fix_Test'
);
insert pp;
System.debug('Created pain point ID: ' + pp.Id + ' with ' + allCaseIds.size() + ' records');

// Step 2: Simulate partial fix of 2 records
List<String> fixedIds = new List<String>{ allCaseIds[0], allCaseIds[1] };
String fixedIdsJson = JSON.serialize(fixedIds);

System.debug('Simulating fix of 2 records: ' + fixedIdsJson);

// Call the markPainPointResolved method
WorkflowAnalyticsController.markPainPointResolved(pp.Id, 2, 5, fixedIdsJson);

// Step 3: Verify the result
Identified_Pain_Point__c updated = [
    SELECT Id, Name, Status__c, Occurrences__c, Impact_Score__c, Example_Records__c
    FROM Identified_Pain_Point__c
    WHERE Id = :pp.Id
];

System.debug('=== POST PARTIAL FIX VERIFICATION ===');
System.debug('Status: ' + updated.Status__c + ' (expected: New)');
System.debug('Occurrences: ' + updated.Occurrences__c + ' (expected: 3)');
System.debug('Impact Score: ' + updated.Impact_Score__c + ' (expected: 300)');
System.debug('Example_Records: ' + updated.Example_Records__c);

// Parse and count remaining records
List<Object> remainingIds = (List<Object>)JSON.deserializeUntyped(updated.Example_Records__c);
System.debug('Remaining record count: ' + remainingIds.size() + ' (expected: 3)');

// Verify no duplicate pain points were created
Integer totalPainPoints = [SELECT COUNT() FROM Identified_Pain_Point__c WHERE Unique_Key__c = 'Partial_Fix_Test'];
System.debug('Total pain points with this key: ' + totalPainPoints + ' (expected: 1)');

// Test assertions
Boolean passed = true;
if (updated.Status__c != 'New') { System.debug('FAIL: Status should be New'); passed = false; }
if (updated.Occurrences__c != 3) { System.debug('FAIL: Occurrences should be 3'); passed = false; }
if (remainingIds.size() != 3) { System.debug('FAIL: Remaining records should be 3'); passed = false; }
if (totalPainPoints != 1) { System.debug('FAIL: Should have exactly 1 pain point'); passed = false; }

// Step 4: Simulate second partial fix (fix 2 more, leaving 1)
System.debug('\n=== SECOND PARTIAL FIX ===');
List<String> secondFixIds = new List<String>{ (String)remainingIds[0], (String)remainingIds[1] };
WorkflowAnalyticsController.markPainPointResolved(pp.Id, 2, 3, JSON.serialize(secondFixIds));

updated = [
    SELECT Id, Status__c, Occurrences__c, Example_Records__c
    FROM Identified_Pain_Point__c
    WHERE Id = :pp.Id
];

System.debug('Status after 2nd partial: ' + updated.Status__c + ' (expected: New)');
System.debug('Occurrences after 2nd partial: ' + updated.Occurrences__c + ' (expected: 1)');

remainingIds = (List<Object>)JSON.deserializeUntyped(updated.Example_Records__c);
System.debug('Remaining after 2nd partial: ' + remainingIds.size() + ' (expected: 1)');

if (updated.Occurrences__c != 1) { System.debug('FAIL: Occurrences should be 1'); passed = false; }
if (remainingIds.size() != 1) { System.debug('FAIL: Remaining should be 1'); passed = false; }

// Step 5: Final fix - complete all remaining
System.debug('\n=== FINAL FIX (Complete All) ===');
List<String> lastId = new List<String>{ (String)remainingIds[0] };
WorkflowAnalyticsController.markPainPointResolved(pp.Id, 1, 1, JSON.serialize(lastId));

updated = [
    SELECT Id, Status__c, Occurrences__c, Example_Records__c
    FROM Identified_Pain_Point__c
    WHERE Id = :pp.Id
];

System.debug('Final Status: ' + updated.Status__c + ' (expected: Resolved)');
System.debug('Final Example_Records: ' + updated.Example_Records__c + ' (expected: [])');

if (updated.Status__c != 'Resolved') { System.debug('FAIL: Final status should be Resolved'); passed = false; }
if (updated.Example_Records__c != '[]') { System.debug('FAIL: Example_Records should be empty array'); passed = false; }

// Final verification - still only 1 pain point
totalPainPoints = [SELECT COUNT() FROM Identified_Pain_Point__c WHERE Unique_Key__c = 'Partial_Fix_Test'];
System.debug('Final pain point count: ' + totalPainPoints + ' (expected: 1)');
if (totalPainPoints != 1) { System.debug('FAIL: Should still have exactly 1 pain point'); passed = false; }

System.debug('\n=== TEST RESULT: ' + (passed ? 'ALL PASSED' : 'SOME FAILED') + ' ===');

// Cleanup
delete [SELECT Id FROM Identified_Pain_Point__c WHERE Unique_Key__c = 'Partial_Fix_Test'];
System.debug('Test cleanup complete');
