import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex Controllers
import getPatternMatches from '@salesforce/apex/PatternAnalysisService.getPatternMatches';
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix';

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
        { label: 'Probability', fieldName: 'Probability', type: 'percent', sortable: true,
            typeAttributes: { maximumFractionDigits: 0 }
        }
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

    // Internal state - Inbox Zero pattern with pending/fixed split
    @track pendingRecords = [];
    @track fixedRecords = [];
    @track columns = [];
    @track _selectedRowIds = [];
    @track isLoading = true;
    @track error = null;
    @track isFixing = false;
    @track activeTab = 'pending';

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
        if (this.ruleDeveloperName) {
            this.loadRecords();
        } else {
            this.isLoading = false;
            this.error = 'No pattern rule specified.';
        }

        this._handleKeyDown = this.handleKeyDown.bind(this);
        window.addEventListener('keydown', this._handleKeyDown);
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
        return `Preview: ${this.ruleLabel || this.ruleDeveloperName || 'Affected Records'}`;
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

    get pendingTabLabel() {
        return `Pending Action (${this.pendingCount})`;
    }

    get fixedTabLabel() {
        return `Successfully Fixed (${this.fixedCount})`;
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
        return !this.isLoading && !this.error && this.pendingCount === 0;
    }

    // --- Data Loading ---

    loadRecords() {
        this.isLoading = true;
        this.error = null;

        getPatternMatches({
            ruleDeveloperName: this.ruleDeveloperName,
            limitCount: 50
        })
        .then(result => {
            this.pendingRecords = result || [];
            this.fixedRecords = [];
            this.columns = this.getColumnsForObject(this.objectApiName);
            // Pre-select all pending rows by default
            this._selectedRowIds = this.pendingRecords.map(r => r.Id);
            console.log('Records loaded:', this.pendingRecords.length, 'Selected:', this._selectedRowIds.length);
        })
        .catch(err => {
            this.error = err?.body?.message || 'Failed to load records.';
            this.pendingRecords = [];
            console.error('Error loading pattern matches:', err);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    getColumnsForObject(objectName) {
        return COLUMN_CONFIG[objectName] || COLUMN_CONFIG.Default;
    }

    // --- Event Handlers ---

    handleTabChange(event) {
        this.activeTab = event.target.value;
    }

    handleRowSelection(event) {
        const newSelection = event.detail.selectedRows.map(row => row.Id);
        this._selectedRowIds = [...newSelection];
        console.log('Row selection changed:', this._selectedRowIds.length, 'rows selected');
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

    handleConfirmFix() {
        if (!this.hasSelection) {
            this.showToast('Warning', 'Please select at least one record to fix.', 'warning');
            return;
        }

        this.isFixing = true;
        const effectiveFixType = this.fixType || this.mapObjectToFixType(this.objectApiName);
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

            // Clear selection
            this._selectedRowIds = [];

            // Show success toast
            this.showToast('Success', result.message || `Fixed ${result.fixedCount} records`, 'success');

            // If all records are fixed, switch to fixed tab
            if (this.pendingCount === 0 && this.fixedCount > 0) {
                this.activeTab = 'fixed';
            }

            // Dispatch event for parent component
            this.dispatchEvent(new CustomEvent('fixcomplete', {
                bubbles: true,
                composed: true,
                detail: {
                    fixedCount: result.fixedCount,
                    remainingCount: this.pendingCount,
                    ruleDeveloperName: this.ruleDeveloperName
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
        console.log('Select All:', this._selectedRowIds.length);
    }

    handleDeselectAll() {
        this._selectedRowIds = [];
        console.log('Deselect All');
    }

    mapObjectToFixType(apiName) {
        const map = {
            'Case': 'Stale Case',
            'Lead': 'Unassigned Lead',
            'Opportunity': 'Stale Opportunity'
        };
        return map[apiName] || apiName;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
