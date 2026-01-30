import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Apex Controllers
import getPainPoints from '@salesforce/apex/WorkflowAnalyticsController.getPainPoints';
import runAutoFix from '@salesforce/apex/WorkflowAnalyticsController.runAutoFix';
import dismissSuggestion from '@salesforce/apex/WorkflowAnalyticsController.dismissSuggestion';
import restoreSuggestion from '@salesforce/apex/WorkflowAnalyticsController.restoreSuggestion';
import markPainPointResolved from '@salesforce/apex/WorkflowAnalyticsController.markPainPointResolved';
import getDashboardData from '@salesforce/apex/WorkflowAnalyticsController.getDashboardData';
import getTotalEventsAnalyzed from '@salesforce/apex/WorkflowAnalyticsController.getTotalEventsAnalyzed';
import getMonitoredObjectsCount from '@salesforce/apex/WorkflowAnalyticsController.getMonitoredObjectsCount';
import getEnhancedSystemHealth from '@salesforce/apex/WorkflowAnalyticsController.getEnhancedSystemHealth';

export default class BehaviorIQDashboard extends LightningElement {
    @track allPainPoints = [];
    @track metrics = [];
    @track recentLogs = [];
    @track isPremium = false;
    @track isLoading = true;
    _hasRefreshedOnLoad = false;

