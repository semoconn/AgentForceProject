import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableObjects from '@salesforce/apex/PatternRuleManagerController.getAvailableObjects';
import getFixTypeOptions from '@salesforce/apex/PatternRuleManagerController.getFixTypeOptions';
import getLogicTypeOptions from '@salesforce/apex/PatternRuleManagerController.getLogicTypeOptions';
import savePatternRule from '@salesforce/apex/PatternRuleManagerController.savePatternRule';
import testPatternQuery from '@salesforce/apex/PatternRuleManagerController.testPatternQuery';

export default class PatternRuleEditor extends LightningElement {
    @api mode = 'create'; // 'create' | 'edit' | 'clone'
    @api rule = null;

    // Form state
    @track developerName = '';
    @track label = '';
    @track objectApiName = '';
    @track logicType = 'Declarative';
    @track queryCondition = '';
    @track thresholdDefault = null;
    @track fixType = 'Task_Creation';
    @track fixConfig = '';
    @track apexHandlerClass = '';
    @track isPremium = true; // Auto-set for premium users
    @track developerNameManuallyEdited = false;
    @track costPerIncident = null;
    @track isActive = true;

    // UI state
    @track isLoading = false;
    @track isSaving = false;
    @track isTesting = false;
    @track testResult = null;
    @track currentStep = 1;

    // Options
    @track objectOptions = [];
    @track fixTypeOptions = [];
    @track logicTypeOptions = [];

    // Load options on connect
    connectedCallback() {
        this.loadOptions();
        if (this.rule) {
            this.populateFromRule();
        }
    }

    async loadOptions() {
        this.isLoading = true;

        try {
            const [objects, fixTypes, logicTypes] = await Promise.all([
                getAvailableObjects(),
                getFixTypeOptions(),
                getLogicTypeOptions()
            ]);

            this.objectOptions = objects.map(o => ({
                label: o.label + (o.isCustom ? ' (Custom)' : ''),
                value: o.value
            }));

            this.fixTypeOptions = fixTypes.map(f => ({
                label: f.label,
                value: f.value
            }));

            // Filter out 'Standard' - only show 'Declarative' and 'Apex_Plugin'
            this.logicTypeOptions = logicTypes
                .filter(l => l.value !== 'Standard')
                .map(l => ({
                    label: l.label,
                    value: l.value
                }));

        } catch (error) {
            console.error('Error loading options:', error);
            this.showToast('Error', 'Failed to load form options', 'error');
        }

        this.isLoading = false;
    }

    populateFromRule() {
        if (!this.rule) return;

        this.developerName = this.mode === 'clone' ? '' : this.rule.developerName;
        this.label = this.rule.label;
        this.objectApiName = this.rule.objectApiName;
        this.logicType = this.rule.logicType || 'Declarative';
        this.queryCondition = this.rule.queryCondition || '';
        this.thresholdDefault = this.rule.thresholdDefault;
        this.fixType = this.rule.fixType;
        this.fixConfig = this.rule.fixConfig || '';
        this.apexHandlerClass = this.rule.apexHandlerClass || '';
        this.isPremium = this.rule.isPremium === true;
        this.costPerIncident = this.rule.costPerIncident;
        this.isActive = this.rule.isActive !== false;

        // Reset manual edit flag for clone mode (allow auto-generation)
        this.developerNameManuallyEdited = this.mode !== 'clone';
    }

    // Computed properties
    get modalTitle() {
        switch (this.mode) {
            case 'edit': return 'Edit Pattern Rule';
            case 'clone': return 'Clone Pattern Rule';
            default: return 'Create Pattern Rule';
        }
    }

    get isCreateMode() {
        return this.mode === 'create' || this.mode === 'clone';
    }

    get isDeclarativeLogic() {
        return this.logicType === 'Declarative';
    }

    get currentStepString() {
        return String(this.currentStep);
    }

    get isApexPlugin() {
        return this.logicType === 'Apex_Plugin';
    }

    get showQueryBuilder() {
        return this.isDeclarativeLogic && this.objectApiName;
    }

    get developerNameDisabled() {
        return this.mode === 'edit';
    }

    get isSaveDisabled() {
        return !this.label || !this.objectApiName || !this.fixType || this.isSaving;
    }

    get stepOneClass() {
        return this.currentStep === 1 ? 'slds-is-active' : (this.currentStep > 1 ? 'slds-is-complete' : '');
    }

    get stepTwoClass() {
        return this.currentStep === 2 ? 'slds-is-active' : (this.currentStep > 2 ? 'slds-is-complete' : '');
    }

    get stepThreeClass() {
        return this.currentStep === 3 ? 'slds-is-active' : (this.currentStep > 3 ? 'slds-is-complete' : '');
    }

    get stepFourClass() {
        return this.currentStep === 4 ? 'slds-is-active' : '';
    }

    get isStepOne() {
        return this.currentStep === 1;
    }

    get isStepTwo() {
        return this.currentStep === 2;
    }

    get isStepThree() {
        return this.currentStep === 3;
    }

    get isStepFour() {
        return this.currentStep === 4;
    }

    get canGoBack() {
        return this.currentStep > 1;
    }

    get canGoNext() {
        if (this.currentStep === 1) {
            return this.label && this.objectApiName;
        }
        if (this.currentStep === 2) {
            return true; // Query condition is optional
        }
        if (this.currentStep === 3) {
            return this.fixType;
        }
        return false;
    }

    get nextButtonLabel() {
        return this.currentStep === 4 ? 'Save Rule' : 'Next';
    }

    get nextButtonVariant() {
        return this.currentStep === 4 ? 'brand' : 'neutral';
    }

