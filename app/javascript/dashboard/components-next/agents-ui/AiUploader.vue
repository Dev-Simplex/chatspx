<script setup>
import { ref } from 'vue';
// Zona de upload iOS: clique ou arrastar-soltar. Emite 'select' com o File.
defineProps({
  accept: { type: String, default: '' },
  hint: { type: String, default: '' },
});
const emit = defineEmits(['select']);
defineOptions({ name: 'AiUploader' });
const input = ref(null);
const over = ref(false);
const fileName = ref('');
const pick = f => {
  if (!f) return;
  fileName.value = f.name;
  emit('select', f);
};
const onChange = e => pick(e.target.files && e.target.files[0]);
const onDrop = e => {
  over.value = false;
  pick(e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]);
};
</script>

<template>
  <div
    class="flex flex-col items-center px-4 py-6 text-center rounded-xl border-2 border-dashed transition cursor-pointer"
    :class="
      over
        ? 'border-n-brand bg-n-brand/5'
        : 'border-n-weak bg-n-alpha-1 hover:border-n-slate-8'
    "
    @click="input.click()"
    @dragover.prevent="over = true"
    @dragleave="over = false"
    @drop.prevent="onDrop"
  >
    <span
      class="mb-2 i-lucide-upload-cloud size-7"
      :class="over ? 'text-n-brand' : 'text-n-slate-10'"
    />
    <p class="text-[13px] font-semibold text-n-slate-12">
      {{ fileName || hint }}
    </p>
    <input
      ref="input"
      type="file"
      :accept="accept"
      class="hidden"
      @change="onChange"
    />
  </div>
</template>
