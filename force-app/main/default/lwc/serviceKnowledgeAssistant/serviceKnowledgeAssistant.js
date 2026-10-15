import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import askAssistant from '@salesforce/apex/ServiceKnowledgeAssistantCtrl.askAssistant';

export default class ServiceKnowledgeAssistant extends NavigationMixin(LightningElement) {
    @api recordId;
    @track messages = [];
    userInput = '';
    isLoading = false;
    usePromptBuilder = false; // Default to instant SOSL + Models API mode

    connectedCallback() {
        this.resetWelcomeMessage();
    }

    resetWelcomeMessage() {
        this.messages = [
            {
                id: Date.now(),
                sender: 'AI Assistant',
                text: 'Hello! I am grounded in this Case and your Salesforce Knowledge Base. Ask me about troubleshooting steps, warranties, or policies.',
                rowClass: 'slds-grid slds-grid_align-start slds-m-bottom_small',
                bubbleClass: 'chat-bubble ai-bubble slds-p-around_x-small',
                isAiReply: false,
                hasCitations: false,
                citations: []
            }
        ];
    }

    get isSendDisabled() {
        return this.isLoading || !this.userInput || !this.userInput.trim();
    }

    handleEngineToggle(event) {
        this.usePromptBuilder = event.target.checked;
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !this.isSendDisabled) {
            this.handleSend();
        }
    }

    handleClearChat() {
        this.resetWelcomeMessage();
    }

    async handleSend() {
        const queryText = this.userInput.trim();
        if (!queryText) return;

        this.appendMessage({
            sender: 'Agent',
            text: queryText,
            isAgent: true
        });

        this.userInput = '';
        this.isLoading = true;

        try {
            // Keep last 6 turns for context window efficiency
            const recentHistory = this.messages
                .slice(-6)
                .map(m => ({ role: m.sender, content: m.text }));

            const result = await askAssistant({
                caseId: this.recordId,
                agentQuery: queryText,
                chatHistoryJson: JSON.stringify(recentHistory),
                usePromptBuilder: this.usePromptBuilder
            });

            this.appendMessage({
                sender: 'AI Assistant',
                text: result.answer,
                isAgent: false,
                isAiReply: true,
                engineBadge: result.engineUsed,
                citations: result.citations || []
            });
        } catch (error) {
            const errMsg = error?.body?.message || error?.message || 'Unexpected error communicating with AI service.';
            this.appendMessage({
                sender: 'System Error',
                text: errMsg,
                isAgent: false,
                isError: true
            });
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }

    appendMessage({ sender, text, isAgent, isAiReply = false, isError = false, engineBadge = '', citations = [] }) {
        let bubbleStyle = 'chat-bubble ai-bubble slds-p-around_x-small';
        if (isAgent) {
            bubbleStyle = 'chat-bubble agent-bubble slds-p-around_x-small';
        } else if (isError) {
            bubbleStyle = 'chat-bubble error-bubble slds-p-around_x-small';
        }

        this.messages = [
            ...this.messages,
            {
                id: Date.now() + Math.random(),
                sender,
                text,
                rowClass: isAgent 
                    ? 'slds-grid slds-grid_align-end slds-m-bottom_small' 
                    : 'slds-grid slds-grid_align-start slds-m-bottom_small',
                bubbleClass: bubbleStyle,
                isAiReply,
                engineBadge,
                hasCitations: citations.length > 0,
                citations
            }
        ];
        this.scrollToBottom();
    }

    scrollToBottom() {
        // Defer scroll until DOM re-renders
        Promise.resolve().then(() => {
            const viewport = this.refs.chatViewport;
            if (viewport) {
                viewport.scrollTop = viewport.scrollHeight;
            }
        });
    }

    handleNavigateToArticle(event) {
        const articleId = event.currentTarget.dataset.id;
        if (!articleId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: articleId,
                objectApiName: 'Knowledge__kav',
                actionName: 'view'
            }
        });
    }

    handleCopyText(event) {
        const textToCopy = event.currentTarget.dataset.text;
        if (!textToCopy) return;
        navigator.clipboard.writeText(textToCopy).then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Copied',
                    message: 'AI response copied to clipboard.',
                    variant: 'success'
                })
            );
        });
    }
}