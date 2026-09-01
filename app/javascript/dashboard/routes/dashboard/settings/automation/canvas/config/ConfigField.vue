<script setup>
// Campo rotulado do painel de configuração: label em cima, controle no slot, dica opcional
// embaixo. Mantém o espaçamento consistente entre todos os editores de nó.
//
// A raiz é um <div role="group">, NÃO um <label>. Um <label> sem `for` é um rótulo IMPLÍCITO:
// o clique em QUALQUER ponto dele é reencaminhado pelo navegador ao primeiro descendente
// "labelable" (button, input, select, textarea, meter, output, progress). Nos editores de
// lista (Enviar opções, Aguardar resposta, Roteador, Classificar com IA, HTTP…) o primeiro
// labelable é o BOTÃO DE LIXEIRA do item 1 — então clicar no espaço vazio do campo, no texto
// "Opções" ou na borda de um item APAGAVA o item 1 sem o usuário encostar na lixeira. Com
// <div> o clique não é reencaminhado; a associação acessível fica por role/aria-label.
defineProps({
  label: {
    type: String,
    default: '',
  },
  hint: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex flex-col gap-1.5"
    role="group"
    :aria-label="label || undefined"
  >
    <span
      v-if="label"
      class="text-xs font-medium text-n-slate-11"
      data-testid="config-field-label"
    >
      {{ label }}
    </span>
    <slot />
    <span v-if="hint" class="text-xs leading-snug text-n-slate-10">
      {{ hint }}
    </span>
  </div>
</template>
