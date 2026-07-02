import { getSupabase } from '../config/supabase.config.js';
import { authService } from '../services/auth/authService.js';
import { toast } from '../components/toast.js';

class NotificationsManager {
  constructor() {
    this.userId = null;
    this.unreadCount = 0;
    this.notifications = [];
    this.preferences = [];
    this.init();
  }

  async init() {
    try {
      const session = await authService.getSession();
      if (!session) return; // not logged in

      const profileData = await authService.me();
      this.userId = profileData?.profile?.id;

      if (!this.userId) return;

      // 1. Mount Bell Icon and Dropdown in Header
      this.mountBell();

      // 2. Fetch Notifications & Preferences
      await Promise.all([
        this.fetchNotifications(),
        this.fetchPreferences()
      ]);

      // 3. Bind UI action events
      this.bindEvents();

    } catch (err) {
      console.error('Failed to initialize notifications manager:', err);
    }
  }

  mountBell() {
    const userBadge = document.getElementById('user-badge');
    if (!userBadge) return;

    // Create bell wrapper div
    const bellWrapper = document.createElement('div');
    bellWrapper.className = 'relative flex items-center mr-4 border-r border-white/10 dark:border-white/10 light:border-black/10 pr-6';
    bellWrapper.innerHTML = `
      <button id="btn-notification-bell" class="relative h-8 w-8 rounded-lg hover:bg-white/5 dark:hover:bg-white/5 light:hover:bg-black/5 border border-transparent hover:border-white/10 flex items-center justify-center text-slate-400 hover:text-white transition duration-200" title="Notifications">
        <i data-lucide="bell" class="h-4.5 w-4.5"></i>
        <span id="unread-notif-count" class="hidden absolute -top-1 -right-1 h-4 w-4 bg-rose-500 rounded-full text-[9px] font-bold text-white flex items-center justify-center animate-pulse">0</span>
      </button>

      <!-- Dropdown Panel -->
      <div id="dropdown-notifications" class="hidden absolute right-0 top-10 w-80 glass rounded-2xl shadow-xl border border-white/5 dark:border-white/5 light:border-black/5 p-4 z-[90] flex flex-col space-y-3">
        <div class="flex justify-between items-center border-b border-white/5 pb-2">
          <span class="text-xs font-bold text-white dark:text-white light:text-slate-900 font-display">Notifications Inbox</span>
          <button id="btn-mark-all-read" class="text-[9px] text-brand-secondary hover:underline font-semibold">Mark all as read</button>
        </div>
        <div id="notifications-list" class="divide-y divide-white/5 overflow-y-auto max-h-64 space-y-2 flex-grow scrollbar-thin">
          <p class="text-[10px] text-slate-500 text-center py-4">No notifications</p>
        </div>
        <div class="border-t border-white/5 pt-2 flex justify-between items-center text-[10px]">
          <button id="btn-open-prefs" class="text-slate-400 hover:text-white flex items-center space-x-1 transition duration-150">
            <i data-lucide="settings-2" class="h-3 w-3"></i>
            <span>Preferences</span>
          </button>
          <span class="text-slate-500 tracking-wider">HydraSpecma System</span>
        </div>
      </div>
    `;

    userBadge.parentNode.insertBefore(bellWrapper, userBadge);
    
    // Re-trigger lucide icons compiling
    if (globalThis.lucide) {
      globalThis.lucide.createIcons();
    }
  }

  async fetchNotifications() {
    try {
      const supabase = getSupabase();
      
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('recipient_id', this.userId)
        .order('created_at', { ascending: false })
        .limit(10);

      if (error) throw error;

      this.notifications = data || [];
      this.unreadCount = this.notifications.filter(n => !n.is_read).length;

      this.renderInbox();

    } catch (err) {
      console.error('Failed to fetch notifications:', err);
    }
  }

  async fetchPreferences() {
    try {
      const supabase = getSupabase();
      const { data, error } = await supabase
        .from('notification_preferences')
        .select('*')
        .eq('user_id', this.userId);

      if (error) throw error;
      this.preferences = data || [];

    } catch (err) {
      console.error('Failed to fetch preferences:', err);
    }
  }

