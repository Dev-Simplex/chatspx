<script setup>
import { computed } from 'vue';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const config = computed({
  get: () => props.modelValue || {},
  set: val => emit('update:modelValue', val),
});

function updateField(key, value) {
  emit('update:modelValue', { ...config.value, [key]: value });
}

function updateSkipLabels(event) {
  const labels = event.target.value
    .split(',')
    .map(l => l.trim())
    .filter(Boolean);
  updateField('skip_labels', labels);
}

function updateOnlyContactPhones(event) {
  const phones = event.target.value
    .split(',')
    .map(p => p.trim())
    .filter(Boolean);
  updateField('only_contact_phones', phones);
}
</script>

<template>
  <div
    id="behavior-router"
    class="rounded-lg border border-n-weak p-4 dark:bg-n-solid-2"
  >
    <h4 class="text-sm font-semibold text-n-slate-12">
      {{ $t('CAPTAIN.BEHAVIOR.ROUTER.TITLE') }}
    </h4>
    <p class="mb-3 text-xs text-n-slate-10">
      {{ $t('CAPTAIN.BEHAVIOR.ROUTER.DESCRIPTION') }}
    </p>

    <div class="space-y-3">
      <div>
        <label class="mb-1 block text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.ROUTER.ONLY_CONTACT_PHONES') }}
        </label>
        <input
          :value="(config.only_contact_phones || []).join(', ')"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="
            $t('CAPTAIN.BEHAVIOR.ROUTER.ONLY_CONTACT_PHONES_PLACEHOLDER')
          "
          @change="updateOnlyContactPhones"
        />
        <p class="mt-1 text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.ROUTER.ONLY_CONTACT_PHONES_HINT') }}
        </p>
      </div>

      <div>
        <label class="mb-1 block text-xs text-n-slate-10">
          {{ $t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_LABELS') }}
        </label>
        <input
          :value="(config.skip_labels || []).join(', ')"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="$t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_LABELS_PLACEHOLDER')"
          @change="updateSkipLabels"
        />
      </div>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.skip_groups"
          type="checkbox"
          @change="updateField('skip_groups', $event.target.checked)"
        />
        {{ $t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_GROUPS') }}
      </label>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.skip_after_human_response"
          type="checkbox"
          @change="
            updateField('skip_after_human_response', $event.target.checked)
          "
        />
        {{ $t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_AFTER_HUMAN_RESPONSE') }}
      </label>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.skip_activity"
          type="checkbox"
          @change="updateField('skip_activity', $event.target.checked)"
        />
        {{ $t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_ACTIVITY') }}
      </label>

      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input
          :checked="config.skip_agent_bot"
          type="checkbox"
          @change="updateField('skip_agent_bot', $event.target.checked)"
        />
        {{ $t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_AGENT_BOT') }}
      </label>
    </div>
  </div>
</template>
