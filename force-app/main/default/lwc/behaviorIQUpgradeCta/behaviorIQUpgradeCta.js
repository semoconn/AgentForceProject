import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import checkLicenseStatus from '@salesforce/apex/LicenseService.checkLicenseStatus';

export default class BehaviorIQUpgradeCta extends LightningElement {
    licenseStatus;
    isLoading = true;

    @wire(checkLicenseStatus)
    wiredLicenseStatus({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.licenseStatus = data;
        } else if (error) {
            // Default to showing upgrade CTA on error (fail-open for marketing)
            this.licenseStatus = 'Free';
            console.error('Error checking license status:', error);
        }
    }

    get isPremium() {
        return this.licenseStatus === 'Premium';
    }

    get showUpgradeBanner() {
        return !this.isLoading && !this.isPremium;
    }

    get showPremiumBadge() {
        return !this.isLoading && this.isPremium;
    }

    handleUpgradeClick() {
        const event = new ShowToastEvent({
            title: 'Premium Features',
            message: 'Thank you for your interest in BehaviorIQ Premium! This feature is coming soon.',
            variant: 'info',
        });
        this.dispatchEvent(event);
    }
}
