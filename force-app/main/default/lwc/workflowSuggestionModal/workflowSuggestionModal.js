import { LightningElement, api, wire } from 'lwc';
import shouldShowSuggestion from '@salesforce/apex/WorkflowSuggestionController.shouldShowSuggestion';

export default class WorkflowOptimizerModal extends LightningElement {
    @api recordId;
    showModal = false;

    connectedCallback() {
        this.checkForSuggestion();
    }

    async checkForSuggestion() {
        try {
            const result = await shouldShowSuggestion({ 
                recordId: this.recordId, 
                objectApiName: 'Case' // Replace as needed
            });

            if (result === true) {
                this.showModal = true;
            }
        } catch (error) {
            console.error('Error checking suggestion:', error);
        }
    }
}

