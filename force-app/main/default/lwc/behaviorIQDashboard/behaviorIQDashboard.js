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

    wiredPainPointsResult;

    connectedCallback() {
        this.loadDashboard();
    }

    // 1. Load Dashboard (License & Metrics)
    loadDashboard() {
        getDashboardData()
            .then(result => {
                this.isPremium = result.isPremium;
                
                // Flatten User Name for Recent Logs
                this.recentLogs = result.recentLogs.map(log => ({
                    ...log,
                    UserName: log.User__r ? log.User__r.Name : 'System'
                }));

                // Process metrics
                this.metrics = result.metrics.map(m => ({
                    ...m,
                    trendClass: m.type === 'alert' ? 'slds-text-color_error' : 'slds-text-color_success'
                }));
            })
            .catch(error => {
                console.error('Error loading dashboard:', error);
            });
    }

    // 2. Load Recommendations
    @wire(getPainPoints)
    wiredData(result) {
        this.wiredPainPointsResult = result;
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
        this.loadDashboard();
        return refreshApex(this.wiredPainPointsResult)
            .then(() => { this.isLoading = false; });
    }

    // --- AUTO-FIX LOGIC ---
    handleAutoFix(event) {
        if (!this.isPremium) {
            this.handlePremiumClick();
            return;
        }

        const recordId = event.currentTarget.dataset.id || (this.selectedRow ? this.selectedRow.Example_Records__c : null);
        const fixType = event.currentTarget.dataset.type || (this.selectedRow ? this.selectedRow.Object_API_Name__c : null);

        if (!recordId) {
            this.showToast('Error', 'No target record ID found for this recommendation.', 'error');
            return;
        }

        if (!fixType) {
            this.showToast('Error', 'Unknown fix type. Cannot proceed.', 'error');
            return;
        }

        this.isLoading = true;

        runAutoFix({ recordIds: [recordId], fixType: fixType })
            .then(result => {
                this.showToast('Success', result, 'success');
                this.closeSolutionModal();
                return refreshApex(this.wiredPainPointsResult);
            })
            .catch(error => {
                let message = 'Unknown error';
                if (error && error.body && error.body.message) {
                    message = error.body.message;
                }
                this.showToast('Auto-Fix Failed', message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // --- Dismiss Logic ---
    handleDismiss(event) {
        const painPointId = event.currentTarget.dataset.id;
        if(!painPointId) return;

        this.isLoading = true;

        dismissSuggestion({ painPointId: painPointId })
            .then(result => {
                this.showToast('Dismissed', result, 'success');
                return refreshApex(this.wiredPainPointsResult);
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
        // Use data-id to find the record, bypassing the need to pass object in HTML
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