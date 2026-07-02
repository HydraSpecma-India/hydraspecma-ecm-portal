/**
 * theme-toggle.js — Fluent-style theme toggle button.
 * Mounts in the header and triggers the themeService.
 */
import { themeService } from '../js/theme.js';

export function mountThemeToggle(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return;

  // Create toggle button
  const button = document.createElement('button');
  button.id = 'btn-theme-toggle';
  button.className = 'h-8 w-8 rounded-lg hover:bg-white/5 border border-transparent hover:border-white/10 flex items-center justify-center text-slate-400 hover:text-white transition duration-200';
  button.title = 'Toggle Color Theme';
  
  // Set initial icon
  updateIcon(button, themeService.get());

  // Click handler
  button.addEventListener('click', () => {
    const next = themeService.toggle();
    updateIcon(button, next);
  });

  container.appendChild(button);
}

function updateIcon(button, theme) {
  const isDark = theme === 'dark';
  button.innerHTML = isDark
    ? `<i data-lucide="sun" class="h-4 w-4 text-amber-400 transition-transform duration-300 rotate-0 hover:rotate-45"></i>`
    : `<i data-lucide="moon" class="h-4 w-4 text-slate-400 transition-transform duration-300 rotate-0 hover:-rotate-12"></i>`;
  
  if (globalThis.lucide) {
    globalThis.lucide.createIcons();
  }
}
