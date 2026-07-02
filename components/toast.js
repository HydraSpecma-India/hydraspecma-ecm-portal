/**
 * toast.js — Fluent-style stackable toast notification system.
 * Usage:
 *   import { toast } from '../components/toast.js';
 *   toast.success('Settings saved successfully!');
 *   toast.error('An error occurred. Please try again.');
 */
class ToastNotifier {
  constructor() {
    this.container = null;
  }

  _initContainer() {
    if (this.container) return;
    this.container = document.createElement('div');
    this.container.id = 'toast-container';
    this.container.className = 'fixed top-6 right-6 z-50 flex flex-col space-y-3 max-w-sm w-full pointer-events-none';
    document.body.appendChild(this.container);
  }

  show(message, type = 'info', duration = 4000) {
    this._initContainer();

    const toast = document.createElement('div');
    toast.className = 'glass flex items-center space-x-3 p-4 rounded-2xl shadow-xl pointer-events-auto transform translate-y-2 opacity-0 transition-all duration-300 border border-white/10';
    
    // Theme-specific colors & icons
    let colorClass = 'text-sky-400';
    let bgGradient = 'from-sky-500/10 to-sky-500/0';
    let icon = 'info';
    
    if (type === 'success') {
      colorClass = 'text-emerald-400';
      bgGradient = 'from-emerald-500/10 to-emerald-500/0';
      icon = 'check-circle-2';
    } else if (type === 'error') {
      colorClass = 'text-rose-400';
      bgGradient = 'from-rose-500/10 to-rose-500/0';
      icon = 'alert-circle';
    } else if (type === 'warning') {
      colorClass = 'text-amber-400';
      bgGradient = 'from-amber-500/10 to-amber-500/0';
      icon = 'alert-triangle';
    }

    toast.classList.add('bg-gradient-to-r', ...bgGradient.split(' '));

    toast.innerHTML = `
      <div class="h-8 w-8 rounded-xl bg-white/5 flex items-center justify-center shrink-0 ${colorClass}">
        <i data-lucide="${icon}" class="h-5 w-5"></i>
      </div>
      <div class="flex-grow text-xs font-medium text-slate-200">${message}</div>
      <button class="text-slate-500 hover:text-slate-300 transition duration-150 shrink-0">
        <i data-lucide="x" class="h-4 w-4"></i>
      </button>
    `;

    // Bind close click
    const closeBtn = toast.querySelector('button');
    closeBtn.addEventListener('click', () => this.dismiss(toast));

    this.container.appendChild(toast);
    
    if (globalThis.lucide) {
      globalThis.lucide.createIcons();
    }

    // Trigger slide-in
    requestAnimationFrame(() => {
      toast.classList.remove('translate-y-2', 'opacity-0');
    });

    // Auto dismiss
    setTimeout(() => {
      this.dismiss(toast);
    }, duration);
  }

  dismiss(toast) {
    if (!toast.parentNode) return;
    toast.classList.add('opacity-0', 'scale-95');
    toast.addEventListener('transitionend', () => {
      toast.remove();
      // Cleanup container if empty
      if (this.container && this.container.childElementCount === 0) {
        this.container.remove();
        this.container = null;
      }
    });
  }

  success(msg, dur) { this.show(msg, 'success', dur); }
  error(msg, dur) { this.show(msg, 'error', dur); }
  info(msg, dur) { this.show(msg, 'info', dur); }
  warn(msg, dur) { this.show(msg, 'warning', dur); }
}

export const toast = new ToastNotifier();
