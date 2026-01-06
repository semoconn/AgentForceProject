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
            console.log('==== LEADERBOARD DEBUG ====');
            console.log('RAW DATA FROM APEX:', JSON.stringify(data, null, 2));
            console.log('Is Premium?', data.isPremium);
            console.log('Total Entries:', data.entries ? data.entries.length : 0);
            
            // Explicitly set premium status from server response
            this.isPremium = data.isPremium;

            // Transform entry list
            if (data.entries && data.entries.length > 0) {
                console.log('==== BEFORE MAPPING ====');
                console.log('First Entry RAW:', JSON.stringify(data.entries[0], null, 2));
                console.log('First Entry topBehaviors type:', typeof data.entries[0].topBehaviors);
                console.log('First Entry topBehaviors isArray:', Array.isArray(data.entries[0].topBehaviors));
                console.log('First Entry topBehaviors value:', data.entries[0].topBehaviors);
                
                this.leaderboardData = data.entries.map((entry, index) => {
                    const rank = index + 1;
                    
                    // DEBUG: Log each entry's behaviors
                    console.log(`\n[${rank}] User: ${entry.userName}`);
                    console.log('  - Raw entry object:', entry);
                    console.log('  - entry.topBehaviors exists?', 'topBehaviors' in entry);
                    console.log('  - entry.topBehaviors type:', typeof entry.topBehaviors);
                    console.log('  - entry.topBehaviors value:', entry.topBehaviors);
                    console.log('  - entry.topBehaviors isArray:', Array.isArray(entry.topBehaviors));
                    
                    if (entry.topBehaviors) {
                        console.log('  - Behaviors Count:', entry.topBehaviors.length);
                        console.log('  - Behaviors Content:', JSON.stringify(entry.topBehaviors));
                        entry.topBehaviors.forEach((behavior, idx) => {
                            console.log(`    [${idx}] "${behavior}" (type: ${typeof behavior})`);
                        });
                    } else {
                        console.log('  - topBehaviors is NULL or UNDEFINED');
                    }
                    
                    // CRITICAL FIX: Ensure topBehaviors is always an array
                    const behaviors = Array.isArray(entry.topBehaviors) ? entry.topBehaviors : [];
                    console.log('  - Final behaviors array:', behaviors);
                    console.log('  - Final behaviors length:', behaviors.length);
                    
                    const mappedEntry = { 
                        userId: entry.userId,
                        userName: entry.userName,
                        photoUrl: entry.photoUrl,
                        totalImpactScore: entry.totalImpactScore,
                        isAnonymized: entry.isAnonymized,
                        topBehaviors: behaviors, // Explicitly set the array
                        rank: rank,
                        rankClass: rank <= 3 ? `rank-badge rank-${rank}` : 'rank-text',
                        blurClass: entry.isAnonymized ? 'user-info-container content-blur' : 'user-info-container',
                        rowClass: 'slds-grid slds-p-vertical_small slds-border_bottom row-item'
                    };
                    
                    console.log('  - Mapped entry topBehaviors:', mappedEntry.topBehaviors);
                    return mappedEntry;
                });
                
                console.log('\n==== AFTER MAPPING ====');
                console.log('Final leaderboardData length:', this.leaderboardData.length);
                console.log('Final leaderboardData:', JSON.stringify(this.leaderboardData, null, 2));
                console.log('First mapped entry topBehaviors:', this.leaderboardData[0].topBehaviors);
            } else {
                this.leaderboardData = [];
                console.log('No entries in data.entries');
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