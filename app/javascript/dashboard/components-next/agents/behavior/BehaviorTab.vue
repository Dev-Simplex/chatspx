<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AiCard from 'dashboard/components-next/agents-ui/AiCard.vue';
import AiToggle from 'dashboard/components-next/agents-ui/AiToggle.vue';
import AiCheckbox from 'dashboard/components-next/agents-ui/AiCheckbox.vue';
import AiField from 'dashboard/components-next/agents-ui/AiField.vue';
import AiNumberField from 'dashboard/components-next/agents-ui/AiNumberField.vue';
import AiSelect from 'dashboard/components-next/agents-ui/AiSelect.vue';
import AiTimeField from 'dashboard/components-next/agents-ui/AiTimeField.vue';
import AiButton from 'dashboard/components-next/agents-ui/AiButton.vue';

const props = defineProps({ assistant: { type: Object, required: true } });
const emit = defineEmits(['save']);
const { t } = useI18n();

const behavior = ref(
  JSON.parse(JSON.stringify(props.assistant.behavior || {}))
);
const saved = ref(false);

const patch = (key, value) => {
  behavior.value = { ...behavior.value, [key]: value };
};
const patchObj = (key, sub) => {
  behavior.value = {
    ...behavior.value,
    [key]: { ...(behavior.value[key] || {}), ...sub },
  };
};
const csv = v =>
  v
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

// Router
const phones = computed({
  get: () => (behavior.value.router?.only_contact_phones || []).join(', '),
  set: v => patchObj('router', { only_contact_phones: csv(v) }),
});
const skipLabels = computed({
  get: () => (behavior.value.router?.skip_labels || []).join(', '),
  set: v => patchObj('router', { skip_labels: csv(v) }),
});
const routerGet = k => !!behavior.value.router?.[k];
const routerSet = (k, v) => patchObj('router', { [k]: v });

// Business hours
const DAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const bhEnabled = computed({
  get: () => !!behavior.value.business_hours?.enabled,
  set: v =>
    patchObj('business_hours', {
      enabled: v,
      timezone: behavior.value.business_hours?.timezone || 'America/Cuiaba',
      outside_hours_action:
        behavior.value.business_hours?.outside_hours_action || 'ignore',
      schedule: behavior.value.business_hours?.schedule || [],
    }),
});
const tz = computed({
  get: () => behavior.value.business_hours?.timezone || '',
  set: v => patchObj('business_hours', { timezone: v }),
});
const outsideAction = computed({
  get: () => behavior.value.business_hours?.outside_hours_action || 'ignore',
  set: v => patchObj('business_hours', { outside_hours_action: v }),
});
const ACTION_OPTS = computed(() => [
  {
    value: 'ignore',
    label: t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.ACTION_IGNORE'),
  },
  {
    value: 'qualify_more',
    label: t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.ACTION_QUALIFY'),
  },
]);
const dayEntry = d =>
  (behavior.value.business_hours?.schedule || []).find(s => s.day === d);
const dayOn = d => !!dayEntry(d);
const dayVal = (d, f) =>
  dayEntry(d)?.ranges?.[0]?.[f] || (f === 'start' ? '08:00' : '17:00');
const setDayOn = (d, on) => {
  let sch = [...(behavior.value.business_hours?.schedule || [])];
  if (on && !dayEntry(d))
    sch.push({ day: d, ranges: [{ start: '08:00', end: '17:00' }] });
  if (!on) sch = sch.filter(s => s.day !== d);
  sch.sort((a, b) => a.day - b.day);
  patchObj('business_hours', { schedule: sch });
};
const setDayTime = (d, f, v) => {
  const sch = (behavior.value.business_hours?.schedule || []).map(s =>
    s.day === d
      ? {
          ...s,
          ranges: [
            { ...(s.ranges?.[0] || { start: '08:00', end: '17:00' }), [f]: v },
          ],
        }
      : s
  );
  patchObj('business_hours', { schedule: sch });
};

// Debounce
const debounceEnabled = computed({
  get: () => Number(behavior.value.debounce_seconds) > 0,
  set: v =>
    patch(
      'debounce_seconds',
      v ? Number(behavior.value.debounce_seconds) || 15 : 0
    ),
});
const debounceSecs = computed({
  get: () => Number(behavior.value.debounce_seconds) || 15,
  set: v => patch('debounce_seconds', Number(v)),
});

// Media pipeline
const mediaGet = k => !!behavior.value.media_pipeline?.[k];
const mediaSet = (k, v) => patchObj('media_pipeline', { [k]: v });

// Humanizer
const humanizerEnabled = computed({
  get: () => !!behavior.value.humanizer?.enabled,
  set: v =>
    patchObj('humanizer', {
      enabled: v,
      max_chars: behavior.value.humanizer?.max_chars || 300,
      delay_ms: behavior.value.humanizer?.delay_ms || 500,
    }),
});
const hMax = computed({
  get: () => behavior.value.humanizer?.max_chars || 300,
  set: v => patchObj('humanizer', { max_chars: Number(v) }),
});
const hDelay = computed({
  get: () => behavior.value.humanizer?.delay_ms || 500,
  set: v => patchObj('humanizer', { delay_ms: Number(v) }),
});

