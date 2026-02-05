import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex Controllers
import getPatternMatches from '@salesforce/apex/PatternAnalysisService.getPatternMatches';
import syncPainPointOccurrences from '@salesforce/apex/PatternAnalysisService.syncPainPointOccurrences';
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix';
import getFixConfig from '@salesforce/apex/WorkflowAnalyticsController.getFixConfig';
import getRecordsByIds from '@salesforce/apex/WorkflowAnalyticsController.getRecordsByIds';

// Column definitions per object type
const COLUMN_CONFIG = {
    Case: [
        { label: 'Case Number', fieldName: 'CaseNumber', type: 'text', sortable: true },
        { label: 'Subject', fieldName: 'Subject', type: 'text', sortable: true },
        { label: 'Status', fieldName: 'Status', type: 'text', sortable: true },
        { label: 'Priority', fieldName: 'Priority', type: 'text', sortable: true },
        { label: 'Created Date', fieldName: 'CreatedDate', type: 'date', sortable: true,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
        }
    ],
    Opportunity: [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'Stage', fieldName: 'StageName', type: 'text', sortable: true },
        { label: 'Amount', fieldName: 'Amount', type: 'currency', sortable: true },
        { label: 'Close Date', fieldName: 'CloseDate', type: 'date', sortable: true },
        { label: 'Probability', fieldName: 'ProbabilityDisplay', type: 'text', sortable: true }
    ],
    Lead: [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'Company', fieldName: 'Company', type: 'text', sortable: true },
        { label: 'Status', fieldName: 'Status', type: 'text', sortable: true },
        { label: 'Email', fieldName: 'Email', type: 'email', sortable: true },
        { label: 'Phone', fieldName: 'Phone', type: 'phone', sortable: true }
    ],
    Account: [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'Industry', fieldName: 'Industry', type: 'text', sortable: true },
        { label: 'Type', fieldName: 'Type', type: 'text', sortable: true },
        { label: 'Phone', fieldName: 'Phone', type: 'phone', sortable: true },
        { label: 'Created Date', fieldName: 'CreatedDate', type: 'date', sortable: true }
    ],
    Contact: [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'Email', fieldName: 'Email', type: 'email', sortable: true },
        { label: 'Phone', fieldName: 'Phone', type: 'phone', sortable: true },
        { label: 'Title', fieldName: 'Title', type: 'text', sortable: true },
        { label: 'Created Date', fieldName: 'CreatedDate', type: 'date', sortable: true }
    ],
    Contract: [
        { label: 'Contract Number', fieldName: 'ContractNumber', type: 'text', sortable: true },
        { label: 'Account', fieldName: 'AccountName', type: 'text', sortable: true },
        { label: 'Status', fieldName: 'Status', type: 'text', sortable: true },
        { label: 'Start Date', fieldName: 'StartDate', type: 'date', sortable: true,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
        },
        { label: 'End Date', fieldName: 'EndDate', type: 'date', sortable: true,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
        }
    ],
    // Default columns for unknown object types
    Default: [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'Created Date', fieldName: 'CreatedDate', type: 'date', sortable: true,
            typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
        }
    ]
};

export default class RemediationPreview extends LightningElement {
    // Public API properties
    @api ruleDeveloperName;
    @api objectApiName;
    @api ruleLabel;
    @api fixType;
    @api painPointId; // ID of the pain point for syncing occurrence counts
    @api exampleRecordIds; // Only used in read-only mode for fixed records display (NOT for filtering active records)
    @api readOnly = false; // When true, shows records in view-only mode (no fix button)
    @api fixedRecordIds; // Cumulative fixed record IDs from pain point (for displaying previously fixed records)
    @api fixedAtTimestamp; // Timestamp when records were fixed (for displaying in Fixed At column)

    // Internal state - Inbox Zero pattern with pending/fixed split
    @track pendingRecords = [];
    @track fixedRecords = [];
    @track columns = [];
    @track _selectedRowIds = [];
    @track isLoading = true;
    @track error = null;
    @track isFixing = false;
    @track hasCompletedFix = false; // Track if user has completed at least one fix in this session

    // Confirmation dialog state
    @track showConfirmation = false;
    @track dontShowAgain = false;
    @track fixConfigInfo = null; // Metadata-driven fix configuration
    static CONFIRMATION_SKIP_KEY = 'behavioriq_skip_fix_confirmation';

    // Getter/setter for selected rows to ensure proper reactivity
    get selectedRows() {
        return this._selectedRowIds;
    }
    set selectedRows(value) {
        this._selectedRowIds = value;
    }

