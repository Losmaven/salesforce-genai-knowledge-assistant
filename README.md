# Enterprise GenAI Knowledge Assistant for Salesforce Service Console

An enterprise-grade, dual-engine Retrieval-Augmented Generation (RAG) knowledge assistant built natively within the Salesforce Service Console. This application grounds Large Language Models (LLMs) in internal Salesforce Knowledge Articles and Case details while strictly enforcing enterprise security, data privacy, and zero-data retention policies.

---

## 🚀 Key Features & Architecture

- **Dual-Engine Flexibility:** Supports both **Native Declarative RAG** (Data Cloud Vector Search + Prompt Builder via `ConnectApi`) and **Pro-Code RAG** (Apex SOSL + Salesforce Models API) with a live toggle directly in the UI.
- **Production-Grade Apex Robustness:** Features a **Dependency Injection Gateway Pattern** (`@TestVisible`) allowing unit test coverage with zero external callout failures during deployment.
- **Advanced Security & Guardrails:** Enforces `USER_MODE` FLS/CRUD data access, a custom regex-based SOSL query sanitizer to prevent syntax crashes, and automated PII masking via the **Einstein Trust Layer**.
- **Interactive Lightning Web Component (LWC):** A ChatGPT-style chat interface featuring multi-turn conversation memory, clickable Knowledge article source citation pills, copy-to-clipboard utilities, and a clean SLDS design.

---

## 🛠️ Technology Stack

- **Salesforce Platform:** LWC (Lightning Web Components), Apex, Lightning Knowledge, Service Console
- **Generative AI & Data:** Salesforce Data Cloud, Agentforce Data Library, Einstein Prompt Builder, Salesforce Models API (OpenAI GPT-4o Mini), Einstein Trust Layer

---

## 📂 Project Structure

```text
salesforce-rag-assistant/
├── force-app/main/default/
│   ├── classes/
│   │   ├── ServiceKnowledgeAssistantCtrl.cls
│   │   └── ServiceKnowledgeAssistantCtrlTest.cls
│   └── lwc/
│       └── serviceKnowledgeAssistant/
│           ├── serviceKnowledgeAssistant.html
│           ├── serviceKnowledgeAssistant.js
│           ├── serviceKnowledgeAssistant.css
│           └── serviceKnowledgeAssistant.js-meta.xml
└── README.md

⚙️ Quick Deployment & Setup Guide
Clone the repository:

Bash
git clone [https://github.com/Losmaven/salesforce-genai-knowledge-assistant.git](https://github.com/Losmaven/salesforce-genai-knowledge-assistant.git)
cd salesforce-genai-knowledge-assistant
Authorize your Salesforce Developer Org using the SFDX CLI:

Bash
sf org login web --alias ####### --set-default
Deploy source code to your org:

Bash
sf project deploy start --source-dir force-app
Run the Apex unit test suite:

Bash
sf apex run test --class-names ServiceKnowledgeAssistantCtrlTest --synchronous --result-format human --code-coverage


🛡️ Engineering Best Practices Implemented
Dependency Injection: Un-mockable AI APIs (ConnectApi and aiplatform.ModelsAPI) are abstracted through interfaces, enabling robust unit testing.

SOSL Sanitization: Natural language queries containing special characters are sanitized to prevent Lucene query syntax exceptions.

Context Window Management: Chat history is strictly sliced and truncated to prevent token overflow.


---

<Elicitations message="What would you like to do next?">
  <Elicitation label="Build the Case Comment feature" query="Show me how to code the 'Post as Case Comment' write-back feature in Apex and LWC so I can add it to my GitHub repository."/>
  <Elicitation label="Prepare LinkedIn/Resume bullet points" query="Give me resume-ready phrasing and portfolio descriptions for this Salesforce GenAI project."/>
</Elicitations>