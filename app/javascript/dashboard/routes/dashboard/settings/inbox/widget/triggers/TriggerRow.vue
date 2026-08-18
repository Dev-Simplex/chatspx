<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  DESKTOP_ONLY_TRIGGERS,
  TRIGGERS_WITHOUT_VALUE,
  TRIGGERS_WITH_SELECTOR,
  TRIGGER_LIMITS,
} from '../composables/widgetTriggersContract';

/**
 * Uma linha da tabela dos sete gatilhos: ligar/desligar por dispositivo, o
 * valor, o intervalo e — nos dois gatilhos que apontam para o DOM do cliente —
 * o seletor CSS.
 *
 * O seletor e validado no BLUR, nao a cada tecla: validar enquanto se digita
 * transforma todo seletor pela metade em erro vermelho, e o administrador
 * aprende a ignorar o vermelho. E a validacao e so de SINTAXE — o site e do
 * cliente, e nos nao temos o DOM dele para dizer se o elemento existe.
 */
const props = defineProps({
  trigger: { type: Object, required: true },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const selectorError = ref('');

const id = computed(() => props.trigger.id);
const chave = computed(() => id.value.toUpperCase());

const hasValue = computed(() => !TRIGGERS_WITHOUT_VALUE.includes(id.value));
const hasSelector = computed(() => TRIGGERS_WITH_SELECTOR.includes(id.value));
const isDesktopOnly = computed(() => DESKTOP_ONLY_TRIGGERS.includes(id.value));

const plataforma = nome => props.trigger[nome] ?? {};

const setPlatform = (nome, patch) =>
  emit('update', {
    ...props.trigger,
    [nome]: { ...plataforma(nome), ...patch },
  });

const setValue = (nome, bruto) => {
  const numero = Number.parseInt(bruto, 10);
  if (Number.isNaN(numero)) return;
  setPlatform(nome, {
    value: Math.min(
      TRIGGER_LIMITS.valueMax,
      Math.max(TRIGGER_LIMITS.valueMin, numero)
    ),
  });
};

/**
 * `document.querySelector` e o mesmo motor que o SDK vai usar no site do
 * cliente: se ele lanca aqui, lancaria la. A mensagem mostra a razao REAL do
 * parser, nao um texto nosso — quem escreveu o seletor precisa saber onde
 * errou.
 */
const validateSelector = () => {
  const valor = (plataforma('desktop').selector ?? '').trim();

  if (!valor) {
    selectorError.value = t('INBOX_WIDGET.TRIGGERS.SELECTOR.EMPTY');
    return;
  }
  if (valor.length > TRIGGER_LIMITS.selectorMaxLength) {
    selectorError.value = t('INBOX_WIDGET.TRIGGERS.SELECTOR.INVALID', {
      reason: `> ${TRIGGER_LIMITS.selectorMaxLength}`,
    });
    return;
  }
  try {
    document.querySelector(valor);
    selectorError.value = '';
  } catch (erro) {
    selectorError.value = t('INBOX_WIDGET.TRIGGERS.SELECTOR.INVALID', {
      reason: erro.message,
    });
  }
};

const setSelector = valor => {
  // Escrever nao valida: o erro so aparece quando o campo perde o foco.
  emit('update', {
    ...props.trigger,
    desktop: { ...plataforma('desktop'), selector: valor },
    mobile: { ...plataforma('mobile'), selector: valor },
  });
};
</script>

<template>
  <div
    class="grid items-start gap-3 py-3 border-b lg:grid-cols-12 border-n-weak"
    :data-testid="`trigger-${id}`"
  >
    <div class="lg:col-span-4">
      <p class="text-sm font-medium text-n-slate-12">
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
        {{ t(`INBOX_WIDGET.TRIGGERS.ITEMS.${chave}.LABEL`) }}
      </p>
      <p class="text-sm text-n-slate-11">
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
        {{ t(`INBOX_WIDGET.TRIGGERS.ITEMS.${chave}.HINT`) }}
      </p>
    </div>

    <div class="flex items-center gap-2 lg:col-span-3">
      <Switch
        :model-value="Boolean(plataforma('desktop').enabled)"
        :aria-label="t('INBOX_WIDGET.TRIGGERS.LIST.DESKTOP')"
        :data-testid="`desktop-${id}`"
        @update:model-value="setPlatform('desktop', { enabled: $event })"
      />
      <Input
        v-if="hasValue"
        type="number"
        class="w-20"
        :model-value="plataforma('desktop').value ?? 0"
        :aria-label="t('INBOX_WIDGET.TRIGGERS.LIST.DESKTOP')"
        :data-testid="`desktop-value-${id}`"
        @update:model-value="setValue('desktop', $event)"
      />
      <span class="text-xs text-n-slate-10">
        <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
        {{ t(`INBOX_WIDGET.TRIGGERS.ITEMS.${chave}.UNIT`) }}
      </span>
    </div>

    <div class="flex items-center gap-2 lg:col-span-3">
      <template v-if="isDesktopOnly">
        <span class="text-xs text-n-slate-10" :data-testid="`mobile-na-${id}`">
          {{ t('INBOX_WIDGET.TRIGGERS.LIST.NOT_AVAILABLE') }}
        </span>
      </template>
      <template v-else>
        <Switch
          :model-value="Boolean(plataforma('mobile').enabled)"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.LIST.MOBILE')"
          :data-testid="`mobile-${id}`"
          @update:model-value="setPlatform('mobile', { enabled: $event })"
        />
        <Input
          v-if="hasValue"
          type="number"
          class="w-20"
          :model-value="plataforma('mobile').value ?? 0"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.LIST.MOBILE')"
          :data-testid="`mobile-value-${id}`"
          @update:model-value="setValue('mobile', $event)"
        />
      </template>
    </div>

    <div class="lg:col-span-2">
      <Input
        type="number"
        class="w-24"
        :model-value="trigger.cooldown_seconds ?? 0"
        :aria-label="t('INBOX_WIDGET.TRIGGERS.LIST.COOLDOWN')"
        :data-testid="`cooldown-${id}`"
        @update:model-value="
          emit('update', {
            ...trigger,
            cooldown_seconds: Math.min(
              TRIGGER_LIMITS.cooldownMax,
              Math.max(TRIGGER_LIMITS.cooldownMin, Number($event) || 0)
            ),
          })
        "
      />
    </div>

    <div
      v-if="hasSelector"
      class="lg:col-span-12"
      :data-testid="`selector-field-${id}`"
    >
      <Input
        class="max-w-lg"
        :model-value="plataforma('desktop').selector ?? ''"
        :label="t('INBOX_WIDGET.TRIGGERS.SELECTOR.LABEL')"
        :placeholder="t('INBOX_WIDGET.TRIGGERS.SELECTOR.PLACEHOLDER')"
        :message="
          selectorError || t('INBOX_WIDGET.TRIGGERS.SELECTOR.SYNTAX_ONLY')
        "
        :message-type="selectorError ? 'error' : 'info'"
        :data-testid="`selector-input-${id}`"
        @update:model-value="setSelector"
        @blur="validateSelector"
      />
    </div>
  </div>
</template>
