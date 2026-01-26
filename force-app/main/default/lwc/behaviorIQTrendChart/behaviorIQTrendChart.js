import { LightningElement, wire, api } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getTrendData from '@salesforce/apex/WorkflowAnalyticsController.getTrendData';
import getAggregatedTrendData from '@salesforce/apex/WorkflowAnalyticsController.getAggregatedTrendData';

// Allowed color values (hex format) for security validation
const ALLOWED_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;
const DEFAULT_COLOR = '#0176d3';

/**
 * @description Professional trend chart component for BehaviorIQ Dashboard.
 * Displays historical trend data from Behavior_Snapshot__c as an SVG line chart.
 */
export default class BehaviorIQTrendChart extends LightningElement {
    // Loading and error state
    isLoading = true;
    hasData = false;
    errorMessage = '';

    // Track completion of both wire calls
    _trendLoaded = false;
    _aggLoaded = false;

    // Chart data
    trendSeries = [];
    aggregatedData = [];
    isTruncated = false;

    // Cached chart model (computed when data changes, not in getter)
    _cachedChartData = null;

    // Wire result references for refreshApex
    _trendWireResult;
    _aggWireResult;

    // Chart configuration
    @api daysBack = 30;
    @api chartHeight = 200;

    // Boolean properties must default to false per LWC rules
    // Properly coerce incoming values to boolean
    _showLegend = true;
    @api
    get showLegend() {
        return this._showLegend;
    }
    set showLegend(value) {
        // Coerce to boolean: handle string "true"/"false" from markup
        this._showLegend = value === '' || value === true || value === 'true';
    }

    // View mode: 'aggregate' (total issues) or 'byPattern' (individual patterns)
    viewMode = 'aggregate';

    // SVG dimensions
    chartWidth = 600;
    padding = { top: 20, right: 20, bottom: 40, left: 50 };

    // Computed dimensions
    get innerWidth() {
        return this.chartWidth - this.padding.left - this.padding.right;
    }

    get innerHeight() {
        return this.chartHeight - this.padding.top - this.padding.bottom;
    }

    get viewBoxString() {
        return `0 0 ${this.chartWidth} ${this.chartHeight}`;
    }

    // Toggle button variants
    get aggregateVariant() {
        return this.viewMode === 'aggregate' ? 'brand' : 'neutral';
    }

    get byPatternVariant() {
        return this.viewMode === 'byPattern' ? 'brand' : 'neutral';
    }

    // Wire methods to fetch data
    @wire(getAggregatedTrendData, { daysBack: '$daysBack' })
    wiredAggregatedData(result) {
        this._aggWireResult = result;
        const { error, data } = result;
        if (data) {
            this.aggregatedData = data;
            this._aggLoaded = true;
            this.updateLoadingState();
            this.computeChartData();
        } else if (error) {
            console.error('Error loading aggregated trend data:', error);
            this.errorMessage = error.body?.message || 'Unable to load trend data';
            this._aggLoaded = true;
            this.updateLoadingState();
        }
    }

    @wire(getTrendData, { daysBack: '$daysBack' })
    wiredTrendData(result) {
        this._trendWireResult = result;
        const { error, data } = result;
        if (data) {
            this.trendSeries = data.series || [];
            this.isTruncated = data.isTruncated || false;
            this._trendLoaded = true;
            this.updateLoadingState();
            this.computeChartData();
        } else if (error) {
            console.error('Error loading trend data:', error);
            this.errorMessage = error.body?.message || 'Unable to load trend data';
            this._trendLoaded = true;
            this.updateLoadingState();
        }
    }

    /**
     * @description Updates loading state based on both wire call completions
     */
    updateLoadingState() {
        this.isLoading = !(this._trendLoaded && this._aggLoaded);
    }

    /**
     * @description Computes and caches chart data when inputs change.
     * Avoids recomputation in getter for performance.
     */
    computeChartData() {
        // Update hasData based on current view mode
        if (this.viewMode === 'aggregate') {
            this.hasData = this.aggregatedData && this.aggregatedData.length > 0;
        } else {
            this.hasData = this.trendSeries && this.trendSeries.length > 0;
        }

        // Compute and cache chart model
        if (this.viewMode === 'aggregate') {
            this._cachedChartData = this.buildAggregateChart();
        } else {
            this._cachedChartData = this.buildPatternChart();
        }
    }

