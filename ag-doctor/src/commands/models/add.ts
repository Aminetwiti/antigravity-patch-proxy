/**
 * `ag-doctor models add` — interactive model creation.
 */
import type { CommandContext, CustomModel } from '../../types';
import { addCustomModel, loadCustomModels, validateCustomModels } from '../../core/custom-models';
import { ask, askSecret, confirm } from '../../cli/prompts';
import { ok, error, info, header } from '../../cli/output';

const PROVIDERS = [
  'openai',
  'anthropic',
  'openrouter',
  'ollama',
  'google',
  'custom',
  'deepseek',
  'groq',
  'mistral',
  'cerebras',
  'kimi',
  'fireworks',
  'lmstudio',
  'llamacpp',
  'nvidia',
] as const;

const DEFAULT_URLS: Record<string, string> = {
  openai: 'https://api.openai.com/v1/chat/completions',
  anthropic: 'https://api.anthropic.com/v1/messages',
  openrouter: 'https://openrouter.ai/api/v1/chat/completions',
  ollama: 'http://localhost:11434/v1/chat/completions',
  google: 'https://generativelanguage.googleapis.com/v1beta/models/',
  deepseek: 'https://api.deepseek.com/anthropic',
  groq: 'https://api.groq.com/openai/v1',
  mistral: 'https://api.mistral.ai/v1',
  cerebras: 'https://api.cerebras.ai/v1',
  kimi: 'https://api.moonshot.ai/anthropic/v1',
  fireworks: 'https://api.fireworks.ai/inference/v1',
  lmstudio: 'http://localhost:1234/v1',
  llamacpp: 'http://localhost:8080/v1',
  nvidia: 'https://integrate.api.nvidia.com/v1',
};

export async function runModelsAdd(ctx: CommandContext): Promise<number> {
  if (!ctx.json) header('Add custom model');

  const provider = await ask(`Provider [${PROVIDERS.join('|')}]: `, 'custom');
  if (!PROVIDERS.includes(provider as (typeof PROVIDERS)[number])) {
    error(`Unknown provider: ${provider}`);
    return 2;
  }

  const name = await ask('Model ID (e.g. models/my-model): ', '');
  if (!name.startsWith('models/')) {
    error('Model ID must start with "models/"');
    return 2;
  }

  const externalModelName = await ask('External model name: ', name.replace(/^models\//, ''));
  const apiUrl = await ask(`API URL [${DEFAULT_URLS[provider] ?? ''}]: `, DEFAULT_URLS[provider] ?? '');
  const apiKey = await askSecret('API key (leave empty for local): ');
  const displayName = await ask('Display name (optional): ', name);

  const model: CustomModel = {
    name,
    displayName,
    provider,
    apiKey: apiKey || undefined,
    apiUrl,
    externalModelName,
  };

  const file = { models: [model] };
  const issues = validateCustomModels(file);
  if (issues.length > 0) {
    error('Validation failed:');
    for (const i of issues) console.log(`  - ${i.model}.${i.field}: ${i.message}`);
    return 2;
  }

  const existing = loadCustomModels();
  if (existing.models.some((m) => m.name === name)) {
    const overwrite = await confirm(`Model "${name}" already exists. Overwrite?`, false);
    if (!overwrite) {
      info('Aborted');
      return 1;
    }
  }

  addCustomModel(model);
  ok(`Saved ${name}`);
  info('Note: encryption happens automatically when the running app next reads this file.');
  return 0;
}
