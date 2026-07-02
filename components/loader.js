/**
 * loader.js — Fluent-style skeleton loaders for dashboards and cards.
 * Usage:
 *   import { loader } from '../components/loader.js';
 *   container.innerHTML = loader.table(5);
 */
export const loader = {
  /** Renders a list of card skeleton components */
  card(count = 1) {
    return Array(count).fill(0).map(() => `
      <div class="glass rounded-3xl p-8 flex flex-col space-y-4 animate-pulse">
        <div class="h-4 bg-white/10 rounded-lg w-1/3"></div>
        <div class="h-8 bg-white/10 rounded-lg w-2/3"></div>
        <div class="space-y-2 mt-4">
          <div class="h-3 bg-white/10 rounded-lg w-full"></div>
          <div class="h-3 bg-white/10 rounded-lg w-5/6"></div>
          <div class="h-3 bg-white/10 rounded-lg w-4/6"></div>
        </div>
      </div>
    `).join('');
  },

  /** Renders a skeleton table body with specified rows & columns */
  table(rowsCount = 5, colsCount = 4) {
    const headerCols = Array(colsCount).fill(0).map(() => `
      <div class="h-3 bg-white/15 rounded-lg w-2/3"></div>
    `).join('</div><div class="p-4">');

    const rowCols = Array(colsCount).fill(0).map(() => `
      <div class="h-3.5 bg-white/10 rounded-lg w-3/4"></div>
    `).join('</div><div class="p-4 border-t border-white/5">');

    return `
      <div class="glass rounded-[32px] overflow-hidden border border-white/5 animate-pulse w-full">
        <!-- Table Header -->
        <div class="grid grid-cols-${colsCount} bg-white/5 p-4 font-semibold text-xs border-b border-white/5">
          <div class="p-4">${headerCols}</div>
        </div>
        <!-- Table Body -->
        <div class="divide-y divide-white/5">
          ${Array(rowsCount).fill(0).map(() => `
            <div class="grid grid-cols-${colsCount} p-4 items-center">
              <div class="p-4 border-t border-white/5">${rowCols}</div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  },

  /** Renders a list skeleton component */
  list(count = 3) {
    return Array(count).fill(0).map(() => `
      <div class="flex items-center space-x-4 p-4 border-b border-white/5 animate-pulse">
        <div class="h-10 w-10 rounded-xl bg-white/10"></div>
        <div class="flex-grow space-y-2">
          <div class="h-3.5 bg-white/10 rounded-lg w-1/3"></div>
          <div class="h-3 bg-white/5 rounded-lg w-1/2"></div>
        </div>
        <div class="h-6 bg-white/10 rounded-lg w-16"></div>
      </div>
    `).join('');
  }
};
