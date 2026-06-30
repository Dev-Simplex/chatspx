<script setup>
defineProps({
  name: { type: String, default: '' },
  desc: { type: String, default: '' },
  color: { type: String, default: '#10a37f' },
  icon: { type: String, default: 'i-lucide-sparkles' },
  provider: { type: String, default: '' }, // openai | anthropic | google
  selected: { type: Boolean, default: false },
});
defineEmits(['select']);
// Card de provedor de IA com logo oficial (chip branco) estilo console.
defineOptions({ name: 'AiProviderCard' });
const BRANDS = ['openai', 'anthropic', 'google'];
</script>

<template>
  <button
    type="button"
    class="flex relative gap-3 items-center p-4 w-full text-left rounded-2xl border backdrop-blur-xl backdrop-saturate-150 transition-all duration-300 active:scale-[.98]"
    :class="
      selected
        ? 'border-n-brand bg-n-brand/[0.07] ring-2 ring-n-brand/30 shadow-lg'
        : 'border-n-weak bg-n-solid-1/60 shadow-md hover:-translate-y-0.5 hover:bg-n-solid-1/80 hover:border-n-slate-7 hover:shadow-lg'
    "
    @click="$emit('select')"
  >
    <span
      v-if="BRANDS.includes(provider)"
      class="grid flex-none place-items-center bg-white rounded-[9px] border border-n-weak size-9"
    >
      <span v-if="provider === 'openai'" class="i-logos-openai-icon size-5" />
      <span
        v-else-if="provider === 'anthropic'"
        class="i-logos-anthropic-icon size-5"
      />
      <span v-else class="i-logos-google-gemini size-5" />
    </span>
    <span
      v-else
      class="grid flex-none place-items-center text-white rounded-[9px] size-9"
      :style="{ background: color }"
    >
      <span :class="icon" class="size-[18px]" />
    </span>
    <span class="min-w-0">
      <span class="block text-sm font-bold truncate text-n-slate-12">{{
        name
      }}</span>
      <span class="block text-[11.5px] text-n-slate-11 truncate">{{
        desc
      }}</span>
    </span>
    <span
      v-if="selected"
      class="absolute top-3 right-3 i-lucide-check size-4 text-n-brand"
    />
  </button>
</template>
