import { LightningElement, wire, track } from 'lwc';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';
import getDashboardData from '@salesforce/apex/WorkflowAnalyticsController.getDashboardData'; // NEW: For License Status
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix'; // NEW: Gated Action
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Id';
import STATUS_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Status__c';

const ACTIONS = [
    { label: 'View Details', name: 'view_details' },
    { label: 'Dismiss', name: 'dismiss' }
];

// FIX: Updated to use CreatedDate since Timestamp__c does not exist on Behavior_Log__c
const COLUMNS = [
    { label: 'Timestamp', fieldName: 'CreatedDate', type: 'date', 
      typeAttributes: { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' } },
    { label: 'Action', fieldName: 'Action_Name__c', type: 'text' },
    { label: 'Object', fieldName: 'Object_API_Name__c', type: 'text' },
    { label: 'User', fieldName: 'UserName', type: 'text' }
];

// Note: I am assuming this LWC is responsible for the dashboard logic. 
// The previous file content you shared showed PainPoint logic in this file, 
// but my previous instruction generated code for the Dashboard view. 
// I will merge the Dashboard Gating logic into your PainPoint logic below.

export default class BehaviorIQDashboard extends LightningElement {
    // --- EXISTING PROPERTIES ---
    @track allPainPoints = [];
    
    // IMPORTANT: I'm using your existing PainPoint columns here for the main table
    // The COLUMNS const above is for the 'recentLogs' table if you choose to display it.
    // Based on your previous paste, your main table uses specific columns.
    @track columns = [
        { label: 'Impact', fieldName: 'Impact_Score__c', type: 'number', cellAttributes: { alignment: 'left' }, initialWidth: 90, sortable: true },
        { label: 'Status', fieldName: 'Status__c', type: 'text' }, 
        { label: 'Type', fieldName: 'Object_API_Name__c', type: 'text' },
        { label: 'Description', fieldName: 'Description__c', type: 'text', wrapText: true },
        { label: 'Count', fieldName: 'Occurrences__c', type: 'number', initialWidth: 100 },
        { label: 'Last Detected', fieldName: 'Last_Detected__c', type: 'date', initialWidth: 130 },
        { type: 'action', typeAttributes: { rowActions: ACTIONS } }
    ];
    
    // Modal & Tabs
    @track isModalOpen = false;
    @track activeTab = 'settings'; 
    
    // Solution Modal
    @track isSolutionModalOpen = false;
    @track selectedRow = {};
    @track solutionSteps = [];

    // Filter State
    @track currentFilter = 'Active'; 
    
    // --- NEW: Feature Gating State ---
    @track isPremium = false; 
    @track isLoading = false;
    
    // New: Recent Logs (if you want to show the secondary table from the Controller)
    @track recentLogs = [];
    @track recentLogsColumns = COLUMNS;

    wiredPainPointsResult;

    // 1. ORIGINAL WIRE: Fetches the main table data
    @wire(getPainPoints)
    wiredData(result) {
        this.wiredPainPointsResult = result;
        if (result.data) {
            this.allPainPoints = result.data;
        } else if (result.error) {
            console.error('Error fetching pain points:', result.error);
            this.allPainPoints = [];
            this.showToast('Error', 'Failed to load findings.', 'error');
        }
    }

    // 2. NEW WIRE: Fetches License Status (and optional metrics/logs)
    @wire(getDashboardData)
    wiredDashboard({ error, data }) {
        if (data) {
            this.isPremium = data.isPremium;
            
            // Flatten User Name for the Recent Logs table (if used)
            this.recentLogs = data.recentLogs.map(log => ({
                ...log,
                UserName: log.User__r ? log.User__r.Name : 'System'
            }));
            
        } else if (error) {
            console.error('Error fetching dashboard config:', error);
        }
    }

    // --- Getters for Filters (Preserved) ---
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

    // Button Variants
    get allVariant() { return this.currentFilter === 'All' ? 'brand' : 'neutral'; }
    get activeVariant() { return this.currentFilter === 'Active' ? 'brand' : 'neutral'; }
    get dismissedVariant() { return this.currentFilter === 'Dismissed' ? 'brand' : 'neutral'; }

    // --- Actions ---
    filterAll() { this.currentFilter = 'All'; }
    filterActive() { this.currentFilter = 'Active'; }
    filterDismissed() { this.currentFilter = 'Dismissed'; }

    handleRefresh() { 
        this.isLoading = true;
        return refreshApex(this.wiredPainPointsResult)
            .then(() => { this.isLoading = false; });
    }

    // --- NEW: Gated "Auto-Fix" Action ---
    handleAutoFix() {
        // Double check License state before calling server
        if (!this.isPremium) {
            this.handlePremiumClick();
            return;
        }

        this.isLoading = true;
        const idsToFix = this.selectedRow && this.selectedRow.Id ? [this.selectedRow.Id] : [];

        runAutoFix({ recordIds: idsToFix })
            .then(() => {
                this.showToast('Success', 'Auto-Fix job initiated successfully.', 'success');
                this.closeSolutionModal();
                return refreshApex(this.wiredPainPointsResult);
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // --- Row Action Handling (Preserved) ---
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'dismiss':
                this.dismissRow(row);
                break;
            case 'view_details':
                this.showSolution(row);
                break;
            default:
        }
    }

    // Action: Dismiss (Preserved)
    async dismissRow(row) {
        const fields = {};
        fields[ID_FIELD.fieldApiName] = row.Id;
        fields[STATUS_FIELD.fieldApiName] = 'Dismissed';

        const recordInput = { fields };

        try {
            await updateRecord(recordInput);
            this.showToast('Success', 'Finding dismissed.', 'success');
            return refreshApex(this.wiredPainPointsResult);
        } catch (error) {
            this.showToast('Error', 'Error dismissing record: ' + error.body.message, 'error');
        }
    }

    // Action: View Solution Guide (Preserved)
    showSolution(row) {
        this.selectedRow = row;
        this.solutionSteps = this.getStepsForType(row.Object_API_Name__c);
        this.isSolutionModalOpen = true;
    }

    closeSolutionModal() {
        this.isSolutionModalOpen = false;
    }

    // Updated: Opens the Admin modal to the licensing tab
    handlePremiumClick() {
        this.closeSolutionModal();
        this.activeTab = 'licensing';
        this.isModalOpen = true; 
    }

    // Helper: Detailed "Root Cause" Steps (Preserved)
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

    // --- Admin Modal Logic (Preserved) ---
    openAdminModal(event) {
        // Check if triggered by an element with a dataset (like the header button)
        const targetTab = event.currentTarget.dataset.tab;
        this.activeTab = targetTab ? targetTab : 'settings';
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }

    // Helper for Toast
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}