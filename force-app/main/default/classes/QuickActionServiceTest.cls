/**
 * @description Test class for the QuickActionService.
 * This class verifies that the service can correctly call the Metadata API
 * to create a Quick Action.
 */
@isTest
private class QuickActionServiceTest {

    @isTest
    static void testCreateSimpleUpdateAction_Success() {
        // ARRANGE
        // Mock the Metadata API callout. This is a required best practice.
        Test.setMock(WebServiceMock.class, new MetadataServiceMock());

        // ACT
        Test.startTest();
        QuickActionService.QuickActionResult result = QuickActionService.createSimpleUpdateAction('Contact', 'Test Quick Action');
        Test.stopTest();

        // ASSERT
        System.assertEquals(true, result.isSuccess, 'The isSuccess flag should be true on a successful call.');
        System.assert(result.message.contains('created successfully'), 'The success message should be returned.');
        System.assertEquals('Contact.Test_Quick_Action', result.actionName, 'The full action name should be returned.');
    }

    /**
     * @description Mock class to simulate a successful response from the Metadata API.
     * This prevents the test from making a real callout, which is not allowed.
     */
    private class MetadataServiceMock implements WebServiceMock {
        public void doInvoke(
            Object stub,
            Object request,
            Map<String, Object> response,
            String endpoint,
            String soapAction,
            String requestName,
            String responseNS,
            String responseName,
            String responseType
        ) {
            // Create a mock success response
            MetadataService.createMetadataResponse_element responseElement = new MetadataService.createMetadataResponse_element();
            MetadataService.SaveResult saveResult = new MetadataService.SaveResult();
            saveResult.success = true;
            saveResult.fullName = 'Contact.Test_Quick_Action';
            responseElement.result = new List<MetadataService.SaveResult>{ saveResult };
            response.put('response_x', responseElement);
        }
    }
}
