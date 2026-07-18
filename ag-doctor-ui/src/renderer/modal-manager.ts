/**
 * ModalManager — promise-based modal abstraction for the ag-doctor renderer.
 *
 * Inspired by `vscode-unify`'s `pickQuickItem` / `stack-router` pattern:
 * the caller `await`s a result without owning the DOM event wiring. The
 * manager owns a single reusable backdrop (#modalBackdrop) and attaches
 * listeners per-open, cleaning them up on close (no leaked handlers).
 *
 * Authored script-style (no top-level import/export) so it compiles into the
 * same `app.js` bundle as `app.ts` and shares the renderer global scope with
 * `features.ts` (which is an IIFE). `tsc` emits this as a script.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface ConfirmOptions {
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
  confirmDisabled?: boolean;
  /** Optional hook to wire custom body content after the manager mounts it. */
  onMount?: (handle: ConfirmModalHandle) => void;
}

interface ConfirmModalHandle {
  backdrop: HTMLDivElement;
  titleEl: HTMLHeadingElement;
  bodyEl: HTMLDivElement;
  confirmBtn: HTMLButtonElement;
  cancelBtn: HTMLButtonElement;
  closeBtn: HTMLButtonElement;
  setConfirmEnabled(enabled: boolean): void;
  setConfirmLabel(label: string): void;
}

// ─────────────────────────────────────────────────────────────────────────────
// ModalManager
// ─────────────────────────────────────────────────────────────────────────────

class ModalManager {
  private backdrop: HTMLDivElement;
  private titleEl: HTMLHeadingElement;
  private bodyEl: HTMLDivElement;
  private confirmBtn: HTMLButtonElement;
  private cancelBtn: HTMLButtonElement;
  private closeBtn: HTMLButtonElement;

  /** Non-null while a modal is open. Prevents overlapping modals. */
  private active: {
    cleanup: () => void;
    resolve: (value: unknown) => void;
  } | null = null;

  constructor() {
    this.backdrop = document.getElementById('modalBackdrop') as HTMLDivElement;
    this.titleEl = document.getElementById('modalTitle') as HTMLHeadingElement;
    this.bodyEl = document.getElementById('modalBody') as HTMLDivElement;
    this.confirmBtn = document.getElementById('modalConfirm') as HTMLButtonElement;
    this.cancelBtn = document.getElementById('modalCancel') as HTMLButtonElement;
    this.closeBtn = document.getElementById('modalClose') as HTMLButtonElement;
    // Safety: ensure hidden on construction.
    this.backdrop.hidden = true;
  }

  /**
   * Open the shared backdrop, run `setup` to wire the body, and resolve with
   * whatever `setup` returns once the modal is closed. Only one modal may be
   * open at a time — a second `open()` rejects immediately.
   */
  open<T>(setup: (handle: ConfirmModalHandle) => T | Promise<T>): Promise<T> {
    if (this.active) {
      return Promise.reject(
        new Error('ModalManager: a modal is already open — close it before opening another.'),
      );
    }

    const handle: ConfirmModalHandle = {
      backdrop: this.backdrop,
      titleEl: this.titleEl,
      bodyEl: this.bodyEl,
      confirmBtn: this.confirmBtn,
      cancelBtn: this.cancelBtn,
      closeBtn: this.closeBtn,
      setConfirmEnabled: (enabled: boolean) => {
        this.confirmBtn.disabled = !enabled;
      },
      setConfirmLabel: (label: string) => {
        this.confirmBtn.textContent = label;
      },
    };

    return new Promise<T>((resolve, reject) => {
      let settled = false;
      let result: T;

      const finish = (value: T) => {
        if (settled) return;
        settled = true;
        result = value;
        cleanup();
        resolve(result);
      };

      const onConfirm = () => {
        if (this.confirmBtn.disabled) return;
        finish(result);
      };
      const onCancel = () => finish(result);
      const onBackdrop = (e: MouseEvent) => {
        if (e.target === this.backdrop) finish(result);
      };
      const onKey = (e: KeyboardEvent) => {
        if (e.key === 'Escape') {
          e.preventDefault();
          finish(result);
        }
      };

      const cleanup = () => {
        this.backdrop.hidden = true;
        this.confirmBtn.disabled = false;
        this.confirmBtn.removeEventListener('click', onConfirm);
        this.cancelBtn.removeEventListener('click', onCancel);
        this.closeBtn.removeEventListener('click', onCancel);
        this.backdrop.removeEventListener('click', onBackdrop);
        document.removeEventListener('keydown', onKey);
        this.active = null;
      };

      this.active = { cleanup, resolve: (v) => finish(v as T) };

      // Wire listeners before showing (avoid race where user clicks instantly).
      this.confirmBtn.addEventListener('click', onConfirm);
      this.cancelBtn.addEventListener('click', onCancel);
      this.closeBtn.addEventListener('click', onCancel);
      this.backdrop.addEventListener('click', onBackdrop);
      document.addEventListener('keydown', onKey);

      this.backdrop.hidden = false;

      // Run setup (may be async). If it throws, reject and close.
      try {
        const setupResult = setup(handle);
        if (setupResult instanceof Promise) {
          setupResult.then(
            (r) => { result = r; },
            (err) => { cleanup(); reject(err); },
          );
        } else {
          result = setupResult;
        }
      } catch (err) {
        cleanup();
        reject(err as Error);
      }
    });
  }

