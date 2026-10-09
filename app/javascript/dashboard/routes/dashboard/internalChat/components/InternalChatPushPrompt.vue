<script setup>
// Convite para o aviso fora da aba (push do navegador) no chat interno.
// Aparece só depois que a pessoa abre uma conversa (é aí que faz sentido),
// e some por 14 dias com "Agora não". Quem já tem push ligado nunca vê.
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  verifyServiceWorkerExistence,
  sendRegistrationToServer,
} from 'dashboard/helper/pushHelper';

const { t } = useI18n();

const DISMISS_KEY = 'internal_chat_push_prompt_dismissed_at';
const DISMISS_DAYS = 14;
// Sem serviço de push (navegador sem suporte, rede bloqueando) a inscrição
// fica pendurada para sempre: depois disso a tela diz que não deu.
const SUBSCRIBE_TIMEOUT_MS = 30000;

// idle → asking → done | blocked | failed
const state = ref(null);

const recentlyDismissed = () => {
  try {
    const at = Number(localStorage.getItem(DISMISS_KEY) || 0);
    return Date.now() - at < DISMISS_DAYS * 24 * 60 * 60 * 1000;
  } catch (e) {
    return false;
  }
};

const dismiss = () => {
  try {
    localStorage.setItem(DISMISS_KEY, String(Date.now()));
  } catch (e) {
    // sem armazenamento: só não lembra
  }
  state.value = null;
};

onMounted(() => {
  if (!('Notification' in window) || !('serviceWorker' in navigator)) return;
  if (!window.chatwootConfig?.vapidPublicKey) return;
  if (Notification.permission === 'denied' || recentlyDismissed()) return;
  verifyServiceWorkerExistence(registration =>
    registration.pushManager.getSubscription().then(subscription => {
      if (!subscription || Notification.permission !== 'granted') {
        state.value = 'idle';
      }
    })
  );
});

const enable = async () => {
  state.value = 'asking';
  const permission =
    Notification.permission === 'granted'
      ? 'granted'
      : await Notification.requestPermission();
  if (permission !== 'granted') {
    state.value = permission === 'denied' ? 'blocked' : 'idle';
    return;
  }
  try {
    const subscribe = navigator.serviceWorker.ready
      .then(registration =>
        registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: window.chatwootConfig.vapidPublicKey,
        })
      )
      .then(sendRegistrationToServer);
    const timeout = new Promise((_, reject) => {
      setTimeout(() => reject(new Error('timeout')), SUBSCRIBE_TIMEOUT_MS);
    });
    await Promise.race([subscribe, timeout]);
    state.value = 'done';
    setTimeout(() => {
      if (state.value === 'done') state.value = null;
    }, 5000);
  } catch (e) {
    state.value = 'failed';
  }
};
</script>

<template>
  <div
    v-if="state"
    class="flex-shrink-0 p-4 m-3 border shadow-lg rounded-2xl bg-n-solid-2 border-n-weak"
    role="status"
  >
    <div class="flex items-start gap-3">
      <span
        class="flex items-center justify-center flex-shrink-0 rounded-full size-8 bg-n-teal-3 text-n-teal-11"
      >
        <span
          class="size-4"
          :class="
            state === 'done'
              ? 'i-lucide-check'
              : state === 'blocked'
                ? 'i-lucide-bell-off'
                : 'i-lucide-bell-ring'
          "
        />
      </span>
      <div class="flex-1 min-w-0">
        <template v-if="['idle', 'asking', 'failed'].includes(state)">
          <div class="text-sm font-medium text-n-slate-12">
            {{ t('INTERNAL_CHAT.PUSH_PROMPT.TITLE') }}
          </div>
          <div class="mt-1 text-xs text-n-slate-11">
            {{
              {
                asking: t('INTERNAL_CHAT.PUSH_PROMPT.ASKING'),
                failed: t('INTERNAL_CHAT.PUSH_PROMPT.FAILED'),
              }[state] || t('INTERNAL_CHAT.PUSH_PROMPT.DESCRIPTION')
            }}
          </div>
          <div v-if="state !== 'asking'" class="flex flex-wrap gap-2 mt-3">
            <button
              type="button"
              class="px-3 py-1.5 text-xs font-medium text-white rounded-full whitespace-nowrap bg-n-teal-9 hover:bg-n-teal-10"
              @click="enable"
            >
              {{
                state === 'failed'
                  ? t('INTERNAL_CHAT.PUSH_PROMPT.RETRY')
                  : t('INTERNAL_CHAT.PUSH_PROMPT.ENABLE')
              }}
            </button>
            <button
              type="button"
              class="px-3 py-1.5 text-xs rounded-full whitespace-nowrap text-n-slate-11 hover:bg-n-alpha-2"
              @click="dismiss"
            >
              {{ t('INTERNAL_CHAT.PUSH_PROMPT.LATER') }}
            </button>
          </div>
        </template>
        <div v-else class="text-sm text-n-slate-12">
          {{
            state === 'done'
              ? t('INTERNAL_CHAT.PUSH_PROMPT.DONE')
              : t('INTERNAL_CHAT.PUSH_PROMPT.BLOCKED')
          }}
        </div>
      </div>
      <button
        v-tooltip="t('INTERNAL_CHAT.PUSH_PROMPT.CLOSE')"
        type="button"
        class="p-1 -mt-1 -mr-1 rounded-full text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2"
        :aria-label="t('INTERNAL_CHAT.PUSH_PROMPT.CLOSE')"
        @click="dismiss"
      >
        <span class="block i-lucide-x size-4" />
      </button>
    </div>
  </div>
</template>
