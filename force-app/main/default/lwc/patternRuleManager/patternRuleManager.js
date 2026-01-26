import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getAllPatternRules from '@salesforce/apex/PatternRuleManagerController.getAllPatternRules';
import checkLicenseStatus from '@salesforce/apex/LicenseService.checkLicenseStatus';

export default class PatternRuleManager extends LightningElement {
    @track isLoading = true;
    @track isLicenseLoading = true;
    @track licenseStatus;
    @track rules = [];
    @track filteredRules = [];
    @track error;

    // Modal state
    @track isEditorOpen = false;
    @track editorMode = 'create'; // 'create' | 'edit' | 'clone'
    @track selectedRule = null;

    // Filter state
    @track activeFilter = 'all';

    // Wired result for refresh
    wiredRulesResult;

    // Check license status
    @wire(checkLicenseStatus)
    wiredLicenseStatus({ error, data }) {
        this.isLicenseLoading = false;
        if (data) {
            this.licenseStatus = data;
        } else if (error) {
            // Default to Free on error (security by default)
            this.licenseStatus = 'Free';
            console.error('Error checking license status:', error);
        }
    }

    @wire(getAllPatternRules)
    wiredRules(result) {
        this.wiredRulesResult = result;
        this.isLoading = true;

        if (result.data) {
            this.rules = result.data;
            this.applyFilter();
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = result.error;
            this.rules = [];
            this.filteredRules = [];
            this.isLoading = false;
            console.error('Error loading rules:', result.error);
        }
    }

    // License computed properties
    get isPremium() {
        return this.licenseStatus === 'Premium';
    }

    get showUpgradeScreen() {
        return !this.isLicenseLoading && !this.isPremium;
    }

    get showRuleManager() {
        return !this.isLicenseLoading && this.isPremium;
    }

    // Computed properties
    get hasRules() {
        return this.filteredRules && this.filteredRules.length > 0;
    }

    get ruleCount() {
        return this.filteredRules ? this.filteredRules.length : 0;
    }

    get totalCount() {
        return this.rules ? this.rules.length : 0;
    }

    get activeCount() {
        return this.rules ? this.rules.filter(r => r.isActive).length : 0;
    }

    get inactiveCount() {
        return this.rules ? this.rules.filter(r => !r.isActive).length : 0;
    }

    get premiumCount() {
        return this.rules ? this.rules.filter(r => r.isPremium).length : 0;
    }

    // Filter button variants
    get allVariant() {
        return this.activeFilter === 'all' ? 'brand' : 'neutral';
    }

    get activeVariant() {
        return this.activeFilter === 'active' ? 'brand' : 'neutral';
    }

    get inactiveVariant() {
        return this.activeFilter === 'inactive' ? 'brand' : 'neutral';
    }

    get premiumVariant() {
        return this.activeFilter === 'premium' ? 'brand' : 'neutral';
    }

    // Filter labels with counts
    get allLabel() {
        return `All (${this.totalCount})`;
    }

    get activeLabel() {
        return `Active (${this.activeCount})`;
    }

    get inactiveLabel() {
        return `Inactive (${this.inactiveCount})`;
    }

    get premiumLabel() {
        return `Premium (${this.premiumCount})`;
    }

    get isFilterActive() {
        return this.activeFilter !== 'all';
    }

    // Filter handlers
    handleFilterAll() {
        this.activeFilter = 'all';
        this.applyFilter();
    }

    handleFilterActive() {
        this.activeFilter = 'active';
        this.applyFilter();
    }

    handleFilterInactive() {
        this.activeFilter = 'inactive';
        this.applyFilter();
    }

    handleFilterPremium() {
        this.activeFilter = 'premium';
        this.applyFilter();
    }