  renderInbox() {
    const countBadge = document.getElementById('unread-notif-count');
    const listEl = document.getElementById('notifications-list');

    if (!countBadge || !listEl) return;

    // Unread count badge
    if (this.unreadCount > 0) {
      countBadge.textContent = this.unreadCount;
      countBadge.classList.remove('hidden');
    } else {
      countBadge.classList.add('hidden');
    }

    if (this.notifications.length === 0) {
      listEl.innerHTML = '<p class="text-[10px] text-slate-500 text-center py-6">All clear! No notifications.</p>';
      return;
    }

    listEl.innerHTML = this.notifications.map(n => {
      const time = new Date(n.created_at).toLocaleDateString(undefined, {
        month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
      });
      const unreadDot = !n.is_read 
        ? '<span class="h-1.5 w-1.5 rounded-full bg-brand-secondary shrink-0 mt-1"></span>' 
        : '';
      
      return `
        <div class="py-2.5 flex items-start space-x-2 cursor-pointer hover:bg-white/5 rounded-lg px-2 transition-all duration-150 text-slate-300 dark:text-slate-300 light:text-slate-700" 
             data-notif-id="${n.id}" data-action-url="${n.action_url || '#'}">
          ${unreadDot}
          <div class="flex-grow">
            <div class="flex justify-between items-start">
              <p class="font-bold text-[11px] text-white dark:text-white light:text-slate-900 leading-tight">${n.title}</p>
              <span class="text-[8px] text-slate-500 ml-2 whitespace-nowrap">${time}</span>
            </div>
            <p class="text-[10px] text-slate-400 dark:text-slate-400 light:text-slate-500 mt-0.5 leading-snug">${n.body || ''}</p>
          </div>
        </div>
      `;
    }).join('');

    // Bind item click redirection
    listEl.querySelectorAll('[data-notif-id]').forEach(el => {
      el.addEventListener('click', async (e) => {
        const item = e.currentTarget;
        const id = item.getAttribute('data-notif-id');
        const url = item.getAttribute('data-action-url');
        
        await this.markAsRead(id);
        
        if (url && url !== '#') {
          globalThis.location.href = url;
        }
      });
    });
  }

  async markAsRead(id) {
    try {
      const supabase = getSupabase();
      const { error } = await supabase
        .from('notifications')
        .update({
          is_read: true,
          read_at: new Date().toISOString()
        })
        .eq('id', id);

      if (error) throw error;
      
      // Update local state
      const local = this.notifications.find(n => n.id === id);
      if (local && !local.is_read) {
        local.is_read = true;
        this.unreadCount = Math.max(0, this.unreadCount - 1);
        this.renderInbox();
      }
    } catch (err) {
      console.error('Failed to mark read:', err);
    }
  }

  async markAllAsRead() {
    toast.info('Marking all read...');
    try {
      const supabase = getSupabase();
      const { error } = await supabase
        .from('notifications')
        .update({
          is_read: true,
          read_at: new Date().toISOString()
        })
        .eq('recipient_id', this.userId)
        .eq('is_read', false);

      if (error) throw error;
      
      this.notifications.forEach(n => n.is_read = true);
      this.unreadCount = 0;
      this.renderInbox();
      toast.success('All marked as read.');

    } catch (err) {
      console.error('Failed to mark all read:', err);
      toast.error('Failed to update inbox.');
    }
  }

  bindEvents() {
    const bellBtn = document.getElementById('btn-notification-bell');
    const dropdown = document.getElementById('dropdown-notifications');
    const markAllReadBtn = document.getElementById('btn-mark-all-read');
    const openPrefsBtn = document.getElementById('btn-open-prefs');

    if (bellBtn && dropdown) {
      // Toggle dropdown
      bellBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        dropdown.classList.toggle('hidden');
      });

