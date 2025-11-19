import { LightningElement, wire, track } from 'lwc';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Id';
import STATUS_FIELD from '@salesforce/schema/Identified_Pain_Point__c.Status__c';

const ACTIONS = [
    { label: 'View Details', name: 'view_details' },
    { label: 'Dismiss', name: 'dismiss' }
];

// FIX: Removed initialWidth from 'Status' and 'Type' to allow flex distribution.
// Description also has no initialWidth, so these 3 columns will now share remaining space,
// ensuring the table pushes all the way to the right edge.
const COLUMNS = [
    { label: 'Impact', fieldName: 'Impact_Score__c', type: 'number', cellAttributes: { alignment: 'left' }, initialWidth: 90, sortable: true },
    { label: 'Status', fieldName: 'Status__c', type: 'text' }, 
    { label: 'Type', fieldName: 'Object_API_Name__c', type: 'text' },
    { label: 'Description', fieldName: 'Description__c', type: 'text', wrapText: true },
    { label: 'Count', fieldName: 'Occurrences__c', type: 'number', initialWidth: 100 },
    { label: 'Last Detected', fieldName: 'Last_Detected__c', type: 'date', initialWidth: 130 },
    {
        type: 'action',
        typeAttributes: { rowActions: ACTIONS },
    },
];

export default class BehaviorIQDashboard extends LightningElement {
    @track allPainPoints = [];
    @track columns = COLUMNS;
    
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

    @wire(getPainPoints)
    wiredData(result) {
        this.wiredPainPointsResult = result;
        if (result.data) {
            this.allPainPoints = result.data;
        } else if (result.error) {
            console.error('Error fetching pain points:', result.error);
            this.allPainPoints = [];
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

    // Button Variants
    get allVariant() { return this.currentFilter === 'All' ? 'brand' : 'neutral'; }
    get activeVariant() { return this.currentFilter === 'Active' ? 'brand' : 'neutral'; }
    get dismissedVariant() { return this.currentFilter === 'Dismissed' ? 'brand' : 'neutral'; }

    // --- Actions ---
    filterAll() { this.currentFilter = 'All'; }
    filterActive() { this.currentFilter = 'Active'; }
    filterDismissed() { this.currentFilter = 'Dismissed'; }

    handleRefresh() { return refreshApex(this.wiredPainPointsResult); }

    // --- Row Action Handling ---
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

    // Action: Dismiss
    async dismissRow(row) {
        const fields = {};
        fields[ID_FIELD.fieldApiName] = row.Id;
        fields[STATUS_FIELD.fieldApiName] = 'Dismissed';

        const recordInput = { fields };

        try {
            await updateRecord(recordInput);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Finding dismissed.',
                    variant: 'success'
                })
            );
            return refreshApex(this.wiredPainPointsResult);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Error dismissing record: ' + error.body.message,
                    variant: 'error'
                })
            );
        }
    }

    // Action: View Solution Guide
    showSolution(row) {
        this.selectedRow = row;
        this.solutionSteps = this.getStepsForType(row.Object_API_Name__c);
        this.isSolutionModalOpen = true;
    }

    closeSolutionModal() {
        this.isSolutionModalOpen = false;
    }

    handlePremiumClick() {
        this.closeSolutionModal();
        this.activeTab = 'licensing';
        this.isModalOpen = true; // Open Admin Modal to Premium tab
    }

    // Helper: Detailed "Root Cause" Steps
    // STRATEGY: Provide the "Manual Recipe" to make the "Premium Automation" tempting.
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
            case 'Task': // Bot Detection
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

    // --- Admin Modal Logic ---
    openAdminModal(event) {
        const targetTab = event.target.dataset.tab;
        this.activeTab = targetTab ? targetTab : 'settings';
        this.isModalOpen = true;
    }

    closeModal() {
        this.isModalOpen = false;
    }
}