<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  options: {
    type: Array,
    default: () => [],
    validator: options =>
      options.every(
        opt => typeof opt === 'object' && 'value' in opt && 'label' in opt
      ),
  },
  groups: {
    type: Array,
    default: () => [],
    validator: groups =>
      groups.every(
        group =>
          'label' in group &&
          Array.isArray(group.options) &&
          group.options.every(opt => 'value' in opt && 'label' in opt)
      ),
  },
  placeholder: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: '',
  },
  // Sem estes dois, o <select> INTERNO nao tinha como receber nome acessivel: atributo
  // solto no componente cai na <div> raiz, nao no controle. Era por isso que os <label>
  // dos formularios que usam este Select ficavam orfaos — nao havia `for` a apontar nem
  // `aria-label` a passar, e o conserto era impossivel no ponto de uso.
  // Opcionais e sem default visivel: quem ja usa o componente nao muda em nada.
  id: {
    type: String,
    default: undefined,
  },
  ariaLabel: {
    type: String,
    default: undefined,
  },
});

const modelValue = defineModel({
  type: [String, Number, Boolean],
  default: '',
});
</script>

<template>
  <div class="w-fit relative">
    <select
      :id="id"
      v-model="modelValue"
      :aria-label="ariaLabel"
      :disabled="disabled"
      class="appearance-none bg-none rounded-lg border-0 outline-1 outline -outline-offset-1 transition-all duration-200 bg-n-surface-1 !mb-0 py-2 px-3 pr-10 text-sm"
      :class="{
        'outline-n-weak hover:outline-n-slate-6 focus:outline-n-blue-9':
          !error && !disabled,
        'outline-n-ruby-9 focus:outline-n-ruby-9': error && !disabled,
        'outline-n-weak bg-n-slate-2 cursor-not-allowed opacity-60': disabled,
      }"
    >
      <option v-if="placeholder" value="" disabled>
        {{ placeholder }}
      </option>
      <template v-if="groups.length">
        <optgroup
          v-for="group in groups"
          :key="group.label"
          :label="group.label"
        >
          <option
            v-for="option in group.options"
            :key="option.value"
            :value="option.value"
            :disabled="option.disabled"
          >
            {{ option.label }}
          </option>
        </optgroup>
      </template>
      <template v-else>
        <option
          v-for="option in options"
          :key="option.value"
          :value="option.value"
          :disabled="option.disabled"
        >
          {{ option.label }}
        </option>
      </template>
    </select>
    <div
      class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none"
    >
      <Icon
        icon="i-lucide-chevron-down"
        class="size-4 text-n-slate-11"
        :class="{ 'opacity-50': disabled }"
      />
    </div>
  </div>
</template>