    // Chart rendering - returns cached computed data
    get chartData() {
        return this._cachedChartData || { paths: [], points: [], xLabels: [], yLabels: [], gridLines: [] };
    }

    /**
     * @description Validates and sanitizes a color value for security.
     * @param {string} color - The color value to validate
     * @returns {string} Validated color or default
     */
    sanitizeColor(color) {
        if (color && ALLOWED_COLOR_PATTERN.test(color)) {
            return color;
        }
        return DEFAULT_COLOR;
    }

    /**
     * @description Builds axis labels and grid lines (shared logic).
     * @param {number} maxValue - Maximum Y value
     * @param {Array} xData - Array of x-axis data for labels
     * @param {number} xScale - X-axis scale factor
     * @param {Function} getXLabel - Function to extract label from data item
     * @returns {Object} Object containing yLabels, xLabels, and gridLines
     */
    buildAxisData(maxValue, xData, xScale, getXLabel) {
        const yLabelCount = 5;
        const yLabels = [];
        for (let i = 0; i <= yLabelCount; i++) {
            const value = Math.round(maxValue * (i / yLabelCount));
            const y = this.padding.top + this.innerHeight - (this.innerHeight * (i / yLabelCount));
            yLabels.push({ value, y, x: this.padding.left - 10 });
        }

        // Generate X-axis labels (show every nth label to avoid crowding)
        const xLabelStep = Math.max(1, Math.floor(xData.length / 6));
        const xLabels = [];
        for (let i = 0; i < xData.length; i++) {
            if (i % xLabelStep === 0 || i === xData.length - 1) {
                xLabels.push({
                    label: getXLabel(xData[i]),
                    x: this.padding.left + (i * xScale),
                    y: this.padding.top + this.innerHeight + 20
                });
            }
        }

        // Generate horizontal grid lines
        const gridLines = yLabels.map(label => ({
            x1: this.padding.left,
            x2: this.padding.left + this.innerWidth,
            y1: label.y,
            y2: label.y
        }));

        return { yLabels, xLabels, gridLines };
    }

    buildAggregateChart() {
        if (!this.aggregatedData || this.aggregatedData.length === 0) {
            return { paths: [], points: [], xLabels: [], yLabels: [], gridLines: [] };
        }

        const data = this.aggregatedData;
        const maxValue = Math.max(...data.map(d => d.recordCount || 0), 1);

        // Calculate scales
        const xScale = this.innerWidth / Math.max(data.length - 1, 1);
        const yScale = this.innerHeight / maxValue;

        // Generate path points using index (O(n) not O(n²))
        const pathPoints = data.map((d, i) => {
            const x = this.padding.left + (i * xScale);
            const y = this.padding.top + this.innerHeight - (d.recordCount || 0) * yScale;
            return { x, y, value: d.recordCount, label: d.formattedDate };
        });

        // Create SVG path string
        const pathD = pathPoints.map((p, i) => {
            return i === 0 ? `M ${p.x} ${p.y}` : `L ${p.x} ${p.y}`;
        }).join(' ');

        // Create area fill path (for gradient effect)
        const areaD = pathD +
            ` L ${pathPoints[pathPoints.length - 1].x} ${this.padding.top + this.innerHeight}` +
            ` L ${this.padding.left} ${this.padding.top + this.innerHeight} Z`;

        // Build axis data using shared helper
        const { yLabels, xLabels, gridLines } = this.buildAxisData(
            maxValue,
            data,
            xScale,
            d => d.formattedDate
        );

        const safeColor = this.sanitizeColor('#0176d3');

        return {
            paths: [{
                d: pathD,
                areaD: areaD,
                color: safeColor,
                name: 'Total Issues'
            }],
            points: pathPoints.map(p => ({
                ...p,
                color: safeColor,
                radius: 4
            })),
            xLabels,
            yLabels,
            gridLines
        };
    }

