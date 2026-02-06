import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getConfigSettings from '@salesforce/apex/BehaviorSettingsController.getConfigSettings';
import saveConfigSettings from '@salesforce/apex/BehaviorSettingsController.saveConfigSettings';

// Factory Defaults for Detection Thresholds (BehaviorIQ_Configuration__c)
const DEFAULT_STALE_CASE_THRESHOLD = 30;
const DEFAULT_STALE_OPP_THRESHOLD = 90;
const DEFAULT_UNASSIGNED_LEAD_HOURS = 48;
const DEFAULT_LEAD_HOARDING_DAYS = 5;
const DEFAULT_HIGH_VALUE_INACTIVITY_DAYS = 14;
const DEFAULT_HIGH_VALUE_AMOUNT = 50000;
const DEFAULT_CONTRACT_EXPIRY_DAYS = 30;

export default class BehaviorSettings extends LightningElement {
    // Detection Threshold settings (BehaviorIQ_Configuration__c)
    @track staleCaseThreshold;
    @track staleOpportunityThreshold;
    @track unassignedLeadHours;
    @track leadHoardingDays;
    @track highValueInactivityDays;
    @track highValueAmountThreshold;
    @track contractExpiryDays;

    @track isLoading = true;

    // Wire result reference for refresh
    wiredConfigSettingsResult;

    @wire(getConfigSettings)
    wiredConfigSettings(result) {
        this.wiredConfigSettingsResult = result;
        const { error, data } = result;

        if (data) {
            this.staleCaseThreshold = data.staleCaseThreshold || DEFAULT_STALE_CASE_THRESHOLD;
            this.staleOpportunityThreshold = data.staleOpportunityThreshold || DEFAULT_STALE_OPP_THRESHOLD;
            this.unassignedLeadHours = data.unassignedLeadHours || DEFAULT_UNASSIGNED_LEAD_HOURS;
            this.leadHoardingDays = data.leadHoardingDays || DEFAULT_LEAD_HOARDING_DAYS;
            this.highValueInactivityDays = data.highValueInactivityDays || DEFAULT_HIGH_VALUE_INACTIVITY_DAYS;
            this.highValueAmountThreshold = data.highValueAmountThreshold || DEFAULT_HIGH_VALUE_AMOUNT;
            this.contractExpiryDays = data.contractExpiryDays || DEFAULT_CONTRACT_EXPIRY_DAYS;
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to load detection threshold settings.', 'error');
            // Set defaults on error
            this.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
            this.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
            this.unassignedLeadHours = DEFAULT_UNASSIGNED_LEAD_HOURS;
            this.leadHoardingDays = DEFAULT_LEAD_HOARDING_DAYS;
            this.highValueInactivityDays = DEFAULT_HIGH_VALUE_INACTIVITY_DAYS;
            this.highValueAmountThreshold = DEFAULT_HIGH_VALUE_AMOUNT;
            this.contractExpiryDays = DEFAULT_CONTRACT_EXPIRY_DAYS;
            this.isLoading = false;
        }
    }

    // ==================== INPUT HANDLERS ====================

    handleConfigInputChange(event) {
        const field = event.target.name;
        const val = field === 'highValueAmountThreshold'
            ? parseFloat(event.target.value)
            : parseInt(event.target.value, 10);

        switch (field) {
            case 'staleCaseThreshold':
                this.staleCaseThreshold = val;
                break;
            case 'staleOpportunityThreshold':
                this.staleOpportunityThreshold = val;
                break;
            case 'unassignedLeadHours':
                this.unassignedLeadHours = val;
                break;
            case 'leadHoardingDays':
                this.leadHoardingDays = val;
                break;
            case 'highValueInactivityDays':
                this.highValueInactivityDays = val;
                break;
            case 'highValueAmountThreshold':
                this.highValueAmountThreshold = val;
                break;
            case 'contractExpiryDays':
                this.contractExpiryDays = val;
                break;
            default:
                break;
        }
    }

    handleResetConfig() {
        this.staleCaseThreshold = DEFAULT_STALE_CASE_THRESHOLD;
        this.staleOpportunityThreshold = DEFAULT_STALE_OPP_THRESHOLD;
        this.unassignedLeadHours = DEFAULT_UNASSIGNED_LEAD_HOURS;
        this.leadHoardingDays = DEFAULT_LEAD_HOARDING_DAYS;
        this.highValueInactivityDays = DEFAULT_HIGH_VALUE_INACTIVITY_DAYS;
        this.highValueAmountThreshold = DEFAULT_HIGH_VALUE_AMOUNT;
        this.contractExpiryDays = DEFAULT_CONTRACT_EXPIRY_DAYS;

        this.showToast('Reset', 'All thresholds reset to defaults. Click Save to apply.', 'info');
    }

    async handleSaveConfig() {
        // Validate inputs
        if (!this.validateThreshold(this.staleCaseThreshold, 'Stale Case Threshold', 1, 999)) return;
        if (!this.validateThreshold(this.staleOpportunityThreshold, 'Stale Opportunity Threshold', 1, 999)) return;
        if (!this.validateThreshold(this.unassignedLeadHours, 'Unassigned Lead Hours', 1, 720)) return;
        if (!this.validateThreshold(this.leadHoardingDays, 'Lead Hoarding Days', 1, 999)) return;
        if (!this.validateThreshold(this.highValueInactivityDays, 'High-Value Inactivity Days', 1, 999)) return;
        if (!this.validateThreshold(this.highValueAmountThreshold, 'High-Value Amount', 1, 999999999)) return;
        if (!this.validateThreshold(this.contractExpiryDays, 'Contract Expiry Days', 1, 999)) return;

        this.isLoading = true;
        try {
            await saveConfigSettings({
                staleCaseThreshold: this.staleCaseThreshold,
                staleOpportunityThreshold: this.staleOpportunityThreshold,
                unassignedLeadHours: this.unassignedLeadHours,
                leadHoardingDays: this.leadHoardingDays,
                highValueInactivityDays: this.highValueInactivityDays,
                highValueAmountThreshold: this.highValueAmountThreshold,
                contractExpiryDays: this.contractExpiryDays
            });

            this.showToast('Success', 'Detection thresholds saved successfully.', 'success');

            // Refresh the wire to get updated data
            await refreshApex(this.wiredConfigSettingsResult);

        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', 'Failed to save settings: ' + errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ==================== UTILITY METHODS ====================

    validateThreshold(value, fieldName, min, max) {
        if (value === null || value === undefined || value < min || value > max) {
            this.showToast('Validation Error', `${fieldName} must be between ${min} and ${max.toLocaleString()}.`, 'error');
            return false;
        }
        return true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
