/**
 * Catalogue of Well-Known Provider Presets.
 * Offers 1-click configuration for standard LLM providers in the UI.
 */

export interface PresetModel {
  id: string;
  displayName: string;
  description?: string;
  enabled?: boolean;
}

export interface PresetProvider {
  id: string;
  name: string;
  category: 'General' | 'Local' | 'Experimental';
  provider: string;
  apiUrl: string;
  models: PresetModel[];
  description?: string;
  docsUrl?: string;
}

export const WELL_KNOWN_PRESETS: PresetProvider[] = [
  {
    id: 'openai-preset',
    name: 'OpenAI',
    category: 'General',
    provider: 'openai',
    apiUrl: 'https://api.openai.com/v1/chat/completions',
    description: 'OpenAI official API (GPT-4o, GPT-4o-mini, o1, o3-mini)',
    docsUrl: 'https://platform.openai.com',
    models: [
      { id: 'gpt-4o', displayName: 'GPT-4o', enabled: true },
      { id: 'gpt-4o-mini', displayName: 'GPT-4o Mini', enabled: true },
      { id: 'o1', displayName: 'o1 Reasoning', enabled: true },
      { id: 'o3-mini', displayName: 'o3 Mini', enabled: true },
    ],
  },
  {
    id: 'anthropic-preset',
    name: 'Anthropic',
    category: 'General',
    provider: 'anthropic',
    apiUrl: 'https://api.anthropic.com/v1/messages',
    description: 'Anthropic Claude 3.5 Sonnet, Claude 3.5 Haiku, Claude 3 Opus',
    docsUrl: 'https://console.anthropic.com',
    models: [
      { id: 'claude-3-5-sonnet-latest', displayName: 'Claude 3.5 Sonnet', enabled: true },
      { id: 'claude-3-5-haiku-latest', displayName: 'Claude 3.5 Haiku', enabled: true },
      { id: 'claude-3-opus-latest', displayName: 'Claude 3 Opus', enabled: true },
    ],
  },
  {
    id: 'openrouter-preset',
    name: 'OpenRouter',
    category: 'General',
    provider: 'openrouter',
    apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
    description: 'Unified gateway for 200+ models (Claude, GPT, DeepSeek, Llama)',
    docsUrl: 'https://openrouter.ai',
    models: [
      { id: 'anthropic/claude-3.5-sonnet', displayName: 'Claude 3.5 Sonnet (via OpenRouter)', enabled: true },
      { id: 'deepseek/deepseek-r1', displayName: 'DeepSeek R1 (via OpenRouter)', enabled: true },
      { id: 'meta-llama/llama-3.3-70b-instruct', displayName: 'Llama 3.3 70B (via OpenRouter)', enabled: true },
    ],
  },
  {
    id: 'deepseek-preset',
    name: 'DeepSeek',
    category: 'General',
    provider: 'deepseek',
    apiUrl: 'https://api.deepseek.com/v1/chat/completions',
    description: 'DeepSeek V3 and DeepSeek R1 reasoning model',
    docsUrl: 'https://platform.deepseek.com',
    models: [
      { id: 'deepseek-chat', displayName: 'DeepSeek V3', enabled: true },
      { id: 'deepseek-reasoner', displayName: 'DeepSeek R1', enabled: true },
    ],
  },
  {
    id: 'groq-preset',
    name: 'Groq (Ultra-Fast LPUs)',
    category: 'General',
    provider: 'groq',
    apiUrl: 'https://api.groq.com/openai/v1/chat/completions',
    description: 'Ultra-low latency inference for Llama 3.3, Mixtral, DeepSeek',
    docsUrl: 'https://console.groq.com',
    models: [
      { id: 'llama-3.3-70b-versatile', displayName: 'Llama 3.3 70B (Groq)', enabled: true },
      { id: 'mixtral-8x7b-32768', displayName: 'Mixtral 8x7B (Groq)', enabled: true },
      { id: 'deepseek-r1-distill-llama-70b', displayName: 'DeepSeek R1 Distill 70B (Groq)', enabled: true },
    ],
  },
  {
    id: 'google-ai-studio-preset',
    name: 'Google AI Studio',
    category: 'General',
    provider: 'google',
    apiUrl: 'https://generativelanguage.googleapis.com/v1beta/models/',
    description: 'Google Gemini 2.0 Flash, Gemini 1.5 Pro via AI Studio API key',
    docsUrl: 'https://aistudio.google.com',
    models: [
      { id: 'gemini-2.0-flash-exp', displayName: 'Gemini 2.0 Flash', enabled: true },
      { id: 'gemini-1.5-pro-latest', displayName: 'Gemini 1.5 Pro', enabled: true },
      { id: 'gemini-1.5-flash-latest', displayName: 'Gemini 1.5 Flash', enabled: true },
    ],
  },
  {
    id: 'ollama-preset',
    name: 'Ollama (Local)',
    category: 'Local',
    provider: 'ollama',
    apiUrl: 'http://localhost:11434/v1/chat/completions',
    description: 'Run open-source LLMs locally on your own GPU/CPU',
    docsUrl: 'https://ollama.com',
    models: [
      { id: 'llama3.3', displayName: 'Llama 3.3 (Local)', enabled: true },
      { id: 'deepseek-r1', displayName: 'DeepSeek R1 (Local)', enabled: true },
      { id: 'qwen2.5-coder', displayName: 'Qwen 2.5 Coder (Local)', enabled: true },
    ],
  },
  {
    id: 'xai-preset',
    name: 'xAI (Grok)',
    category: 'General',
    provider: 'xai',
    apiUrl: 'https://api.x.ai/v1/chat/completions',
    description: 'xAI Grok conversational models with reasoning support',
    docsUrl: 'https://docs.x.ai',
    models: [
      { id: 'grok-2', displayName: 'Grok 2', enabled: true },
      { id: 'grok-2-mini', displayName: 'Grok 2 Mini', enabled: true },
      { id: 'grok-beta', displayName: 'Grok Beta', enabled: true },
    ],
  },
  {
    id: 'moonshot-preset',
    name: 'Moonshot (Kimi)',
    category: 'General',
    provider: 'moonshot',
    apiUrl: 'https://api.moonshot.cn/v1/chat/completions',
    description: 'Moonshot Kimi K2 with 128K-256K context windows',
    docsUrl: 'https://platform.moonshot.cn',
    models: [
      { id: 'moonshot-v1-128k', displayName: 'Kimi 128K', enabled: true },
      { id: 'moonshot-v1-32k', displayName: 'Kimi 32K', enabled: true },
      { id: 'kimi-k2-0711-preview', displayName: 'Kimi K2 (Preview)', enabled: true },
    ],
  },
  {
    id: 'mistral-preset',
    name: 'Mistral',
    category: 'General',
    provider: 'mistral',
    apiUrl: 'https://api.mistral.ai/v1/chat/completions',
    description: 'Mistral Large 3, Codestral, Pixtral multimodal',
    docsUrl: 'https://docs.mistral.ai',
    models: [
      { id: 'mistral-large-latest', displayName: 'Mistral Large', enabled: true },
      { id: 'codestral-latest', displayName: 'Codestral', enabled: true },
      { id: 'pixtral-12b-2409', displayName: 'Pixtral 12B (Vision)', enabled: true },
    ],
  },
  {
    id: 'cohere-preset',
    name: 'Cohere',
    category: 'General',
    provider: 'cohere',
    apiUrl: 'https://api.cohere.com/v1/chat',
    description: 'Cohere Command R+ with grounded RAG support',
    docsUrl: 'https://docs.cohere.com',
    models: [
      { id: 'command-r-plus', displayName: 'Command R+', enabled: true },
      { id: 'command-r', displayName: 'Command R', enabled: true },
      { id: 'embed-english-v3.0', displayName: 'Embed English v3', enabled: true },
    ],
  },
  {
    id: 'groq-preset-extended',
    name: 'Groq (Extended)',
    category: 'General',
    provider: 'groq',
    apiUrl: 'https://api.groq.com/openai/v1/chat/completions',
    description: 'Groq Gemma 2, Llama 3.1, Whisper and additional models',
    docsUrl: 'https://console.groq.com',
    models: [
      { id: 'llama-3.1-70b-versatile', displayName: 'Llama 3.1 70B (Groq)', enabled: true },
      { id: 'llama-3.1-8b-instant', displayName: 'Llama 3.1 8B Instant', enabled: true },
      { id: 'gemma2-9b-it', displayName: 'Gemma 2 9B Instruct', enabled: true },
    ],
  },
  {
    id: 'openai-preset-extended',
    name: 'OpenAI (Extended)',
    category: 'General',
    provider: 'openai',
    apiUrl: 'https://api.openai.com/v1/chat/completions',
    description: 'OpenAI o3, o4-mini, GPT-4.1 family',
    docsUrl: 'https://platform.openai.com',
    models: [
      { id: 'o3', displayName: 'o3 Reasoning', enabled: true },
      { id: 'o4-mini', displayName: 'o4 Mini', enabled: true },
      { id: 'gpt-4.1', displayName: 'GPT-4.1', enabled: true },
      { id: 'gpt-4.1-mini', displayName: 'GPT-4.1 Mini', enabled: true },
    ],
  },
  {
    id: 'anthropic-preset-extended',
    name: 'Anthropic (Extended)',
    category: 'General',
    provider: 'anthropic',
    apiUrl: 'https://api.anthropic.com/v1/messages',
    description: 'Anthropic Claude 4 Sonnet / Opus / Haiku',
    docsUrl: 'https://console.anthropic.com',
    models: [
      { id: 'claude-sonnet-4-20250514', displayName: 'Claude Sonnet 4', enabled: true },
      { id: 'claude-opus-4-20250514', displayName: 'Claude Opus 4', enabled: true },
      { id: 'claude-3-7-sonnet-latest', displayName: 'Claude 3.7 Sonnet', enabled: true },
    ],
  },
  {
    id: 'openrouter-preset-extended',
    name: 'OpenRouter (Top Trending)',
    category: 'General',
    provider: 'openrouter',
    apiUrl: 'https://openrouter.ai/api/v1/chat/completions',
    description: 'Trending on OpenRouter: Qwen 3, GLM, Mistral, Kimi K2',
    docsUrl: 'https://openrouter.ai',
    models: [
      { id: 'qwen/qwen3-235b-a22b', displayName: 'Qwen 3 235B (OpenRouter)', enabled: true },
      { id: 'thudm/glm-4-32b', displayName: 'GLM-4 32B (OpenRouter)', enabled: true },
      { id: 'mistralai/mistral-large-3', displayName: 'Mistral Large 3 (OpenRouter)', enabled: true },
      { id: 'moonshotai/kimi-k2', displayName: 'Kimi K2 (OpenRouter)', enabled: true },
    ],
  },
  {
    id: 'deepseek-preset-extended',
    name: 'DeepSeek (Extended)',
    category: 'General',
    provider: 'deepseek',
    apiUrl: 'https://api.deepseek.com/v1/chat/completions',
    description: 'DeepSeek V3, R1, Coder Variant',
    docsUrl: 'https://platform.deepseek.com',
    models: [
      { id: 'deepseek-coder', displayName: 'DeepSeek Coder', enabled: true },
      { id: 'deepseek-v3-0324', displayName: 'DeepSeek V3 (2024-03)', enabled: true },
    ],
  },
];
