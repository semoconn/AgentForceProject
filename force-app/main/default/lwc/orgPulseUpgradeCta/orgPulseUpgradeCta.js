import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class OrgPulseUpgradeCta extends NavigationMixin(LightningElement) {
    handleLearnMore() {
        // In a real AppExchange app, this would navigate to your product page or a custom lead capture page.
        // For now, we'll navigate to a placeholder URL.
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: 'http://www.salesforce.com' // Placeholder URL
            }
        });
    }
}