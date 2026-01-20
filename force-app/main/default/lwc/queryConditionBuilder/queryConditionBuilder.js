import { LightningElement, api, track, wire } from 'lwc';
import getObjectFields from '@salesforce/apex/PatternRuleManagerController.getObjectFields';
import getPicklistValues from '@salesforce/apex/PatternRuleManagerController.getPicklistValues';
import validateQueryCondition from '@salesforce/apex/PatternRuleManagerController.validateQueryCondition';

// Operators by field type
const OPERATORS = {
    STRING: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'contains', value: 'LIKE' },
        { label: 'starts with', value: 'STARTS' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    PICKLIST: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'in', value: 'IN' },
        { label: 'not in', value: 'NOT_IN' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    BOOLEAN: [
        { label: 'equals', value: '=' }
    ],
    NUMBER: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'greater than', value: '>' },
        { label: 'greater or equal', value: '>=' },
        { label: 'less than', value: '<' },
        { label: 'less or equal', value: '<=' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    DATE: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'greater than', value: '>' },
        { label: 'greater or equal', value: '>=' },
        { label: 'less than', value: '<' },
        { label: 'less or equal', value: '<=' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    DATETIME: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'greater than', value: '>' },
        { label: 'greater or equal', value: '>=' },
        { label: 'less than', value: '<' },
        { label: 'less or equal', value: '<=' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    ID: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ],
    REFERENCE: [
        { label: 'equals', value: '=' },
        { label: 'not equals', value: '!=' },
        { label: 'is null', value: 'IS_NULL' },
        { label: 'is not null', value: 'IS_NOT_NULL' }
    ]
};

const DATE_LITERALS = [
    { label: 'Today', value: 'TODAY' },
    { label: 'Yesterday', value: 'YESTERDAY' },
    { label: 'Tomorrow', value: 'TOMORROW' },
    { label: 'Last N Days', value: 'LAST_N_DAYS' },
    { label: 'Next N Days', value: 'NEXT_N_DAYS' },
    { label: 'This Week', value: 'THIS_WEEK' },
    { label: 'Last Week', value: 'LAST_WEEK' },
    { label: 'Next Week', value: 'NEXT_WEEK' },
    { label: 'This Month', value: 'THIS_MONTH' },
    { label: 'Last Month', value: 'LAST_MONTH' },
    { label: 'Next Month', value: 'NEXT_MONTH' },
    { label: 'Last N Months', value: 'LAST_N_MONTHS' },
    { label: 'This Quarter', value: 'THIS_QUARTER' },
    { label: 'Last Quarter', value: 'LAST_QUARTER' },
    { label: 'This Year', value: 'THIS_YEAR' },
    { label: 'Last Year', value: 'LAST_YEAR' },
    { label: 'Specific Date', value: 'SPECIFIC' }
];

const BOOLEAN_OPTIONS = [
    { label: 'True', value: 'true' },
    { label: 'False', value: 'false' }
];

const LOGIC_OPTIONS = [
    { label: 'AND', value: 'AND' },
    { label: 'OR', value: 'OR' }
];

export default class QueryConditionBuilder extends LightningElement {
    @api objectApiName;
    @api initialCondition = '';

    @track conditions = [];
    @track fields = [];
    @track isLoadingFields = false;
    @track validationError = '';
    @track isValidating = false;

    // Current condition being built
    @track currentField = '';
    @track currentOperator = '';
    @track currentValue = '';
    @track currentLogic = 'AND';
    @track currentFieldType = '';
    @track currentDateLiteral = '';
    @track currentDateN = '';

    // Picklist values for picklist fields
    @track picklistOptions = [];
    @track isLoadingPicklist = false;

    // Track if initial field load has been attempted
    _hasLoadedFields = false;

    connectedCallback() {
        if (this.initialCondition) {
            this.parseInitialCondition();
        }
    }

