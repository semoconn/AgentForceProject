import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMonitoredObjects from '@salesforce/apex/ExclusionBuilderController.getMonitoredObjects';
import getObjectFields from '@salesforce/apex/ExclusionBuilderController.getObjectFields';
import getPicklistValues from '@salesforce/apex/ExclusionBuilderController.getPicklistValues';
import getExclusionConfig from '@salesforce/apex/ExclusionBuilderController.getExclusionConfig';
import saveExclusions from '@salesforce/apex/ExclusionBuilderController.saveExclusions';

const OPERATORS = [
    { label: 'Equals', value: '=' },
    { label: 'Not Equals', value: '!=' },
    { label: 'Greater Than', value: '>' },
    { label: 'Less Than', value: '<' },
    { label: 'Greater Than or Equal', value: '>=' },
    { label: 'Less Than or Equal', value: '<=' },
    { label: 'Contains', value: 'LIKE' },
    { label: 'Starts With', value: 'STARTS' },
    { label: 'Is Null', value: 'IS_NULL' },
    { label: 'Is Not Null', value: 'IS_NOT_NULL' }
];

const STRING_OPERATORS = ['=', '!=', 'LIKE', 'STARTS', 'IS_NULL', 'IS_NOT_NULL'];
const NUMERIC_OPERATORS = ['=', '!=', '>', '<', '>=', '<=', 'IS_NULL', 'IS_NOT_NULL'];
const BOOLEAN_OPERATORS = ['=', '!='];
const PICKLIST_OPERATORS = ['=', '!=', 'IS_NULL', 'IS_NOT_NULL'];

const RULE_COLUMNS = [
    { label: 'Object', fieldName: 'objectLabel', type: 'text', initialWidth: 120 },
    { label: 'Field', fieldName: 'fieldLabel', type: 'text', initialWidth: 150 },
    { label: 'Operator', fieldName: 'operatorLabel', type: 'text', initialWidth: 120 },
    { label: 'Value', fieldName: 'displayValue', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [{ label: 'Remove', name: 'remove' }]
        }
    }
];

export default class ExclusionBuilder extends LightningElement {
    @track isLoading = true;
    @track isSaving = false;

    // Dropdown options
    @track objectOptions = [];
    @track fieldOptions = [];
    @track operatorOptions = [];
    @track picklistOptions = [];

    // Selected values
    @track selectedObject = '';
    @track selectedField = '';
    @track selectedOperator = '';
    @track selectedValue = '';

    // Field metadata
    @track currentFieldType = '';

    // Rules table
    @track rules = [];
    @track hasRules = false;
    columns = RULE_COLUMNS;

    // Wire result references for refresh
    wiredConfigResult;
    wiredObjectsResult;

    // Field caches
    fieldCache = {};
    picklistCache = {};

    @wire(getMonitoredObjects)
    wiredObjects(result) {
        this.wiredObjectsResult = result;
        const { error, data } = result;

        if (data) {
            this.objectOptions = data.map(obj => ({
                label: obj.label,
                value: obj.value
            }));
        } else if (error) {
            this.showToast('Error', 'Failed to load objects: ' + this.getErrorMessage(error), 'error');
        }
    }

    @wire(getExclusionConfig)
    wiredConfig(result) {
        this.wiredConfigResult = result;
        const { error, data } = result;

        if (data) {
            this.parseExistingConfig(data.jsonConfig);
            this.isLoading = false;
        } else if (error) {
            this.showToast('Error', 'Failed to load configuration: ' + this.getErrorMessage(error), 'error');
            this.isLoading = false;
        }
    }

    parseExistingConfig(jsonConfig) {
        this.rules = [];

        if (!jsonConfig || jsonConfig === '{}') {
            this.hasRules = false;
            return;
        }

        try {
            const config = JSON.parse(jsonConfig);

            for (const objectName in config) {
                if (Object.prototype.hasOwnProperty.call(config, objectName)) {
                    const criteria = config[objectName];
                    const parsed = this.parseCriteria(objectName, criteria);
                    if (parsed) {
                        this.rules.push(parsed);
                    }
                }
            }

            this.hasRules = this.rules.length > 0;
        } catch (e) {
            console.error('Failed to parse existing config:', e);
        }
    }

