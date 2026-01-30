import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLeaderboardData from '@salesforce/apex/UserLeaderboardController.getLeaderboardData';
import nudgeUser from '@salesforce/apex/UserLeaderboardController.nudgeUser';

export default class UserLeaderboard extends LightningElement {
    @track leaderboardData = [];
    @track isLoading = true;
    @track isPremium = false; 

    @wire(getLeaderboardData)
    wiredLeaderboard({ error, data }) {
        this.isLoading = false;
        if (data) {
            // Explicitly set premium status from server response
            this.isPremium = data.isPremium;

            // Transform entry list
            if (data.entries && data.entries.length > 0) {
                this.leaderboardData = data.entries.map((entry, index) => {
                    const rank = index + 1;

                    // Ensure topBehaviors is always an array
                    const behaviors = Array.isArray(entry.topBehaviors) ? entry.topBehaviors : [];

                    // Format impact score as currency
                    const impactValue = entry.totalImpactScore || 0;
                    const formattedImpact = impactValue > 0
                        ? '$' + impactValue.toLocaleString()
                        : '-';

                    // Determine impact severity class
                    let impactClass = 'score-text slds-m-right_small';
                    if (impactValue >= 50000) {
                        impactClass += ' slds-text-color_error'; // High severity: red
                    } else if (impactValue >= 5000) {
                        impactClass += ' slds-text-color_warning'; // Medium severity: orange
                    }

                    // Build detailed tooltip
                    const issueCount = entry.issueCount || 0;
                    const activityCount = entry.activityCount || 0;
                    const impactTooltip = `Impact: $${impactValue.toLocaleString()} at risk from ${issueCount} issue(s). Activity: ${activityCount} tracked events.`;

                    return {
                        userId: entry.userId,
                        userName: entry.userName,
                        photoUrl: entry.photoUrl,
                        totalImpactScore: impactValue,
                        formattedImpact: formattedImpact,
                        impactClass: impactClass,
                        impactTooltip: impactTooltip,
                        issueCount: issueCount,
                        hasIssues: issueCount > 0,
                        activityCount: activityCount,
                        isAnonymized: entry.isAnonymized,
                        topBehaviors: behaviors,
                        rank: rank,
                        rankClass: rank <= 3 ? `rank-badge rank-${rank}` : 'rank-text',
                        blurClass: entry.isAnonymized ? 'user-info-container content-blur' : 'user-info-container',
                        rowClass: 'slds-grid slds-p-vertical_small slds-border_bottom row-item'
                    };
                });
            } else {
                this.leaderboardData = [];
            }
            
        } else if (error) {
            console.error('Leaderboard Error:', error);
            
            // UX IMPROVEMENT: Show the actual error message for easier debugging
            let message = 'Could not load leaderboard.';
            if (error.body) {
                if (Array.isArray(error.body)) {
                    message = error.body.map(e => e.message).join(', ');
                } else if (typeof error.body.message === 'string') {
                    message = error.body.message;
                }
            }
            
            // Only suppress strict access errors, show others
            if (!message.includes('Access Denied')) {
                this.showToast('Error', message, 'error');
            }
        }
    }

    get isEmpty() {
        return !this.isLoading && this.leaderboardData.length === 0;
    }

    get showUpgradeCta() {
        // Show CTA only if we have data AND we are not premium
        return !this.isLoading && !this.isPremium && this.leaderboardData.length > 0;
    }

    handleNudge(event) {
        const userId = event.target.dataset.userId;
        if (!userId) {
            this.showToast('Error', 'Unable to identify user.', 'error');
            return;
        }

        nudgeUser({ userId: userId })
            .then((result) => {
                this.showToast('Success', result || 'Nudge sent successfully!', 'success');
            })
            .catch((error) => {
                let message = 'Failed to send nudge.';
                if (error.body && error.body.message) {
                    message = error.body.message;
                }
                this.showToast('Error', message, 'error');
            });
    }

    handleUpgradeClick() {
        this.dispatchEvent(new CustomEvent('upgrade'));
        this.showToast('Info', 'Opening Premium Upgrade options...', 'info');
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