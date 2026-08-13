<script setup>
import { computed, nextTick, onMounted, onBeforeUnmount, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { DotLottieVue } from '@lottiefiles/dotlottie-vue';

const TARGET_ACCOUNT_ID = 6;
// Banner SÓ aparece no servidor SOURCE. Se hostname for o destino, esconde.
const DESTINATION_HOST = 'tozi.chatspx.app';
const LOTTIE_URL =
  'https://lottie.host/5cf4073a-f598-4f91-a0da-4163ec1acaac/fqJLxOauh4.lottie';
const MANUAL_URL = `https://${DESTINATION_HOST}`;

const store = useStore();
const { accountId: currentAccountId } = useAccount();
const loading = ref(false);
const errorMsg = ref('');
const ctaRef = ref(null);
const cardRef = ref(null);

const currentUser = computed(() => store.getters.getCurrentUser);

const isOnSourceServer = computed(() => {
  if (typeof window === 'undefined') return false;
  return window.location.hostname !== DESTINATION_HOST;
});

// User precisa TER Account 6 (pra logar no destino)
const userHasTargetAccount = computed(() => {
  const accounts = currentUser.value?.accounts || [];
  return accounts.some(a => a.id === TARGET_ACCOUNT_ID);
});

// E estar navegando NA Account 6 (URL atual). Banner não aparece nas outras
// contas que o user também é membro.
const isOnTargetAccount = computed(
  () => Number(currentAccountId?.value) === TARGET_ACCOUNT_ID
);

const shouldShow = computed(
  () =>
    isOnSourceServer.value &&
    userHasTargetAccount.value &&
    isOnTargetAccount.value
);

const prefersReducedMotion =
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

const handleMigrate = async () => {
  loading.value = true;
  errorMsg.value = '';
  try {
    const res = await fetch('/migration_sso/issue', {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.error || `HTTP ${res.status}`);
    }
    const data = await res.json();
    if (!data.redirect_url) throw new Error('redirect_url ausente');
    window.location.href = data.redirect_url;
  } catch (e) {
    errorMsg.value = e.message || 'Falha desconhecida';
    loading.value = false;
    nextTick(() => ctaRef.value?.focus());
  }
};

// Focus trap: Tab cicla entre elementos focáveis dentro do card.
const handleKeydown = e => {
  if (!shouldShow.value) return;
  if (e.key !== 'Tab' || !cardRef.value) return;
  const focusable = cardRef.value.querySelectorAll(
    'button, a, [tabindex]:not([tabindex="-1"])'
  );
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault();
    last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault();
    first.focus();
  }
};

onMounted(() => {
  if (shouldShow.value) {
    nextTick(() => ctaRef.value?.focus());
    document.addEventListener('keydown', handleKeydown);
  }
});

onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleKeydown);
});
</script>

<template>
  <div
    v-if="shouldShow"
    class="fixed inset-0 z-[100000] flex items-center justify-center bg-slate-900/85 dark:bg-slate-900/90 backdrop-blur-md p-4"
    role="dialog"
    aria-modal="true"
    aria-labelledby="migration-title"
    aria-describedby="migration-desc"
  >
    <div
      ref="cardRef"
      tabindex="-1"
      class="max-w-md w-full bg-white dark:bg-slate-800 rounded-2xl p-6 sm:p-8 shadow-2xl border border-slate-200 dark:border-slate-700 text-center"
    >
      <div class="flex justify-center mb-2" aria-hidden="true">
        <DotLottieVue
          :src="LOTTIE_URL"
          :autoplay="!prefersReducedMotion"
          loop
          class="w-[200px] h-[200px] sm:w-[240px] sm:h-[240px]"
        />
      </div>

      <h1
        id="migration-title"
        class="text-2xl sm:text-3xl font-bold text-n-teal-11 mb-3"
      >
        A Tozi mudou de endereço
      </h1>

      <p
        id="migration-desc"
        class="text-slate-700 dark:text-slate-200 text-base leading-relaxed mb-6"
      >
        A Tozi agora tem sistema próprio, mais rápido e estável.
        Acesse abaixo — login automático.
      </p>

      <button
        ref="ctaRef"
        type="button"
        :disabled="loading"
        class="w-full inline-flex items-center justify-center gap-2 bg-n-teal-9 hover:bg-n-teal-10 disabled:bg-n-teal-8 disabled:cursor-wait text-white font-semibold text-base sm:text-lg py-3 sm:py-4 px-6 rounded-xl transition-all shadow-lg hover:shadow-n-teal-9/20 focus:outline-none focus-visible:ring-4 focus-visible:ring-n-teal-8"
        @click="handleMigrate"
      >
        <!-- Spinner SVG (Lucide-style) -->
        <svg
          v-if="loading"
          class="animate-spin w-5 h-5"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
        </svg>
        <span>{{ loading ? 'Gerando link de acesso…' : 'Acessar a nova versão' }}</span>
        <!-- Arrow Right (Lucide) -->
        <svg
          v-if="!loading"
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M5 12h14" />
          <path d="m12 5 7 7-7 7" />
        </svg>
      </button>

      <div v-if="errorMsg" class="mt-4 text-sm" role="alert">
        <p class="text-red-500 mb-2">
          Não foi possível gerar o link automático ({{ errorMsg }}).
        </p>
        <p class="text-slate-600 dark:text-slate-300">
          Acesse manualmente:
          <a :href="MANUAL_URL" class="text-n-teal-11 underline font-medium">
            {{ DESTINATION_HOST }}
          </a>
        </p>
        <button
          type="button"
          class="mt-3 text-sm underline text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200"
          @click="handleMigrate"
        >
          Tentar novamente
        </button>
      </div>

      <p class="text-slate-400 dark:text-slate-500 text-xs mt-6">
        Em caso de dúvida, contate o suporte da Simplex.
      </p>
    </div>
  </div>
</template>
