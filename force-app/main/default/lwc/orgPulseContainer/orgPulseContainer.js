import { LightningElement, wire, track } from 'lwc';
import isSetupComplete from '@salesforce/apex/SetupWizardController.isSetupComplete';

export default class OrgPulseContainer extends LightningElement {
    @track isSetupComplete = false;
    @track isLoading = true;

    // Call the Apex method to check if setup is complete
    @wire(isSetupComplete)
    wiredSetupCheck({ error, data }) {
        if (data !== undefined) {
            this.isSetupComplete = data;
            this.isLoading = false;
        } else if (error) {
            // Handle error, maybe show an error message
            console.error('Error checking setup status:', error);
            this.isLoading = false;
        }
    }

    // This event is fired from the setup wizard when the user clicks "Finish"
    handleSetupComplete() {
        this.isSetupComplete = true;
    }
}