    applyFilter() {
        if (!this.rules) {
            this.filteredRules = [];
            return;
        }

        switch (this.activeFilter) {
            case 'active':
                this.filteredRules = this.rules.filter(r => r.isActive);
                break;
            case 'inactive':
                this.filteredRules = this.rules.filter(r => !r.isActive);
                break;
            case 'premium':
                this.filteredRules = this.rules.filter(r => r.isPremium);
                break;
            default:
                this.filteredRules = [...this.rules];
        }
    }

    // Action handlers
    handleCreateRule() {
        this.editorMode = 'create';
        this.selectedRule = null;
        this.isEditorOpen = true;
    }

    handleEditRule(event) {
        const developerName = event.detail.developerName;
        const rule = this.rules.find(r => r.developerName === developerName);

        if (rule) {
            this.editorMode = 'edit';
            this.selectedRule = { ...rule };
            this.isEditorOpen = true;
        }
    }

    handleCloneRule(event) {
        const developerName = event.detail.developerName;
        const rule = this.rules.find(r => r.developerName === developerName);

        if (rule) {
            this.editorMode = 'clone';
            // Clone the rule but clear the developerName so a new one is generated
            this.selectedRule = {
                ...rule,
                developerName: null,
                label: rule.label + ' (Copy)'
            };
            this.isEditorOpen = true;
        }
    }

    handleDeactivateRule(event) {
        // Dispatch to list component to handle
        const listComponent = this.template.querySelector('c-pattern-rule-list');
        if (listComponent) {
            listComponent.deactivateRule(event.detail.developerName);
        }
    }

    handleReactivateRule(event) {
        const listComponent = this.template.querySelector('c-pattern-rule-list');
        if (listComponent) {
            listComponent.reactivateRule(event.detail.developerName);
        }
    }

    handleEditorClose() {
        this.isEditorOpen = false;
        this.selectedRule = null;
    }

    handleEditorSave(event) {
        this.isEditorOpen = false;
        this.selectedRule = null;

        // Show deploying toast
        this.showToast('Deploying', 'Rule is being deployed. This may take a moment...', 'info');

        // Refresh after a short delay to allow deployment to complete
        // In a real app, we'd poll for deployment status
        setTimeout(() => {
            this.refreshData();
        }, 3000);
    }

    handleRefresh() {
        this.refreshData();
    }

    handleRuleUpdated(event) {
        const { developerName, isActive, optimistic, rollback } = event.detail || {};

        if (optimistic) {
            // Immediately update local state for instant feedback
            this.updateRuleActiveState(developerName, isActive);
            return;
        }

        if (rollback) {
            // Revert the optimistic update on error
            this.updateRuleActiveState(developerName, isActive);
            this.showToast('Error', 'Failed to update rule. Changes have been reverted.', 'error');
            return;
        }

        // Deployment started successfully - show confirmation and schedule background refresh
        this.showToast('Success', `Rule ${isActive ? 'activated' : 'deactivated'} successfully`, 'success');

        // Refresh in background after deployment likely completes (for data consistency)
        setTimeout(() => {
            this.refreshDataSilently();
        }, 5000);
    }

    /**
     * Updates a rule's active state in local data (optimistic update)
     */
    updateRuleActiveState(developerName, isActive) {
        if (!developerName) return;

        this.rules = this.rules.map(rule => {
            if (rule.developerName === developerName) {
                return { ...rule, isActive };
            }
            return rule;
        });
        this.applyFilter();
    }

    /**
     * Silently refresh data without showing toast (for background sync)
     */
    async refreshDataSilently() {
        try {
            await refreshApex(this.wiredRulesResult);
        } catch (error) {
            console.error('Background refresh error:', error);
        }
    }

    async refreshData() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredRulesResult);
            this.showToast('Success', 'Rules refreshed successfully', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to refresh rules', 'error');
            console.error('Refresh error:', error);
        }
        this.isLoading = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    handleUpgradeClick() {
        this.showToast(
            'Upgrade to Premium',
            'Please contact your Salesforce administrator or visit the AppExchange listing to upgrade to BehaviorIQ Premium.',
            'info'
        );
    }
}
