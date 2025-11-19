import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTrackableObjects from '@salesforce/apex/SetupWizardController.getTrackableObjects';
import scheduleAnalysisJob from '@salesforce/apex/SetupWizardController.scheduleAnalysisJob';
import saveMonitoringSettings from '@salesforce/apex/SetupWizardController.saveMonitoringSettings';

export default class SetupWizard extends LightningElement {
    @track step = 1;
    // FIX: Added 'Contact' and 'Task' to the default selection list
    @track selectedObjects = ['Account', 'Opportunity', 'Case', 'Lead', 'Contact', 'Task']; 
    @track objectOptions = [];
    @track isLoading = false;

    get isStepOne() { return this.step === 1; }
    get isStepTwo() { return this.step === 2; }
    
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
            await saveMonitoringSettings({ monitoredObjects: this.selectedObjects });
            await scheduleAnalysisJob();

            this.showToast('Success', 'BehaviorIQ is now configured and running!', 'success');
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