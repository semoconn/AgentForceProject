import { LightningElement, api, track } from 'lwc';

// Fix type configurations - defines the fields needed for each fix type
const FIX_TYPE_CONFIGS = {
    'Task_Creation': {
        label: 'Task Creation',
        description: 'Creates a follow-up task for each detected record.',
        fields: [
            { name: 'subject', label: 'Task Subject', type: 'text', required: true, placeholder: 'e.g., Follow up on stale record' },
            { name: 'priority', label: 'Priority', type: 'picklist', required: false, options: [
                { label: 'High', value: 'High' },
                { label: 'Normal', value: 'Normal' },
                { label: 'Low', value: 'Low' }
            ], defaultValue: 'Normal' },
            { name: 'description', label: 'Description', type: 'textarea', required: false, placeholder: 'Task description...' },
            { name: 'dueInDays', label: 'Due In (Days)', type: 'number', required: false, placeholder: '7', helpText: 'Number of days from today' }
        ]
    },
    'Owner_Assignment': {
        label: 'Owner Assignment',
        description: 'Assigns records to a specific user or queue.',
        fields: [
            { name: 'queueName', label: 'Queue Name', type: 'text', required: false, placeholder: 'e.g., Sales Queue', helpText: 'Enter queue name (leave blank to use assignment rules)' },
            { name: 'fallbackOwnerId', label: 'Fallback Owner ID', type: 'text', required: false, placeholder: '005...', helpText: '15 or 18 character User ID' },
            { name: 'useAssignmentRules', label: 'Use Assignment Rules', type: 'checkbox', required: false }
        ]
    },
    'Field_Update': {
        label: 'Field Update',
        description: 'Updates a specific field to a new value.',
        fields: [
            { name: 'field', label: 'Field API Name', type: 'text', required: true, placeholder: 'e.g., Status__c' },
            { name: 'value', label: 'New Value', type: 'text', required: true, placeholder: 'e.g., On Hold' }
        ]
    },
    'Email_Notification': {
        label: 'Email Notification',
        description: 'Sends an email notification about detected records.',
        fields: [
            { name: 'subject', label: 'Email Subject', type: 'text', required: true, placeholder: 'e.g., Action Required: Stale Records Detected' },
            { name: 'body', label: 'Email Body', type: 'textarea', required: false, placeholder: 'Email content...' },
            { name: 'recipientField', label: 'Recipient Field', type: 'text', required: false, placeholder: 'e.g., OwnerId or Account.OwnerId', helpText: 'Field path to the recipient User ID' },
            { name: 'additionalRecipients', label: 'Additional Recipients', type: 'text', required: false, placeholder: 'email1@example.com, email2@example.com', helpText: 'Comma-separated email addresses' }
        ]
    },
    'Opportunity_Creation': {
        label: 'Opportunity Creation',
        description: 'Creates a new Opportunity from the detected record.',
        fields: [
            { name: 'opportunityName', label: 'Opportunity Name Template', type: 'text', required: true, placeholder: 'e.g., Renewal - {AccountName}', helpText: 'Use {FieldName} for merge fields' },
            { name: 'stageName', label: 'Initial Stage', type: 'text', required: true, placeholder: 'e.g., Prospecting' },
            { name: 'closeDateOffset', label: 'Close Date Offset (Days)', type: 'number', required: false, placeholder: '30', helpText: 'Days from today for close date' },
            { name: 'amount', label: 'Amount', type: 'number', required: false, placeholder: '0' }
        ]
    },
    'Escalation_Revert': {
        label: 'Escalation Revert',
        description: 'Reverts escalated records back to their original state.',
        fields: [
            { name: 'revertField', label: 'Field to Revert', type: 'text', required: true, placeholder: 'e.g., Priority' },
            { name: 'revertValue', label: 'Revert to Value', type: 'text', required: true, placeholder: 'e.g., Normal' },
            { name: 'addComment', label: 'Add Comment', type: 'checkbox', required: false },
            { name: 'commentText', label: 'Comment Text', type: 'textarea', required: false, placeholder: 'Auto-reverted by BehaviorIQ' }
        ]
    },
    'No_Action': {
        label: 'No Action',
        description: 'Detection only - no automatic remediation.',
        fields: []
    }
};

