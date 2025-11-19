/**
 * @description       : Main dashboard LWC for BehaviorIQ. Displays high-level stats and a prioritized list of identified pain points.
 * @version           : 4.0 - Final MVP version with Dismissed filter.
**/
import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWorkflowStats from '@salesforce/apex/WorkflowAnalyticsController.getWorkflowStats';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';
import updatePainPointStatus from '@salesforce/apex/PainPointController.updatePainPointStatus';
import getSolutionGuide from '@salesforce/apex/SolutionGuideController.getSolutionGuide';

// Action definition for the datatable
const actions = [
    { label: 'View Details', name: 'view_details' },
    { label: 'Acknowledge', name: 'acknowledge' },
    { label: 'Dismiss', name: 'dismiss' }
];

const columns = [
    { label: 'Pain Point', fieldName: 'Name', type: 'text', wrapText: true },
    { label: 'Description', fieldName: 'Description__c', type: 'text', wrapText: true },
    { label: 'Object', fieldName: 'Object_API_Name__c', type: 'text', initialWidth: 120 },
    { 
        label: 'Impact Score', fieldName: 'Impact_Score__c', type: 'number', sortable: true,
        cellAttributes: { alignment: 'left', class: 'slds-text-color_error slds-text-heading_small' },
        initialWidth: 140
    },
    { label: 'Status', fieldName: 'Status__c', type: 'text', initialWidth: 120 },
    {
        type: 'action',
        typeAttributes: { rowActions: actions },
    }
];

export default class BehaviorIQDashboard extends LightningElement {
    @track columns = columns;
    @track painPointsData = [];
    @track filteredPainPoints = [];
    @track error;
    @track isLoading = true;
    @track statusFilter = 'New';

    wiredStatsResult;
    wiredPainPointsResult;

    @track isDetailModalOpen = false;
    @track selectedPainPoint = {};
    @track isSolutionModalOpen = false;
    @track solutionGuide = {};

    @wire(getWorkflowStats)
    wiredStats(result) {
        this.wiredStatsResult = result;
    }

    get stats() {
        return this.wiredStatsResult?.data;
    }
    
    @wire(getPainPoints)
    wiredPainPoints(result) {
        this.isLoading = false;
        this.wiredPainPointsResult = result;
        if (result.data) {
            this.painPointsData = result.data;
            this.applyFilter();
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.painPointsData = [];
        }
    }
    
    get hasPainPoints() {
        return this.filteredPainPoints && this.filteredPainPoints.length > 0;
    }

    // --- UPDATED: Added 'Dismissed' to the filter options ---
    get filterOptions() {
        return [
            { label: 'New', value: 'New' },
            { label: 'Acknowledged', value: 'Acknowledged' },
            { label: 'Dismissed', value: 'Dismissed' },
            { label: 'All', value: 'All' },
        ];
    }

    handleFilterChange(event) {
        this.statusFilter = event.detail.value;
        this.applyFilter();
    }

    applyFilter() {
        if (this.statusFilter === 'All') {
            this.filteredPainPoints = this.painPointsData;
        } else {
            this.filteredPainPoints = this.painPointsData.filter(
                pp => pp.Status__c === this.statusFilter
            );
        }
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'view_details':
                this.selectedPainPoint = row;
                this.isDetailModalOpen = true;
                break;
            case 'acknowledge':
                this.updateStatus(row.Id, 'Acknowledged');
                break;
            case 'dismiss':
                this.updateStatus(row.Id, 'Dismissed');
                break;
            default:
        }
    }

    updateStatus(painPointId, status) {
        this.isLoading = true;
        updatePainPointStatus({ painPointId: painPointId, status: status })
            .then(() => {
                this.showToast('Success', `Pain point marked as ${status}.`, 'success');
                return this.handleRefresh();
            })
            .catch(error => {
                this.showToast('Error updating status', error.body.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleViewSolution() {
        if (this.selectedPainPoint && this.selectedPainPoint.Unique_Key__c) {
            getSolutionGuide({ painPointKey: this.selectedPainPoint.Unique_Key__c })
                .then(result => {
                    this.solutionGuide = result;
                    this.isDetailModalOpen = false;
                    this.isSolutionModalOpen = true;
                })
                .catch(error => {
                    this.error = error;
                    this.solutionGuide = { title: 'Error', steps: ['Could not load the solution guide.']};
                    this.isDetailModalOpen = false;
                    this.isSolutionModalOpen = true;
                });
        }
    }

    closeModal() {
        this.isDetailModalOpen = false;
        this.isSolutionModalOpen = false;
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await Promise.all([refreshApex(this.wiredStatsResult), refreshApex(this.wiredPainPointsResult)]);
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

