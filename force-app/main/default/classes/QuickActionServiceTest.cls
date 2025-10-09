/**
 * @description Test class for the QuickActionService.
 * This class verifies that the service can correctly call the Metadata API
 * to create a Quick Action AND add it to a page layout.
 */
@isTest
private class QuickActionServiceTest {

    @isTest
    static void testCreateSimpleUpdateAction_Success() {
        // ARRANGE
        // Set the mock to handle the full sequence of Metadata API calls
        Test.setMock(WebServiceMock.class, new FullMetadataServiceMock());

        // ACT
        Test.startTest();
        QuickActionService.QuickActionResult result = QuickActionService.createSimpleUpdateAction('Contact', 'Test Quick Action');
        Test.stopTest();

        // ASSERT
        System.assertEquals(true, result.isSuccess, 'The isSuccess flag should be true.');
        System.assert(result.message.contains('added to the page layout successfully'), 'The success message should be returned.');
        System.assertEquals('Contact.Test_Quick_Action', result.actionName, 'The full action name should be returned.');
    }

    /**
     * @description Mock class to simulate successful responses for all Metadata API calls.
     */
    private class FullMetadataServiceMock implements WebServiceMock {
        public void doInvoke(
            Object stub, Object request, Map<String, Object> response,
            String endpoint, String soapAction, String requestName,
            String responseNS, String responseName, String responseType
        ) {
            // Mock for the createMetadata call
            if (request instanceof MetadataService.createMetadata_element) {
                MetadataService.createMetadataResponse_element resElement = new MetadataService.createMetadataResponse_element();
                MetadataService.SaveResult saveResult = new MetadataService.SaveResult();
                saveResult.success = true;
                saveResult.fullName = 'Contact.Test_Quick_Action';
                resElement.result = new List<MetadataService.SaveResult>{ saveResult };
                response.put('response_x', resElement);
            
            // Mock for the readMetadata call to get the Layout
            } else if (request instanceof MetadataService.readMetadata_element) {
                MetadataService.readLayoutResponse_element resElement = new MetadataService.readLayoutResponse_element();
                MetadataService.ReadLayoutResult readResult = new MetadataService.ReadLayoutResult();
                MetadataService.Layout layout = new MetadataService.Layout();
                layout.fullName = 'Contact-Contact Layout';
                readResult.records = new List<MetadataService.Layout>{ layout };
                resElement.result = readResult;
                response.put('response_x', resElement);

            // Mock for the updateMetadata call to save the Layout
            } else if (request instanceof MetadataService.updateMetadata_element) {
                MetadataService.updateMetadataResponse_element resElement = new MetadataService.updateMetadataResponse_element();
                MetadataService.SaveResult saveResult = new MetadataService.SaveResult();
                saveResult.success = true;
                saveResult.fullName = 'Contact-Contact Layout';
                resElement.result = new List<MetadataService.SaveResult>{ saveResult };
                response.put('response_x', resElement);
            }
        }
    }
}