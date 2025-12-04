import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardData from '@salesforce/apex/WorkflowAnalyticsController.getDashboardData';
import getPainPoints from '@salesforce/apex/WorkflowAnalyticsController.getPainPoints';
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix';
import dismissSuggestion from '@salesforce/apex/WorkflowAnalyticsController.dismissSuggestion';
import { refreshApex } from '@salesforce/apex';
import { updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Id';
import STATUS_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Status__c';

const ACTIONS = [
    { label: 'View Details', name: 'view_details' },
    { label: 'Dismiss', name: 'dismiss' }
];

export default class BehaviorIQDashboard extends LightningElement {
    @track allPainPoints = [];
    @track metrics = [];
    @track recentLogs = [];
    @track isPremium = false;
    @track isLoading = true;
    
    // Modal & Tabs
    @track isModalOpen = false;
    @track activeTab = 'settings'; 
    
    // Solution Modal
    @track isSolutionModalOpen = false;
    @track selectedRow = {};
    @track solutionSteps = [];

    // Filter State
    @track currentFilter = 'Active'; 

    // Wired Results (Stored for Refresh)
    _wiredPainPointsResult;
    _wiredDashboardResult;

    connectedCallback() {
        // No imperative call needed here as we use wires
    }

    // 1. Load Dashboard (License & Metrics)
    @wire(getDashboardData)
    wiredDashboard(result) {
        this._wiredDashboardResult = result;
        if (result.data) {
            this.isPremium = result.data.isPremium;
            
            // Flatten User Name for Recent Logs
            this.recentLogs = result.data.recentLogs.map(log => ({
                ...log,
                UserName: log.User__r ? log.User__r.Name : 'System'
            }));

            // Process metrics
            this.metrics = result.data.metrics.map(m => ({
                ...m,
                trendClass: m.type === 'alert' ? 'slds-text-color_error' : 'slds-text-color_success'
            }));
        } else if (result.error) {
            console.error('Error loading dashboard:', result.error);
        }
    }

    // 2. Load Recommendations
    @wire(getPainPoints)
    wiredData(result) {
        this._wiredPainPointsResult = result;
        if (result.data) {
            this.allPainPoints = result.data;
            this.isLoading = false;
        } else if (result.error) {
            console.error('Error fetching pain points:', result.error);
            this.allPainPoints = [];
            this.showToast('Error', 'Failed to load findings.', 'error');
            this.isLoading = false;
        }
    }

    // --- Getters for Filters ---
    get filteredPainPoints() {
        if (!this.allPainPoints) return [];
        switch (this.currentFilter) {
            case 'Active':
                return this.allPainPoints.filter(item => item.Status__c !== 'Dismissed' && item.Status__c !== 'Resolved');
            case 'Dismissed':
                return this.allPainPoints.filter(item => item.Status__c === 'Dismissed' || item.Status__c === 'Resolved');
            case 'All':
            default:
                return this.allPainPoints;
        }
    }

    get hasPainPoints() { return this.filteredPainPoints.length > 0; }
    get filteredCount() { return this.filteredPainPoints.length; }

    get allVariant() { return this.currentFilter === 'All' ? 'brand' : 'neutral'; }
    get activeVariant() { return this.currentFilter === 'Active' ? 'brand' : 'neutral'; }
    get dismissedVariant() { return this.currentFilter === 'Dismissed' ? 'brand' : 'neutral'; }

    get isFixDisabled() { return !this.isPremium; }

    // NEW: Dynamic Tooltip
    get autoFixButtonTitle() {
        return this.isPremium ? 'Apply Auto-Fix' : 'Apply Auto-Fix (Premium)';
    }

    // --- Actions ---
    filterAll() { this.currentFilter = 'All'; }
    filterActive() { this.currentFilter = 'Active'; }
    filterDismissed() { this.currentFilter = 'Dismissed'; }

    handleRefresh() { 
        this.isLoading = true;
        
        const dashboardPromise = refreshApex(this._wiredDashboardResult);
        const painPointsPromise = refreshApex(this._wiredPainPointsResult);

        const leaderboard = this.template.querySelector('c-user-leaderboard');
        let leaderboardPromise = Promise.resolve();
        if (leaderboard && typeof leaderboard.refresh === 'function') {
            leaderboardPromise = leaderboard.refresh();
        }

        return Promise.all([dashboardPromise, painPointsPromise, leaderboardPromise])
            .then(() => { 
                this.isLoading = false; 
                this.showToast('Success', 'Dashboard refreshed', 'success');
            })
            .catch(error => {
                this.isLoading = false;
                console.error('Refresh error:', error);
            });
    }

    handleUpgradeRequest() {
        this.handlePremiumClick();
    }

    // --- AUTO-FIX LOGIC (FIXED) ---
    handleAutoFix(event) {
        if (!this.isPremium) {
            this.handlePremiumClick();
            return;
        }

        // Get values from button dataset OR selected row context
        let rawId = event.currentTarget.dataset.id;
        let objectApiName = event.currentTarget.dataset.type;

        // Fallback to selectedRow if we are in the modal context
        if (!rawId && this.selectedRow) {
            rawId = this.selectedRow.Example_Records__c;
        }
        if (!objectApiName && this.selectedRow) {
            objectApiName = this.selectedRow.Object_API_Name__c;
        }

        if (!rawId) {
            this.showToast('Error', 'No target record ID found for this recommendation.', 'error');
            return;
        }

        if (!objectApiName) {
            this.showToast('Error', 'Unknown fix type. Cannot proceed.', 'error');
            return;
        }

        // FIX: Convert Object API Name to the fixType expected by Apex
        const fixType = this.mapObjectToFixType(objectApiName);
        
        if (!fixType) {
            this.showToast('Error', `No Auto-Fix available for ${objectApiName} records yet.`, 'warning');
            return;
        }

        // Ensure rawId is a string before splitting
        const idString = String(rawId);
        
        // Split by comma, trim whitespace, and filter out empty strings
        const recordIds = idString.split(',')
            .map(id => id.trim())
            .filter(id => id.length > 0);

        if (recordIds.length === 0) {
            this.showToast('Error', 'Could not parse valid Record IDs.', 'error');
            return;
        }

        console.log('=== AUTO-FIX DEBUG ===');
        console.log('Object API Name:', objectApiName);
        console.log('Mapped fixType:', fixType);
        console.log('Record IDs:', recordIds);
        console.log('Record IDs type:', typeof recordIds);
        console.log('Record IDs isArray:', Array.isArray(recordIds));

        this.isLoading = true;

        runAutoFix({ recordIds: recordIds, fixType: fixType })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.closeSolutionModal();
                return refreshApex(this._wiredPainPointsResult);
            })
            .catch(error => {
                console.error('Auto-Fix Failed:', error);
                let message = 'Unknown error';
                if (error && error.body && error.body.message) {
                    message = error.body.message;
                } else if (error && error.body && Array.isArray(error.body)) {
                    message = error.body.map(e => e.message).join(', ');
                } else if (typeof error === 'string') {
                    message = error;
                }
                this.showToast('Auto-Fix Failed', message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // CRITICAL FIX: Map Object API Names to fixType strings expected by Apex
    mapObjectToFixType(objectApiName) {
        const mapping = {
            'Case': 'Stale Case',
            'Lead': 'Unassigned Lead',
            'Opportunity': 'Stale Opportunity', // Add more as you implement them in Apex
            'Account': 'Hoarding Records',
            'Contact': 'Duplicate Contacts'
        };
        return mapping[objectApiName] || null;
    }

    // --- Dismiss Logic ---
    handleDismiss(event) {
        const painPointId = event.currentTarget.dataset.id;
        if(!painPointId) return;

        this.isLoading = true;

        dismissSuggestion({ painPointId: painPointId })
            .then(result => {
                this.showToast('Dismissed', result, 'success');
                return refreshApex(this._wiredPainPointsResult);
            })
            .catch(error => {
                this.showToast('Error', 'Could not dismiss suggestion', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // --- Modal Handling ---
    handleViewDetails(event) {
        const rowId = event.currentTarget.dataset.id; 
        
        if (rowId) {
            this.selectedRow = this.allPainPoints.find(row => row.Id === rowId);
            if (this.selectedRow) {
                this.solutionSteps = this.getStepsForType(this.selectedRow.Object_API_Name__c);
                this.isSolutionModalOpen = true;
            }
        }
    }

    closeSolutionModal() {
        this.isSolutionModalOpen = false;
    }

    openAdminModal(event) {
        const targetTab = event.currentTarget.dataset.tab;
        this.activeTab = targetTab ? targetTab : 'settings';
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    handlePremiumClick() {
        this.closeSolutionModal();
        this.activeTab = 'licensing';
        this.isModalOpen = true; 
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getStepsForType(type) {
        switch (type) {
            case 'Opportunity':
                return [
                    'ROOT CAUSE: Opportunities often stall due to lack of structured follow-up processes.',
                    'MANUAL FIX: Create a Scheduled Flow that runs daily.',
                    'LOGIC: If Stage is not "Closed" AND LastActivityDate > 30 days, send an email alert to the Owner.',
                    'OPTIONAL: Add a validation rule preventing Stage regression without a logged Task.'
                ];
            case 'Lead':
                return [
                    'ROOT CAUSE: "New" leads are not being claimed by sales reps, indicating a queue visibility issue.',
                    'MANUAL FIX: Configure an Omni-Channel Queue or Assignment Rule.',
                    'LOGIC: If Status = "New" for > 48 hours, re-assign to the "General Sales Manager" or "Unassigned Queue".',
                    'TIP: Use a Formula Field to visually flag "Stale Leads" on List Views.'
                ];
            case 'Task': 
                return [
                    'ROOT CAUSE: High volume creation suggests an API loop or a malfunctioning Flow/Trigger.',
                    'INVESTIGATE: Go to Setup > Apex Jobs to check for recursive triggers.',
                    'MANUAL FIX: Deactivate the integration user immediately if unauthorized.',
                    'CLEANUP: Use Data Loader to mass delete the erroneous task records.'
                ];
            case 'Case':
                return [
                    'ROOT CAUSE: Cases are sitting in "Open" status, violating potential SLAs.',
                    'MANUAL FIX: Setup Standard Entitlement Processes and Milestones.',
                    'LOGIC: Configure warning actions (email alerts) 1 hour before SLA breach.',
                    'REVIEW: Check if the "Case Owner" is an inactive user or a queue with no members.'
                ];
            default:
                return [
                    'Analyze the record history for unusual patterns.',
                    'Check with the record owner for context.',
                    'Review recent automation changes in the Audit Trail.'
                ];
        }
    }
}