/**
 * @description       : Main dashboard LWC for OrgPulse. Displays high-level stats and a prioritized list of identified pain points.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-14-2025
 * @last modified by  : Gemini
**/
import { LightningElement, wire, track } from 'lwc';
import getWorkflowStats from '@salesforce/apex/WorkflowAnalyticsController.getWorkflowStats';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';

// Define the columns for the datatable, including the new 'action' column
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

    // Properties for the modal
    @track isModalOpen = false;
    @track selectedPainPoint = {};

    // Wired properties for stats
    @wire(getWorkflowStats) stats;

    // Consolidate the pain points wire into a single function to handle data, errors, and loading state
    @wire(getPainPoints)
    wiredPainPoints({ error, data }) {
        if (data) {
            this.painPointsData = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.painPointsData = [];
        }
        this.isLoading = false; // <-- This now correctly handles loading state
    }
    
    get hasPainPoints() {
        return this.painPointsData && this.painPointsData.length > 0;
    }

    // Handle the 'View Details' action from the datatable
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_details') {
            this.selectedPainPoint = row;
            this.isModalOpen = true;
        }
    }

    // Close the modal
    closeModal() {
        this.isModalOpen = false;
        this.selectedPainPoint = {};
    }
}