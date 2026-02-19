import { createElement } from '@lwc/engine-dom';
import BehaviorSettings from 'c/behaviorSettings';
import getConfigSettings from '@salesforce/apex/BehaviorSettingsController.getConfigSettings';
import saveConfigSettings from '@salesforce/apex/BehaviorSettingsController.saveConfigSettings';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/BehaviorSettingsController.getConfigSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BehaviorSettingsController.saveConfigSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const MOCK_CONFIG = {
    staleCaseThreshold: 30,
    staleOpportunityThreshold: 90,
    unassignedLeadHours: 48,
    leadHoardingDays: 5,
    highValueInactivityDays: 14,
    highValueAmountThreshold: 50000,
    contractExpiryDays: 30,
    rawLogRetentionDays: 14,
    summaryRetentionDays: 365,
    snapshotRetentionDays: 90,
    healthLogRetentionDays: 90,
    remediationRetentionDays: 365,
    recordId: '001000000000001'
};

// Helper to flush promises
const flushPromises = () => new Promise(process.nextTick);

describe('c-behavior-settings', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders with default config data', async () => {
        getConfigSettings.mockResolvedValue(MOCK_CONFIG);

        const element = createElement('c-behavior-settings', {
            is: BehaviorSettings
        });
        document.body.appendChild(element);

        // Wait for wire adapter to resolve
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
    });

    it('renders Data Retention section with 5 retention inputs', async () => {
        getConfigSettings.mockResolvedValue(MOCK_CONFIG);

        const element = createElement('c-behavior-settings', {
            is: BehaviorSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const retentionInputs = Array.from(inputs).filter(input =>
            ['rawLogRetentionDays', 'summaryRetentionDays', 'snapshotRetentionDays',
             'healthLogRetentionDays', 'remediationRetentionDays'].includes(input.name)
        );

        expect(retentionInputs.length).toBe(5);
    });

    it('populates retention fields from wire data', async () => {
        const customConfig = {
            ...MOCK_CONFIG,
            snapshotRetentionDays: 60,
            healthLogRetentionDays: 45,
            remediationRetentionDays: 500
        };
        getConfigSettings.mockResolvedValue(customConfig);

        const element = createElement('c-behavior-settings', {
            is: BehaviorSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const snapshotInput = Array.from(inputs).find(i => i.name === 'snapshotRetentionDays');
        const healthInput = Array.from(inputs).find(i => i.name === 'healthLogRetentionDays');
        const remInput = Array.from(inputs).find(i => i.name === 'remediationRetentionDays');

        expect(snapshotInput.value).toBe(60);
        expect(healthInput.value).toBe(45);
        expect(remInput.value).toBe(500);
    });

    it('renders component even when wire returns error', async () => {
        getConfigSettings.mockRejectedValue(new Error('Test error'));

        const element = createElement('c-behavior-settings', {
            is: BehaviorSettings
        });
        document.body.appendChild(element);
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
    });
});
