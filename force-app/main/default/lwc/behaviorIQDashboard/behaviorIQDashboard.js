import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Apex Controllers
import getPainPoints from '@salesforce/apex/WorkflowAnalyticsController.getPainPoints';
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix';
import dismissSuggestion from '@salesforce/apex/WorkflowAnalyticsController.dismissSuggestion';
import restoreSuggestion from '@salesforce/apex/WorkflowAnalyticsController.restoreSuggestion';
import getDashboardData from '@salesforce/apex/WorkflowAnalyticsController.getDashboardData';
import getTotalEventsAnalyzed from '@salesforce/apex/WorkflowAnalyticsController.getTotalEventsAnalyzed';

export default class BehaviorIQDashboard extends LightningElement {
    @track allPainPoints = [];
    @track metrics = [];
    @track recentLogs = [];
    @track isPremium = false;
    @track isLoading = true;

    // Modal & Tabs
    @track isModalOpen = false;
    @track activeTab = 'settings';

    // Solution Modal
    @track isSolutionModalOpen = false;
    @track selectedRow = {};
    @track solutionSteps = [];

    // Remediation Preview Modal (Sprint 4)
    @track previewRuleDeveloperName = '';
    @track previewObjectApiName = '';
    @track previewRuleLabel = '';
    @track previewFixType = '';

    // Getter to safely control modal visibility - only show when we have valid data
    get isPreviewModalOpen() {
        return this._isPreviewModalOpen && this.previewRuleDeveloperName;
    }
    _isPreviewModalOpen = false;

    // Filter State
    @track currentFilter = 'Active';

    _wiredPainPointsResult;
    _wiredDashboardResult;
    _wiredEventsResult;
    @track totalEventsAnalyzed = 0;

    // 0. Load Total Events Analyzed (Dynamic ROI metric)
    @wire(getTotalEventsAnalyzed)
    wiredEvents(result) {
        this._wiredEventsResult = result;
        if (result.data !== undefined) {
            this.totalEventsAnalyzed = result.data;
            this.updateMetricsWithDynamicData();
        } else if (result.error) {
            console.error('Error loading events count:', result.error);
            this.totalEventsAnalyzed = 0;
        }
    }

    // 1. Load Dashboard Data & Force 4-Card Layout
    @wire(getDashboardData)
    wiredDashboard(result) {
        this._wiredDashboardResult = result;
        if (result.data) {
            this.isPremium = result.data.isPremium;

            // Map Logs
            this.recentLogs = result.data.recentLogs.map(log => ({
                ...log,
                UserName: log.User__r ? log.User__r.Name : 'System'
            }));

            // Build metrics with dynamic data
            this.updateMetricsWithDynamicData();

        } else if (result.error) {
            console.error('Error loading dashboard:', result.error);
        }
    }

    /**
     * @description Updates the metrics array with real dynamic data from Apex.
     * Replaces hardcoded demo values with actual counts from the database.
     */
    updateMetricsWithDynamicData() {
        // Format the events count with thousands separator
        const formattedEventsCount = this.totalEventsAnalyzed.toLocaleString();

        // Calculate active users from recent logs (unique users in last 30 days)
        const uniqueUsers = new Set(this.recentLogs.map(log => log.User__c)).size;

        // Calculate objects monitored from recent logs
        const uniqueObjects = new Set(this.recentLogs.map(log => log.Object_API_Name__c)).size;

        // Format last scan time
        const lastScanTime = this.recentLogs.length > 0
            ? this.formatLastScan(this.recentLogs[0].CreatedDate)
            : 'No data';

        // Build metrics with real data (fallback to sensible defaults if no data)
        this.metrics = [
            { id: '1', label: 'Events Analyzed', value: formattedEventsCount || '0', key: 'events_analyzed' },
            { id: '2', label: 'Active Users', value: String(uniqueUsers || 0), key: 'active_users' },
            { id: '3', label: 'Objects Monitored', value: String(uniqueObjects || 0), key: 'objects_monitored' },
            { id: '4', label: 'Last Scan', value: lastScanTime, key: 'last_scan' }
        ];

        // Apply Icons and Colors
        this.metrics = this.metrics.map(m => ({
            ...m,
            icon: this.getMetricIcon(m.key),
            cssClass: this.getMetricClass(m.key)
        }));
    }

    /**
     * @description Formats a datetime into a human-readable "Last Scan" string.
     * @param {string} dateTimeString - ISO datetime string
     * @returns {string} Formatted string like "Today, 2:00 PM" or "Dec 15, 3:30 PM"
     */
    formatLastScan(dateTimeString) {
        if (!dateTimeString) return 'No data';

        const scanDate = new Date(dateTimeString);
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);

        const timeOptions = { hour: 'numeric', minute: '2-digit', hour12: true };
        const timeStr = scanDate.toLocaleTimeString('en-US', timeOptions);

