public with sharing class ServiceKnowledgeAssistantCtrl {

    // Constants for limits and defaults
    private static final Integer MAX_DESCRIPTION_LENGTH = 2000;
    private static final Integer MAX_QUERY_LENGTH = 500;
    private static final String DEFAULT_MODEL = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';
    private static final String DEFAULT_PROMPT_TEMPLATE = 'Service_Agent_Knowledge_Assistant';

    // Dependency Injection Gateway for 100% Unit Test Coverage
    public interface IAIGateway {
        String invokeModelsApi(String modelName, String promptText);
        String invokePromptTemplate(String templateName, Id caseId, String agentQuery);
    }

    // Live Production Gateway Implementation
    public class LiveAIGateway implements IAIGateway {
        public String invokeModelsApi(String modelName, String promptText) {
            aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
            request.modelName = modelName;

            aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
            body.prompt = promptText;
            request.body = body;

            aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
            aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request);
            return response.Code200.generation.generatedText;
        }

        public String invokePromptTemplate(String templateName, Id caseId, String agentQuery) {
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput = 
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.isPreview = false;

            Map<String, ConnectApi.WrappedValue> valueMap = new Map<String, ConnectApi.WrappedValue>();

            Map<String, String> caseRecordMap = new Map<String, String>{ 'id' => String.valueOf(caseId) };
            ConnectApi.WrappedValue caseWrapped = new ConnectApi.WrappedValue();
            caseWrapped.value = caseRecordMap;
            valueMap.put('Input:Current_Case', caseWrapped);

            ConnectApi.WrappedValue queryWrapped = new ConnectApi.WrappedValue();
            queryWrapped.value = agentQuery;
            valueMap.put('Input:Agent_Question', queryWrapped);

            promptInput.inputParams = valueMap;
            promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            promptInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response = 
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, promptInput);

            if (response != null && response.generations != null && !response.generations.isEmpty()) {
                return response.generations[0].text;
            }
            return 'No response generated from Prompt Template.';
        }
    }

    @TestVisible
    private static IAIGateway aiGateway = new LiveAIGateway();

    // Data Transfer Object (DTO) returned to LWC with full citation traceability
    public class AssistantResponse {
        @AuraEnabled public String answer { get; set; }
        @AuraEnabled public String engineUsed { get; set; }
        @AuraEnabled public List<KnowledgeCitation> citations { get; set; }

        public AssistantResponse(String answer, String engineUsed, List<KnowledgeCitation> citations) {
            this.answer = answer;
            this.engineUsed = engineUsed;
            this.citations = citations != null ? citations : new List<KnowledgeCitation>();
        }
    }

    public class KnowledgeCitation {
        @AuraEnabled public Id articleId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String urlName { get; set; }

        public KnowledgeCitation(Id articleId, String title, String urlName) {
            this.articleId = articleId;
            this.title = title;
            this.urlName = urlName;
        }
    }

    /**
     * Main Entry Point from LWC: Supports both Pro-Code RAG (Models API + SOSL) 
     * and Native Declarative RAG (Prompt Builder + Data Cloud)
     */
    @AuraEnabled
    public static AssistantResponse askAssistant(
        Id caseId, 
        String agentQuery, 
        String chatHistoryJson, 
        Boolean usePromptBuilder
    ) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required to ground the assistant.');
        }
        if (String.isBlank(agentQuery)) {
            throw new AuraHandledException('Please enter a valid question.');
        }

        String safeQuery = agentQuery.trim().abbreviate(MAX_QUERY_LENGTH);
        Boolean isNativeMode = (usePromptBuilder != null && usePromptBuilder);

        try {
            // Always fetch matching citations for UI transparency
            List<KnowledgeCitation> matchedCitations = new List<KnowledgeCitation>();
            String knowledgeContext = retrieveKnowledgeContext(safeQuery, matchedCitations);

            if (isNativeMode) {
                String answer = aiGateway.invokePromptTemplate(DEFAULT_PROMPT_TEMPLATE, caseId, safeQuery);
                return new AssistantResponse(answer, 'Prompt Builder (Data Cloud RAG)', matchedCitations);
            } else {
                Case currentCase = fetchSafeCaseContext(caseId);
                String hydratedPrompt = buildGroundedPrompt(currentCase, knowledgeContext, chatHistoryJson, safeQuery);
                String answer = aiGateway.invokeModelsApi(DEFAULT_MODEL, hydratedPrompt);
                return new AssistantResponse(answer, 'Models API (Pro-Code SOSL RAG)', matchedCitations);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Assistant Error: ' + e.getMessage());
        }
    }

    /**
     * Enforces User Mode FLS/Sharing on Case retrieval
     */
    private static Case fetchSafeCaseContext(Id caseId) {
        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cases.isEmpty()) {
            throw new CustomAssistantException('Case not found or inaccessible under current user permissions.');
        }
        return cases[0];
    }

    /**
     * Executes sanitized SOSL against Knowledge__kav (or graceful fallback if Knowledge is empty)
     */
    @TestVisible
    private static String retrieveKnowledgeContext(String rawQuery, List<KnowledgeCitation> citationsOut) {
        String cleanSoslTerm = sanitizeSoslQuery(rawQuery);
        if (String.isBlank(cleanSoslTerm) || cleanSoslTerm.length() < 2) {
            return 'No valid search keywords extracted.';
        }

        String knowledgeContext = '';
        try {
            // Dynamic SOSL prevents compile-time failure if Knowledge__kav fields vary across orgs
            String sosl = 'FIND \'' + String.escapeSingleQuotes(cleanSoslTerm) + '\' IN ALL FIELDS ' +
                          'RETURNING Knowledge__kav(Id, Title, Summary, UrlName WHERE PublishStatus = \'Online\' LIMIT 3)';
            
            List<List<SObject>> searchResults = Search.query(sosl, AccessLevel.USER_MODE);
            if (!searchResults.isEmpty() && !searchResults[0].isEmpty()) {
                Integer index = 1;
                for (SObject record : searchResults[0]) {
                    Id artId = (Id)record.get('Id');
                    String title = (String)record.get('Title');
                    String summary = (String)record.get('Summary');
                    String urlName = (String)record.get('UrlName');

                    citationsOut.add(new KnowledgeCitation(artId, title, urlName));
                    knowledgeContext += '[Article ' + index + '] Title: ' + title + '\n' +
                                        'Summary: ' + (String.isNotBlank(summary) ? summary : 'N/A') + '\n\n';
                    index++;
                }
            }
        } catch (Exception ex) {
            // Log and gracefully fallback if SOSL syntax or Knowledge object isn't populated
            knowledgeContext = 'No matching Knowledge Articles found.';
        }

        return String.isNotBlank(knowledgeContext) 
            ? knowledgeContext 
            : 'No matching Knowledge Articles found in the database.';
    }

    /**
     * Strips SOSL reserved characters (? * & | ! { } [ ] ( ) ^ ~ : \ " ' + -) 
     * and joins keywords with OR so natural language questions match relevant articles
     */
    @TestVisible
    public static String sanitizeSoslQuery(String input) {
        if (String.isBlank(input)) return '';
        // Replace all non-alphanumeric characters with spaces
        String alphaNumericOnly = input.replaceAll('[^a-zA-Z0-9\\s]', ' ');
        List<String> rawWords = alphaNumericOnly.split('\\s+');
        
        Set<String> stopWords = new Set<String>{
            'what', 'is', 'the', 'how', 'do', 'i', 'for', 'a', 'an', 'in', 'on', 'of', 'to', 'and', 'or', 'with'
        };
        
        List<String> validKeywords = new List<String>();
        for (String w : rawWords) {
            String lower = w.toLowerCase().trim();
            if (lower.length() >= 2 && !stopWords.contains(lower)) {
                validKeywords.add(w.trim());
            }
        }
        if (validKeywords.isEmpty()) {
            return alphaNumericOnly.trim();
        }
        return String.join(validKeywords, ' OR ');
    }

    /**
     * Constructs the augmented prompt with strict anti-hallucination guardrails
     */
    private static String buildGroundedPrompt(
        Case currentCase, 
        String knowledgeContext, 
        String chatHistoryJson, 
        String agentQuery
    ) {
        String safeDesc = String.isNotBlank(currentCase.Description) 
            ? currentCase.Description.abbreviate(MAX_DESCRIPTION_LENGTH) 
            : 'None provided';
        String safeHistory = String.isNotBlank(chatHistoryJson) 
            ? chatHistoryJson.abbreviate(3000) 
            : '[]';

        return 'You are a Salesforce Service Agent AI Assistant. Your job is to help the support agent resolve the current Case accurately.\n\n'
            + '=== STRICT GROUNDING RULES ===\n'
            + '1. Answer the agent question using ONLY the Knowledge Base Context and Case Details below.\n'
            + '2. Always cite the exact [Article Title] at the end of your response when using knowledge context.\n'
            + '3. If the answer cannot be verified from the provided Knowledge Base Context, respond strictly with: "I could not find a verified Knowledge Article for this policy or issue."\n\n'
            + '=== CURRENT CASE CONTEXT ===\n'
            + 'Case Number: ' + currentCase.CaseNumber + '\n'
            + 'Subject: ' + (String.isNotBlank(currentCase.Subject) ? currentCase.Subject : 'N/A') + '\n'
            + 'Priority: ' + (String.isNotBlank(currentCase.Priority) ? currentCase.Priority : 'N/A') + '\n'
            + 'Description: ' + safeDesc + '\n\n'
            + '=== KNOWLEDGE BASE CONTEXT (RETRIEVED CHUNKS) ===\n'
            + knowledgeContext + '\n\n'
            + '=== CONVERSATION HISTORY ===\n'
            + safeHistory + '\n\n'
            + '=== AGENT QUESTION ===\n'
            + agentQuery;
    }

    public class CustomAssistantException extends Exception {}
}