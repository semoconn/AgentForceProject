import { LightningElement, track } from 'lwc';
import isSetupComplete from '@salesforce/apex/SetupWizardController.isSetupComplete';

export default class BehaviorIQContainer extends LightningElement {
    @track isSetupComplete = false;
    @track isLoading = true;

    // Use imperative Apex call on every component load to avoid cache issues
    // Wire adapters with cacheable=true can return stale data after navigation
    connectedCallback() {
        this.checkSetupStatus();
    }

    // Imperative call to check setup status - always gets fresh data
    checkSetupStatus() {
        this.isLoading = true;
        isSetupComplete()
            .then(result => {
                this.isSetupComplete = result;
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error checking setup status:', error);
                this.isSetupComplete = false;
                this.isLoading = false;
            });
    }

    // This event is fired from the setup wizard when the user clicks "Finish"
    handleSetupComplete() {
        this.isSetupComplete = true;
    }
}
