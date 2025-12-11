import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getBehaviorSettings from '@salesforce/apex/BehaviorSettingsController.getBehaviorSettings';
import updateBehaviorSettings from '@salesforce/apex/BehaviorSettingsController.updateBehaviorSettings';
import getConfigSettings from '@salesforce/apex/BehaviorSettingsController.getConfigSettings';
import saveConfigSettings from '@salesforce/apex/BehaviorSettingsController.saveConfigSettings';

// Factory Defaults for Metadata-based settings
const DEFAULT_STALE_DAYS = 30;
const DEFAULT_LEAD_HOURS = 48;
const DEFAULT_CASE_DAYS = 14;
const DEFAULT_SEQ_THRESHOLD = 5;

// Factory Defaults for Pattern Analysis (BehaviorIQ_Configuration__c)
const DEFAULT_STALE_CASE_THRESHOLD = 30;
const DEFAULT_STALE_OPP_THRESHOLD = 90;

export default class BehaviorSettings extends LightningElement {
    // Metadata-based settings (Behavior_Setting__mdt)
    @track staleDays;
    @track leadHours;
    @track seqThreshold;
    @track caseDays;

    // Pattern Analysis settings (BehaviorIQ_Configuration__c)
    @track staleCaseThreshold;
    @track staleOpportunityThreshold;

    @track isLoading = true;

    // Wire result references for refresh
    wiredBehaviorSettingsResult;
    wiredConfigSettingsResult;

    // Track loading states for each section
    behaviorSettingsLoaded = false;
    configSettingsLoaded = false;

    @wire(getBehaviorSettings)
    wiredBehaviorSettings(result) {
        this.wiredBehaviorSettingsResult = result;
        const { error, data } = result;

        if (data) {
            this.staleDays = data.Stale_Opportunity_Days__c;
            this.leadHours = data.Unassigned_Lead_Age_Hours__c;
            this.seqThreshold = data.Sequential_Action_Threshold__c;
            this.caseDays = data.Stale_Case_Days__c || DEFAULT_CASE_DAYS;
            this.behaviorSettingsLoaded = true;
            this.checkLoadingComplete();
        } else if (error) {
            this.showToast('Error', 'Failed to load behavior settings.', 'error');
            // Set defaults on error
            this.staleDays = DEFAULT_STALE_DAYS;
            this.leadHours = DEFAULT_LEAD_HOURS;
            this.seqThreshold = DEFAULT_SEQ_THRESHOLD;
            this.caseDays = DEFAULT_CASE_DAYS;
            this.behaviorSettingsLoaded = true;
            this.checkLoadingComplete();
        }
    }

    @wire(getConfigSettings)
    wiredConfigSettings(result) {
        this.wiredConfigSettingsResult = result;
        const { error, data } = result;

        if (data) {
            this.staleCaseThreshold = data.staleCaseThreshold || DEFAULT_STALE_CASE_THRESHOLD;
            this.staleOpportunityThreshold = data.staleOpportunityThreshold || DEFAULT_STALE_OPP_THRESHOLD;
            this.configSettingsLoaded = true;
            this.checkLoadingComplete();
        } else if (error) {
            this.showToast('Error', 'Failed to load pattern analysis settings.', 'error');
            // Set defaults on error
            this.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
            this.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
            this.configSettingsLoaded = true;
            this.checkLoadingComplete();
        }
    }

    checkLoadingComplete() {
        if (this.behaviorSettingsLoaded && this.configSettingsLoaded) {
            this.isLoading = false;
        }
    }

    // ==================== METADATA SETTINGS HANDLERS ====================

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

    // ==================== PATTERN ANALYSIS CONFIG HANDLERS (Sprint 3.4) ====================

    handleConfigInputChange(event) {
        const field = event.target.name;
        const val = parseInt(event.target.value, 10);

        if (field === 'staleCaseThreshold') {
            this.staleCaseThreshold = val;
        } else if (field === 'staleOpportunityThreshold') {
            this.staleOpportunityThreshold = val;
        }
    }

    handleResetConfig() {
        this.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
        this.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;

        this.showToast('Reset', 'Pattern analysis thresholds reset to defaults (30/90 days). Click Save to apply.', 'info');
    }

    async handleSaveConfig() {
        // Validate inputs
        if (!this.staleCaseThreshold || this.staleCaseThreshold < 1 || this.staleCaseThreshold > 999) {
            this.showToast('Validation Error', 'Stale Case Threshold must be between 1 and 999 days.', 'error');
            return;
        }
        if (!this.staleOpportunityThreshold || this.staleOpportunityThreshold < 1 || this.staleOpportunityThreshold > 999) {
            this.showToast('Validation Error', 'Stale Opportunity Threshold must be between 1 and 999 days.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await saveConfigSettings({
                staleCaseThreshold: this.staleCaseThreshold,
                staleOpportunityThreshold: this.staleOpportunityThreshold
            });

            this.showToast('Success', 'Pattern analysis settings saved successfully.', 'success');

            // Refresh the wire to get updated data
            await refreshApex(this.wiredConfigSettingsResult);

        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', 'Failed to save pattern settings: ' + errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ==================== UTILITY METHODS ====================

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
