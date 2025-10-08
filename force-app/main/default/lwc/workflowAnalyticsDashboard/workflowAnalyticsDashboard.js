import { LightningElement, wire } from 'lwc';
import getWorkflowStats from '@salesforce/apex/WorkflowAnalyticsController.getWorkflowStats';
import getTopActions from '@salesforce/apex/WorkflowAnalyticsController.getTopActions';

export default class WorkflowAnalyticsDashboard extends LightningElement {
    stats;
    topActions;
    error;

    @wire(getWorkflowStats)
    wiredStats({ error, data }) {
        if (data) {
            this.stats = data;
            this.error = undefined;
        } else if (error) {
            this.handleError(error);
        }
    }

    @wire(getTopActions)
    wiredTopActions({ error, data }) {
        if (data) {
            this.topActions = data;
            this.error = undefined;
        } else if (error) {
            this.handleError(error);
        }
    }

    handleError(error) {
        console.error('Error loading analytics:', error);
        this.error = 'Error loading analytics data.';
    }
}
