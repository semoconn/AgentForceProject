// Enhanced logWorkflowEvent.js - Automatic behavior tracking
import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
import logWorkflowEvent from '@salesforce/apex/WorkflowSuggestionController.logWorkflowEvent';

export default class LogWorkflowEvent extends LightningElement {
    @api recordId;
    @api objectApiName;
    
    @track behaviorData = {
        pageLoadTime: null,
        timeOnPage: 0,
        clickCount: 0,
        scrollDepth: 0,
        fieldsViewed: [],
        buttonsClicked: []
    };

    pageStartTime = Date.now();
    scrollTimer;
    clickTimer;

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef) {
            this.logEvent('Page_Load', {
                url: pageRef.attributes.recordId,
                type: pageRef.type
            });
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: [] })
    wiredRecord({ error, data }) {
        if (data) {
            this.behaviorData.pageLoadTime = Date.now() - this.pageStartTime;
            this.startBehaviorTracking();
        }
    }

    connectedCallback() {
        this.setupEventListeners();
        // Log page view automatically
        this.logEvent('Page_View', {
            timestamp: new Date().toISOString(),
            userAgent: navigator.userAgent
        });
    }

    disconnectedCallback() {
        this.logEvent('Page_Exit', {
            timeOnPage: Date.now() - this.pageStartTime,
            finalBehaviorData: this.behaviorData
        });
        this.removeEventListeners();
    }

    setupEventListeners() {
        // Track clicks anywhere on the page
        document.addEventListener('click', this.handleGlobalClick.bind(this));
        
        // Track scroll behavior
        window.addEventListener('scroll', this.handleScroll.bind(this));
        
        // Track form interactions
        document.addEventListener('focusin', this.handleFieldFocus.bind(this));
        
        // Track time spent
        this.timeTracker = setInterval(() => {
            this.behaviorData.timeOnPage = Date.now() - this.pageStartTime;
            
            // Log extended session every 30 seconds
            if (this.behaviorData.timeOnPage % 30000 === 0) {
                this.logEvent('Extended_Session', {
                    duration: this.behaviorData.timeOnPage,
                    engagement: this.calculateEngagement()
                });
            }
        }, 1000);
    }

    removeEventListeners() {
        document.removeEventListener('click', this.handleGlobalClick.bind(this));
        window.removeEventListener('scroll', this.handleScroll.bind(this));
        document.removeEventListener('focusin', this.handleFieldFocus.bind(this));
        if (this.timeTracker) {
            clearInterval(this.timeTracker);
        }
    }

    handleGlobalClick(event) {
        this.behaviorData.clickCount++;
        
        const element = event.target;
        const elementInfo = {
            tagName: element.tagName,
            className: element.className,
            id: element.id,
            text: element.textContent?.substring(0, 50)
        };

        // Track specific button/link clicks
        if (element.tagName === 'BUTTON' || element.tagName === 'A') {
            this.behaviorData.buttonsClicked.push(elementInfo);
            this.logEvent('Button_Click', elementInfo);
        }

        // Track if user is clicking around trying to find something
        if (this.behaviorData.clickCount > 10) {
            this.logEvent('High_Click_Activity', {
                clickCount: this.behaviorData.clickCount,
                possibleFrustration: true
            });
        }
    }

    handleScroll(event) {
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const documentHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
        const scrollDepth = (scrollTop / documentHeight) * 100;
        
        this.behaviorData.scrollDepth = Math.max(this.behaviorData.scrollDepth, scrollDepth);
        
        // Detect rapid scrolling (possible frustration)
        clearTimeout(this.scrollTimer);
        this.scrollTimer = setTimeout(() => {
            if (scrollDepth > 80) {
                this.logEvent('Deep_Scroll', {
                    scrollDepth: scrollDepth,
                    possibleSearchBehavior: true
                });
            }
        }, 500);
    }

    handleFieldFocus(event) {
        const field = event.target;
        if (field.tagName === 'INPUT' || field.tagName === 'TEXTAREA' || field.tagName === 'SELECT') {
            const fieldInfo = {
                fieldName: field.name || field.id,
                fieldType: field.type,
                timestamp: new Date().toISOString()
            };
            
            this.behaviorData.fieldsViewed.push(fieldInfo);
            this.logEvent('Field_Focus', fieldInfo);
        }
    }

    calculateEngagement() {
        return {
            clicksPerMinute: this.behaviorData.clickCount / (this.behaviorData.timeOnPage / 60000),
            scrollEngagement: this.behaviorData.scrollDepth,
            fieldsInteracted: this.behaviorData.fieldsViewed.length,
            overallScore: this.getEngagementScore()
        };
    }

    getEngagementScore() {
        let score = 0;
        score += Math.min(this.behaviorData.clickCount * 2, 50);
        score += Math.min(this.behaviorData.scrollDepth, 30);
        score += Math.min(this.behaviorData.fieldsViewed.length * 5, 20);
        return score;
    }

    async logEvent(actionName, additionalData = {}) {
        try {
            const eventData = {
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                actionName: actionName,
                behaviorData: JSON.stringify({
                    ...this.behaviorData,
                    ...additionalData,
                    timestamp: new Date().toISOString(),
                    sessionId: this.generateSessionId()
                })
            };

            await logWorkflowEvent(eventData);
            console.log(`Behavior logged: ${actionName}`);
            
            // Check for patterns that indicate pain points
            this.detectPainPoints(actionName, additionalData);
            
        } catch (error) {
            console.error('Error logging behavior event:', error);
        }
    }

    detectPainPoints(actionName, data) {
        // Detect potential pain points in real-time
        const painPoints = [];
        
        if (this.behaviorData.clickCount > 15 && this.behaviorData.timeOnPage > 120000) {
            painPoints.push('High click count with long session - possible navigation issues');
        }
        
        if (this.behaviorData.scrollDepth > 90 && this.behaviorData.clickCount < 3) {
            painPoints.push('Deep scrolling with few clicks - content may be hard to find');
        }
        
        if (this.behaviorData.fieldsViewed.length > 10 && actionName === 'Field_Focus') {
            painPoints.push('Many field interactions - form may be confusing');
        }
        
        if (painPoints.length > 0) {
            this.logEvent('Pain_Point_Detected', {
                painPoints: painPoints,
                severity: painPoints.length > 2 ? 'High' : 'Medium'
            });
        }
    }

    generateSessionId() {
        return 'session_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }

    startBehaviorTracking() {
        // Additional tracking can be added here
        console.log('Behavior tracking started for:', this.objectApiName, this.recordId);
    }
}