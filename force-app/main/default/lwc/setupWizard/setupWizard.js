/**
 * @description       : Controls the multi-step setup wizard for OrgPulse.
 * @version           : 2.0 - Added step counter, updated progress bar logic, and included Task by default.
**/
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTrackableObjects from '@salesforce/apex/SetupWizardController.getTrackableObjects';
import scheduleAnalysisJob from '@salesforce/apex/SetupWizardController.scheduleAnalysisJob';
import saveMonitoringSettings from '@salesforce/apex/SetupWizardController.saveMonitoringSettings';

const TOTAL_STEPS = 5;

export default class SetupWizard extends LightningElement {
    @track currentStep = '1';
    // --- UPDATED: 'Task' is now included in the default selections ---
    @track selectedObjects = ['Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'Task'];
    @track isJobScheduled = false;
    
    @wire(getTrackableObjects)
    wiredObjects;

    get objectOptions() {
        if (this.wiredObjects.data) {
            return this.wiredObjects.data.map(obj => ({
                label: obj.label,
                value: obj.apiName
            }));
        }
        return [];
    }
    
    // --- UPDATED: Progress bar starts at 0% ---
    get progress() {
        // This calculation ensures the bar is empty on step 1 and full on the final step.
        return ((parseInt(this.currentStep, 10) - 1) / (TOTAL_STEPS - 1)) * 100;
    }

    // --- NEW: Step counter text ---
    get stepCounter() {
        return `Step ${this.currentStep} of ${TOTAL_STEPS}`;
    }

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }
    get isStep4() { return this.currentStep === '4'; }
    get isStep5() { return this.currentStep === '5'; }

    async handleNext() {
        if (this.currentStep === '2') {
            if (this.selectedObjects.length === 0) {
                this.showToast('Error', 'Please select at least one object to monitor.', 'error');
                return;
            }
        }

        if (this.currentStep === '4') {
             if (!this.isJobScheduled) {
                this.showToast('Information', 'Please schedule the nightly job to continue.', 'info');
                return;
            }
            await this.saveSettings();
        }
        
        let step = parseInt(this.currentStep, 10);
        if (step < TOTAL_STEPS) {
            this.currentStep = (step + 1).toString();
        }
    }

    handlePrevious() {
        let step = parseInt(this.currentStep, 10);
        if (step > 1) {
            this.currentStep = (step - 1).toString();
        }
    }

    handleFinish() {
        this.showToast('Success', 'Configuration saved! You will now be taken to the dashboard.', 'success');
        
        const completeEvent = new CustomEvent('setupcomplete');
        this.dispatchEvent(completeEvent);
    }

    handleObjectSelection(event) {
        this.selectedObjects = event.detail.value;
    }

    handleScheduleJob() {
        scheduleAnalysisJob()
            .then(() => {
                this.isJobScheduled = true;
                this.showToast('Success', 'The nightly analysis job has been scheduled.', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Could not schedule job. ' + error.body.message, 'error');
            });
    }

    async saveSettings() {
        try {
            await saveMonitoringSettings({ monitoredObjects: this.selectedObjects });
            console.log('Settings saved successfully.');
        } catch (error) {
            this.showToast('Error', 'Could not save monitoring settings. ' + error.body.message, 'error');
            throw new Error('Save failed');
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }
}
