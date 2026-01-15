import { LightningElement, wire, track } from 'lwc';
import getEnhancedSystemHealth from '@salesforce/apex/WorkflowAnalyticsController.getEnhancedSystemHealth';

export default class BehaviorIQSystemHealth extends LightningElement {
    @track health;
    @track error;
    @track isLoading = true;

    @wire(getEnhancedSystemHealth)
    wiredHealth({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.health = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.health = undefined;
        }
    }

    get hasHealthData() {
        return this.health && this.health.hasData;
    }

    get isSuccess() {
        return this.health && this.health.status === 'Success';
    }

    get statusLabel() {
        if (!this.health) return 'Unknown';
        return this.health.status || 'Unknown';
    }

    get sourceLabel() {
        if (!this.health || !this.health.source) return '';
        // Make the source user-friendly
        if (this.health.source === 'System_Health_Log__c') {
            return 'Analysis Job';
        } else if (this.health.source === 'Behavior_Log__c') {
            return 'Behavior Tracking';
        }
        return this.health.source;
    }

    get noHealthData() {
        return !this.hasHealthData;
    }

    get showNoDataMessage() {
        return !this.isLoading && this.noHealthData;
    }

    get hasError() {
        return !!this.error;
    }

    get noError() {
        return !this.error;
    }
}
