@isTest
private class ServiceKnowledgeAssistantCtrlTest {

    // Mock AI Gateway to simulate both Models API and Prompt Builder without external callout failures
    private class MockAIGateway implements ServiceKnowledgeAssistantCtrl.IAIGateway {
        public Boolean shouldThrowError = false;

        public String invokeModelsApi(String modelName, String promptText) {
            if (shouldThrowError) {
                throw new ServiceKnowledgeAssistantCtrl.CustomAssistantException('Simulated Models API timeout');
            }
            return 'Mock Models API Grounded Response: Issue replacement REPL-OMEGA and $25 credit.';
        }

        public String invokePromptTemplate(String templateName, Id caseId, String agentQuery) {
            if (shouldThrowError) {
                throw new ServiceKnowledgeAssistantCtrl.CustomAssistantException('Simulated Prompt Builder error');
            }
            return 'Mock Prompt Builder Response: Verified via Data Cloud Retriever.';
        }
    }

    @testSetup
    static void setupTestData() {
        Case testCase = new Case(
            Subject = 'Customer getting Error E-504 on Omega-99 Router',
            Description = 'Customer reports red blinking light and error E-504.',
            Priority = 'High',
            Status = 'New'
        );
        insert testCase;
    }

    @isTest
    static void testProCodeModelsApiRagSuccess() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        ServiceKnowledgeAssistantCtrl.aiGateway = new MockAIGateway();

        Test.startTest();
        ServiceKnowledgeAssistantCtrl.AssistantResponse res = ServiceKnowledgeAssistantCtrl.askAssistant(
            testCase.Id,
            'What is the policy for Error E-504 on Omega-99?',
            '[{"role":"Agent","content":"Hi"}]',
            false // Pro-Code Models API Mode
        );
        Test.stopTest();

        Assert.isNotNull(res, 'Response should not be null');
        Assert.isTrue(res.answer.contains('REPL-OMEGA'), 'Should return grounded mock response');
        Assert.areEqual('Models API (Pro-Code SOSL RAG)', res.engineUsed, 'Engine label should match Pro-Code mode');
    }

    @isTest
    static void testNativePromptBuilderRagSuccess() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        ServiceKnowledgeAssistantCtrl.aiGateway = new MockAIGateway();

        Test.startTest();
        ServiceKnowledgeAssistantCtrl.AssistantResponse res = ServiceKnowledgeAssistantCtrl.askAssistant(
            testCase.Id,
            'How do I resolve E-504?',
            '[]',
            true // Native Prompt Builder Mode
        );
        Test.stopTest();

        Assert.isNotNull(res, 'Response should not be null');
        Assert.isTrue(res.answer.contains('Data Cloud Retriever'), 'Should return Prompt Builder response');
        Assert.areEqual('Prompt Builder (Data Cloud RAG)', res.engineUsed, 'Engine label should match Native mode');
    }

    @isTest
    static void testSoslQuerySanitization() {
        // Contains special characters (?, -, !, &) that normally crash raw SOSL
        String dirtyQuery = 'What is the policy for E-504? (Omega-99) & router! [urgent]';
        String sanitized = ServiceKnowledgeAssistantCtrl.sanitizeSoslQuery(dirtyQuery);

        Assert.isFalse(sanitized.contains('?'), 'Question marks must be stripped');
        Assert.isFalse(sanitized.contains('&'), 'Ampersands must be stripped');
        Assert.isTrue(sanitized.contains('OR'), 'Keywords should be joined by OR operator');
    }

    @isTest
    static void testValidationAndExceptionHandling() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];

        // 1. Null Case ID Check
        try {
            ServiceKnowledgeAssistantCtrl.askAssistant(null, 'Valid question', '[]', false);
            Assert.fail('Should have thrown exception for null Case Id');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }

        // 2. Blank Query Check
        try {
            ServiceKnowledgeAssistantCtrl.askAssistant(testCase.Id, '   ', '[]', false);
            Assert.fail('Should have thrown exception for blank query');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }

        // 3. Simulated AI Gateway Exception
        MockAIGateway failingMock = new MockAIGateway();
        failingMock.shouldThrowError = true;
        ServiceKnowledgeAssistantCtrl.aiGateway = failingMock;

        try {
            ServiceKnowledgeAssistantCtrl.askAssistant(testCase.Id, 'Test failure', '[]', false);
            Assert.fail('Should have caught and rethrown AI exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}