        if (scanDate.toDateString() === today.toDateString()) {
            return `Today, ${timeStr}`;
        } else if (scanDate.toDateString() === yesterday.toDateString()) {
            return `Yesterday, ${timeStr}`;
        } else {
            const dateOptions = { month: 'short', day: 'numeric' };
            const dateStr = scanDate.toLocaleDateString('en-US', dateOptions);
            return `${dateStr}, ${timeStr}`;
        }
    }

    getMetricIcon(key) {
        const iconMap = {
            'events_analyzed': 'standard:logging',      
            'active_users': 'standard:user',            
            'objects_monitored': 'standard:maintenance_asset', 
            'last_scan': 'standard:recent',             
            'active_anomalies': 'utility:warning' // Fallback
        };
        return iconMap[key] || 'standard:iot_orchestration';
    }

    getMetricClass(key) {
        const classMap = {
            'events_analyzed': 'icon-box icon-blue',
            'active_users': 'icon-box icon-green',
            'objects_monitored': 'icon-box icon-red',
            'last_scan': 'icon-box icon-lightblue',
            'active_anomalies': 'icon-box icon-red' // Fallback
        };
        return classMap[key] || 'icon-box icon-blue';
    }

    // 2. Load Recommendations
    @wire(getPainPoints)
    wiredData(result) {
        this._wiredPainPointsResult = result;
        if (result.data) {
            this.allPainPoints = result.data;
            this.isLoading = false;
        } else if (result.error) {
            this.allPainPoints = [];
            this.isLoading = false;
        }
    }

    // --- Getters for Filters ---
    get filteredPainPoints() {
        if (!this.allPainPoints) return [];
        let filtered;
        switch (this.currentFilter) {
            case 'Active':
                filtered = this.allPainPoints.filter(item => item.Status !== 'Dismissed' && item.Status !== 'Resolved');
                break;
            case 'Dismissed':
                filtered = this.allPainPoints.filter(item => item.Status === 'Dismissed' || item.Status === 'Resolved');
                break;
            default:
                filtered = this.allPainPoints;
        }
        // Add computed properties for each point
        return filtered.map(point => ({
            ...point,
            // Show cost per incident only for non-Opportunity/Contract objects that have a cost
            showCostPerIncident: point.CostPerIncident &&
                point.ObjectApiName &&
                point.ObjectApiName.toLowerCase() !== 'opportunity' &&
                point.ObjectApiName.toLowerCase() !== 'contract',
            // Track if item is dismissed for UI (restore vs dismiss button)
            isDismissed: point.Status === 'Dismissed' || point.Status === 'Resolved'
        }));
    }

    get hasPainPoints() { return this.filteredPainPoints.length > 0; }
    get filteredCount() { return this.filteredPainPoints.length; }
    get allVariant() { return this.currentFilter === 'All' ? 'brand' : 'neutral'; }
    get activeVariant() { return this.currentFilter === 'Active' ? 'brand' : 'neutral'; }
    get dismissedVariant() { return this.currentFilter === 'Dismissed' ? 'brand' : 'neutral'; }
    get isFixDisabled() { return !this.isPremium; }
    get autoFixButtonTitle() { return this.isPremium ? 'Apply Auto-Fix' : 'Apply Auto-Fix (Premium)'; }

    // --- Actions ---
    filterAll() { this.currentFilter = 'All'; }
    filterActive() { this.currentFilter = 'Active'; }
    filterDismissed() { this.currentFilter = 'Dismissed'; }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this._wiredDashboardResult),
            refreshApex(this._wiredPainPointsResult),
            refreshApex(this._wiredEventsResult)
        ]).then(() => {
            this.isLoading = false;
            this.showToast('Success', 'Dashboard refreshed', 'success');
        });
    }

    handleAutoFix(event) {
        if (!this.isPremium) { this.handlePremiumClick(); return; }

        // Get pain point info from button data attributes or selected row
        let objectApiName = event.currentTarget.dataset.type || (this.selectedRow ? this.selectedRow.ObjectApiName : null);
        let uniqueKey = event.currentTarget.dataset.key || (this.selectedRow ? this.selectedRow.UniqueKey : null);
        let ruleLabel = event.currentTarget.dataset.label || (this.selectedRow ? this.selectedRow.Name : null);

        if (!objectApiName) {
            return this.showToast('Error', 'Unable to determine object type.', 'error');
        }

        // Map object to rule developer name
        const ruleDeveloperName = this.mapObjectToRuleDeveloperName(objectApiName, uniqueKey);

        if (!ruleDeveloperName) {
            return this.showToast('Error', 'No pattern rule found for this object.', 'warning');
        }

        // Close solution modal if open, then open preview modal
        this.closeSolutionModal();

        // Set preview modal properties
        this.previewRuleDeveloperName = ruleDeveloperName;
        this.previewObjectApiName = objectApiName;
        this.previewRuleLabel = ruleLabel || objectApiName + ' Issues';
        this.previewFixType = this.mapObjectToFixType(objectApiName);
        this._isPreviewModalOpen = true;
    }

    // Legacy direct fix method (for backward compatibility or quick fixes)
    handleDirectFix(event) {
        if (!this.isPremium) { this.handlePremiumClick(); return; }

        let rawId = event.currentTarget.dataset.id || (this.selectedRow ? this.selectedRow.ExampleRecords : null);
        let objectApiName = event.currentTarget.dataset.type || (this.selectedRow ? this.selectedRow.ObjectApiName : null);

        if (!rawId) return this.showToast('Error', 'No target record ID found.', 'error');

        const fixType = this.mapObjectToFixType(objectApiName);
        if (!fixType) return this.showToast('Error', 'No Auto-Fix available.', 'warning');

        let recordIds = [];
        try {
            recordIds = rawId.startsWith('[') ? JSON.parse(rawId) : rawId.split(',').map(id => id.trim());
        } catch(e) { return; }

        this.isLoading = true;
        runAutoFix({ recordIds, fixType })
            .then(res => {
                this.showToast('Success', res, 'success');
                this.closeSolutionModal();
                refreshApex(this._wiredPainPointsResult);
            })
            .catch(err => this.showToast('Error', err?.body?.message || 'Failed', 'error'))
            .finally(() => this.isLoading = false);
    }

    mapObjectToFixType(apiName) {
        const map = { 'Case': 'Stale Case', 'Lead': 'Unassigned Lead', 'Opportunity': 'Stale Opportunity' };
        return map[apiName] || null;
    }

    mapObjectToRuleDeveloperName(objectApiName, uniqueKey) {
        // The uniqueKey from the pain point IS the rule's DeveloperName - use it directly
        // This ensures we always use the exact metadata name (e.g., Stale_Opp_90, not Stale_Opp_30)
        if (uniqueKey) {
            return uniqueKey;
        }

        // Fallback: Only used if uniqueKey is somehow missing (shouldn't happen with proper data)
        // These are just defaults and may not match actual metadata in the org
        const defaultRuleMap = {
            'Case': 'Stale_Case_30',
            'Lead': 'Unassigned_Lead_48',
            'Opportunity': 'Stale_Opp_90'
        };

        return defaultRuleMap[objectApiName] || null;
    }

    // --- Remediation Preview Modal Handlers ---

    handlePreviewClose() {
        this._isPreviewModalOpen = false;
        this.previewRuleDeveloperName = '';
        this.previewObjectApiName = '';
        this.previewRuleLabel = '';
        this.previewFixType = '';
    }

    handlePreviewFixComplete(event) {
        const { fixedCount, ruleDeveloperName } = event.detail;
        this.handlePreviewClose();
        this.showToast('Success', `Successfully fixed ${fixedCount} record(s).`, 'success');
        refreshApex(this._wiredPainPointsResult);
    }

    handleDismiss(event) {
        const painPointId = event.currentTarget.dataset.id;
        if(!painPointId) return;
        this.isLoading = true;
        dismissSuggestion({ painPointId })
            .then(() => {
                this.showToast('Dismissed', 'Suggestion dismissed', 'success');
                refreshApex(this._wiredPainPointsResult);
            })
            .finally(() => this.isLoading = false);
    }

    handleRestore(event) {
        const painPointId = event.currentTarget.dataset.id;
        if(!painPointId) return;
        this.isLoading = true;
        restoreSuggestion({ painPointId })
            .then(() => {
                this.showToast('Restored', 'Suggestion restored to active', 'success');
                refreshApex(this._wiredPainPointsResult);
            })
            .catch(err => this.showToast('Error', err?.body?.message || 'Failed to restore', 'error'))
            .finally(() => this.isLoading = false);
    }

    // Modal Helpers
    handleViewDetails(event) {
        const rowId = event.currentTarget.dataset.id; 
        this.selectedRow = this.allPainPoints.find(row => row.Id === rowId);
        if (this.selectedRow) {
            this.solutionSteps = this.getStepsForType(this.selectedRow.ObjectApiName);
            this.isSolutionModalOpen = true;
        }
    }
    closeSolutionModal() { this.isSolutionModalOpen = false; }
    
    openAdminModal(event) {
        this.activeTab = event.currentTarget.dataset.tab || 'settings';
        this.isModalOpen = true;
    }
    closeModal() { this.isModalOpen = false; }
    
    handlePremiumClick() {
        this.closeSolutionModal();
        this.activeTab = 'licensing';
        this.isModalOpen = true; 
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getStepsForType(type) {
        if(type === 'Opportunity') return ['Check Last Activity Date', 'Email Owner', 'Update Stage'];
        if(type === 'Lead') return ['Check Lead Status', 'Re-assign to Queue'];
        return ['Analyze record history', 'Check Audit Trail'];
    }
}