<script setup>
import { GLASS_CARD, SECTION_TITLE, SECTION_SUB } from './styles';

// Cartao de secao dos Relatorios: titulo forte, subtitulo curto, acoes a direita e o conteudo.
defineProps({
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
});
</script>

<template>
  <section class="flex flex-col p-5 min-w-0" :class="GLASS_CARD">
    <div
      v-if="title || $slots.actions"
      class="flex flex-wrap items-start justify-between gap-3"
    >
      <div class="min-w-0">
        <h2 :class="SECTION_TITLE">{{ title }}</h2>
        <p v-if="subtitle" :class="SECTION_SUB">{{ subtitle }}</p>
      </div>
      <div v-if="$slots.actions" class="flex items-center gap-2 shrink-0">
        <slot name="actions" />
      </div>
    </div>
    <slot />
  </section>
</template>
