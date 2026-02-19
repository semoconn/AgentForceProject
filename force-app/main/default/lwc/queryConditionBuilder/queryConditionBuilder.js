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

    // Searchable field picker state
    @track fieldSearchTerm = '';
    @track isFieldDropdownOpen = false;
    _fieldBlurTimeout = null;

    // Track if initial field load has been attempted
    _hasLoadedFields = false;

    connectedCallback() {
        // Parsing is deferred to after loadFields() completes
        // so field labels and types are available for the parser
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

        // Parse initial condition now that fields are available
        if (this.initialCondition && this.conditions.length === 0) {
            this.parseInitialCondition();
        }
    }

    // Computed properties
    get fieldOptions() {
        return this.fields;
    }

    // Searchable field picker computed properties
    get filteredFieldOptions() {
        const searchLower = (this.fieldSearchTerm || '').toLowerCase();
        let filtered = this.fields;

        if (searchLower) {
            filtered = this.fields.filter(f =>
                f.label.toLowerCase().includes(searchLower) ||
                f.value.toLowerCase().includes(searchLower)
            );
        }

        // Add selection styling
        return filtered.map(f => ({
            ...f,
            itemClass: f.value === this.currentField
                ? 'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small slds-is-selected'
                : 'slds-media slds-listbox__option slds-listbox__option_plain slds-media_small'
        }));
    }

    get hasFilteredFields() {
        return this.filteredFieldOptions.length > 0;
    }

    get fieldComboboxClass() {
        return this.isFieldDropdownOpen
            ? 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open'
            : 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
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

    // Searchable field picker event handlers
    handleFieldInputFocus() {
        if (this._fieldBlurTimeout) {
            clearTimeout(this._fieldBlurTimeout);
            this._fieldBlurTimeout = null;
        }
        this.isFieldDropdownOpen = true;
    }

    handleFieldInputBlur() {
        // Delay closing to allow click events on dropdown items
        this._fieldBlurTimeout = setTimeout(() => {
            this.isFieldDropdownOpen = false;
        }, 200);
    }

    handleFieldSearchInput(event) {
        this.fieldSearchTerm = event.target.value;
        this.isFieldDropdownOpen = true;
    }

    handleFieldSelect(event) {
        const fieldValue = event.currentTarget.dataset.value;
        this.selectField(fieldValue);
    }

    handleFieldKeyDown(event) {
        if (event.key === 'Escape') {
            this.isFieldDropdownOpen = false;
        } else if (event.key === 'Enter' && this.filteredFieldOptions.length === 1) {
            // Auto-select if only one match
            this.selectField(this.filteredFieldOptions[0].value);
            event.preventDefault();
        }
    }

    handleDropdownMouseDown(event) {
        // Prevent blur from firing when clicking dropdown
        event.preventDefault();
    }

    selectField(fieldValue) {
        this.currentField = fieldValue;

        // Find field and set display
        const field = this.fields.find(f => f.value === fieldValue);
        this.fieldSearchTerm = field ? field.label : fieldValue;
        this.currentFieldType = field ? field.dataType : '';

        // Close dropdown
        this.isFieldDropdownOpen = false;

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

    // Legacy event handler (kept for compatibility)
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
        this.fieldSearchTerm = '';
        this.isFieldDropdownOpen = false;
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

    // Parse a SOQL condition string back into individual visual condition rows
    parseInitialCondition() {
        if (!this.initialCondition) return;

        const rawCondition = this.initialCondition.trim();

        // Split into individual condition fragments on top-level AND/OR
        const fragments = this._splitConditionFragments(rawCondition);

        const parsedConditions = [];
        let hasFailure = false;

        for (const fragment of fragments) {
            try {
                const parsed = this._parseSingleCondition(fragment.condition);
                if (parsed) {
                    parsed.logic = fragment.logic;
                    parsed.id = Date.now() + parsedConditions.length;
                    parsedConditions.push(parsed);
                } else {
                    hasFailure = true;
                    break;
                }
            } catch (e) {
                hasFailure = true;
                break;
            }
        }

        // All-or-nothing: if any fragment fails, fall back to raw display
        if (hasFailure || parsedConditions.length === 0) {
            this._fallbackToRawCondition(rawCondition);
        } else {
            this.conditions = parsedConditions;
        }
    }

    // Split a condition string on top-level AND/OR (not inside parens or quotes)
    _splitConditionFragments(conditionStr) {
        const fragments = [];
        let depth = 0;
        let inQuote = false;
        let current = '';
        let logic = '';

        for (let i = 0; i < conditionStr.length; i++) {
            const c = conditionStr[i];

            if (c === "'" && !inQuote) { inQuote = true; current += c; continue; }
            if (c === "'" && inQuote) { inQuote = false; current += c; continue; }
            if (inQuote) { current += c; continue; }

            if (c === '(') { depth++; current += c; continue; }
            if (c === ')') { depth--; current += c; continue; }

            // Only split at depth 0
            if (depth === 0) {
                const remaining = conditionStr.substring(i);
                const andMatch = remaining.match(/^(\s+AND\s+)/i);
                const orMatch = remaining.match(/^(\s+OR\s+)/i);

                if (andMatch) {
                    if (current.trim()) {
                        fragments.push({ logic, condition: current.trim() });
                    }
                    logic = 'AND';
                    current = '';
                    i += andMatch[1].length - 1;
                    continue;
                }
                if (orMatch) {
                    if (current.trim()) {
                        fragments.push({ logic, condition: current.trim() });
                    }
                    logic = 'OR';
                    current = '';
                    i += orMatch[1].length - 1;
                    continue;
                }
            }

            current += c;
        }

        if (current.trim()) {
            fragments.push({ logic, condition: current.trim() });
        }

        return fragments;
    }

    // Parse a single SOQL condition fragment into a condition object
    _parseSingleCondition(fragment) {
        let condition = fragment.trim();

        // Strip simple wrapping parens if they don't contain top-level logic
        while (condition.startsWith('(') && condition.endsWith(')') &&
               !this._containsTopLevelLogic(condition.slice(1, -1))) {
            condition = condition.slice(1, -1).trim();
        }

        // If it still contains parens with logic inside, we can't parse it
        if (this._containsTopLevelLogic(condition)) {
            return null;
        }

        // If it contains SOQL functions like DAY_IN_WEEK(), we can't parse it
        if (/\w+\(/.test(condition) && !/LIKE|IN|NOT/.test(condition.split('(')[0].trim().split(/\s+/).pop())) {
            return null;
        }

        let match;

        // Pattern 1: field = null
        match = condition.match(/^(\S+)\s*=\s*null$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'IS_NULL', null, 'null');
        }

        // Pattern 2: field != null
        match = condition.match(/^(\S+)\s*!=\s*null$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'IS_NOT_NULL', null, 'not null');
        }

        // Pattern 3: field LIKE '%value%' (contains)
        match = condition.match(/^(\S+)\s+LIKE\s+'%(.+)%'$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'LIKE', match[2], match[2]);
        }

        // Pattern 4: field LIKE 'value%' (starts with) — must not start with %
        match = condition.match(/^(\S+)\s+LIKE\s+'([^%].*)%'$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'STARTS', match[2], match[2]);
        }

        // Pattern 5: field NOT IN ('value1','value2')
        match = condition.match(/^(\S+)\s+NOT\s+IN\s+\('(.+)'\)$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'NOT_IN', match[2], match[2]);
        }

        // Pattern 6: field IN ('value1','value2')
        match = condition.match(/^(\S+)\s+IN\s+\('(.+)'\)$/i);
        if (match) {
            return this._buildConditionObj(match[1], 'IN', match[2], match[2]);
        }

        // Pattern 7: field op 'string value' (quoted)
        match = condition.match(/^(\S+)\s*(=|!=|>=?|<=?)\s+'(.+)'$/);
        if (match) {
            return this._buildConditionObj(match[1], match[2], match[3], match[3]);
        }

        // Pattern 8: field op DATE_LITERAL:N (e.g., LAST_N_DAYS:30)
        match = condition.match(/^(\S+)\s*(=|!=|>=?|<=?)\s+(LAST_N_DAYS|NEXT_N_DAYS|LAST_N_MONTHS|NEXT_N_MONTHS|LAST_N_WEEKS|NEXT_N_WEEKS):(\d+)$/i);
        if (match) {
            const dateLiteral = match[3].toUpperCase();
            const dateN = match[4];
            const displayValue = `${dateLiteral}:${dateN}`;
            return this._buildConditionObj(match[1], match[2], displayValue, displayValue, dateLiteral, dateN);
        }

        // Pattern 9: field op DATE_LITERAL (e.g., TODAY, LAST_MONTH)
        const simpleDateLiterals = [
            'TODAY', 'YESTERDAY', 'TOMORROW',
            'THIS_WEEK', 'LAST_WEEK', 'NEXT_WEEK',
            'THIS_MONTH', 'LAST_MONTH', 'NEXT_MONTH',
            'THIS_QUARTER', 'LAST_QUARTER',
            'THIS_YEAR', 'LAST_YEAR'
        ];
        const dateRegex = new RegExp(
            `^(\\S+)\\s*(=|!=|>=?|<=?)\\s+(${simpleDateLiterals.join('|')})$`, 'i'
        );
        match = condition.match(dateRegex);
        if (match) {
            const literal = match[3].toUpperCase();
            return this._buildConditionObj(match[1], match[2], literal, literal, literal, '');
        }

        // Pattern 10: field op unquoted value (number/boolean)
        match = condition.match(/^(\S+)\s*(=|!=|>=?|<=?)\s+(\S+)$/);
        if (match) {
            return this._buildConditionObj(match[1], match[2], match[3], match[3]);
        }

        // No pattern matched
        return null;
    }

    // Build a structured condition object from parsed parts
    _buildConditionObj(fieldApiName, operator, value, displayValue, dateLiteral, dateN) {
        const field = this.fields.find(f => f.value.toLowerCase() === fieldApiName.toLowerCase());
        const fieldLabel = field ? field.label : fieldApiName;
        const fieldType = field ? this.normalizeFieldType(field.dataType) : 'STRING';

        // Look up operator label
        const operatorSet = OPERATORS[fieldType] || OPERATORS.STRING;
        const opEntry = operatorSet.find(o => o.value === operator);
        const operatorLabel = opEntry ? opEntry.label : operator;

        // Reconstruct conditionString as buildConditionString would produce
        const conditionString = this._reconstructConditionString(
            field ? field.value : fieldApiName, operator, value, fieldType, dateLiteral, dateN
        );

        // Display value for booleans
        let finalDisplayValue = displayValue || '';
        if (fieldType === 'BOOLEAN' && (value === 'true' || value === 'false')) {
            finalDisplayValue = value === 'true' ? 'True' : 'False';
        }

        return {
            id: 0,
            field: field ? field.value : fieldApiName,
            fieldLabel,
            operator,
            operatorLabel,
            value: finalDisplayValue,
            logic: '',
            conditionString
        };
    }

    // Reconstruct a SOQL condition string from parsed parts (mirrors buildConditionString)
    _reconstructConditionString(field, op, value, fieldType, dateLiteral, dateN) {
        if (op === 'IS_NULL') return `${field} = null`;
        if (op === 'IS_NOT_NULL') return `${field} != null`;
        if (op === 'LIKE') return `${field} LIKE '%${value}%'`;
        if (op === 'STARTS') return `${field} LIKE '${value}%'`;
        if (op === 'IN') return `${field} IN ('${value}')`;
        if (op === 'NOT_IN') return `${field} NOT IN ('${value}')`;

        if (dateLiteral) {
            const dateValue = dateN ? `${dateLiteral}:${dateN}` : dateLiteral;
            return `${field} ${op} ${dateValue}`;
        }

        if (fieldType === 'STRING' || fieldType === 'ID' || fieldType === 'REFERENCE') {
            return `${field} ${op} '${value}'`;
        }

        return `${field} ${op} ${value}`;
    }

    // Check if a string contains top-level AND/OR (not inside parens or quotes)
    _containsTopLevelLogic(str) {
        let depth = 0;
        let inQuote = false;
        for (let i = 0; i < str.length; i++) {
            const c = str[i];
            if (c === "'" && !inQuote) { inQuote = true; continue; }
            if (c === "'" && inQuote) { inQuote = false; continue; }
            if (inQuote) continue;
            if (c === '(') { depth++; continue; }
            if (c === ')') { depth--; continue; }
            if (depth === 0) {
                const remaining = str.substring(i);
                if (/^\s+AND\s+/i.test(remaining) || /^\s+OR\s+/i.test(remaining)) {
                    return true;
                }
            }
        }
        return false;
    }

    // Fallback: show raw SOQL text when parsing fails
    _fallbackToRawCondition(rawCondition) {
        this.conditions = [{
            id: Date.now(),
            field: 'Custom',
            fieldLabel: 'Raw SOQL',
            operator: '',
            operatorLabel: '',
            value: '',
            logic: '',
            conditionString: rawCondition,
            isRawFallback: true
        }];
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
