<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';

/**
 * Composer for free-form WhatsApp interactive messages (reply buttons / list).
 * The agent writes a body prompt and a set of options; on send we emit an
 * `input_select` message whose content_attributes.items carry the options.
 * The WAHA backend renders <=3 options as reply buttons and >3 as a list.
 */

const props = defineProps({
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['send', 'cancel', 'update:show']);

const { t } = useI18n();

const MAX_OPTIONS = 10;
const BUTTON_THRESHOLD = 3;
const TITLE_MAX = 24;
const BODY_MAX = 1024;

const body = ref('');
const options = ref([{ title: '' }, { title: '' }]);

const localShow = computed({
  get: () => props.show,
  set: value => emit('update:show', value),
});

watch(
  () => props.show,
  open => {
    if (open) {
      body.value = '';
      options.value = [{ title: '' }, { title: '' }];
    }
  }
);

const filledOptions = computed(() =>
  options.value.map(o => (o.title || '').trim()).filter(Boolean)
);

const isList = computed(() => filledOptions.value.length > BUTTON_THRESHOLD);

const canAddOption = computed(() => options.value.length < MAX_OPTIONS);

const isValid = computed(
  () => body.value.trim().length > 0 && filledOptions.value.length >= 1
);

const modeHint = computed(() =>
  isList.value
    ? t('INTERACTIVE_MESSAGE.MODE.LIST')
    : t('INTERACTIVE_MESSAGE.MODE.BUTTONS')
);

function addOption() {
  if (canAddOption.value) options.value.push({ title: '' });
}

function removeOption(index) {
  if (options.value.length <= 1) return;
  options.value.splice(index, 1);
}

// Stable, readable reply id derived from the option title. WhatsApp echoes this
// back on tap; falls back to a positional id when slugging yields nothing.
function slugify(text, index) {
  const slug = (text || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);
  return slug || `option_${index + 1}`;
}

function onSend() {
  if (!isValid.value) return;
  const items = options.value
    .map((o, index) => ({ title: (o.title || '').trim(), index }))
    .filter(o => o.title)
    .map((o, idx) => ({ title: o.title, value: slugify(o.title, idx) }));

  emit('send', {
    message: body.value.trim(),
    contentType: 'input_select',
    contentAttributes: { items },
  });
}

function onClose() {
  emit('cancel');
}
</script>

<template>
  <woot-modal v-model:show="localShow" :on-close="onClose" size="modal-big">
    <woot-modal-header
      :header-title="$t('INTERACTIVE_MESSAGE.TITLE')"
      :header-content="$t('INTERACTIVE_MESSAGE.SUBTITLE')"
    />
    <div class="flex flex-col gap-4 p-8">
      <!-- Body / prompt -->
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12" for="im-body">
          {{ $t('INTERACTIVE_MESSAGE.BODY_LABEL') }}
        </label>
        <textarea
          id="im-body"
          v-model="body"
          :maxlength="BODY_MAX"
          rows="3"
          class="w-full resize-y rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
          :placeholder="$t('INTERACTIVE_MESSAGE.BODY_PLACEHOLDER')"
        />
      </div>

      <!-- Options -->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <label class="text-sm font-medium text-n-slate-12">
            {{ $t('INTERACTIVE_MESSAGE.OPTIONS_LABEL') }}
          </label>
          <span
            class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11"
          >
            <Icon
              :icon="isList ? 'i-lucide-list' : 'i-lucide-rectangle-horizontal'"
              class="size-3"
            />
            {{ modeHint }}
          </span>
        </div>

        <div
          v-for="(option, index) in options"
          :key="index"
          class="flex items-center gap-2"
        >
          <span
            class="inline-flex size-6 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-[11px] font-semibold text-n-slate-11"
          >
            {{ index + 1 }}
          </span>
          <input
            v-model="option.title"
            :maxlength="TITLE_MAX"
            class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            :placeholder="
              $t('INTERACTIVE_MESSAGE.OPTION_PLACEHOLDER', { index: index + 1 })
            "
            @keydown.enter.prevent="addOption"
          />
          <button
            type="button"
            :disabled="options.length <= 1"
            :aria-label="$t('INTERACTIVE_MESSAGE.REMOVE_OPTION')"
            class="inline-flex size-8 items-center justify-center rounded-md text-n-slate-11 transition-colors hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-40"
            @click="removeOption(index)"
          >
            <Icon icon="i-lucide-trash-2" class="size-4" />
          </button>
        </div>

        <button
          type="button"
          :disabled="!canAddOption"
          class="mt-1 inline-flex w-fit items-center gap-1 rounded-md border border-dashed border-n-weak px-3 py-1.5 text-xs font-medium text-n-slate-11 transition-colors hover:border-n-brand hover:text-n-brand disabled:cursor-not-allowed disabled:opacity-40"
          @click="addOption"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
          {{ $t('INTERACTIVE_MESSAGE.ADD_OPTION') }}
        </button>
      </div>

      <p class="text-[11px] text-n-slate-10">
        {{ $t('INTERACTIVE_MESSAGE.HELP') }}
      </p>

      <!-- Footer -->
      <div
        class="mt-1 flex items-center justify-end gap-3 border-t border-n-weak pt-4"
      >
        <ButtonV4
          variant="ghost"
          color="slate"
          size="md"
          :label="$t('INTERACTIVE_MESSAGE.CANCEL')"
          @click="onClose"
        />
        <ButtonV4
          variant="solid"
          color="teal"
          size="md"
          icon="i-lucide-send"
          :label="$t('INTERACTIVE_MESSAGE.SEND')"
          :disabled="!isValid"
          @click="onSend"
        />
      </div>
    </div>
  </woot-modal>
</template>