    // Sorting state
    sortedBy;
    sortedDirection = 'desc';

    // Lifecycle hooks
    connectedCallback() {
        // Set columns first
        this.columns = this.getColumnsForObject(this.objectApiName);

        if (this.readOnly) {
            // Read-only mode: load fixed records directly by IDs
            // Don't use getPatternMatches since the records no longer match the pattern
            this.loadFixedRecordsDirectly();
        } else if (this.ruleDeveloperName) {
            // Edit mode: load pending records via pattern matching
            this.loadRecords();
            this.loadFixConfig();
        } else {
            this.isLoading = false;
            this.error = 'No pattern rule specified.';
        }

        this._handleKeyDown = this.handleKeyDown.bind(this);
        window.addEventListener('keydown', this._handleKeyDown);
    }

    // Load fix configuration from metadata
    loadFixConfig() {
        getFixConfig({ ruleDeveloperName: this.ruleDeveloperName })
            .then(result => {
                this.fixConfigInfo = result;
            })
            .catch(err => {
                console.warn('Could not load fix config:', err);
                // Non-fatal - we'll fall back to generic messages
            });
    }

    disconnectedCallback() {
        if (this._handleKeyDown) {
            window.removeEventListener('keydown', this._handleKeyDown);
        }
    }

    handleKeyDown(event) {
        if (event.key === 'Escape' || event.keyCode === 27) {
            this.handleCancel();
        }
    }

    handleBackdropClick() {
        this.handleCancel();
    }

    // --- Getters ---

    get modalTitle() {
        if (this.readOnly) {
            // If we have a fixedAtTimestamp, these are previously fixed records
            // Otherwise, this is a read-only view of currently affected records
            if (this.fixedAtTimestamp) {
                return `Fixed Records: ${this.ruleLabel || this.ruleDeveloperName || 'Remediated Records'}`;
            }
            return `Affected Records: ${this.ruleLabel || this.ruleDeveloperName || 'Sample Records'}`;
        }
        return `Preview: ${this.ruleLabel || this.ruleDeveloperName || 'Affected Records'}`;
    }

    // Check if we should hide the fix button (read-only mode or no selection)
    get showFixButton() {
        return !this.readOnly;
    }

    get pendingCount() {
        return this.pendingRecords.length;
    }

    get fixedCount() {
        return this.fixedRecords.length;
    }

    get selectedCount() {
        return this._selectedRowIds.length;
    }

    get hasPendingRecords() {
        return this.pendingRecords.length > 0;
    }

    get hasFixedRecords() {
        return this.fixedRecords.length > 0;
    }

    get hasSelection() {
        return this._selectedRowIds.length > 0;
    }

    get fixButtonLabel() {
        return `Fix ${this.selectedCount} Record${this.selectedCount !== 1 ? 's' : ''}`;
    }

    get fixButtonDisabled() {
        return !this.hasSelection || this.isFixing;
    }

    // Columns for fixed records include a "Fixed At" column
    get fixedColumns() {
        const baseColumns = this.getColumnsForObject(this.objectApiName);
        // Add Fixed At column for tracking when records were fixed
        return [
            ...baseColumns,
            { label: 'Fixed At', fieldName: 'fixedAt', type: 'text', sortable: true }
        ];
    }

    get summaryText() {
        if (this.isLoading) return 'Loading records...';
        if (this.error) return '';
        if (this.pendingCount === 0 && this.fixedCount > 0) {
            return 'All records have been remediated!';
        }
        return `${this.pendingCount} record${this.pendingCount !== 1 ? 's' : ''} pending. Select records to fix.`;
    }

    get maxRowSelection() {
        return 200;
    }

    get showRowNumbers() {
        return true;
    }

    get allCaughtUp() {
        // Only show "All Caught Up" if user has completed at least one fix in this session
        // This prevents the confusing "Inbox Zero" message when records simply don't load
        return !this.isLoading && !this.error && this.pendingCount === 0 && this.hasCompletedFix;
    }

    // Check if no records were found (initial load returned empty without any fix being performed)
    get noRecordsFound() {
        return !this.isLoading && !this.error && this.pendingCount === 0 && !this.hasCompletedFix && !this.readOnly;
    }