// Dedup
const dedupEnabled = computed({
  get: () => !!behavior.value.dedup?.enabled,
  set: v =>
    patchObj('dedup', {
      enabled: v,
      ttl_seconds: behavior.value.dedup?.ttl_seconds || 120,
    }),
});
const dedupTtl = computed({
  get: () => behavior.value.dedup?.ttl_seconds || 120,
  set: v => patchObj('dedup', { ttl_seconds: Number(v) }),
});

// Copilot
const copilotEnabled = computed({
  get: () => !!behavior.value.copilot_trigger?.enabled,
  set: v =>
    patchObj('copilot_trigger', {
      enabled: v,
      hashtag: behavior.value.copilot_trigger?.hashtag || '#copilot',
    }),
});
const copilotTag = computed({
  get: () => behavior.value.copilot_trigger?.hashtag || '#copilot',
  set: v => patchObj('copilot_trigger', { hashtag: v }),
});

const SEP = '–';
const OFF = '—';
const save = () => {
  emit('save', behavior.value);
  saved.value = true;
  setTimeout(() => {
    saved.value = false;
  }, 1800);
};
</script>

<template>
  <div class="px-6 pt-4 pb-24 mx-auto space-y-3 max-w-3xl">
    <!-- Roteamento -->
    <AiCard id="behavior-router">
      <p class="text-[14px] font-bold text-n-slate-12">
        {{ t('CAPTAIN.BEHAVIOR.ROUTER.TITLE') }}
      </p>
      <p class="mt-0.5 mb-3 text-[12.5px] text-n-slate-11">
        {{ t('CAPTAIN.BEHAVIOR.ROUTER.DESCRIPTION') }}
      </p>
      <div class="space-y-3">
        <div>
          <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.ROUTER.ONLY_CONTACT_PHONES') }}
          </label>
          <AiField
            v-model="phones"
            :placeholder="
              t('CAPTAIN.BEHAVIOR.ROUTER.ONLY_CONTACT_PHONES_PLACEHOLDER')
            "
          />
        </div>
        <div>
          <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_LABELS') }}
          </label>
          <AiField
            v-model="skipLabels"
            :placeholder="t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_LABELS_PLACEHOLDER')"
          />
        </div>
        <div class="grid grid-cols-1 gap-2.5 pt-1 sm:grid-cols-2">
          <AiCheckbox
            :model-value="routerGet('skip_groups')"
            :label="t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_GROUPS')"
            @update:model-value="routerSet('skip_groups', $event)"
          />
          <AiCheckbox
            :model-value="routerGet('skip_after_human_response')"
            :label="t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_AFTER_HUMAN_RESPONSE')"
            @update:model-value="routerSet('skip_after_human_response', $event)"
          />
          <AiCheckbox
            :model-value="routerGet('skip_activity')"
            :label="t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_ACTIVITY')"
            @update:model-value="routerSet('skip_activity', $event)"
          />
          <AiCheckbox
            :model-value="routerGet('skip_agent_bot')"
            :label="t('CAPTAIN.BEHAVIOR.ROUTER.SKIP_AGENT_BOT')"
            @update:model-value="routerSet('skip_agent_bot', $event)"
          />
        </div>
      </div>
    </AiCard>

    <!-- Horário comercial -->
    <AiCard id="behavior-business_hours">
      <div class="flex gap-3 justify-between items-start">
        <div>
          <p class="text-[14px] font-bold text-n-slate-12">
            {{ t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.TITLE') }}
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.DESCRIPTION') }}
          </p>
        </div>
        <AiToggle v-model="bhEnabled" />
      </div>
      <div v-if="bhEnabled" class="mt-4 space-y-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
              {{ t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.TIMEZONE_LABEL') }}
            </label>
            <AiField v-model="tz" placeholder="America/Cuiaba" />
          </div>
          <div>
            <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
              {{ t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.OUTSIDE_ACTION') }}
            </label>
            <AiSelect v-model="outsideAction" :options="ACTION_OPTS" />
          </div>
        </div>
        <div>
          <p class="mb-2 text-[12px] font-semibold text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.BUSINESS_HOURS.SCHEDULE_LABEL') }}
          </p>
          <div class="space-y-2">
            <div
              v-for="(d, i) in DAYS"
              :key="i"
              class="flex gap-3 items-center"
            >
              <AiCheckbox
                :model-value="dayOn(i)"
                @update:model-value="setDayOn(i, $event)"
              />
              <span class="w-9 text-[13px] font-semibold text-n-slate-12">{{
                d
              }}</span>
              <template v-if="dayOn(i)">
                <AiTimeField
                  :model-value="dayVal(i, 'start')"
                  @update:model-value="setDayTime(i, 'start', $event)"
                />
                <span class="text-n-slate-10">{{ SEP }}</span>
                <AiTimeField
                  :model-value="dayVal(i, 'end')"
                  @update:model-value="setDayTime(i, 'end', $event)"
                />
              </template>
              <span v-else class="text-[12.5px] text-n-slate-9">{{ OFF }}</span>
            </div>
          </div>
        </div>
      </div>
    </AiCard>

    <!-- Debounce -->
    <AiCard id="behavior-debounce_seconds">
      <div class="flex gap-3 justify-between items-start">
        <div>
          <p class="text-[14px] font-bold text-n-slate-12">
            {{ t('CAPTAIN.BEHAVIOR.DEBOUNCE.TITLE') }}
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.DEBOUNCE.DESCRIPTION') }}
          </p>
        </div>
        <AiToggle v-model="debounceEnabled" />
      </div>
      <div v-if="debounceEnabled" class="flex gap-3 items-center mt-4">
        <span class="text-[12.5px] text-n-slate-11">{{
          t('CAPTAIN.BEHAVIOR.DEBOUNCE.SECONDS_LABEL')
        }}</span>
        <AiNumberField v-model="debounceSecs" :min="1" :max="60" suffix="s" />
      </div>
    </AiCard>

    <!-- Mídias -->
    <AiCard id="behavior-media_pipeline">
      <p class="text-[14px] font-bold text-n-slate-12">
        {{ t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.TITLE') }}
      </p>
      <p class="mt-0.5 mb-3 text-[12.5px] text-n-slate-11">
        {{ t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.DESCRIPTION') }}
      </p>
      <div class="space-y-2.5">
        <AiCheckbox
          :model-value="mediaGet('audio_transcription')"
          :label="t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.AUDIO_TRANSCRIPTION')"
          @update:model-value="mediaSet('audio_transcription', $event)"
        />
        <AiCheckbox
          :model-value="mediaGet('image_description')"
          :label="t('CAPTAIN.BEHAVIOR.MEDIA_PIPELINE.IMAGE_DESCRIPTION')"
          @update:model-value="mediaSet('image_description', $event)"
        />
      </div>
    </AiCard>

    <!-- Humanizer -->
    <AiCard id="behavior-humanizer">
      <div class="flex gap-3 justify-between items-start">
        <div>
          <p class="text-[14px] font-bold text-n-slate-12">
            {{ t('CAPTAIN.BEHAVIOR.HUMANIZER.TITLE') }}
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.HUMANIZER.DESCRIPTION') }}
          </p>
        </div>
        <AiToggle v-model="humanizerEnabled" />
      </div>
      <div v-if="humanizerEnabled" class="flex flex-wrap gap-5 mt-4">
        <div>
          <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.HUMANIZER.MAX_CHARS') }}
          </label>
          <AiNumberField v-model="hMax" :min="100" :max="1000" :step="10" />
        </div>
        <div>
          <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.HUMANIZER.DELAY_MS') }}
          </label>
          <AiNumberField
            v-model="hDelay"
            :min="100"
            :max="5000"
            :step="100"
            suffix="ms"
          />
        </div>
      </div>
    </AiCard>

    <!-- Dedup -->
    <AiCard id="behavior-dedup">
      <div class="flex gap-3 justify-between items-start">
        <div>
          <p class="text-[14px] font-bold text-n-slate-12">
            {{ t('CAPTAIN.BEHAVIOR.DEDUP.TITLE') }}
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.DEDUP.DESCRIPTION') }}
          </p>
        </div>
        <AiToggle v-model="dedupEnabled" />
      </div>
      <div v-if="dedupEnabled" class="flex gap-3 items-center mt-4">
        <span class="text-[12.5px] text-n-slate-11">{{
          t('CAPTAIN.BEHAVIOR.DEDUP.TTL_LABEL')
        }}</span>
        <AiNumberField v-model="dedupTtl" :min="10" :max="3600" suffix="s" />
      </div>
    </AiCard>

    <!-- Copilot trigger -->
    <AiCard id="behavior-copilot_trigger">
      <div class="flex gap-3 justify-between items-start">
        <div>
          <p class="text-[14px] font-bold text-n-slate-12">
            {{ t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.TITLE') }}
          </p>
          <p class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.DESCRIPTION') }}
          </p>
        </div>
        <AiToggle v-model="copilotEnabled" />
      </div>
      <div v-if="copilotEnabled" class="mt-4 max-w-xs">
        <label class="block mb-1 text-[12px] font-semibold text-n-slate-11">
          {{ t('CAPTAIN.BEHAVIOR.COPILOT_TRIGGER.HASHTAG_LABEL') }}
        </label>
        <AiField v-model="copilotTag" placeholder="#copilot" />
      </div>
    </AiCard>

    <div class="flex sticky bottom-0 gap-2 justify-end items-center py-3">
      <span
        v-if="saved"
        class="text-[12.5px] font-semibold text-g-600 dark:text-g-400"
      >
        <span class="i-lucide-check align-middle size-4" />
      </span>
      <AiButton @click="save">
        <span class="i-lucide-save size-4" />
        {{ t('CAPTAIN.BEHAVIOR.SAVE') }}
      </AiButton>
    </div>
  </div>
</template>