export default class FixConfigEditor extends LightningElement {
    @api fixType = '';
    @api initialConfig = '';

    @track configValues = {};
    @track _fixType = '';

    connectedCallback() {
        this._fixType = this.fixType;
        this.parseInitialConfig();
    }

    // Watch for fixType changes
    @api
    set selectedFixType(value) {
        if (value !== this._fixType) {
            this._fixType = value;
            // Reset config when fix type changes
            this.configValues = {};
            this.setDefaults();
        }
    }

    get selectedFixType() {
        return this._fixType;
    }

    // Parse initial config if provided
    parseInitialConfig() {
        if (this.initialConfig) {
            try {
                this.configValues = JSON.parse(this.initialConfig);
            } catch (e) {
                console.error('Error parsing initial config:', e);
                this.configValues = {};
            }
        }
        this.setDefaults();
    }

    // Set default values for fields
    setDefaults() {
        const config = this.currentConfig;
        if (config && config.fields) {
            config.fields.forEach(field => {
                if (field.defaultValue && !this.configValues[field.name]) {
                    this.configValues[field.name] = field.defaultValue;
                }
            });
        }
    }

    // Computed properties
    get currentConfig() {
        return FIX_TYPE_CONFIGS[this._fixType] || null;
    }

    get configDescription() {
        return this.currentConfig ? this.currentConfig.description : '';
    }

    get configFields() {
        if (!this.currentConfig) return [];

        return this.currentConfig.fields.map(field => ({
            ...field,
            value: this.configValues[field.name] || '',
            isText: field.type === 'text',
            isNumber: field.type === 'number',
            isTextarea: field.type === 'textarea',
            isCheckbox: field.type === 'checkbox',
            isPicklist: field.type === 'picklist',
            checked: field.type === 'checkbox' ? (this.configValues[field.name] === true) : false
        }));
    }

    get hasFields() {
        return this.currentConfig && this.currentConfig.fields && this.currentConfig.fields.length > 0;
    }

    get isNoAction() {
        return this._fixType === 'No_Action';
    }

    // Event handlers
    handleInputChange(event) {
        const fieldName = event.target.dataset.field;
        let value = event.target.value;

        // Handle checkbox
        if (event.target.type === 'checkbox') {
            value = event.target.checked;
        }

        // Handle number
        if (event.target.type === 'number' && value !== '') {
            value = parseFloat(value);
        }

        this.configValues = {
            ...this.configValues,
            [fieldName]: value
        };

        this.fireChange();
    }

    handlePicklistChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.detail.value;

        this.configValues = {
            ...this.configValues,
            [fieldName]: value
        };

        this.fireChange();
    }

    // Get the JSON config string
    @api
    getConfigJson() {
        if (!this.hasFields) {
            return '';
        }

        // Filter out empty values
        const filteredConfig = {};
        Object.keys(this.configValues).forEach(key => {
            const value = this.configValues[key];
            if (value !== '' && value !== null && value !== undefined) {
                filteredConfig[key] = value;
            }
        });

        return Object.keys(filteredConfig).length > 0
            ? JSON.stringify(filteredConfig)
            : '';
    }

    // Validate required fields
    @api
    validate() {
        if (!this.currentConfig || !this.currentConfig.fields) {
            return { isValid: true };
        }

        const missingFields = [];

        this.currentConfig.fields.forEach(field => {
            if (field.required) {
                const value = this.configValues[field.name];
                if (value === undefined || value === null || value === '') {
                    missingFields.push(field.label);
                }
            }
        });

        if (missingFields.length > 0) {
            return {
                isValid: false,
                errorMessage: `Required fields missing: ${missingFields.join(', ')}`
            };
        }

        return { isValid: true };
    }

    // Clear config
    @api
    clear() {
        this.configValues = {};
        this.setDefaults();
        this.fireChange();
    }

    // Set config from external source
    @api
    setConfig(configJson) {
        if (configJson) {
            try {
                this.configValues = JSON.parse(configJson);
            } catch (e) {
                this.configValues = {};
            }
        } else {
            this.configValues = {};
        }
        this.setDefaults();
    }

    // Fire change event
    fireChange() {
        this.dispatchEvent(new CustomEvent('configchange', {
            detail: {
                config: this.getConfigJson()
            }
        }));
    }
}