    buildPatternChart() {
        if (!this.trendSeries || this.trendSeries.length === 0) {
            return { paths: [], points: [], xLabels: [], yLabels: [], gridLines: [] };
        }

        // Find global max across all series and collect all dates
        let maxValue = 1;
        const allDates = new Set();

        this.trendSeries.forEach(series => {
            const dataPoints = series.dataPoints || [];
            dataPoints.forEach(d => {
                maxValue = Math.max(maxValue, d.recordCount || 0);
                if (d.formattedDate) {
                    allDates.add(d.formattedDate);
                }
            });
        });

        // Sort dates and build index map for O(1) lookup
        const dateArray = Array.from(allDates).sort();
        const dateIndexMap = new Map(dateArray.map((d, i) => [d, i]));

        const xScale = this.innerWidth / Math.max(dateArray.length - 1, 1);
        const yScale = this.innerHeight / maxValue;

        const paths = [];
        const allPoints = [];

        // Generate path for each series
        this.trendSeries.forEach(series => {
            const dataPoints = series.dataPoints || [];
            if (dataPoints.length === 0) return;

            // Use Map for O(1) date index lookup instead of O(n) indexOf
            const pathPoints = dataPoints.map(d => {
                const dateIndex = dateIndexMap.get(d.formattedDate) || 0;
                const x = this.padding.left + (dateIndex * xScale);
                const y = this.padding.top + this.innerHeight - (d.recordCount || 0) * yScale;
                return { x, y, value: d.recordCount, label: d.formattedDate };
            });

            const pathD = pathPoints.map((p, i) => {
                return i === 0 ? `M ${p.x} ${p.y}` : `L ${p.x} ${p.y}`;
            }).join(' ');

            const safeColor = this.sanitizeColor(series.color);

            paths.push({
                d: pathD,
                color: safeColor,
                name: series.displayName
            });

            pathPoints.forEach(p => {
                allPoints.push({
                    ...p,
                    color: safeColor,
                    radius: 3,
                    seriesName: series.displayName
                });
            });
        });

        // Build axis data using shared helper
        const { yLabels, xLabels, gridLines } = this.buildAxisData(
            maxValue,
            dateArray,
            xScale,
            d => d
        );

        return {
            paths,
            points: allPoints,
            xLabels,
            yLabels,
            gridLines
        };
    }

    // Legend data for pattern view
    get legendItems() {
        if (this.viewMode !== 'byPattern' || !this.trendSeries) {
            return [];
        }
        return this.trendSeries.map(series => ({
            name: series.displayName,
            color: this.sanitizeColor(series.color),
            colorStyle: `background-color: ${this.sanitizeColor(series.color)};`
        }));
    }

    get showPatternLegend() {
        return this.showLegend && this.viewMode === 'byPattern' && this.legendItems.length > 0;
    }

    // Event handlers
    handleViewModeChange(event) {
        const mode = event.currentTarget.dataset.mode;
        if (mode && mode !== this.viewMode) {
            this.viewMode = mode;
            this.computeChartData();
        }
    }

    async handleRefresh() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            // Use refreshApex for proper wire refresh
            await Promise.all([
                refreshApex(this._trendWireResult),
                refreshApex(this._aggWireResult)
            ]);

            // Refresh completed (whether data changed or not).
            // Clear loading state deterministically based on promise completion,
            // not on wire handler re-firing (which may not happen if data is cached).
            this._trendLoaded = true;
            this._aggLoaded = true;
            this.updateLoadingState();

            // Recompute chart with current data (wired properties hold current value)
            this.computeChartData();
        } catch (error) {
            console.error('Error refreshing trend data:', error);
            this.errorMessage = 'Failed to refresh data';
            // Ensure loading clears even on error
            this._trendLoaded = true;
            this._aggLoaded = true;
            this.updateLoadingState();
        }
    }

    // Getters for template conditionals
    get showChart() {
        return !this.isLoading && this.hasData;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasData;
    }

    get chartStyles() {
        return `height: ${this.chartHeight}px;`;
    }

    // Date range label
    get dateRangeLabel() {
        return `Last ${this.daysBack} Days`;
    }
}
