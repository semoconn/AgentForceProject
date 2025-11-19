import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BehaviorIQUpgradeCta extends LightningElement {
    
    handleUpgradeClick() {
        // Placeholder for actual upgrade flow (e.g., navigate to AppExchange or a contact form)
        const event = new ShowToastEvent({
            title: 'Premium Features',
            message: 'Thank you for your interest in BehaviorIQ Premium! This feature is coming soon.',
            variant: 'info',
        });
        this.dispatchEvent(event);
    }
}