    // Event handlers
    handleLabelChange(event) {
        this.label = event.detail.value;

        // Auto-generate developer name for new rules until user manually edits it
        if (this.isCreateMode && !this.developerNameManuallyEdited) {
            this.developerName = this.generateDeveloperName(this.label);
        }
    }

    handleDeveloperNameChange(event) {
        this.developerName = this.sanitizeDeveloperName(event.detail.value);
        // Mark as manually edited so auto-generation stops
        this.developerNameManuallyEdited = true;
    }

    handleObjectChange(event) {
        this.objectApiName = event.detail.value;

        // Reset query condition when object changes
        this.queryCondition = '';

        // Clear query builder
        const queryBuilder = this.template.querySelector('c-query-condition-builder');
        if (queryBuilder) {
            queryBuilder.clear();
        }
    }

    handleLogicTypeChange(event) {
        this.logicType = event.detail.value;

        // Clear query condition if switching to Apex Plugin
        if (this.isApexPlugin) {
            this.queryCondition = '';
        }
    }

    handleThresholdChange(event) {
        this.thresholdDefault = event.detail.value ? parseInt(event.detail.value, 10) : null;
    }

    handleApexHandlerChange(event) {
        this.apexHandlerClass = event.detail.value;
    }

    handleFixTypeChange(event) {
        this.fixType = event.detail.value;

        // Update fix config editor
        const fixConfigEditor = this.template.querySelector('c-fix-config-editor');
        if (fixConfigEditor) {
            fixConfigEditor.selectedFixType = this.fixType;
        }
    }

    handleCostChange(event) {
        this.costPerIncident = event.detail.value ? parseFloat(event.detail.value) : null;
    }

    handleConditionChange(event) {
        this.queryCondition = event.detail.condition;
    }

    handleConfigChange(event) {
        this.fixConfig = event.detail.config;
    }

    // Navigation
    handleBack() {
        if (this.currentStep > 1) {
            this.currentStep--;
        }
    }

    handleNext() {
        if (this.currentStep < 4) {
            this.currentStep++;
        } else {
            this.handleSave();
        }
    }

    // Test query
    async handleTestQuery() {
        if (!this.objectApiName) {
            this.showToast('Error', 'Please select an object first', 'error');
            return;
        }

        // Get condition from builder
        const queryBuilder = this.template.querySelector('c-query-condition-builder');
        const condition = queryBuilder ? queryBuilder.getQueryCondition() : this.queryCondition;

        this.isTesting = true;
        this.testResult = null;

        try {
            const count = await testPatternQuery({
                objectName: this.objectApiName,
                condition: condition
            });

            this.testResult = {
                success: true,
                count: count,
                message: `Found ${count} matching records`
            };

            this.showToast('Query Test Passed', `Found ${count} matching records`, 'success');
        } catch (error) {
            this.testResult = {
                success: false,
                count: 0,
                message: error.body?.message || error.message
            };

            this.showToast('Query Test Failed', error.body?.message || error.message, 'error');
        }

        this.isTesting = false;
    }

    // Save
    async handleSave() {
        // Validate
        if (!this.validateForm()) {
            return;
        }

        // Get final values from child components
        const queryBuilder = this.template.querySelector('c-query-condition-builder');
        if (queryBuilder && this.isDeclarativeLogic) {
            this.queryCondition = queryBuilder.getQueryCondition();

            // Validate query
            const validation = await queryBuilder.validate();
            if (!validation.isValid) {
                this.showToast('Validation Error', validation.errorMessage, 'error');
                return;
            }
        }

        const fixConfigEditor = this.template.querySelector('c-fix-config-editor');
        if (fixConfigEditor) {
            const configValidation = fixConfigEditor.validate();
            if (!configValidation.isValid) {
                this.showToast('Validation Error', configValidation.errorMessage, 'error');
                return;
            }
            this.fixConfig = fixConfigEditor.getConfigJson();
        }

        // Build rule object
        const ruleData = {
            developerName: this.developerName || this.generateDeveloperName(this.label),
            label: this.label,
            objectApiName: this.objectApiName,
            logicType: this.logicType,
            queryCondition: this.queryCondition,
            thresholdDefault: this.thresholdDefault,
            fixType: this.fixType,
            fixConfig: this.fixConfig,
            apexHandlerClass: this.apexHandlerClass,
            isPremium: this.isPremium,
            costPerIncident: this.costPerIncident,
            isActive: this.isActive
        };

        this.isSaving = true;

        try {
            const jobId = await savePatternRule({
                ruleJson: JSON.stringify(ruleData)
            });

            this.showToast('Success', 'Rule deployment started (Job ID: ' + jobId + ')', 'success');

            this.dispatchEvent(new CustomEvent('save', {
                detail: { jobId, rule: ruleData }
            }));

        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }

        this.isSaving = false;
    }

    validateForm() {
        if (!this.label) {
            this.showToast('Validation Error', 'Rule label is required', 'error');
            return false;
        }

        if (!this.objectApiName) {
            this.showToast('Validation Error', 'Object is required', 'error');
            return false;
        }

        if (!this.fixType) {
            this.showToast('Validation Error', 'Fix type is required', 'error');
            return false;
        }

        if (this.isApexPlugin && !this.apexHandlerClass) {
            this.showToast('Validation Error', 'Apex Handler Class is required for Apex Plugin logic', 'error');
            return false;
        }

        return true;
    }

    // Close modal
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Utility methods
    generateDeveloperName(label) {
        if (!label) return '';

        return label
            .replace(/[^a-zA-Z0-9\s]/g, '') // Remove special chars
            .replace(/\s+/g, '_') // Replace spaces with underscores
            .substring(0, 40); // Max 40 chars
    }

    sanitizeDeveloperName(name) {
        return name
            .replace(/[^a-zA-Z0-9_]/g, '')
            .substring(0, 40);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}
