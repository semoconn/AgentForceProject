import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import shouldShowSuggestion from '@salesforce/apex/WorkflowSuggestionController.shouldShowSuggestion';
import createSimpleUpdateAction from '@salesforce/apex/QuickActionService.createSimpleUpdateAction';
import dismissSuggestion from '@salesforce/apex/WorkflowSuggestionController.dismissSuggestion';

export default class WorkflowSuggestionModal extends LightningElement {
    @api recordId;
    _objectApiName;

    // State properties for the modal's flow
    isVisible = false;
    showActionNameInput = false;
    isLoading = false;
    actionLabel = '';
    
    // The action that triggered the suggestion
    detectedActionName = 'Record_Created'; // Currently hardcoded

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

    async checkForSuggestion() {
        if (!this.recordId || !this._objectApiName) return;
        try {
            const result = await shouldShowSuggestion({ 
                recordId: this.recordId, 
                objectApiName: this._objectApiName
            });
            if (result) {
                this.isVisible = true;
            }
        } catch (error) {
            console.error('Error checking for suggestion:', error);
        }
    }

    handleAccept() {
        // ✅ FIX #1: Transition to the next step instead of showing a toast
        this.showActionNameInput = true;
    }

    handleLabelChange(event) {
        this.actionLabel = event.target.value;
    }

    async handleCreateAction() {
        if (!this.actionLabel) {
            this.showToast('Error', 'Please enter a label for the Quick Action.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const result = await createSimpleUpdateAction({
                objectApiName: this._objectApiName,
                actionLabel: this.actionLabel
            });

            if (result.isSuccess) {
                this.showToast('Success', result.message, 'success');
                // ✅ FIX #3: Also dismiss the suggestion after successful creation
                await this.dismiss(); 
                this.closeModal();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'An error occurred: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    handleCancel() {
        this.closeModal();
    }

    async handleDismiss() {
        // ✅ FIX #3: Call the new Apex method to permanently dismiss this suggestion
        await this.dismiss();
        this.showToast('Dismissed', 'You will not see this suggestion for this action again.', 'info');
        this.closeModal();
    }
    
    // Helper method to call the dismiss Apex action
    async dismiss() {
        try {
            await dismissSuggestion({
                objectApiName: this._objectApiName,
                actionName: this.detectedActionName
            });
        } catch (error) {
            console.error('Error dismissing suggestion:', error);
            // Don't show a toast for this, as it's a background process
        }
    }

    closeModal() {
        this.isVisible = false;
        this.showActionNameInput = false;
        this.actionLabel = '';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(event);
    }
}

