/**
 * Centralized model capability detection.
 * Replaces ~9 duplicate regex blocks across proxy.ts.
 */
export { REASONING_EFFORTS, THINKING_BUDGETS, adaptiveReasoningEffort, budgetReasoningEffort, coerceReasoningEffort, coerceThinkingBudget, isReasoningLikeModel, type ReasoningEffort as AdaptiveReasoningEffort, type ThinkingBudget as AdaptiveThinkingBudget, } from '../presets/reasoningEffort';
export interface CustomModelConfig {
    name: string;
    provider: string;
    externalModelName?: string;
    displayName?: string;
}
export interface ModelCapabilities {
    isThinking: boolean;
    isDeepSeek: boolean;
    isClaude: boolean;
    maxTokens: number;
    maxOutputTokens: number;
    supportsImages: boolean;
}
export interface ModelNameCapabilities {
    isClaudeThinkingModel: boolean;
    isThinkingModel: boolean;
}
export interface ModelUXBadges {
    supportsVision: boolean;
    supportsTools: boolean;
    supportsThinking: boolean;
    isLocal: boolean;
    contextWindowLabel: string;
}
export type ReasoningEffort = 'low' | 'medium' | 'high' | 'auto' | 'none';
export type ThinkingBudget = 'auto' | 'disabled' | 'enabled';
export type ModelMode = 'thinking' | 'reasoning' | 'non-thinking' | 'auto';
export interface ModelModeConfig {
    /** The model ID from /v1/models */
    id: string;
    /** Display name shown in the UI */
    name: string;
    /** Provider this model belongs to */
    provider: string;
    /**
     * Whether this model supports thinking/reasoning.
     * Determined by the API response, not by hardcoded regex.
     */
    supportsReasoning: boolean;
    /**
     * Whether this model supports images.
     */
    supportsImages: boolean;
    /**
     * The maximum number of tokens this model can output.
     */
    maxOutputTokens: number;
    /**
     * The maximum context window.
     */
    maxTokens: number;
    /**
     * The reasoning effort this model supports (if any).
     * e.g. o1 supports 'low', 'medium', 'high'
     * e.g. o3 supports 'low', 'medium', 'high'
     */
    supportedReasoningEfforts?: ReasoningEffort[];
    /**
     * The thinking budget this model supports (if any).
     */
    supportedThinkingBudgets?: ThinkingBudget[];
    /**
     * Default mode for this model.
     */
    defaultMode?: ModelMode;
}
/**
 * Detects model capabilities from a custom model config object.
 */
export declare function detectModelCapabilities(m: CustomModelConfig, includeDisplayName?: boolean): ModelCapabilities;
/**
 * Simplified detection for Gemini↔Anthropic translation (checks modelName string only).
 */
export declare function detectModelCapabilitiesByName(modelName: string): ModelNameCapabilities;
/**
 * Maps a model from the /v1/models endpoint to a ModelModeConfig,
 * detecting its reasoning/thinking capabilities dynamically.
 */
export declare function mapApiModelToModeConfig(apiModel: {
    id: string;
    name: string;
}, provider: string): ModelModeConfig;
/**
 * Computes UX badges for a model (Vision 🖼️, Tools 🛠️, Thinking 🧠, Local 💻, Context Window Label).
 */
export declare function detectModelUXBadges(m: CustomModelConfig): ModelUXBadges;
/**
 * Merge two `ModelModeConfig` records into a single one.
 *
 * Rules:
 *  - `id`/`name`/`provider` come from `base`.
 *  - `supportsReasoning` and `supportsImages` OR-combined.
 *  - `maxTokens` and `maxOutputTokens` take the larger value.
 *  - `supportedReasoningEfforts` / `supportedThinkingBudgets` are the union
 *    of both inputs (deduplicated, preserving order).
 *  - `defaultMode` is preferred when set, otherwise undefined.
 *
 * @example
 * mergeModelCapabilities(apiModel, presetModel)
 */
export declare function mergeModelCapabilities(base: ModelModeConfig, override: ModelModeConfig): ModelModeConfig;
/**
 * Returns the preferred mode for a model, falling back to a deterministic
 * default based on capabilities. Inspired by the UCP preset-templates
 * `resolvePresetTemplateConfigurationDefault` helper.
 */
export declare function resolveDefaultMode(model: ModelModeConfig): ModelMode;
/**
 * Detects whether a model config string is a "thinking" or "reasoning" one.
 * Convenience wrapper around `isReasoningLikeModel`.
 */
export declare function modelHasReasoningCapability(modelName: string): boolean;
//# sourceMappingURL=modelUtils.d.ts.map