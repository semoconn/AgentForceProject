import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

// Import fields from the Workflow_Log__c object
import BEHAVIOR_DATA_FIELD from '@salesforce/schema/Workflow_Log__c.Behavior_Data__c';
import ACTION_NAME_FIELD from '@salesforce/schema/Workflow_Log__c.Action_Name__c';
import OBJECT_API_NAME_FIELD from '@salesforce/schema/Workflow_Log__c.Object_API_Name__c';

// Define the fields to query
const fields = [BEHAVIOR_DATA_FIELD, ACTION_NAME_FIELD, OBJECT_API_NAME_FIELD];

export default class WorkflowLogViewer extends LightningElement {
    @api recordId;
    parsedData = [];
    actionName;
    objectApiName;
    error;

    @wire(getRecord, { recordId: '$recordId', fields })
    wiredLog({ error, data }) {
        if (data) {
            this.actionName = getFieldValue(data, ACTION_NAME_FIELD);
            this.objectApiName = getFieldValue(data, OBJECT_API_NAME_FIELD);
            const behaviorDataJson = getFieldValue(data, BEHAVIOR_DATA_FIELD);
            this.parseBehaviorData(behaviorDataJson);
            this.error = undefined;
        } else if (error) {
            this.error = 'An error occurred while loading the log data.';
            console.error('Error loading log:', error);
            this.parsedData = [];
        }
    }

    parseBehaviorData(jsonString) {
        if (!jsonString) {
            this.parsedData = [];
            return;
        }

        try {
            const data = JSON.parse(jsonString);
            const formattedData = [];

            // Flatten the JSON into a key-value array for easy display
            for (const key in data) {
                if (data.hasOwnProperty(key)) {
                    let value = data[key];
                    // If the value is an object, stringify it to make it readable
                    if (typeof value === 'object' && value !== null) {
                        value = JSON.stringify(value, null, 2); // Pretty print nested JSON
                    }
                    formattedData.push({ id: key, key: this.formatLabel(key), value: value });
                }
            }
            this.parsedData = formattedData;
        } catch (e) {
            this.error = 'Could not parse the behavior data JSON.';
            console.error('JSON Parsing Error:', e);
            this.parsedData = [{ id: 'error', key: 'Parsing Error', value: jsonString }];
        }
    }

    // Helper function to format keys like 'userId' into 'User Id'
    formatLabel(key) {
        const result = key.replace(/([A-Z])/g, ' $1');
        return result.charAt(0).toUpperCase() + result.slice(1);
    }
}
