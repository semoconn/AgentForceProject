/**
 * Find all Lead Queues in the org and output their IDs
 *
 * You'll need a Queue ID for the Unassigned_Lead_48 pattern test data.
 * Run this script first to find available queues, then use the ID in the CSV import.
 */

// Find all Queues that support Lead object
List<Group> leadQueues = [
    SELECT Id, Name, DeveloperName, Type
    FROM Group
    WHERE Type = 'Queue'
    AND Id IN (SELECT QueueId FROM QueueSobject WHERE SobjectType = 'Lead')
];

System.debug('=== LEAD QUEUES FOUND ===');
System.debug('Total Lead Queues: ' + leadQueues.size());
System.debug('');

if (leadQueues.isEmpty()) {
    System.debug('WARNING: No Lead queues found!');
    System.debug('You need to create a Lead queue in Setup > Queues before importing the CSV.');
    System.debug('');
    System.debug('To create a queue:');
    System.debug('1. Go to Setup > Queues');
    System.debug('2. Click "New"');
    System.debug('3. Name: "Lead Queue" (or similar)');
    System.debug('4. Add "Lead" to Supported Objects');
    System.debug('5. Add yourself as a Queue Member');
    System.debug('6. Save');
} else {
    System.debug('Copy one of these Queue IDs for the CSV import:');
    System.debug('');
    for (Group q : leadQueues) {
        System.debug('Queue Name: ' + q.Name);
        System.debug('Queue ID:   ' + q.Id);
        System.debug('Developer Name: ' + q.DeveloperName);
        System.debug('---');
    }
}

System.debug('');
System.debug('=== NEXT STEPS ===');
System.debug('1. Copy a Queue ID from above');
System.debug('2. Open scripts/data/unassigned_lead_48_import.csv');
System.debug('3. Replace REPLACE_WITH_QUEUE_ID with the actual Queue ID');
System.debug('4. Import via Data Loader with "Set Audit Fields" enabled');
