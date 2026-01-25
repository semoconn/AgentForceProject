import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import deactivateRule from '@salesforce/apex/PatternRuleManagerController.deactivateRule';
import reactivateRule from '@salesforce/apex/PatternRuleManagerController.reactivateRule';
import testPatternQuery from '@salesforce/apex/PatternRuleManagerController.testPatternQuery';

const COLUMNS = [
    {
        label: 'Rule Name',
        fieldName: 'label',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'labelClass' }
        }
    },
    {
        label: 'Object',
        fieldName: 'objectLabel',
        type: 'text',
        sortable: true
    },
    {
        label: 'Logic Type',
        fieldName: 'logicType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Fix Type',
        fieldName: 'fixType',
        type: 'text',
        sortable: true
    },
    {
        label: 'Status',
        fieldName: 'statusLabel',
        type: 'text',
        sortable: true,
        cellAttributes: {
            class: { fieldName: 'statusClass' }
        }
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: { fieldName: 'availableActions' }
        }
    }
];

export default class PatternRuleList extends LightningElement {
    @api rules = [];
    @track columns = COLUMNS;
    @track isProcessing = false;

    // Queue for processing toggle requests sequentially
    _toggleQueue = [];
    _isProcessingQueue = false;

    // Computed properties
    get hasRules() {
        return this.rules && this.rules.length > 0;
    }

    get tableData() {
        if (!this.rules) return [];

        return this.rules.map(rule => {
            const isActive = rule.isActive !== false;
            const isPremium = rule.isPremium === true;

            // Build row actions based on rule state
            const actions = [
                { label: 'Edit', name: 'edit' },
                { label: 'Clone', name: 'clone' },
                { label: 'Test Query', name: 'test' }
            ];

            if (isActive) {
                actions.push({ label: 'Deactivate', name: 'deactivate' });
            } else {
                actions.push({ label: 'Reactivate', name: 'reactivate' });
            }

            // Build status label
            let statusLabel = isActive ? 'Active' : 'Inactive';
            if (isPremium) {
                statusLabel += ' • Premium';
            }

            return {
                ...rule,
                id: rule.developerName,
                statusLabel,
                statusClass: isActive ? 'slds-text-color_success' : 'slds-text-color_weak',
                labelClass: isActive ? '' : 'slds-text-color_weak',
                availableActions: actions
            };
        });
    }

    // Row action handler
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'edit':
                this.dispatchEvent(new CustomEvent('edit', {
                    detail: { developerName: row.developerName }
                }));
                break;
            case 'clone':
                this.dispatchEvent(new CustomEvent('clone', {
                    detail: { developerName: row.developerName }
                }));
                break;
            case 'test':
                this.handleTestQuery(row);
                break;
            case 'deactivate':
                this.deactivateRule(row.developerName);
                break;
            case 'reactivate':
                this.reactivateRule(row.developerName);
                break;
            default:
                break;
        }
    }

    // Test query
    async handleTestQuery(rule) {
        if (!rule.queryCondition && rule.logicType !== 'Apex_Plugin') {
            this.showToast('Info', 'This rule has no query condition. It will match all records of the target object.', 'info');
            return;
        }

        if (rule.logicType === 'Apex_Plugin') {
            this.showToast('Info', 'Apex Plugin rules use custom logic. Test by running the full analysis.', 'info');
            return;
        }

        this.isProcessing = true;

        try {
            const count = await testPatternQuery({
                objectName: rule.objectApiName,
                condition: rule.queryCondition
            });

            this.showToast(
                'Query Test Result',
                `Found ${count} matching ${rule.objectLabel} records`,
                count > 0 ? 'success' : 'info'
            );
        } catch (error) {
            this.showToast('Query Test Failed', error.body?.message || error.message, 'error');
        }

        this.isProcessing = false;
    }

    // Deactivate rule (public method for parent to call)
    @api
    deactivateRule(developerName) {
        this.queueToggle(developerName, false);
    }

    // Reactivate rule (public method for parent to call)
    @api
    reactivateRule(developerName) {
        this.queueToggle(developerName, true);
    }

    /**
     * Queue a toggle request to ensure sequential processing
     * This prevents race conditions when admin rapid-fires toggles
     */
    queueToggle(developerName, targetActiveState) {
        // Check if there's already a pending request for this rule
        const existingIndex = this._toggleQueue.findIndex(
            item => item.developerName === developerName
        );

        if (existingIndex !== -1) {
            // Update the existing queued request with the new target state
            this._toggleQueue[existingIndex].targetActiveState = targetActiveState;
        } else {
            // Add new request to queue
            this._toggleQueue.push({ developerName, targetActiveState });
        }

        // Dispatch optimistic update immediately for instant UI feedback
        this.dispatchEvent(new CustomEvent('ruleupdated', {
            detail: { developerName, isActive: targetActiveState, optimistic: true }
        }));

        // Start processing queue if not already running
        this.processQueue();
    }

    /**
     * Process queued toggle requests sequentially
     */
    async processQueue() {
        if (this._isProcessingQueue || this._toggleQueue.length === 0) {
            return;
        }

        this._isProcessingQueue = true;
        this.isProcessing = true;

        while (this._toggleQueue.length > 0) {
            const { developerName, targetActiveState } = this._toggleQueue.shift();

            try {
                if (targetActiveState) {
                    await reactivateRule({ developerName });
                } else {
                    await deactivateRule({ developerName });
                }

                // Dispatch confirmed update
                this.dispatchEvent(new CustomEvent('ruleupdated', {
                    detail: { developerName, isActive: targetActiveState, optimistic: false }
                }));
            } catch (error) {
                // Rollback on error
                this.dispatchEvent(new CustomEvent('ruleupdated', {
                    detail: { developerName, isActive: !targetActiveState, rollback: true }
                }));
                this.showToast('Error', error.body?.message || error.message, 'error');
            }
        }

        this._isProcessingQueue = false;
        this.isProcessing = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}
