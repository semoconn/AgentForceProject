import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getEnhancedSystemHealth from '@salesforce/apex/WorkflowAnalyticsController.getEnhancedSystemHealth';
import runAnalysisNow from '@salesforce/apex/WorkflowAnalyticsController.runAnalysisNow';

export default class BehaviorIQSystemHealth extends LightningElement {
    @track health;
    @track error;
    @track isLoading = true;
    @track isRunning = false;

    _wiredHealthResult;

    @wire(getEnhancedSystemHealth)
    wiredHealth(result) {
        this._wiredHealthResult = result;
        this.isLoading = false;
        if (result.data) {
            this.health = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
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

    get runButtonLabel() {
        return this.isRunning ? 'Running...' : 'Run Analysis Now';
    }

    async handleRunAnalysis() {
        this.isRunning = true;

        try {
            const result = await runAnalysisNow();

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: result,
                    variant: 'success'
                })
            );

            // Refresh the health status after a short delay to allow batch to update
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.refreshHealthStatus();
            }, 3000);

        } catch (error) {
            const errorMessage = error.body?.message || error.message || 'An error occurred';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isRunning = false;
        }
    }

    async refreshHealthStatus() {
        try {
            await refreshApex(this._wiredHealthResult);
        } catch (e) {
            // Silent refresh failure
        }
    }
}
