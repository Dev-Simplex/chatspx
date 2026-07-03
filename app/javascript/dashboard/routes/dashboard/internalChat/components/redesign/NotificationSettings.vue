<script setup>
import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

const { uiSettings, updateUISettings } = useUISettings();

// Toques disponíveis (mesmos do seletor oficial do Chatwoot, em public/audio/dashboard).
const TONES = [
  { value: 'ding', label: 'Ding' },
  { value: 'bell', label: 'Bell' },
  { value: 'chime', label: 'Chime' },
  { value: 'magic', label: 'Magic' },
  { value: 'ping', label: 'Ping' },
];

const soundOn = computed(
  () => uiSettings.value?.internal_chat_sound_notifications !== false
);
const desktopOn = computed(
  () => uiSettings.value?.internal_chat_desktop_notifications !== false
);
const tone = computed({
  get: () => uiSettings.value?.internal_chat_notification_tone || 'ding',
  set: value => updateUISettings({ internal_chat_notification_tone: value }),
});

const toggleSound = () =>
  updateUISettings({ internal_chat_sound_notifications: !soundOn.value });
const toggleDesktop = () =>
  updateUISettings({ internal_chat_desktop_notifications: !desktopOn.value });

const preview = new Audio();
const playPreview = () => {
  try {
    preview.src = `/audio/dashboard/${tone.value}.mp3`;
    preview.currentTime = 0;
    preview.play().catch(() => {});
  } catch (e) {
    // áudio é não-crítico
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="p-2">
    <p
      class="px-2 pt-1 pb-2 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
    >
      Notificações
    </p>

    <!-- Toggle: som -->
    <button
      type="button"
      role="switch"
      :aria-checked="soundOn"
      class="flex items-center justify-between w-full gap-3 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
      @click="toggleSound"
    >
      Som de notificação
      <span
        class="relative inline-flex items-center flex-shrink-0 h-5 transition-colors rounded-full w-9"
        :class="soundOn ? 'bg-n-brand' : 'bg-n-slate-4'"
      >
        <span
          class="inline-block w-4 h-4 transition-transform bg-white rounded-full shadow"
          :class="soundOn ? 'translate-x-4' : 'translate-x-0.5'"
        />
      </span>
    </button>

    <!-- Toggle: desktop -->
    <button
      type="button"
      role="switch"
      :aria-checked="desktopOn"
      class="flex items-center justify-between w-full gap-3 px-3 py-2.5 text-sm text-left rounded-xl text-n-slate-12 hover:bg-n-alpha-1"
      @click="toggleDesktop"
    >
      Notificação no desktop
      <span
        class="relative inline-flex items-center flex-shrink-0 h-5 transition-colors rounded-full w-9"
        :class="desktopOn ? 'bg-n-brand' : 'bg-n-slate-4'"
      >
        <span
          class="inline-block w-4 h-4 transition-transform bg-white rounded-full shadow"
          :class="desktopOn ? 'translate-x-4' : 'translate-x-0.5'"
        />
      </span>
    </button>

    <!-- Seletor de toque + prévia -->
    <div class="px-3 pt-2 pb-1">
      <p class="mb-1.5 text-xs font-medium text-n-slate-11">Som</p>
      <div class="flex items-center gap-2">
        <select
          v-model="tone"
          class="reset-base flex-1 h-9 px-2 text-sm border rounded-lg outline-none cursor-pointer bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12"
          :disabled="!soundOn"
        >
          <option v-for="t in TONES" :key="t.value" :value="t.value">
            {{ t.label }}
          </option>
        </select>
        <button
          type="button"
          class="inline-flex items-center justify-center flex-shrink-0 rounded-lg w-9 h-9 text-n-slate-11 ring-1 ring-inset ring-n-weak hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-40"
          title="Ouvir"
          :disabled="!soundOn"
          @click="playPreview"
        >
          <span class="text-lg i-lucide-volume-2" />
        </button>
      </div>
    </div>
  </div>
</template>
