/**
 * @description       : Main dashboard LWC for OrgPulse. Displays high-level stats and a prioritized list of identified pain points.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-13-2025
 * @last modified by  : Gemini
**/
import { LightningElement, wire, track } from 'lwc';
import getWorkflowStats from '@salesforce/apex/WorkflowAnalyticsController.getWorkflowStats';
import getPainPoints from '@salesforce/apex/PainPointController.getPainPoints';

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
    { label: 'Last Detected', fieldName: 'Last_Detected__c', type: 'date', initialWidth: 150 }
];

export default class OrgPulseDashboard extends LightningElement {
    @track columns = columns;
    @track isLoading = true;

    // Wired properties to hold data from Apex controllers
    @wire(getWorkflowStats) stats;
    @wire(getPainPoints) painPoints;

    /**
     * @description Getter to determine if pain points were found.
     */
    get hasPainPoints() {
        return this.painPoints && this.painPoints.data && this.painPoints.data.length > 0;
    }

    /**
     * @description Stop the loading spinner once the pain points data has been returned from Apex.
     */
    @wire(getPainPoints)
    wiredPainPoints({ error, data }) {
        if (data || error) {
            this.isLoading = false;
        }
    }
}
