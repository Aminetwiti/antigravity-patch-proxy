import { registerApiBridge } from './api';

export function initPreload(): void {
  registerApiBridge();
}

export * from './api';
export * from './types';
