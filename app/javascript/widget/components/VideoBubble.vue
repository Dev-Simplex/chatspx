<script setup>
// Bloco 2.03 — o horário saiu daqui pelo mesmo motivo do `ImageBubble`, e aqui
// ele ainda cobria a barra de controles do vídeo, no canto inferior direito.
// Quem o desenha agora é a linha da mensagem, fora do balão.
defineProps({
  url: { type: String, default: '' },
});

const emit = defineEmits(['error']);

const onVideoError = () => {
  emit('error');
};
</script>

<template>
  <div class="block max-w-full">
    <video
      class="w-full max-w-[250px] h-auto"
      :src="url"
      controls
      @error="onVideoError"
    />
  </div>
</template>