    renderedCallback() {
        // Load fields once when objectApiName is available
        if (this.objectApiName && !this._hasLoadedFields && !this.isLoadingFields) {
            this._hasLoadedFields = true;
            this.loadFields();
        }
    }

    // Watch for object changes
    @api
    set objectName(value) {
        if (value !== this.objectApiName) {
            this.objectApiName = value;
            this._hasLoadedFields = true; // Prevent duplicate load from renderedCallback
            this.loadFields();
            // Clear conditions when object changes
            this.conditions = [];
            this.resetCurrentCondition();
        }
    }

    get objectName() {
        return this.objectApiName;
    }

    // Load fields when object changes
    async loadFields() {
        if (!this.objectApiName) {
            this.fields = [];
            return;
        }

        this.isLoadingFields = true;

        try {
            const result = await getObjectFields({ objectName: this.objectApiName });
            this.fields = result.map(f => ({
                label: f.label,
                value: f.value,
                dataType: f.dataType
            }));
        } catch (error) {
            console.error('Error loading fields:', error);
            this.fields = [];
        }

        this.isLoadingFields = false;
    }

    // Computed properties
    get fieldOptions() {
        return this.fields;
    }

    get operatorOptions() {
        if (!this.currentFieldType) return [];

        const type = this.normalizeFieldType(this.currentFieldType);
        return OPERATORS[type] || OPERATORS.STRING;
    }

    get dateLiteralOptions() {
        return DATE_LITERALS;
    }

    get booleanOptions() {
        return BOOLEAN_OPTIONS;
    }

    get logicOptions() {
        return LOGIC_OPTIONS;
    }

    get hasConditions() {
        return this.conditions && this.conditions.length > 0;
    }

    get isFieldDisabled() {
        return !this.objectApiName || this.isLoadingFields;
    }

    get isOperatorDisabled() {
        return !this.currentField;
    }

    get showValueInput() {
        return this.currentOperator && !this.isNullOperator;
    }

    get isNullOperator() {
        return this.currentOperator === 'IS_NULL' || this.currentOperator === 'IS_NOT_NULL';
    }

    get showTextInput() {
        if (!this.currentFieldType || this.isNullOperator) return false;
        const type = this.normalizeFieldType(this.currentFieldType);
        return type === 'STRING' || type === 'ID' || type === 'REFERENCE';
    }

    get showNumberInput() {
        if (!this.currentFieldType || this.isNullOperator) return false;
        const type = this.normalizeFieldType(this.currentFieldType);
        return type === 'NUMBER';
    }

    get showPicklistInput() {
        if (!this.currentFieldType || this.isNullOperator) return false;
        const type = this.normalizeFieldType(this.currentFieldType);
        return type === 'PICKLIST';
    }

    get showBooleanInput() {
        if (!this.currentFieldType || this.isNullOperator) return false;
        const type = this.normalizeFieldType(this.currentFieldType);
        return type === 'BOOLEAN';
    }

    get showDateInput() {
        if (!this.currentFieldType || this.isNullOperator) return false;
        const type = this.normalizeFieldType(this.currentFieldType);
        return type === 'DATE' || type === 'DATETIME';
    }

    get showDateNInput() {
        return this.showDateInput && this.currentDateLiteral &&
            (this.currentDateLiteral.includes('LAST_N_') || this.currentDateLiteral.includes('NEXT_N_'));
    }

    get showSpecificDateInput() {
        return this.showDateInput && this.currentDateLiteral === 'SPECIFIC';
    }

    get isAddDisabled() {
        if (!this.currentField || !this.currentOperator) return true;

        if (this.isNullOperator) return false;

        if (this.showDateInput) {
            if (!this.currentDateLiteral) return true;
            if (this.showDateNInput && !this.currentDateN) return true;
            if (this.showSpecificDateInput && !this.currentValue) return true;
        } else if (!this.currentValue && !this.showBooleanInput) {
            return true;
        }

        return false;
    }

    get showLogicSelector() {
        return this.conditions.length > 0;
    }