    parseCriteria(objectName, criteria) {
        // Parse criteria like "Type != 'Customer'" or "IsActive = true"
        const patterns = [
            /^(\w+)\s*(!=|=|>=|<=|>|<)\s*'([^']*)'$/,  // Field operator 'value'
            /^(\w+)\s*(!=|=|>=|<=|>|<)\s*(\d+\.?\d*)$/, // Field operator number
            /^(\w+)\s*(!=|=)\s*(true|false)$/i,        // Field operator boolean
            /^(\w+)\s+(IS NOT NULL|IS NULL)$/i         // Field IS NULL/IS NOT NULL
        ];

        for (const pattern of patterns) {
            const match = criteria.match(pattern);
            if (match) {
                let fieldName, operator, value;

                if (pattern.source.includes('IS NOT NULL|IS NULL')) {
                    fieldName = match[1];
                    operator = match[2].toUpperCase().replace(' ', '_');
                    value = '';
                } else {
                    fieldName = match[1];
                    operator = match[2];
                    value = match[3];
                }

                return {
                    id: Date.now() + Math.random(),
                    objectName: objectName,
                    objectLabel: objectName,
                    fieldName: fieldName,
                    fieldLabel: fieldName,
                    operator: operator,
                    operatorLabel: this.getOperatorLabel(operator),
                    value: value,
                    displayValue: value || '(empty)'
                };
            }
        }

        // Fallback: store as-is
        return {
            id: Date.now() + Math.random(),
            objectName: objectName,
            objectLabel: objectName,
            fieldName: 'custom',
            fieldLabel: 'Custom Criteria',
            operator: 'custom',
            operatorLabel: 'Custom',
            value: criteria,
            displayValue: criteria
        };
    }

    getOperatorLabel(operator) {
        const found = OPERATORS.find(op => op.value === operator);
        return found ? found.label : operator;
    }

    // Getters for dynamic rendering
    get showValueInput() {
        return this.selectedField &&
               this.selectedOperator &&
               !['IS_NULL', 'IS_NOT_NULL'].includes(this.selectedOperator);
    }

    get showTextInput() {
        return this.showValueInput &&
               !this.isPicklistField &&
               !this.isBooleanField;
    }

    get showPicklistInput() {
        return this.showValueInput && this.isPicklistField;
    }

    get showBooleanInput() {
        return this.showValueInput && this.isBooleanField;
    }

    get isPicklistField() {
        return this.currentFieldType === 'PICKLIST' || this.currentFieldType === 'MULTIPICKLIST';
    }

    get isBooleanField() {
        return this.currentFieldType === 'BOOLEAN';
    }

    get isFieldDisabled() {
        return !this.selectedObject;
    }

    get isOperatorDisabled() {
        return !this.selectedField;
    }

    get isClearDisabled() {
        return !this.hasRules;
    }

    get isAddDisabled() {
        if (!this.selectedObject || !this.selectedField || !this.selectedOperator) {
            return true;
        }

        // If operator requires value, check if value is provided
        if (!['IS_NULL', 'IS_NOT_NULL'].includes(this.selectedOperator)) {
            if (!this.selectedValue && this.selectedValue !== false && this.selectedValue !== 'false') {
                return true;
            }
        }

        return false;
    }

    get isSaveDisabled() {
        return !this.hasRules || this.isSaving;
    }

    get booleanOptions() {
        return [
            { label: 'True', value: 'true' },
            { label: 'False', value: 'false' }
        ];
    }

    // Event Handlers
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedField = '';
        this.selectedOperator = '';
        this.selectedValue = '';
        this.fieldOptions = [];
        this.operatorOptions = [];
        this.currentFieldType = '';

        if (this.selectedObject) {
            this.loadFields(this.selectedObject);
        }
    }

    async loadFields(objectName) {
        if (this.fieldCache[objectName]) {
            this.fieldOptions = this.fieldCache[objectName];
            return;
        }

        try {
            const fields = await getObjectFields({ objectName: objectName });
            this.fieldCache[objectName] = fields.map(field => ({
                label: field.label,
                value: field.value,
                dataType: field.dataType
            }));
            this.fieldOptions = this.fieldCache[objectName];
        } catch (error) {
            this.showToast('Error', 'Failed to load fields: ' + this.getErrorMessage(error), 'error');
        }
    }

    handleFieldChange(event) {
        this.selectedField = event.detail.value;
        this.selectedOperator = '';
        this.selectedValue = '';
        this.picklistOptions = [];

        // Find the selected field's data type
        const selectedFieldOption = this.fieldOptions.find(f => f.value === this.selectedField);
        if (selectedFieldOption) {
            this.currentFieldType = selectedFieldOption.dataType;
            this.updateOperatorOptions();

            // Load picklist values if applicable
            if (this.isPicklistField) {
                this.loadPicklistValues(this.selectedObject, this.selectedField);
            }
        }
    }

    updateOperatorOptions() {
        let validOperators;

        switch (this.currentFieldType) {
            case 'BOOLEAN':
                validOperators = BOOLEAN_OPERATORS;
                break;
            case 'PICKLIST':
            case 'MULTIPICKLIST':
                validOperators = PICKLIST_OPERATORS;
                break;
            case 'INTEGER':
            case 'DOUBLE':
            case 'CURRENCY':
            case 'PERCENT':
            case 'DATE':
            case 'DATETIME':
                validOperators = NUMERIC_OPERATORS;
                break;
            default:
                validOperators = STRING_OPERATORS;
        }

        this.operatorOptions = OPERATORS.filter(op => validOperators.includes(op.value));
    }

    async loadPicklistValues(objectName, fieldName) {
        const cacheKey = `${objectName}.${fieldName}`;

        if (this.picklistCache[cacheKey]) {
            this.picklistOptions = this.picklistCache[cacheKey];
            return;
        }

        try {
            const values = await getPicklistValues({
                objectName: objectName,
                fieldName: fieldName
            });
            this.picklistCache[cacheKey] = values.map(val => ({
                label: val.label,
                value: val.value
            }));
            this.picklistOptions = this.picklistCache[cacheKey];
        } catch (error) {
            this.showToast('Error', 'Failed to load picklist values: ' + this.getErrorMessage(error), 'error');
        }
    }

    handleOperatorChange(event) {
        this.selectedOperator = event.detail.value;

        // Clear value if operator doesn't need one
        if (['IS_NULL', 'IS_NOT_NULL'].includes(this.selectedOperator)) {
            this.selectedValue = '';
        }
    }

    handleValueChange(event) {
        this.selectedValue = event.detail.value;
    }

    handleBooleanChange(event) {
        this.selectedValue = event.detail.value;
    }

    handleAddRule() {
        if (this.isAddDisabled) {
            return;
        }

        // Get labels for display
        const objectOption = this.objectOptions.find(o => o.value === this.selectedObject);
        const fieldOption = this.fieldOptions.find(f => f.value === this.selectedField);
        const operatorOption = this.operatorOptions.find(op => op.value === this.selectedOperator);

        let displayValue = this.selectedValue;
        if (this.isPicklistField) {
            const picklistOption = this.picklistOptions.find(p => p.value === this.selectedValue);
            displayValue = picklistOption ? picklistOption.label : this.selectedValue;
        }

        // Check for existing rule for this object
        const existingIndex = this.rules.findIndex(r => r.objectName === this.selectedObject);
        if (existingIndex !== -1) {
            // Replace existing rule for this object
            this.rules.splice(existingIndex, 1);
            this.showToast('Info', `Replaced existing rule for ${objectOption.label}`, 'info');
        }

        const newRule = {
            id: Date.now() + Math.random(),
            objectName: this.selectedObject,
            objectLabel: objectOption ? objectOption.label : this.selectedObject,
            fieldName: this.selectedField,
            fieldLabel: fieldOption ? fieldOption.label : this.selectedField,
            operator: this.selectedOperator,
            operatorLabel: operatorOption ? operatorOption.label : this.selectedOperator,
            value: this.selectedValue,
            displayValue: displayValue || '(null)'
        };

        this.rules = [...this.rules, newRule];
        this.hasRules = true;

        // Reset inputs
        this.resetInputs();

        this.showToast('Success', 'Rule added successfully', 'success');
    }

    resetInputs() {
        this.selectedObject = '';
        this.selectedField = '';
        this.selectedOperator = '';
        this.selectedValue = '';
        this.fieldOptions = [];
        this.operatorOptions = [];
        this.picklistOptions = [];
        this.currentFieldType = '';
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'remove') {
            this.rules = this.rules.filter(r => r.id !== row.id);
            this.hasRules = this.rules.length > 0;
            this.showToast('Success', 'Rule removed', 'success');
        }
    }

    async handleSave() {
        if (this.isSaveDisabled) {
            return;
        }

        this.isSaving = true;

        try {
            const jsonConfig = this.buildJsonConfig();

            await saveExclusions({ jsonConfig: jsonConfig });

            this.showToast('Success', 'Exclusion rules saved successfully', 'success');

            // Refresh the wire to get updated data
            await refreshApex(this.wiredConfigResult);

        } catch (error) {
            this.showToast('Error', 'Failed to save: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    buildJsonConfig() {
        const config = {};

        for (const rule of this.rules) {
            let criteria;

            if (rule.operator === 'custom') {
                criteria = rule.value;
            } else if (rule.operator === 'IS_NULL') {
                criteria = `${rule.fieldName} = NULL`;
            } else if (rule.operator === 'IS_NOT_NULL') {
                criteria = `${rule.fieldName} != NULL`;
            } else if (rule.operator === 'LIKE') {
                criteria = `${rule.fieldName} LIKE '%${rule.value}%'`;
            } else if (rule.operator === 'STARTS') {
                criteria = `${rule.fieldName} LIKE '${rule.value}%'`;
            } else {
                // Determine if value needs quotes
                const needsQuotes = !['true', 'false'].includes(String(rule.value).toLowerCase()) &&
                                    isNaN(Number(rule.value));

                if (needsQuotes) {
                    criteria = `${rule.fieldName} ${rule.operator} '${rule.value}'`;
                } else {
                    criteria = `${rule.fieldName} ${rule.operator} ${rule.value}`;
                }
            }

            config[rule.objectName] = criteria;
        }

        return JSON.stringify(config);
    }

    handleClearAll() {
        this.rules = [];
        this.hasRules = false;
        this.resetInputs();
        this.showToast('Info', 'All rules cleared. Click Save to apply changes.', 'info');
    }

    async handleRefresh() {
        this.isLoading = true;
        this.fieldCache = {};
        this.picklistCache = {};
        this.resetInputs();

        try {
            await refreshApex(this.wiredConfigResult);
            await refreshApex(this.wiredObjectsResult);
            this.showToast('Success', 'Configuration refreshed', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to refresh: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (error.message) {
            return error.message;
        }
        return 'An unknown error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
