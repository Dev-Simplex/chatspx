<script setup>
import Label from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  id: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  isActive: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  disabledLabel: {
    type: String,
    default: '',
  },
  disabledMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['select']);

const handleChange = () => {
  if (!props.isActive && !props.disabled) {
    emit('select', props.id);
  }
};
</script>

<template>
  <div
    class="cursor-pointer rounded-xl outline outline-1 p-4 transition-all duration-200 bg-n-solid-1 py-4 ltr:pl-4 rtl:pr-4 ltr:pr-6 rtl:pl-6"
    :class="[
      disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer',
      isActive ? 'outline-n-blue-9' : 'outline-n-weak',
      !disabled && !isActive ? 'hover:outline-n-strong' : '',
    ]"
    @click="handleChange"
  >
    <div class="flex flex-col gap-2 items-start">
      <div class="flex items-center justify-between w-full gap-3">
        <div class="flex items-center gap-2">
          <h3 :id="`${id}-label`" class="text-heading-3 text-n-slate-12">
            {{ label }}
          </h3>
          <Label v-if="disabled" :label="disabledLabel" color="amber" compact />
        </div>
        <!--
          O radio precisa de NOME ACESSIVEL proprio. O texto visivel mora no <h3> ao lado e,
          sem associacao explicita, o axe acusa `label` como violacao SERIA e o leitor de tela
          anuncia so "botao de opcao" — a pessoa nao sabe qual opcao esta escolhendo. Medido em
          Chromium na tela de gatilhos: 5 de uma vez (#approach-discreet, #approach-bold,
          #approach-aggressive, #mode-recommended, #mode-advanced).
          `aria-labelledby` e nao `aria-label` porque o texto JA existe na tela: duplica-lo
          criaria duas fontes que divergem na proxima traducao.
        -->
        <input
          :id="`${id}`"
          :checked="isActive"
          :value="id"
          :name="id"
          :disabled="disabled"
          :aria-labelledby="`${id}-label`"
          :aria-describedby="`${id}-description`"
          type="radio"
          class="h-4 w-4 border-n-slate-6 text-n-brand focus:ring-n-brand focus:ring-offset-0 flex-shrink-0"
          @change="handleChange"
        />
      </div>
      <p :id="`${id}-description`" class="text-body-main text-n-slate-11">
        {{ disabled && disabledMessage ? disabledMessage : description }}
      </p>
      <slot />
    </div>
  </div>
</template>