    // Auto-refresh dashboard data on first load to bypass wire adapter caching
    // This ensures fresh data is shown immediately after setup wizard completes
    connectedCallback() {
        // Delay refresh to allow wire adapters to fire first
        // Using 1 second delay to ensure wires have populated
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            if (!this._hasRefreshedOnLoad) {
                this._hasRefreshedOnLoad = true;
                this.refreshAllData();
            }
        }, 1000);
    }

    // Silent refresh (no toast) for auto-refresh on load
    // Only refreshes wire results that have been populated (non-null)
    refreshAllData() {
        this.isLoading = true;
        const refreshPromises = [];

        // Only add refreshApex calls for wire results that exist
        if (this._wiredDashboardResult) refreshPromises.push(refreshApex(this._wiredDashboardResult));
        if (this._wiredPainPointsResult) refreshPromises.push(refreshApex(this._wiredPainPointsResult));
        if (this._wiredEventsResult) refreshPromises.push(refreshApex(this._wiredEventsResult));
        if (this._wiredObjectsCountResult) refreshPromises.push(refreshApex(this._wiredObjectsCountResult));
        if (this._wiredSystemHealthResult) refreshPromises.push(refreshApex(this._wiredSystemHealthResult));

        if (refreshPromises.length > 0) {
            Promise.all(refreshPromises).then(() => {
                this.refreshHealthGauge();
                this.isLoading = false;
            }).catch(() => {
                this.isLoading = false;
            });
        } else {
            this.isLoading = false;
        }
    }

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
    @track previewPainPointId = ''; // Pain point ID for occurrence count synchronization
    @track previewExampleRecordIds = ''; // Whitelist of record IDs for partial fix filtering
    @track previewReadOnly = false; // When true, shows records in view-only mode (for completed items)
    @track previewFixedRecordIds = ''; // Cumulative fixed record IDs for displaying in the modal
    @track previewFixedAtTimestamp = ''; // Timestamp when records were fixed

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
    _wiredObjectsCountResult;
    _wiredSystemHealthResult;
    _currentPainPointId = null; // Track the pain point being fixed for resolution
    @track totalEventsAnalyzed = 0;
    @track monitoredObjectsCount = 0;
    @track lastScanTime = null; // From System_Health_Log__c for accurate analysis job timing

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

    // 0b. Load Monitored Objects Count from Configuration
    @wire(getMonitoredObjectsCount)
    wiredObjectsCount(result) {
        this._wiredObjectsCountResult = result;
        if (result.data !== undefined) {
            this.monitoredObjectsCount = result.data;
            this.updateMetricsWithDynamicData();
        } else if (result.error) {
            console.error('Error loading monitored objects count:', result.error);
            this.monitoredObjectsCount = 0;
        }
    }

    // 0c. Load System Health for Last Scan time (analysis job completion time)
    @wire(getEnhancedSystemHealth)
    wiredSystemHealth(result) {
        this._wiredSystemHealthResult = result;
        if (result.data) {
            this.lastScanTime = result.data.lastRunTime;
            this.updateMetricsWithDynamicData();
        } else if (result.error) {
            console.error('Error loading system health:', result.error);
            this.lastScanTime = null;
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

        // Use configured monitored objects count (from BehaviorIQ_Configuration__c)
        const objectsMonitored = this.monitoredObjectsCount;

        // Format last scan time from System_Health_Log__c (analysis job completion time)
        const lastScanDisplay = this.lastScanTime
            ? this.formatLastScan(this.lastScanTime)
            : 'No data';

        // Build metrics with real data (fallback to sensible defaults if no data)
        this.metrics = [
            { id: '1', label: 'Events Analyzed', value: formattedEventsCount || '0', key: 'events_analyzed' },
            { id: '2', label: 'Active Users', value: String(uniqueUsers || 0), key: 'active_users' },
            { id: '3', label: 'Objects Monitored', value: String(objectsMonitored || 0), key: 'objects_monitored' },
            { id: '4', label: 'Last Scan', value: lastScanDisplay, key: 'last_scan' }
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
                // Active: Not dismissed AND not resolved AND has records to show
                // Filter out pain points with empty ExampleRecords (nothing to remediate)
                filtered = this.allPainPoints.filter(item => {
                    if (item.Status === 'Dismissed' || item.Status === 'Resolved') {
                        return false;
                    }
                    // Also filter out items with no example records
                    if (!item.ExampleRecords || item.ExampleRecords === '[]' || item.ExampleRecords === '') {
                        return false;
                    }
                    return true;
                });
                break;
            case 'Completed':
                // Completed: Successfully fixed (Resolved status)
                filtered = this.allPainPoints.filter(item => item.Status === 'Resolved');
                break;
            case 'Dismissed':
                // Dismissed: Manually dismissed by user (NOT resolved via auto-fix)
                filtered = this.allPainPoints.filter(item => item.Status === 'Dismissed');
                break;
            default:
                filtered = this.allPainPoints;
        }
        // Add computed properties for each point
        return filtered.map(point => {
            // Calculate actual record count based on status
            let actualCount = point.Occurrences;

            // IMPORTANT: Always trust the database Occurrences__c value for Active/Dismissed items.
            // ExampleRecords is just a SAMPLE of record IDs (limited to ~5 for storage efficiency),
            // NOT the full list. The Occurrences field has the accurate total count from the batch job.
            // Only recalculate from FixedRecordIds for Resolved items where we need to show
            // how many records were actually fixed.
            if (point.Status === 'Resolved' && point.FixedRecordIds) {
                // For Completed items: Use FixedRecordIds count if available
                // This shows how many records were actually fixed
                try {
                    const fixedIds = point.FixedRecordIds.startsWith('[')
                        ? JSON.parse(point.FixedRecordIds)
                        : point.FixedRecordIds.split(',').filter(id => id.trim());
                    actualCount = fixedIds.length;
                } catch (e) {
                    // Fall back to stored Occurrences if parsing fails
                    console.warn('Failed to parse FixedRecordIds:', e);
                    actualCount = point.Occurrences;
                }
            }
            // For Active/Dismissed items: Always use Occurrences from the database
            // Do NOT recalculate from ExampleRecords - that's just a sample, not the full count!

            return {
                ...point,
                // Use calculated count for accuracy
                Occurrences: actualCount,
                // Show cost per incident only for non-Opportunity/Contract objects that have a cost
                showCostPerIncident: point.CostPerIncident &&
                    point.ObjectApiName &&
                    point.ObjectApiName.toLowerCase() !== 'opportunity' &&
                    point.ObjectApiName.toLowerCase() !== 'contract',
                // Track if item is dismissed for UI (restore vs dismiss button)
                isDismissed: point.Status === 'Dismissed',
                // Track if item is completed (resolved via auto-fix)
                isCompleted: point.Status === 'Resolved'
            };
        });
    }

    get hasPainPoints() { return this.filteredPainPoints.length > 0; }
    get filteredCount() { return this.filteredPainPoints.length; }
    get allVariant() { return this.currentFilter === 'All' ? 'brand' : 'neutral'; }
    get activeVariant() { return this.currentFilter === 'Active' ? 'brand' : 'neutral'; }
    get completedVariant() { return this.currentFilter === 'Completed' ? 'brand' : 'neutral'; }
    get dismissedVariant() { return this.currentFilter === 'Dismissed' ? 'brand' : 'neutral'; }
    get isFixDisabled() { return !this.isPremium; }
    get autoFixButtonTitle() { return this.isPremium ? 'Apply Auto-Fix' : 'Apply Auto-Fix (Premium)'; }

    // --- Actions ---
    filterAll() { this.currentFilter = 'All'; }
    filterActive() { this.currentFilter = 'Active'; }
    filterCompleted() { this.currentFilter = 'Completed'; }
    filterDismissed() { this.currentFilter = 'Dismissed'; }

    handleRefresh() {
        this.isLoading = true;
        Promise.all([
            refreshApex(this._wiredDashboardResult),
            refreshApex(this._wiredPainPointsResult),
            refreshApex(this._wiredEventsResult),
            refreshApex(this._wiredObjectsCountResult),
            refreshApex(this._wiredSystemHealthResult)
        ]).then(() => {
            // Also refresh the health gauge component
            this.refreshHealthGauge();
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
        let painPointId = event.currentTarget.dataset.painpointId || (this.selectedRow ? this.selectedRow.Id : null);
        // Get Example_Records__c from the pain point - this is the whitelist of remaining record IDs
        let exampleRecords = event.currentTarget.dataset.id || (this.selectedRow ? this.selectedRow.ExampleRecords : null);
        // Get Fixed_Record_Ids__c for cumulative display of previously fixed records
        let fixedRecordIds = event.currentTarget.dataset.fixedIds || (this.selectedRow ? this.selectedRow.FixedRecordIds : null);
        // Get LastModifiedDate as the timestamp for when records were previously fixed
        let fixedAtTimestamp = event.currentTarget.dataset.timestamp || (this.selectedRow ? this.selectedRow.LastModifiedDate : null);

        if (!objectApiName) {
            return this.showToast('Error', 'Unable to determine object type.', 'error');
        }

        // Map object to rule developer name
        const ruleDeveloperName = this.mapObjectToRuleDeveloperName(objectApiName, uniqueKey);

        if (!ruleDeveloperName) {
            return this.showToast('Error', 'No pattern rule found for this object.', 'warning');
        }

        // Store pain point ID for resolution after fix
        this._currentPainPointId = painPointId;

        // Close solution modal if open, then open preview modal
        this.closeSolutionModal();

        // Set preview modal properties
        this.previewRuleDeveloperName = ruleDeveloperName;
        this.previewObjectApiName = objectApiName;
        this.previewRuleLabel = ruleLabel || objectApiName + ' Issues';
        this.previewFixType = this.mapObjectToFixType(objectApiName);
        // CRITICAL: Pass the pain point ID for occurrence count synchronization
        // This enables the preview to sync the dashboard count with the live query result
        this.previewPainPointId = painPointId || '';
        // Pass the Example_Records__c as whitelist for filtering - this ensures we only show remaining unfixed records
        this.previewExampleRecordIds = exampleRecords || '';
        // Pass Fixed_Record_Ids__c for cumulative display of previously fixed records
        this.previewFixedRecordIds = fixedRecordIds || '';
        // Pass the timestamp for when records were previously fixed
        this.previewFixedAtTimestamp = fixedAtTimestamp || '';
        this.previewReadOnly = false; // Editable mode for fixing
        this._isPreviewModalOpen = true;
    }

    // Handler for viewing fixed records from completed pain points
    handleViewFixedRecords(event) {
        // Get pain point info from button data attributes
        const objectApiName = event.currentTarget.dataset.type;
        const uniqueKey = event.currentTarget.dataset.key;
        const ruleLabel = event.currentTarget.dataset.label;
        // Use Fixed_Record_Ids__c instead of Example_Records__c for completed pain points
        const fixedRecords = event.currentTarget.dataset.fixedIds;
        // Get the LastModifiedDate as the timestamp when records were fixed
        const fixedAtTimestamp = event.currentTarget.dataset.timestamp;

        if (!objectApiName) {
            return this.showToast('Error', 'Unable to load fixed records data.', 'error');
        }

        // If no fixed records, show an info message
        if (!fixedRecords) {
            return this.showToast('Info', 'No fixed record IDs found for this pain point.', 'info');
        }

        // Map object to rule developer name
        const ruleDeveloperName = this.mapObjectToRuleDeveloperName(objectApiName, uniqueKey);

        if (!ruleDeveloperName) {
            return this.showToast('Error', 'No pattern rule found for this object.', 'warning');
        }

        // Close solution modal if open
        this.closeSolutionModal();

        // Set preview modal properties in READ-ONLY mode
        this.previewRuleDeveloperName = ruleDeveloperName;
        this.previewObjectApiName = objectApiName;
        this.previewRuleLabel = ruleLabel || objectApiName + ' Fixed Records';
        this.previewFixType = this.mapObjectToFixType(objectApiName);
        // For completed pain points, use Fixed_Record_Ids__c to show only the fixed records
        this.previewExampleRecordIds = fixedRecords || '';
        this.previewFixedRecordIds = ''; // Not needed in read-only mode
        // Pass the timestamp for when records were fixed
        this.previewFixedAtTimestamp = fixedAtTimestamp || '';
        this.previewReadOnly = true; // Read-only mode for viewing fixed records
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
        this.previewPainPointId = '';
        this.previewExampleRecordIds = '';
        this.previewFixedRecordIds = '';
        this.previewFixedAtTimestamp = '';
    }

    /**
     * @description Handles the occurrence sync event from the remediation preview.
     * This is triggered when the preview detects that the live record count differs
     * from the stored Occurrences__c value and syncs them.
     * @param {CustomEvent} event - Contains previousCount, newCount, statusChanged, newStatus
     */
    handleOccurrenceSynced(event) {
        const { painPointId, previousCount, newCount, statusChanged, newStatus } = event.detail;

        // Refresh the pain points list to show the updated count
        refreshApex(this._wiredPainPointsResult);

        // If status changed (e.g., auto-resolved because count hit 0), refresh health gauge too
        if (statusChanged) {
            this.refreshHealthGauge();

            // Show toast for status change
            if (newStatus === 'Resolved') {
                this.showToast('Info', `Pain point auto-resolved: all ${previousCount} records have been fixed externally.`, 'info');
            }
        }
    }

    handlePreviewFixComplete(event) {
        const { fixedCount, remainingCount, ruleDeveloperName, fixedRecordIds } = event.detail;
        this.handlePreviewClose();
        this.showToast('Success', `Successfully fixed ${fixedCount} record(s).`, 'success');

        // Mark pain point as resolved (handles partial fixes by creating new record for remaining)
        // IMPORTANT: Wait for the database update to complete before refreshing
        if (this._currentPainPointId) {
            const totalCount = fixedCount + (remainingCount || 0);
            const painPointIdToResolve = this._currentPainPointId;
            this.isLoading = true;

            markPainPointResolved({
                painPointId: painPointIdToResolve,
                fixedCount: fixedCount,
                totalCount: totalCount,
                fixedRecordIds: fixedRecordIds ? fixedRecordIds.join(',') : ''
            })
            .then(() => {
                // Now refresh pain points AFTER the database update completes
                return refreshApex(this._wiredPainPointsResult);
            })
            .then(() => {
                // Refresh health gauge after pain points are updated
                this.refreshHealthGauge();
            })
            .catch(err => {
                console.error('Error in pain point resolution flow:', err);
                const errorMsg = err?.body?.message || err?.message || 'Unknown error';
                console.error('Error details:', errorMsg);
                this.showToast('Error', `Failed to update pain point: ${errorMsg}`, 'error');
            })
            .finally(() => {
                this._currentPainPointId = null;
                this.isLoading = false;
            });
        } else {
            // No pain point ID - just refresh
            refreshApex(this._wiredPainPointsResult);
            this.refreshHealthGauge();
        }
    }

    handleDismiss(event) {
        const painPointId = event.currentTarget.dataset.id;
        if (!painPointId) return;
        this.isLoading = true;
        dismissSuggestion({ painPointId })
            .then(() => {
                this.showToast('Dismissed', 'Suggestion dismissed', 'success');
                refreshApex(this._wiredPainPointsResult);
                this.refreshHealthGauge();
            })
            .finally(() => this.isLoading = false);
    }

    handleRestore(event) {
        const painPointId = event.currentTarget.dataset.id;
        if (!painPointId) return;
        this.isLoading = true;
        restoreSuggestion({ painPointId })
            .then(() => {
                this.showToast('Restored', 'Suggestion restored to active', 'success');
                refreshApex(this._wiredPainPointsResult);
                this.refreshHealthGauge();
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

    // Refresh the health gauge component dynamically
    refreshHealthGauge() {
        const healthGauge = this.template.querySelector('c-behavior-i-q-health-gauge');
        if (healthGauge && typeof healthGauge.refresh === 'function') {
            healthGauge.refresh();
        }
    }

    getStepsForType(type) {
        if(type === 'Opportunity') return ['Check Last Activity Date', 'Email Owner', 'Update Stage'];
        if(type === 'Lead') return ['Check Lead Status', 'Re-assign to Queue'];
        return ['Analyze record history', 'Check Audit Trail'];
    }
}