      // Close dropdown when clicking outside
      document.addEventListener('click', (e) => {
        if (!dropdown.classList.contains('hidden') && !dropdown.contains(e.target) && e.target !== bellBtn) {
          dropdown.classList.add('hidden');
        }
      });
    }

    if (markAllReadBtn) {
      markAllReadBtn.addEventListener('click', () => this.markAllAsRead());
    }

    if (openPrefsBtn) {
      openPrefsBtn.addEventListener('click', () => {
        dropdown.classList.add('hidden');
        this.openPreferencesModal();
      });
    }
  }

  openPreferencesModal() {
    // Check if modal already exists
    let modal = document.getElementById('modal-notification-prefs');
    if (modal) {
      modal.remove();
    }

    // Inject dynamic modal
    modal = document.createElement('div');
    modal.id = 'modal-notification-prefs';
    modal.className = 'fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm';
    
    const eventTypes = [
      { code: 'ecm.transition', name: 'Workflow Status Changes' },
      { code: 'task.assigned', name: 'Task Assignments' },
      { code: 'approval.pending', name: 'Awaiting Gate Approvals' },
      { code: 'task.reminder', name: 'Task Reminders' }
    ];

    const getPrefState = (eventCode, channel) => {
      const p = this.preferences.find(pref => pref.event_type === eventCode && pref.channel === channel);
      return p ? p.enabled : true; // default true if not configured
    };

    modal.innerHTML = `
      <div class="w-full max-w-lg glass rounded-3xl p-8 flex flex-col space-y-6">
        <div class="flex justify-between items-start border-b border-white/5 pb-4">
          <div>
            <h3 class="text-sm font-bold font-display text-white dark:text-white light:text-slate-900">Notification Preferences</h3>
            <p class="text-[10px] text-slate-400 mt-1">Configure your preferred notification channels per event.</p>
          </div>
          <button type="button" class="btn-close-prefs text-slate-500 hover:text-white transition duration-200">
            <i data-lucide="x" class="h-5 w-5"></i>
          </button>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs border-collapse">
            <thead>
              <tr class="text-slate-400 border-b border-white/5">
                <th class="py-2.5 px-4 font-semibold">Event Trigger</th>
                <th class="py-2.5 px-4 font-semibold text-center">In-App</th>
                <th class="py-2.5 px-4 font-semibold text-center">Email</th>
                <th class="py-2.5 px-4 font-semibold text-center">Teams</th>
              </tr>
            </thead>
            <tbody>
              ${eventTypes.map(ev => `
                <tr class="border-b border-white/5 text-slate-200 dark:text-slate-200 light:text-slate-700">
                  <td class="py-3 px-4 font-semibold">${ev.name}</td>
                  <td class="py-3 px-4 text-center">
                    <input type="checkbox" data-event="${ev.code}" data-channel="in_app" ${getPrefState(ev.code, 'in_app') ? 'checked' : ''} 
                           class="h-4 w-4 rounded bg-black/35 border border-white/10 text-brand-secondary focus:ring-0 cursor-pointer">
                  </td>
                  <td class="py-3 px-4 text-center">
                    <input type="checkbox" data-event="${ev.code}" data-channel="email" ${getPrefState(ev.code, 'email') ? 'checked' : ''} 
                           class="h-4 w-4 rounded bg-black/35 border border-white/10 text-brand-secondary focus:ring-0 cursor-pointer">
                  </td>
                  <td class="py-3 px-4 text-center">
                    <input type="checkbox" data-event="${ev.code}" data-channel="teams" ${getPrefState(ev.code, 'teams') ? 'checked' : ''} 
                           class="h-4 w-4 rounded bg-black/35 border border-white/10 text-brand-secondary focus:ring-0 cursor-pointer">
                  </td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>

        <button id="btn-save-prefs" class="w-full py-3 rounded-xl bg-gradient-to-r from-brand-primary to-brand-secondary font-semibold text-xs text-white transition duration-200 flex items-center justify-center">
          Save Preferences
        </button>
      </div>
    `;

    document.body.appendChild(modal);

    if (globalThis.lucide) {
      globalThis.lucide.createIcons();
    }

    // Close buttons binding
    modal.querySelector('.btn-close-prefs').addEventListener('click', () => modal.remove());

    // Save preferences
    modal.querySelector('#btn-save-prefs').addEventListener('click', async () => {
      const inputs = modal.querySelectorAll('input[type="checkbox"]');
      const upserts = [];

      inputs.forEach(input => {
        upserts.push({
          user_id: this.userId,
          event_type: input.getAttribute('data-event'),
          channel: input.getAttribute('data-channel'),
          enabled: input.checked
        });
      });

      toast.info('Saving preferences...');
      try {
        const supabase = getSupabase();
        const { error } = await supabase
          .from('notification_preferences')
          .upsert(upserts);

        if (error) throw error;
        
        this.preferences = upserts;
        toast.success('Notification preferences updated!');
        
        // Dispatch Microsoft Teams mock notification logs
        console.log('--- MICROSOFT TEAMS WEBHOOK PAYLOAD DISPATCH ---');
        console.log('Target Channel: Configuration Controller General Webhook');
        console.log('Payload:', {
          title: 'Notification Preferences Configured',
          user: this.userId,
          timestamp: new Date().toISOString(),
          preferences: upserts
        });
        console.log('Teams webhook status: 200 OK');

        modal.remove();

      } catch (err) {
        console.error('Failed to save preferences:', err);
        toast.error('Failed to save configuration.');
      }
    });
  }
}

// Instantiate
new NotificationsManager();
