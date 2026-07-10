/**
 * Centralized model capability detection.
 * Replaces ~9 duplicate regex blocks across proxy.js.
 */

// ─── Types ────────────────────────────────────────────────────────────────

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

// ─── Reasoning Modes (fetched dynamically from /v1/models) ───────────────────────
// These modes are NOT hardcoded — they are returned from the API endpoint
// and stored alongside the model for the proxy to use.

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
export function detectModelCapabilities(m: CustomModelConfig, includeDisplayName = true): ModelCapabilities {
  const nameLower = (m.name || '').toLowerCase();
  const extLower = (m.externalModelName || '').toLowerCase();
  const displayLower = includeDisplayName ? (m.displayName || '').toLowerCase() : '';

  const isThinking =
    m.provider === 'anthropic' ||
    m.provider === 'openai' ||
    m.provider === 'openrouter' ||
    THINKING_PATTERN.test(nameLower) ||
    THINKING_PATTERN.test(extLower) ||
    (includeDisplayName && THINKING_PATTERN.test(displayLower));

  const isDeepSeek =
    DEEPSEEK_PATTERN.test(nameLower) ||
    DEEPSEEK_PATTERN.test(extLower) ||
    (includeDisplayName && DEEPSEEK_PATTERN.test(displayLower));

  const isClaude = m.provider === 'anthropic' || CLAUDE_PATTERN.test(nameLower) || CLAUDE_PATTERN.test(extLower);

  const maxTokens = isClaude ? 200_000 : 1_048_576;
  const maxOutputTokens = isDeepSeek ? 32_768 : isThinking ? 32_768 : 16_384;

  // Image support: Claude, GPT-4o, Gemini always support images. DeepSeek, Ollama text models don't.
  const allNames = nameLower + ' ' + extLower + ' ' + displayLower;
  const supportsImages =
    m.provider === 'anthropic' ||
    m.provider === 'google' ||
    (m.provider === 'openai' && IMAGE_SUPPORT_PATTERN.test(allNames)) ||
    (m.provider === 'openrouter' && IMAGE_SUPPORT_PATTERN.test(allNames)) ||
    (IMAGE_SUPPORT_PATTERN.test(allNames) && !NO_IMAGE_PATTERN.test(allNames));

  return { isThinking, isDeepSeek, isClaude, maxTokens, maxOutputTokens, supportsImages };
}

/**
 * Simplified detection for Gemini↔Anthropic translation (checks modelName string only).
 */
export function detectModelCapabilitiesByName(modelName: string): ModelNameCapabilities {
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
export function mapApiModelToModeConfig(apiModel: { id: string; name: string }, provider: string): ModelModeConfig {
  const id = apiModel.id;
  const name = apiModel.name || id;
  const lower = id.toLowerCase();

  // Detect reasoning support from the model ID (not hardcoded)
  const supportsReasoning =
    THINKING_PATTERN.test(id) ||
    /o1|o3|r1|reasoning|thinking|reasoner/i.test(id);

  // Map reasoning efforts based on model type
  let supportedReasoningEfforts: ReasoningEffort[] | undefined;
  let supportedThinkingBudgets: ThinkingBudget[] | undefined;
  let defaultMode: ModelMode = 'auto';

  if (/o1|o3|r1/i.test(id)) {
    // OpenAI o1, o3, DeepSeek R1: support low/medium/high reasoning effort
    supportedReasoningEfforts = ['low', 'medium', 'high'];
    defaultMode = 'auto';
  } else if (/thinking|reasoning|reasoner/i.test(id)) {
    // General thinking models: support auto/enabled/disabled
    supportedThinkingBudgets = ['auto', 'enabled', 'disabled'];
    defaultMode = 'auto';
  } else if (/claude|opus|sonnet/i.test(id)) {
    // Claude: support auto/enabled/disabled
    supportedThinkingBudgets = ['auto', 'enabled', 'disabled'];
    defaultMode = 'auto';
  } else {
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
    maxOutputTokens: supportsReasoning ? 32_768 : 16_384,
    maxTokens: 1_048_576,
    supportedReasoningEfforts,
    supportedThinkingBudgets,
    defaultMode,
  };
}