    // Normalize field type to our categories
    normalizeFieldType(type) {
        const typeMap = {
            'STRING': 'STRING',
            'TEXTAREA': 'STRING',
            'EMAIL': 'STRING',
            'PHONE': 'STRING',
            'URL': 'STRING',
            'PICKLIST': 'PICKLIST',
            'MULTIPICKLIST': 'PICKLIST',
            'BOOLEAN': 'BOOLEAN',
            'INTEGER': 'NUMBER',
            'DOUBLE': 'NUMBER',
            'CURRENCY': 'NUMBER',
            'PERCENT': 'NUMBER',
            'DATE': 'DATE',
            'DATETIME': 'DATETIME',
            'ID': 'ID',
            'REFERENCE': 'REFERENCE'
        };

        return typeMap[type?.toUpperCase()] || 'STRING';
    }

    // Event handlers
    handleFieldChange(event) {
        this.currentField = event.detail.value;

        // Find field type
        const field = this.fields.find(f => f.value === this.currentField);
        this.currentFieldType = field ? field.dataType : '';

        // Reset operator and value
        this.currentOperator = '';
        this.currentValue = '';
        this.currentDateLiteral = '';
        this.currentDateN = '';

        // Load picklist values if needed
        if (this.normalizeFieldType(this.currentFieldType) === 'PICKLIST') {
            this.loadPicklistValues();
        }
    }

    async loadPicklistValues() {
        this.isLoadingPicklist = true;
        this.picklistOptions = [];

        try {
            const result = await getPicklistValues({
                objectName: this.objectApiName,
                fieldName: this.currentField
            });
            this.picklistOptions = result.map(p => ({
                label: p.label,
                value: p.value
            }));
        } catch (error) {
            console.error('Error loading picklist values:', error);
        }

        this.isLoadingPicklist = false;
    }

    handleOperatorChange(event) {
        this.currentOperator = event.detail.value;
        this.currentValue = '';
        this.currentDateLiteral = '';
        this.currentDateN = '';
    }

    handleValueChange(event) {
        this.currentValue = event.detail.value;
    }

    handleDateLiteralChange(event) {
        this.currentDateLiteral = event.detail.value;
        this.currentDateN = '';
        this.currentValue = '';
    }

    handleDateNChange(event) {
        this.currentDateN = event.detail.value;
    }

    handleLogicChange(event) {
        this.currentLogic = event.detail.value;
    }

    handleAddCondition() {
        // Build the condition string
        const condition = this.buildConditionString();

        if (condition) {
            this.conditions.push({
                id: Date.now(),
                field: this.currentField,
                fieldLabel: this.fields.find(f => f.value === this.currentField)?.label || this.currentField,
                operator: this.currentOperator,
                operatorLabel: this.operatorOptions.find(o => o.value === this.currentOperator)?.label || this.currentOperator,
                value: this.getDisplayValue(),
                logic: this.conditions.length > 0 ? this.currentLogic : '',
                conditionString: condition
            });

            this.resetCurrentCondition();
            this.fireChange();
        }
    }

    buildConditionString() {
        const field = this.currentField;
        const op = this.currentOperator;

        if (op === 'IS_NULL') {
            return `${field} = null`;
        }
        if (op === 'IS_NOT_NULL') {
            return `${field} != null`;
        }

        let value = this.currentValue;
        const type = this.normalizeFieldType(this.currentFieldType);

        // Handle date literals
        if (type === 'DATE' || type === 'DATETIME') {
            if (this.currentDateLiteral === 'SPECIFIC') {
                value = this.currentValue;
            } else if (this.currentDateLiteral.includes('_N_')) {
                value = `${this.currentDateLiteral}:${this.currentDateN}`;
            } else {
                value = this.currentDateLiteral;
            }
        }

        // Handle string values (add quotes)
        if (type === 'STRING' || type === 'ID' || type === 'REFERENCE') {
            if (op === 'LIKE') {
                return `${field} LIKE '%${value}%'`;
            }
            if (op === 'STARTS') {
                return `${field} LIKE '${value}%'`;
            }
            value = `'${value}'`;
        }

        // Handle picklist IN/NOT IN
        if (op === 'IN' || op === 'NOT_IN') {
            const operator = op === 'IN' ? 'IN' : 'NOT IN';
            if (type === 'PICKLIST') {
                value = `('${value}')`;
            } else {
                value = `(${value})`;
            }
            return `${field} ${operator} ${value}`;
        }

        // Handle boolean
        if (type === 'BOOLEAN') {
            value = value === 'true' ? 'true' : 'false';
        }

        return `${field} ${op} ${value}`;
    }

