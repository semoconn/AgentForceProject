/**
 * Creates test data for Missing Attachment patterns:
 * - Missing_Attachment_Closed_Case: Closed cases WITHOUT file attachments
 * - Missing_Attachment_Closed_Won: Closed Won opportunities WITHOUT file attachments
 *
 * Run this script, then execute PatternAnalysisBatch to detect the patterns.
 * Pain points should appear IMMEDIATELY after batch completes.
 */

// ============================================
// PART 1: Create Closed Cases WITHOUT Attachments
// Pattern: Missing_Attachment_Closed_Case
// Condition: Status = 'Closed' AND ClosedDate >= LAST_N_DAYS:30
// ============================================

List<Case> casesNoAttachment = new List<Case>();
for (Integer i = 1; i <= 8; i++) {
    casesNoAttachment.add(new Case(
        Subject = 'BIQ Test - Closed Case Missing Documentation ' + i,
        Status = 'Closed',
        Origin = 'Email',
        Priority = 'Medium',
        Description = 'This case was closed without proper resolution documentation attached. ' +
                      'The MissingAttachmentPlugin should detect this record.'
    ));
}
insert casesNoAttachment;
System.debug('SUCCESS: Created ' + casesNoAttachment.size() + ' closed cases WITHOUT attachments');

// Log the IDs for verification
for (Case c : casesNoAttachment) {
    System.debug('  Case ID: ' + c.Id + ' - ' + c.Subject);
}

// ============================================
// PART 2: Create Closed Won Opportunities WITHOUT Attachments
// Pattern: Missing_Attachment_Closed_Won
// Condition: StageName = 'Closed Won' AND CloseDate >= LAST_N_DAYS:90
// ============================================

List<Opportunity> oppsNoAttachment = new List<Opportunity>();
for (Integer i = 1; i <= 8; i++) {
    oppsNoAttachment.add(new Opportunity(
        Name = 'BIQ Test - Closed Won Missing Contract ' + i,
        StageName = 'Closed Won',
        CloseDate = Date.today().addDays(-5 * i), // Stagger dates within last 90 days
        Amount = 25000 + (i * 15000), // $40K to $145K range
        Description = 'This closed-won opportunity is missing contract documentation. ' +
                      'The MissingAttachmentPlugin should detect this record.'
    ));
}
insert oppsNoAttachment;
System.debug('SUCCESS: Created ' + oppsNoAttachment.size() + ' Closed Won opportunities WITHOUT attachments');

// Log the IDs for verification
for (Opportunity o : oppsNoAttachment) {
    System.debug('  Opp ID: ' + o.Id + ' - ' + o.Name + ' - Amount: $' + o.Amount);
}

// ============================================
// VERIFICATION
// ============================================
System.debug('');
System.debug('=== DATA CREATED ===');

Integer closedCases = [SELECT COUNT() FROM Case WHERE Status = 'Closed' AND Subject LIKE 'BIQ Test - Closed Case Missing%'];
System.debug('Closed cases created (no attachments): ' + closedCases);

Integer closedWonOpps = [SELECT COUNT() FROM Opportunity WHERE StageName = 'Closed Won' AND Name LIKE 'BIQ Test - Closed Won Missing%'];
System.debug('Closed Won opportunities created (no attachments): ' + closedWonOpps);

System.debug('');
System.debug('=== NEXT STEPS ===');
System.debug('1. Run: Database.executeBatch(new PatternAnalysisBatch(), 200);');
System.debug('2. Wait for batch to complete');
System.debug('3. Check for Missing_Attachment_Closed_Case and Missing_Attachment_Closed_Won pain points');
