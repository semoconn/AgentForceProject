import { LightningElement, wire, track } from 'lwc';
// Assuming you have an Apex controller to fetch this data
import getSystemHealth from '@salesforce/apex/WorkflowAnalyticsController.getSystemHealth';

export default class BehaviorIQSystemHealth extends LightningElement {
    @track healthData;
    @track error;
    @track isLoading = true;

    @wire(getSystemHealth)
    wiredHealth({ error, data }) {
        this.isLoading = true;
        if (data) {
            this.healthData = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.healthData = undefined;
        }
        this.isLoading = false;
    }

    get healthStatusClass() {
        if (!this.healthData) return 'slds-box';
        
        const baseClasses = 'slds-box slds-text-align_center ';
        if (this.healthData.status === 'Healthy') {
            return baseClasses + 'slds-theme_success';
        } else if (this.healthData.status === 'Warning') {
            return baseClasses + 'slds-theme_warning';
        }
        return baseClasses + 'slds-theme_error';
    }
}