    getDisplayValue() {
        if (this.isNullOperator) {
            return this.currentOperator === 'IS_NULL' ? 'null' : 'not null';
        }

        const type = this.normalizeFieldType(this.currentFieldType);

        if (type === 'DATE' || type === 'DATETIME') {
            if (this.currentDateLiteral === 'SPECIFIC') {
                return this.currentValue;
            }
            if (this.currentDateLiteral.includes('_N_')) {
                return `${this.currentDateLiteral}:${this.currentDateN}`;
            }
            return this.currentDateLiteral;
        }

        if (type === 'BOOLEAN') {
            return this.currentValue === 'true' ? 'True' : 'False';
        }

        if (type === 'PICKLIST') {
            const opt = this.picklistOptions.find(p => p.value === this.currentValue);
            return opt ? opt.label : this.currentValue;
        }

        return this.currentValue;
    }

    handleRemoveCondition(event) {
        const conditionId = parseInt(event.target.dataset.id, 10);
        this.conditions = this.conditions.filter(c => c.id !== conditionId);

        // Reset logic on first condition if removed
        if (this.conditions.length > 0) {
            this.conditions[0].logic = '';
        }

        this.fireChange();
    }

    resetCurrentCondition() {
        this.currentField = '';
        this.currentOperator = '';
        this.currentValue = '';
        this.currentFieldType = '';
        this.currentDateLiteral = '';
        this.currentDateN = '';
        this.currentLogic = 'AND';
    }

    // Build the full WHERE clause
    @api
    getQueryCondition() {
        if (this.conditions.length === 0) {
            return '';
        }

        return this.conditions.map((c, index) => {
            if (index === 0) {
                return c.conditionString;
            }
            return `${c.logic} ${c.conditionString}`;
        }).join(' ');
    }

    // Set conditions from a query string (for editing)
    parseInitialCondition() {
        // For simplicity, we'll just display the raw condition
        // A full parser would be complex; users can clear and rebuild
        if (this.initialCondition) {
            this.conditions = [{
                id: Date.now(),
                field: 'Custom',
                fieldLabel: 'Custom Condition',
                operator: '',
                operatorLabel: '',
                value: '',
                logic: '',
                conditionString: this.initialCondition
            }];
        }
    }

    // Fire change event to parent
    fireChange() {
        this.dispatchEvent(new CustomEvent('conditionchange', {
            detail: {
                condition: this.getQueryCondition()
            }
        }));
    }

    // Validate the query
    @api
    async validate() {
        const condition = this.getQueryCondition();

        if (!condition) {
            this.validationError = '';
            return { isValid: true };
        }

        this.isValidating = true;
        this.validationError = '';

        try {
            const result = await validateQueryCondition({
                objectName: this.objectApiName,
                condition: condition
            });

            if (!result.isValid) {
                this.validationError = result.errorMessage;
            }

            this.isValidating = false;
            return result;
        } catch (error) {
            this.validationError = error.body?.message || error.message;
            this.isValidating = false;
            return { isValid: false, errorMessage: this.validationError };
        }
    }

    // Clear all conditions
    @api
    clear() {
        this.conditions = [];
        this.resetCurrentCondition();
        this.validationError = '';
        this.fireChange();
    }
}
