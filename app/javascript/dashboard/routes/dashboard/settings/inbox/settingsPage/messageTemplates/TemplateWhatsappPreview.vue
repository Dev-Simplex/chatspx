<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  template: { type: Object, required: true },
  businessName: { type: String, default: '' },
});
const emit = defineEmits(['close']);

const { t } = useI18n();

const components = computed(() => props.template?.components || []);

// Substitui {{1}}, {{2}}... pelos valores de exemplo do template (como o cliente veria).
function fillVars(text, examples) {
  if (!text) return '';
  return text.replace(/\{\{\s*(\d+)\s*\}\}/g, (match, n) => {
    const value = examples?.[Number(n) - 1];
    return value != null && value !== '' ? value : match;
  });
}

const header = computed(() => {
  const c = components.value.find(x => x.type === 'HEADER');
  if (!c) return null;
  if (c.format === 'TEXT') {
    return { format: 'TEXT', text: fillVars(c.text, c.example?.header_text) };
  }
  return { format: c.format };
});

const body = computed(() => {
  const c = components.value.find(x => x.type === 'BODY');
  return c ? fillVars(c.text, c.example?.body_text?.[0]) : '';
});

const footer = computed(() => {
  const c = components.value.find(x => x.type === 'FOOTER');
  return c?.text || '';
});

const buttons = computed(() => {
  const c = components.value.find(x => x.type === 'BUTTONS');
  return c?.buttons || [];
});

const mediaMeta = computed(() => {
  if (!header.value || header.value.format === 'TEXT') return null;
  const map = {
    IMAGE: { icon: 'i-lucide-image', label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.IMAGE') },
    VIDEO: { icon: 'i-lucide-video', label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.VIDEO') },
    DOCUMENT: {
      icon: 'i-lucide-file-text',
      label: t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.DOCUMENT'),
    },
  };
  return map[header.value.format] || null;
});

const buttonIcon = type => {
  const map = {
    URL: 'i-lucide-external-link',
    PHONE_NUMBER: 'i-lucide-phone',
    COPY_CODE: 'i-lucide-copy',
    QUICK_REPLY: 'i-lucide-reply',
  };
  return map[type] || 'i-lucide-reply';
};

const initial = computed(() =>
  (props.businessName || 'T').trim().charAt(0).toUpperCase()
);
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-black/60"
    @click.self="emit('close')"
  >
    <div class="flex flex-col w-full max-w-sm overflow-hidden shadow-2xl rounded-2xl">
      <!-- Barra superior do WhatsApp -->
      <div
        class="flex items-center gap-3 px-3 py-2.5 text-white bg-[#008069] dark:bg-[#202c33]"
      >
        <button type="button" class="shrink-0" @click="emit('close')">
          <Icon icon="i-lucide-arrow-left" class="size-5" />
        </button>
        <div
          class="flex items-center justify-center text-sm font-semibold rounded-full size-9 shrink-0 bg-white/25"
        >
          {{ initial }}
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium leading-tight truncate">
            {{
              businessName ||
              t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.BUSINESS_FALLBACK')
            }}
          </p>
          <p class="text-xs leading-tight text-white/70">
            {{ t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.ONLINE') }}
          </p>
        </div>
        <Icon
          icon="i-lucide-x"
          class="cursor-pointer size-5 shrink-0"
          @click="emit('close')"
        />
      </div>

      <!-- Area do chat -->
      <div
        class="max-h-[62vh] min-h-[320px] overflow-y-auto px-3 py-4 bg-[#efeae2] dark:bg-[#0b141a]"
      >
        <div class="max-w-[85%]">
          <!-- Balao recebido -->
          <div
            class="relative px-2.5 pt-2 pb-1.5 bg-white shadow-sm rounded-lg rounded-tl-none dark:bg-[#202c33]"
          >
            <!-- Header -->
            <p
              v-if="header && header.format === 'TEXT' && header.text"
              class="mb-1 text-sm font-bold break-words whitespace-pre-line text-[#111b21] dark:text-[#e9edef]"
            >
              {{ header.text }}
            </p>
            <div
              v-else-if="mediaMeta"
              class="flex items-center justify-center h-28 gap-2 mb-1.5 rounded-md bg-n-black/5 text-[#667781] dark:bg-white/5 dark:text-[#8696a0]"
            >
              <Icon :icon="mediaMeta.icon" class="size-6" />
              <span class="text-xs">{{ mediaMeta.label }}</span>
            </div>

            <!-- Corpo (texto completo) -->
            <p
              class="text-sm break-words whitespace-pre-line text-[#111b21] dark:text-[#e9edef]"
            >
              {{ body || t('WHATSAPP_TEMPLATES_MGMT.PREVIEW.BODY_PLACEHOLDER') }}
            </p>

            <!-- Rodape -->
            <p
              v-if="footer"
              class="mt-1.5 text-xs break-words whitespace-pre-line text-[#667781] dark:text-[#8696a0]"
            >
              {{ footer }}
            </p>

            <span
              class="block mt-0.5 text-[10px] leading-none text-right text-[#667781] dark:text-[#8696a0]"
            >
              09:41
            </span>
          </div>

          <!-- Botoes (bloco anexado, como no WhatsApp) -->
          <div
            v-if="buttons.length"
            class="mt-1 overflow-hidden bg-white divide-y rounded-lg shadow-sm divide-n-black/5 dark:divide-white/10 dark:bg-[#202c33]"
          >
            <div
              v-for="(btn, idx) in buttons"
              :key="idx"
              class="flex items-center justify-center gap-2 py-2.5 text-sm font-medium text-[#00a5f4]"
            >
              <Icon :icon="buttonIcon(btn.type)" class="size-4" />
              <span class="truncate">{{ btn.text || '—' }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
