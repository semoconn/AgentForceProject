import { LightningElement, wire, track } from 'lwc';
import getHealthScore from '@salesforce/apex/WorkflowAnalyticsController.getHealthScore';

export default class BehaviorIQHealthGauge extends LightningElement {
    @track score = 0;
    @track statusText = 'Loading...';
    @track highCount = 0;
    @track mediumCount = 0;
    @track lowCount = 0;
    @track totalAtRisk = 0;
    @track isLoaded = false;

    // Animated display score (starts at 0 and animates to actual score)
    @track animatedScore = 0;

    @wire(getHealthScore)
    wiredHealthScore({ error, data }) {
        if (data) {
            this.score = data.score;
            this.statusText = data.status;
            this.highCount = data.highCount || 0;
            this.mediumCount = data.mediumCount || 0;
            this.lowCount = data.lowCount || 0;
            this.totalAtRisk = data.totalAtRisk || 0;
            this.isLoaded = true;

            // Trigger animation after data loads
            this.animateScore();
        } else if (error) {
            console.error('Error loading health score:', error);
            this.score = 100;
            this.statusText = 'Healthy';
            this.isLoaded = true;
        }
    }

    // Animate the score from 0 to actual value
    animateScore() {
        const duration = 1000; // 1 second animation
        const startTime = performance.now();
        const startScore = 0;
        const endScore = this.score;

        const animate = (currentTime) => {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);

            // Easing function (ease-out)
            const easeOut = 1 - Math.pow(1 - progress, 3);

            this.animatedScore = Math.round(startScore + (endScore - startScore) * easeOut);

            if (progress < 1) {
                requestAnimationFrame(animate);
            }
        };

        requestAnimationFrame(animate);
    }

    // Display score (uses animated value)
    get displayScore() {
        return this.isLoaded ? this.animatedScore : 0;
    }

    // Gauge style with conic gradient
    // The conic-gradient starts at 180deg (left side) and goes clockwise
    // Score 0% = 0deg fill, Score 100% = 180deg fill
    get gaugeStyle() {
        // Convert score (0-100) to angle (0-180 degrees)
        const fillAngle = (this.animatedScore / 100) * 180;
        const color = this.gaugeColor;

        return `--gauge-color: ${color}; --fill-angle: ${fillAngle}deg;`;
    }

    // Get gauge color based on score
    get gaugeColor() {
        if (this.score > 80) {
            return '#2e844a'; // Green
        } else if (this.score >= 50) {
            return '#dd7a01'; // Orange
        } else {
            return '#ba0517'; // Red
        }
    }

    // Score text color class
    get scoreClass() {
        if (this.score > 80) {
            return 'score-green';
        } else if (this.score >= 50) {
            return 'score-orange';
        } else {
            return 'score-red';
        }
    }

    // Status text color class
    get statusClass() {
        if (this.score > 80) {
            return 'status-green';
        } else if (this.score >= 50) {
            return 'status-orange';
        } else {
            return 'status-red';
        }
    }

    // Show breakdown only if there are any issues
    get hasBreakdown() {
        return this.highCount > 0 || this.mediumCount > 0 || this.lowCount > 0;
    }

    // Show total at risk only if there is risk
    get hasTotalAtRisk() {
        return this.totalAtRisk > 0;
    }
}
