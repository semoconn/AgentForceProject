/**
 * @description       : LWC to display the status of the last OrgPulse analysis job.
 * @author            : Gemini
 * @group             : OrgPulse
 * @last modified on  : 10-20-2025
 * @last modified by  : Gemini
**/
import { LightningElement, wire } from 'lwc';
import getSystemHealth from '@salesforce/apex/WorkflowAnalyticsController.getSystemHealth';

export default class OrgPulseSystemHealth extends LightningElement {
    health;
    error;

    @wire(getSystemHealth)
    wiredHealth({ error, data }) {
        if (data) {
            this.health = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.health = undefined;
            console.error('Error fetching system health:', error);
        }
    }

    get isSuccess() {
        return this.health && this.health.Status__c === 'Success';
    }
}