  /**
   * Convenience wrapper: render a title + HTML body and resolve `true` on
   * confirm, `false` on cancel/backdrop/Escape. Mirrors the old `confirmModal`.
   */
  confirm(title: string, bodyHtml: string, opts?: ConfirmOptions): Promise<boolean> {
    return this.open<boolean>((handle) => {
      handle.titleEl.textContent = title;
      handle.bodyEl.innerHTML = bodyHtml;
      handle.confirmBtn.textContent = opts?.confirmLabel ?? 'Confirm';
      handle.cancelBtn.textContent = opts?.cancelLabel ?? 'Cancel';
      handle.confirmBtn.className = `btn ${opts?.danger ? 'btn-danger' : opts?.confirmDisabled ? 'btn-muted' : 'btn-primary'}`;
      handle.setConfirmEnabled(!opts?.confirmDisabled);
      opts?.onMount?.(handle);
      return false; // default result; flipped to true on confirm
    });
  }

  /** Force-close the current modal (if any) without resolving a value. */
  closeCurrent(): void {
    this.active?.cleanup();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Overlay registry — for non-blocking custom modals (e.g. the Add-Model
  // modal) that own their own DOM but should share the SAME single Escape /
  // backdrop lifecycle as the confirm modals. Registering an overlay moves its
  // key/backdrop listeners into the manager so we never leak duplicate
  // document `keydown` handlers (the previous AddModelModalController added and
  // removed its own listener per open).
  // ───────────────────────────────────────────────────────────────────────────

  private overlays = new Map<string, {
    backdrop: HTMLDivElement;
    onOpen?: () => void;
    onClose?: () => void;
  }>();

  private activeOverlayKey: string | null = null;

  registerOverlay(opts: {
    id: string;
    backdrop: HTMLDivElement;
    onOpen?: () => void;
    onClose?: () => void;
  }): void {
    this.overlays.set(opts.id, opts);
    // Ensure hidden until explicitly opened.
    opts.backdrop.hidden = true;
    opts.backdrop.style.display = 'none';
  }

  openOverlay(id: string): void {
    const overlay = this.overlays.get(id);
    if (!overlay) return;
    if (this.activeOverlayKey) return; // only one overlay at a time
    this.activeOverlayKey = id;
    overlay.backdrop.hidden = false;
    overlay.backdrop.style.display = 'grid';
    overlay.backdrop.addEventListener('click', this.onOverlayBackdrop);
    document.addEventListener('keydown', this.onOverlayKey);
    overlay.onOpen?.();
  }

  closeOverlay(id: string): void {
    const overlay = this.overlays.get(id);
    if (!overlay || this.activeOverlayKey !== id) return;
    overlay.backdrop.hidden = true;
    overlay.backdrop.style.display = 'none';
    overlay.backdrop.removeEventListener('click', this.onOverlayBackdrop);
    document.removeEventListener('keydown', this.onOverlayKey);
    this.activeOverlayKey = null;
    overlay.onClose?.();
  }

  private onOverlayBackdrop = (e: MouseEvent): void => {
    const key = this.activeOverlayKey;
    if (!key) return;
    const overlay = this.overlays.get(key);
    if (overlay && e.target === overlay.backdrop) this.closeOverlay(key);
  };

  private onOverlayKey = (e: KeyboardEvent): void => {
    if (e.key === 'Escape' && this.activeOverlayKey) {
      e.preventDefault();
      this.closeOverlay(this.activeOverlayKey);
    }
  };
}

