// Check if we can query the org settings for audit fields
// Note: This requires manual enablement in Setup > User Interface > "Enable 'Set Audit Fields upon Record Creation' and 'Update Records with Inactive Owners' User Permissions"

System.debug('=== Audit Fields Check ===');
System.debug('To enable audit fields for backdating:');
System.debug('1. Go to Setup > User Interface');
System.debug('2. Enable "Set Audit Fields upon Record Creation"');
System.debug('3. Enable "Update Records with Inactive Owners"');
System.debug('4. Assign the "Set Audit Fields upon Record Creation" permission to your user profile or permission set');
System.debug('');
System.debug('After enabling, re-run this script to create backdated test data.');
