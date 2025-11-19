import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTrackableObjects from '@salesforce/apex/SetupWizardController.getTrackableObjects';
import scheduleAnalysisJob from '@salesforce/apex/SetupWizardController.scheduleAnalysisJob';
import saveMonitoringSettings from '@salesforce/apex/SetupWizardController.saveMonitoringSettings';

export default class SetupWizard extends LightningElement {
    @track step = 1;
    @track selectedObjects = ['Account', 'Opportunity', 'Case', 'Lead']; // Defaults
    @track objectOptions = [];
    @track isLoading = false;

    get isStepOne() { return this.step === 1; }
    get isStepTwo() { return this.step === 2; }
    
    // NEW: Helper for the progress indicator
    get currentStepValue() { return this.step.toString(); }

    get isNextDisabled() { return this.selectedObjects.length === 0; }

    @wire(getTrackableObjects)
    wiredObjects({ error, data }) {
        if (data) {
            this.objectOptions = data.map(obj => ({ label: obj.label, value: obj.apiName }));
        } else if (error) {
            this.showToast('Error', 'Could not load trackable objects.', 'error');
        }
    }

    handleObjectChange(event) {
        this.selectedObjects = event.detail.value;
    }

    goToStepTwo() {
        this.step = 2;
    }

    goToStepOne() {
        this.step = 1;
    }

    async handleFinishSetup() {
        this.isLoading = true;
        try {
            // 1. Save Settings
            await saveMonitoringSettings({ monitoredObjects: this.selectedObjects });
            
            // 2. Schedule Job
            await scheduleAnalysisJob();

            // 3. Notify Success
            this.showToast('Success', 'BehaviorIQ is now configured and running!', 'success');
            
            // 4. Fire Event to Parent to switch view
            this.dispatchEvent(new CustomEvent('setupcomplete'));

        } catch (error) {
            this.showToast('Setup Failed', error.body ? error.body.message : error.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}