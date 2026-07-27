import log from 'electron-log';
import { loadCustomModels } from './modelLoader';
import { detectModelCapabilities } from './modelUtils';
import { generateModelPlaceholderId, toSlug } from './idGenerator';
import type { CustomModel } from './types';

export function getMappedCustomModels() {
  const customModels = loadCustomModels();
  const mappedCustom: Record<string, unknown> = {};
  customModels.forEach((m) => {
    const slug = toSlug(m);
    const pid = generateModelPlaceholderId(m);
    mappedCustom[slug] = {
      displayName: m.displayName,
      maxTokens: 1048576,
      maxOutputTokens: 4096,
      model: pid,
      planModel: pid,
      requestedModel: pid,
      apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
      modelProvider: 'MODEL_PROVIDER_GOOGLE',
    };
  });
  return mappedCustom;
}

export function getCustomModelsList() {
  const customModels = loadCustomModels();
  return customModels.map((m) => ({
    name: 'models/' + generateModelPlaceholderId(m),
    version: '1.0',
    displayName: m.displayName,
    description: m.description,
    inputTokenLimit: 1048576,
    outputTokenLimit: 4096,
    supportedGenerationMethods: ['generateContent', 'countTokens'],
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
  }));
}

export function mergeModels(target: unknown, customModels: CustomModel[]): unknown {
  if (Array.isArray(target)) {
    const mapped = customModels.map((m) => {
      const cap = detectModelCapabilities(m, true);
      const pid = generateModelPlaceholderId(m);
      return {
        name: 'models/' + pid,
        model: pid,
        planModel: pid,
        requestedModel: pid,
        version: '1.0',
        displayName: m.displayName,
        description: m.description,
        inputTokenLimit: cap.maxTokens,
        outputTokenLimit: cap.maxOutputTokens,
        supportedGenerationMethods: ['generateContent', 'countTokens'],
        temperature: cap.isThinking ? undefined : 0.7,
        topP: cap.isThinking ? undefined : 0.9,
        topK: cap.isThinking ? undefined : 40,
        reasoningEffort: m.reasoningEffort || undefined,
        thinkingBudget: m.thinkingBudget || undefined,
        mode: m.mode || undefined,
      };
    });
    return [...mapped, ...target];
  } else if (target && typeof target === 'object') {
    const result = { ...(target as Record<string, unknown>) };
    customModels.forEach((m) => {
      const slug = toSlug(m);
      const cap = detectModelCapabilities(m, true);
      const pid = generateModelPlaceholderId(m);
      const entry: Record<string, unknown> = {
        displayName: m.displayName,
        supportsImages: cap.supportsImages,
        supportsThinking: cap.isThinking,
        reasoningEffort: m.reasoningEffort || undefined,
        thinkingBudget: m.thinkingBudget || undefined,
        mode: m.mode || undefined,
        recommended: true,
        maxTokens: cap.maxTokens,
        maxOutputTokens: cap.maxOutputTokens,
        tokenizerType: 'LLAMA_WITH_SPECIAL',
        model: pid,
        planModel: pid,
        requestedModel: pid,
        apiProvider: 'API_PROVIDER_GOOGLE_GEMINI',
        modelProvider: 'MODEL_PROVIDER_GOOGLE',
      };
      if (cap.supportsImages) {
        entry.supportsVideo = false;
        entry.supportedMimeTypes = {
          'image/png': true,
          'image/jpeg': true,
          'image/webp': true,
          'image/gif': true,
          'image/heic': true,
          'image/heif': true,
          'text/plain': true,
          'text/markdown': true,
          'text/html': true,
          'text/css': true,
          'text/xml': true,
          'text/csv': true,
          'application/json': true,
          'application/pdf': true,
          'application/x-javascript': true,
          'application/x-typescript': true,
          'application/x-python-code': true,
          'application/x-ipynb+json': true,
        };
      } else {
        entry.supportsVideo = false;
        entry.supportedMimeTypes = {
          'text/plain': true,
          'text/markdown': true,
          'text/html': true,
          'text/css': true,
          'text/xml': true,
          'text/csv': true,
          'application/json': true,
          'application/pdf': true,
          'application/x-javascript': true,
          'application/x-typescript': true,
          'application/x-python-code': true,
          'application/x-ipynb+json': true,
        };
      }
      (result as Record<string, unknown>)[slug] = entry;
      m._slug = slug;
      log.info(
        `[Proxy] Custom model "${m.displayName}" => slug: ${slug} => model: ${generateModelPlaceholderId(m)} => thinking: ${cap.isThinking} => images: ${cap.supportsImages}`,
      );
    });
    return result;
  }
  return target;
}