    get confirmationMessage() {
        // Use metadata-driven configuration if available
        if (this.fixConfigInfo && this.fixConfigInfo.fixType) {
            return this.buildDetailedConfirmationMessage();
        }

        // Fallback: Generate context-aware confirmation message based on fix type
        const fixType = this.fixType || this.mapObjectToFixType(this.objectApiName) || '';
        const normalizedType = fixType.toLowerCase();

        if (normalizedType.includes('case')) {
            return 'High-priority follow-up tasks will be created for the selected cases.';
        } else if (normalizedType.includes('opportunity')) {
            return 'Follow-up tasks will be created for the selected opportunities.';
        } else if (normalizedType.includes('lead')) {
            return 'You will be assigned as the owner of the selected leads.';
        }
        return 'The selected records will be remediated according to the pattern rule configuration.';
    }

    // Build a detailed confirmation message from metadata configuration
    buildDetailedConfirmationMessage() {
        const config = this.fixConfigInfo;
        const fixType = config.fixType;
        let message = '';

        switch (fixType) {
            case 'Task_Creation':
                message = 'A task will be created for each selected record';
                if (config.subject) {
                    message += ` with subject: "${config.subject}"`;
                }
                if (config.priority) {
                    message += ` (${config.priority} priority)`;
                }
                message += '.';
                if (config.description) {
                    message += `\n\nTask description: "${config.description}"`;
                }
                break;

            case 'Owner_Assignment':
                if (config.queueName) {
                    message = `Selected records will be assigned to the "${config.queueName}" queue for redistribution.`;
                } else {
                    message = 'You will be assigned as the owner of the selected records.';
                }
                break;

            case 'Field_Update':
                if (config.fieldName && config.fieldValue) {
                    message = `The "${config.fieldName}" field will be updated to "${config.fieldValue}" on selected records.`;
                } else {
                    message = 'A field will be updated on the selected records.';
                }
                break;

            case 'Email_Notification':
                message = 'An email notification will be sent to the record owners.';
                if (config.subject) {
                    message += ` Subject: "${config.subject}"`;
                }
                break;

            case 'Opportunity_Creation':
                message = 'Renewal opportunities will be created from the selected records.';
                break;

            case 'Escalation_Revert':
                message = 'The IsEscalated flag will be set to FALSE on the selected cases, removing them from the escalation queue.';
                if (config.postChatter) {
                    message += '\n\nA Chatter post will be added to each case';
                    if (config.chatterMessage) {
                        message += `: "${config.chatterMessage}"`;
                    } else {
                        message += ' notifying the team of the de-escalation.';
                    }
                }
                break;

            default:
                message = `The selected records will be processed using "${fixType}" action.`;
        }

        return message;
    }

    // Check if we have detailed fix information to display
    get hasDetailedFixInfo() {
        return this.fixConfigInfo && this.fixConfigInfo.fixType;
    }

    // Get fix type display name for the confirmation dialog header
    get fixTypeDisplayName() {
        if (!this.fixConfigInfo || !this.fixConfigInfo.fixType) {
            return 'Auto-Fix';
        }
        // Convert snake_case to Title Case
        return this.fixConfigInfo.fixType.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }

    // Check if confirmation should be skipped (user previously checked "Don't show again")
    get shouldSkipConfirmation() {
        try {
            return localStorage.getItem(RemediationPreview.CONFIRMATION_SKIP_KEY) === 'true';
        } catch (e) {
            // localStorage might be unavailable in some contexts
            return false;
        }
    }

    // --- Data Loading ---

