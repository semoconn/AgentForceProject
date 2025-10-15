/**
 * @description       : Main dashboard LWC for OrgPulse. Displays high-level stats and a prioritized list of identified pain points.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-15-2025
 * @last modified by  : Gemini
**/
import { LightningElement, wire, track } from 'lwc';
import getWorkflowStats from '@salesforce/apex/WorkflowAnalyticsController.getWorkflowStats';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';
import getSolutionGuide from '@salesforce/apex/SolutionGuideController.getSolutionGuide';

const columns = [
    { label: 'Pain Point', fieldName: 'Name', type: 'text', wrapText: true },
    { label: 'Description', fieldName: 'Description__c', type: 'text', wrapText: true },
    { label: 'Object', fieldName: 'Object_API_Name__c', type: 'text', initialWidth: 120 },
    { 
        label: 'Impact Score', 
        fieldName: 'Impact_Score__c', 
        type: 'number', 
        sortable: true,
        cellAttributes: { 
            alignment: 'left',
            class: 'slds-text-color_error slds-text-heading_small' 
        },
        initialWidth: 140
    },
    { label: 'Status', fieldName: 'Status__c', type: 'text', initialWidth: 100 },
    { label: 'Last Detected', fieldName: 'Last_Detected__c', type: 'date', initialWidth: 150 },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'View Details', name: 'view_details' }] },
    }
];

export default class OrgPulseDashboard extends LightningElement {
    @track columns = columns;
    @track painPointsData = [];
    @track error;
    @track isLoading = true;

    // Properties for the details modal
    @track isDetailModalOpen = false;
    @track selectedPainPoint = {};

    // Properties for the solution modal
    @track isSolutionModalOpen = false;
    @track solutionGuide = {};

    @wire(getWorkflowStats) stats;

    @wire(getPainPoints)
    wiredPainPoints({ error, data }) {
        if (data) {
            // The pain point object from Apex already contains the Unique_Key__c.
            this.painPointsData = data; 
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.painPointsData = [];
        }
        this.isLoading = false;
    }
    
    get hasPainPoints() {
        return this.painPointsData && this.painPointsData.length > 0;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_details') {
            this.selectedPainPoint = row;
            this.isDetailModalOpen = true;
        }
    }

    handleViewSolution() {
        if (this.selectedPainPoint && this.selectedPainPoint.Unique_Key__c) {
            getSolutionGuide({ painPointKey: this.selectedPainPoint.Unique_Key__c })
                .then(result => {
                    this.solutionGuide = result;
                    this.isDetailModalOpen = false; // Hide details modal
                    this.isSolutionModalOpen = true; // Show solution modal
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
        this.selectedPainPoint = {}; // Clear selection on close
    }
}