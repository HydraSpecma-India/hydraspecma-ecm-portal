/**
 * modal.js — Fluent-style accessible modal manager.
 * Usage:
 *   import { Modal } from '../components/modal.js';
 *   const myModal = new Modal('modal-element-id');
 *   myModal.open();
 */
export class Modal {
  constructor(elementId) {
    this.modal = document.getElementById(elementId);
    if (!this.modal) return;

    this.closeBtn = this.modal.querySelector('[data-modal-close]') || this.modal.querySelector('.btn-close-modal');
    this.focusableElements = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';
    
    this._handleKeyDown = this._handleKeyDown.bind(this);
    this._handleBackdropClick = this._handleBackdropClick.bind(this);
    this.close = this.close.bind(this);

    this.init();
  }

  init() {
    if (!this.modal) return;
    
    // Close button click listener
    if (this.closeBtn) {
      this.closeBtn.addEventListener('click', this.close);
    }

    // Backdrop click listener
    this.modal.addEventListener('click', this._handleBackdropClick);
  }

  open() {
    if (!this.modal) return;
    
    this.modal.classList.remove('hidden');
    document.body.classList.add('overflow-hidden'); // Disable background scrolling
    
    // Trap focus
    this.modal.addEventListener('keydown', this._handleKeyDown);
    
    // Set focus to the first interactive element inside the modal
    const focusable = this.modal.querySelectorAll(this.focusableElements);
    if (focusable.length > 0) {
      focusable[0].focus();
    }
  }

  close() {
    if (!this.modal) return;

    this.modal.classList.add('hidden');
    document.body.classList.remove('overflow-hidden');
    
    this.modal.removeEventListener('keydown', this._handleKeyDown);
  }

  _handleBackdropClick(e) {
    // If the click is directly on the modal container/backdrop (and not on its children)
    if (e.target === this.modal) {
      this.close();
    }
  }

  _handleKeyDown(e) {
    if (e.key === 'Escape') {
      this.close();
      return;
    }

    if (e.key === 'Tab') {
      const focusable = Array.from(this.modal.querySelectorAll(this.focusableElements));
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (e.shiftKey) { // Shift + Tab
        if (document.activeElement === first) {
          last.focus();
          e.preventDefault();
        }
      } else { // Tab
        if (document.activeElement === last) {
          first.focus();
          e.preventDefault();
        }
      }
    }
  }
}