    loadRecords() {
        this.isLoading = true;
        this.error = null;

        // Build exclusion list from already-fixed records
        // The fixedRecordIds prop contains cumulative IDs of records that have been fixed
        // and should NOT appear in the preview anymore
        let excludeIds = '';
        if (this.fixedRecordIds) {
            // fixedRecordIds may be a comma-separated string or JSON array
            excludeIds = this.fixedRecordIds;
        }

        getPatternMatches({
            ruleDeveloperName: this.ruleDeveloperName,
            limitCount: 200,
            includeOnlyRecordIds: '', // Don't use whitelist - query all matching records
            excludeRecordIds: excludeIds // Exclude already-fixed records
        })
        .then(result => {
            let records = result || [];
            // Transform Opportunity records to add ProbabilityDisplay field with % suffix
            if (this.objectApiName === 'Opportunity') {
                records = records.map(r => ({
                    ...r,
                    ProbabilityDisplay: r.Probability != null ? `${r.Probability}%` : ''
                }));
            }

            // Transform Contract records to flatten Account.Name to AccountName
            if (this.objectApiName === 'Contract') {
                records = records.map(r => ({
                    ...r,
                    AccountName: r.Account ? r.Account.Name : ''
                }));
            }

            this.columns = this.getColumnsForObject(this.objectApiName);

            // In read-only mode (viewing completed/fixed records), load into fixedRecords
            // and switch to the fixed tab
            if (this.readOnly) {
                this.fixedRecords = records;
                this.pendingRecords = [];
                this._selectedRowIds = [];
            } else {
                // Normal mode: load into pendingRecords for fixing
                this.pendingRecords = records;
                this.fixedRecords = [];
                // Pre-select all pending rows by default
                this._selectedRowIds = this.pendingRecords.map(r => r.Id);

                // CRITICAL: Sync the pain point's occurrence count with server-calculated live count
                // This solves the "dual source of truth" problem where dashboard shows stale counts
                // The server calculates the count to avoid trust boundary issues
                this.syncOccurrenceCount();
            }
        })
        .catch(err => {
            this.error = err?.body?.message || 'Failed to load records.';
            this.pendingRecords = [];
            this.fixedRecords = [];
            console.error('Error loading pattern matches:', err);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    getColumnsForObject(objectName) {
        return COLUMN_CONFIG[objectName] || COLUMN_CONFIG.Default;
    }

    // Load fixed records directly by ID for read-only mode (completed pain points)
    loadFixedRecordsDirectly() {
        this.isLoading = true;
        this.error = null;

        // Use exampleRecordIds which now contains the Fixed_Record_Ids__c for completed pain points
        const recordIdsToLoad = this.exampleRecordIds;

        if (!recordIdsToLoad || !this.objectApiName) {
            this.isLoading = false;
            this.fixedRecords = [];
            return;
        }

        getRecordsByIds({
            objectApiName: this.objectApiName,
            recordIds: recordIdsToLoad
        })
        .then(result => {
            if (result && result.length > 0) {
                // Format the timestamp for display
                const displayTimestamp = this.formatFixedAtTimestamp(this.fixedAtTimestamp);

                // Transform records and add formatted timestamp
                this.fixedRecords = result.map(r => {
                    let record = { ...r };
                    // Add Probability display for Opportunities
                    if (this.objectApiName === 'Opportunity' && r.Probability != null) {
                        record.ProbabilityDisplay = `${r.Probability}%`;
                    }
                    record.fixedAt = displayTimestamp;
                    return record;
                });
            } else {
                this.fixedRecords = [];
            }
            this.pendingRecords = [];
            this._selectedRowIds = [];
        })
        .catch(err => {
            this.error = err?.body?.message || 'Unable to load fixed records.';
            this.fixedRecords = [];
            console.error('Error loading fixed records:', err);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // Format a timestamp for display in the Fixed At column
    formatFixedAtTimestamp(timestamp) {
        if (!timestamp) {
            return 'Fixed';
        }

        try {
            const date = new Date(timestamp);
            if (isNaN(date.getTime())) {
                return 'Fixed';
            }

            // Format as "Jan 13, 2026, 2:30 PM"
            return date.toLocaleDateString('en-US', {
                month: 'short',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        } catch (e) {
            console.warn('Error formatting timestamp:', e);
            return 'Fixed';
        }
    }

    // --- Event Handlers ---

    handleRowSelection(event) {
        const newSelection = event.detail.selectedRows.map(row => row.Id);
        this._selectedRowIds = [...newSelection];
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
        this.sortData(fieldName, sortDirection);
    }

    sortData(fieldName, direction) {
        const parseData = JSON.parse(JSON.stringify(this.pendingRecords));
        const isReverse = direction === 'asc' ? 1 : -1;

        parseData.sort((a, b) => {
            let valueA = a[fieldName] || '';
            let valueB = b[fieldName] || '';

            if (typeof valueA === 'string') {
                valueA = valueA.toLowerCase();
                valueB = (valueB || '').toLowerCase();
            }

            if (valueA > valueB) return isReverse;
            if (valueA < valueB) return -isReverse;
            return 0;
        });

        this.pendingRecords = parseData;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    // Handler for fix button click - shows confirmation or proceeds directly
    handleFixButtonClick() {
        if (!this.hasSelection) {
            this.showToast('Warning', 'Please select at least one record to fix.', 'warning');
            return;
        }

        // Skip confirmation if user previously checked "Don't show again"
        if (this.shouldSkipConfirmation) {
            this.handleConfirmFix();
        } else {
            this.showConfirmation = true;
        }
    }

    // Handler for "Don't show again" checkbox
    handleDontShowAgainChange(event) {
        this.dontShowAgain = event.target.checked;
    }

    // Handler for confirmation cancel button
    handleConfirmationCancel() {
        this.showConfirmation = false;
        this.dontShowAgain = false;
    }

    // Handler for confirmation proceed button
    handleConfirmationProceed() {
        // Save preference if checkbox was checked
        if (this.dontShowAgain) {
            try {
                localStorage.setItem(RemediationPreview.CONFIRMATION_SKIP_KEY, 'true');
            } catch (e) {
                console.warn('Could not save confirmation preference to localStorage:', e);
            }
        }

        this.showConfirmation = false;
        this.handleConfirmFix();
    }

    // Actual fix execution (called after confirmation or directly if skipped)
    handleConfirmFix() {
        this.isFixing = true;
        // Use ruleDeveloperName for PatternFixService - this is the metadata key that defines the fix logic
        // Falls back to fixType or object-based mapping for backward compatibility
        const effectiveFixType = this.ruleDeveloperName || this.fixType || this.mapObjectToFixType(this.objectApiName);
        const selectedIds = [...this._selectedRowIds];

        runAutoFix({
            recordIds: selectedIds,
            fixType: effectiveFixType
        })
        .then(result => {
            // result is now an AutoFixResult object with message and fixedRecordIds
            const fixedIdSet = new Set(result.fixedRecordIds || selectedIds.map(id => String(id)));

            // Move fixed records from pending to fixed
            const nowFixed = this.pendingRecords.filter(r => fixedIdSet.has(r.Id));
            const stillPending = this.pendingRecords.filter(r => !fixedIdSet.has(r.Id));

            // Add timestamp to fixed records for display
            const timestamp = new Date().toLocaleTimeString();
            nowFixed.forEach(r => {
                r.fixedAt = timestamp;
            });

            // Update state - "Inbox Zero" pattern
            this.fixedRecords = [...nowFixed, ...this.fixedRecords];
            this.pendingRecords = stillPending;

            // Mark that we've completed at least one fix in this session
            this.hasCompletedFix = true;

            // Clear selection
            this._selectedRowIds = [];

            // Show success toast
            this.showToast('Success', result.message || `Fixed ${result.fixedCount} records`, 'success');


            // Dispatch event for parent component with fixed record IDs for pain point resolution
            this.dispatchEvent(new CustomEvent('fixcomplete', {
                bubbles: true,
                composed: true,
                detail: {
                    fixedCount: result.fixedCount,
                    remainingCount: this.pendingCount,
                    ruleDeveloperName: this.ruleDeveloperName,
                    fixedRecordIds: result.fixedRecordIds || selectedIds
                }
            }));
        })
        .catch(err => {
            this.showToast('Error', err?.body?.message || 'Fix operation failed.', 'error');
        })
        .finally(() => {
            this.isFixing = false;
        });
    }

    handleSelectAll() {
        this._selectedRowIds = this.pendingRecords.map(r => r.Id);
    }

    handleDeselectAll() {
        this._selectedRowIds = [];
    }

    mapObjectToFixType(apiName) {
        const map = {
            'Case': 'Stale Case',
            'Lead': 'Unassigned Lead',
            'Opportunity': 'Stale Opportunity'
        };
        return map[apiName] || apiName;
    }

    /**
     * @description Synchronizes the pain point's stored occurrence count with the server-calculated live count.
     * This solves the critical "dual source of truth" issue where:
     * - Dashboard displays stored Occurrences__c (set by batch job, becomes stale)
     * - Preview loads live records via getPatternMatches (always current)
     *
     * SECURITY: The server calculates the live count to avoid trust boundary issues.
     * We do NOT pass a client-side count to prevent tampering.
     */
    syncOccurrenceCount() {
        // Only sync if we have a pain point ID
        if (!this.painPointId) {
            return;
        }

        // Server calculates the count - we don't pass it to avoid trust boundary issues
        syncPainPointOccurrences({
            painPointId: this.painPointId
        })
        .then(result => {
            if (result.success) {
                // If count changed, dispatch event to notify parent to refresh
                if (result.previousCount !== result.newCount) {
                    this.dispatchEvent(new CustomEvent('occurrencesynced', {
                        bubbles: true,
                        composed: true,
                        detail: {
                            painPointId: this.painPointId,
                            previousCount: result.previousCount,
                            newCount: result.newCount,
                            statusChanged: result.statusChanged,
                            newStatus: result.newStatus
                        }
                    }));
                }

                // If status changed to Resolved (all records fixed externally), notify user
                if (result.statusChanged && result.newStatus === 'Resolved') {
                    this.showToast('Info', 'All affected records have been resolved externally.', 'info');
                }
            } else {
                console.warn('Occurrence sync failed:', result.message);
            }
        })
        .catch(err => {
            // Non-fatal - just log the error, don't disrupt the preview experience
            console.error('Error syncing occurrence count:', err);
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
