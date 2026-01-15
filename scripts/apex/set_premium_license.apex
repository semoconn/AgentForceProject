// Set license to Premium for testing
BehaviorIQ_License__c license = BehaviorIQ_License__c.getOrgDefaults();
if (license.Id == null) {
    license = new BehaviorIQ_License__c(SetupOwnerId = UserInfo.getOrganizationId());
}
license.Status__c = 'Premium';
upsert license;
System.debug('License set to: ' + license.Status__c);
