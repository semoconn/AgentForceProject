import { LightningElement, api } from 'lwc';
import shouldShowSuggestion from '@salesforce/apex/WorkflowSuggestionController.shouldShowSuggestion';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WorkflowSuggestionModal extends LightningElement {
    @api recordId;
    
    _objectApiName;
    @api 
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        if (value) {
            this.checkForSuggestion();
        }
    }

    isVisible = false;

    async checkForSuggestion() {
        // No longer need connectedCallback, this runs when objectApiName is set
        if (!this.recordId || !this._objectApiName) {
            return; // Exit if required properties aren't set
        }

        try {
            const result = await shouldShowSuggestion({ 
                recordId: this.recordId, 
                objectApiName: this._objectApiName
            });

            if (result === true) {
                this.isVisible = true;
            }
        } catch (error) {
            console.error('Error checking for suggestion:', error);
        }
    }

    handleAccept() {
        // TODO: Implement actual quick action creation logic
        this.showToast('Success', 'Quick Action creation feature coming soon!', 'info');
        this.isVisible = false;
    }

    handleRemindLater() {
        this.showToast('Reminder Set', 'We will remind you later.', 'success');
        this.isVisible = false;
    }

    handleDismiss() {
        // TODO: Store user preference to never show this again
        this.showToast('Dismissed', 'You will not see this suggestion again.', 'info');
        this.isVisible = false;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}
