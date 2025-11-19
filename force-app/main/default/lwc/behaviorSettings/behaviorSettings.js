import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getBehaviorSettings from '@salesforce/apex/BehaviorSettingsController.getBehaviorSettings';
import updateBehaviorSettings from '@salesforce/apex/BehaviorSettingsController.updateBehaviorSettings';

// Factory Defaults
const DEFAULT_STALE_DAYS = 30;
const DEFAULT_LEAD_HOURS = 48;
const DEFAULT_CASE_DAYS = 14; // New default for Cases
const DEFAULT_SEQ_THRESHOLD = 5;

export default class BehaviorSettings extends LightningElement {
    @track staleDays;
    @track leadHours;
    @track seqThreshold;
    @track caseDays; // New variable
    @track isLoading = true;

    @wire(getBehaviorSettings)
    wiredSettings({ error, data }) {
        this.isLoading = true;
        if (data) {
            this.staleDays = data.Stale_Opportunity_Days__c;
            this.leadHours = data.Unassigned_Lead_Age_Hours__c;
            this.seqThreshold = data.Sequential_Action_Threshold__c;
            this.caseDays = data.Stale_Case_Days__c || DEFAULT_CASE_DAYS; // Fallback if field is null
            
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to load current settings.', 'error');
            this.isLoading = false;
        }
    }

    handleInputChange(event) {
        const field = event.target.name;
        const val = parseInt(event.target.value, 10);

        if (field === 'staleDays') this.staleDays = val;
        else if (field === 'leadHours') this.leadHours = val;
        else if (field === 'seqThreshold') this.seqThreshold = val;
        else if (field === 'caseDays') this.caseDays = val;
    }

    handleReset() {
        this.staleDays = DEFAULT_STALE_DAYS;
        this.leadHours = DEFAULT_LEAD_HOURS;
        this.seqThreshold = DEFAULT_SEQ_THRESHOLD;
        this.caseDays = DEFAULT_CASE_DAYS;
        
        this.showToast('Reset', 'Values reset to factory defaults. Click Save to apply.', 'info');
    }

    async handleSave() {
        this.isLoading = true;
        try {
            await updateBehaviorSettings({
                staleDays: this.staleDays,
                leadHours: this.leadHours,
                seqThreshold: this.seqThreshold,
                caseDays: this.caseDays
            });

            this.showToast('Update Queued', 'Settings update has been queued.', 'success');
            
        } catch (error) {
            this.showToast('Error', 'Failed to update settings: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}