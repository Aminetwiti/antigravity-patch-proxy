"use strict";
/**
 * Centralized model capability detection.
 * Replaces ~9 duplicate regex blocks across proxy.ts.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.detectModelCapabilities = detectModelCapabilities;
exports.detectModelCapabilitiesByName = detectModelCapabilitiesByName;
exports.mapApiModelToModeConfig = mapApiModelToModeConfig;
exports.detectModelUXBadges = detectModelUXBadges;
// ─── Detection ────────────────────────────────────────────────────────────
const THINKING_PATTERN = /thinking|reasoning|reasoner|o1|o3|r1|opus-4|sonnet-4|claude-4|3-7|4-7|3\.7|4\.7/i;
const DEEPSEEK_PATTERN = /deepseek/i;
const CLAUDE_PATTERN = /claude|opus|sonnet/i;
const CLAUDE_THINKING_PATTERN = /opus-4|sonnet-4|claude-4|claude-3-5|claude-3-7/i;
const THINKING_MODEL_PATTERN = /opus-4|sonnet-4|claude-4/i;
const IMAGE_SUPPORT_PATTERN = /gpt-4o|gpt-4-turbo|claude|gemini|vision|llava|qwenvl|pixtral|yi-vision|cogvlm|kimi|moonshot/i;
const NO_IMAGE_PATTERN = /deepseek(?!.*vision)|llama(?!.*vision)|mixtral(?!.*vision)|mistral(?!.*pixtral)|codestral|qwen(?!.*vl)/i;
/**
 * Detects model capabilities from a custom model config object.
 */
function detectModelCapabilities(m, includeDisplayName = true) {
    const nameLower = (m.name || '').toLowerCase();
    const extLower = (m.externalModelName || '').toLowerCase();
    const displayLower = includeDisplayName ? (m.displayName || '').toLowerCase() : '';
    const isThinking = m.provider === 'anthropic' ||
        m.provider === 'openai' ||
        m.provider === 'openrouter' ||
        THINKING_PATTERN.test(nameLower) ||
        THINKING_PATTERN.test(extLower) ||
        (includeDisplayName && THINKING_PATTERN.test(displayLower));
    const isDeepSeek = DEEPSEEK_PATTERN.test(nameLower) ||
        DEEPSEEK_PATTERN.test(extLower) ||
        (includeDisplayName && DEEPSEEK_PATTERN.test(displayLower));
    const isClaude = m.provider === 'anthropic' || CLAUDE_PATTERN.test(nameLower) || CLAUDE_PATTERN.test(extLower);
    const maxTokens = isClaude ? 200000 : 1048576;
    const maxOutputTokens = isDeepSeek ? 32768 : isThinking ? 32768 : 16384;
    // Image support: Claude, GPT-4o, Gemini always support images. DeepSeek, Ollama text models don't.
    const allNames = nameLower + ' ' + extLower + ' ' + displayLower;
    const supportsImages = m.provider === 'anthropic' ||
        m.provider === 'google' ||
        (m.provider === 'openai' && IMAGE_SUPPORT_PATTERN.test(allNames)) ||
        (m.provider === 'openrouter' && IMAGE_SUPPORT_PATTERN.test(allNames)) ||
        (IMAGE_SUPPORT_PATTERN.test(allNames) && !NO_IMAGE_PATTERN.test(allNames));
    return { isThinking, isDeepSeek, isClaude, maxTokens, maxOutputTokens, supportsImages };
}
/**
 * Simplified detection for Gemini↔Anthropic translation (checks modelName string only).
 */
function detectModelCapabilitiesByName(modelName) {
    const lower = (modelName || '').toLowerCase();
    return {
        isClaudeThinkingModel: CLAUDE_THINKING_PATTERN.test(lower),
        isThinkingModel: THINKING_MODEL_PATTERN.test(lower),
    };
}
/**
 * Maps a model from the /v1/models endpoint to a ModelModeConfig,
 * detecting its reasoning/thinking capabilities dynamically.
 */
function mapApiModelToModeConfig(apiModel, provider) {
    const id = apiModel.id;
    const name = apiModel.name || id;
    const lower = id.toLowerCase();
    // Detect reasoning support from the model ID (not hardcoded)
    const supportsReasoning = THINKING_PATTERN.test(id) ||
        /o1|o3|r1|reasoning|thinking|reasoner/i.test(id);
    // Map reasoning efforts based on model type
    let supportedReasoningEfforts;
    let supportedThinkingBudgets;
    let defaultMode = 'auto';
    if (/o1|o3|r1/i.test(id)) {
        // OpenAI o1, o3, DeepSeek R1: support low/medium/high reasoning effort
        supportedReasoningEfforts = ['low', 'medium', 'high'];
        defaultMode = 'auto';
    }
    else if (/thinking|reasoning|reasoner/i.test(id)) {
        // General thinking models: support auto/enabled/disabled
        supportedThinkingBudgets = ['auto', 'enabled', 'disabled'];
        defaultMode = 'auto';
    }
    else if (/claude|opus|sonnet/i.test(id)) {
        // Claude: support auto/enabled/disabled
        supportedThinkingBudgets = ['auto', 'enabled', 'disabled'];
        defaultMode = 'auto';
    }
    else {
        // Non-thinking models: no reasoning effort, default to 'none'
        supportedReasoningEfforts = undefined;
        supportedThinkingBudgets = undefined;
        defaultMode = 'non-thinking';
    }
    return {
        id,
        name,
        provider,
        supportsReasoning,
        supportsImages: IMAGE_SUPPORT_PATTERN.test(id) && !NO_IMAGE_PATTERN.test(id),
        maxOutputTokens: supportsReasoning ? 32768 : 16384,
        maxTokens: 1048576,
        supportedReasoningEfforts,
        supportedThinkingBudgets,
        defaultMode,
    };
}
/**
 * Computes UX badges for a model (Vision 🖼️, Tools 🛠️, Thinking 🧠, Local 💻, Context Window Label).
 */
function detectModelUXBadges(m) {
    const caps = detectModelCapabilities(m);
    const isLocal = m.provider === 'ollama' || m.provider === 'lmstudio' || m.provider === 'llamacpp';
    const supportsTools = true; // All proxy translators map tool calls
    const contextWindowLabel = caps.maxTokens >= 1000000 ? '1M' : `${Math.round(caps.maxTokens / 1000)}k`;
    return {
        supportsVision: caps.supportsImages,
        supportsTools,
        supportsThinking: caps.isThinking,
        isLocal,
        contextWindowLabel,
    };
}
//# sourceMappingURL=modelUtils.js.map