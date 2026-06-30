<script setup>
// Input iOS. secret=true → mascara com olho de mostrar/ocultar.
import { ref } from 'vue';

defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  secret: { type: Boolean, default: false },
});
defineEmits(['update:modelValue']);
defineOptions({ name: 'AiField' });
const reveal = ref(false);
</script>

<template>
  <div class="relative">
    <input
      :value="modelValue"
      :type="secret && !reveal ? 'password' : 'text'"
      :placeholder="placeholder"
      autocomplete="new-password"
      name="api-key"
      data-lpignore="true"
      data-1p-ignore
      data-form-type="other"
      class="reset-base px-3.5 py-2.5 w-full text-sm rounded-xl border outline-none transition border-n-weak bg-n-solid-1 text-n-slate-12 focus:border-n-brand focus:ring-2 focus:ring-n-brand/30"
      :class="secret ? 'pr-10 font-mono tracking-wide' : ''"
      @input="$emit('update:modelValue', $event.target.value)"
    />
    <button
      v-if="secret"
      type="button"
      class="grid absolute right-2 top-1/2 place-items-center rounded-lg -translate-y-1/2 size-7 text-n-slate-10 hover:bg-n-alpha-2"
      @click="reveal = !reveal"
    >
      <span
        :class="reveal ? 'i-lucide-eye-off' : 'i-lucide-eye'"
        class="size-4"
      />
    </button>
  </div>
</template>
