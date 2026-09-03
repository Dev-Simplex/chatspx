<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import {
  DEVICES,
  TRIGGER_LIMITS,
  URL_OPERATORS,
} from '../composables/widgetTriggersContract';

/**
 * Onde o convite aparece: endereco da pagina, e em que dispositivos.
 *
 * A tela avisa, em uma linha, que **estas regras sao publicas** — elas viajam
 * no payload de boot e ficam legiveis no codigo-fonte do site do cliente. A
 * avaliacao e do SDK, no navegador do visitante (arbitragem A5), e isso e uma
 * escolha, nao um descuido: todos os criterios da v1 sao observaveis pelo
 * proprio navegador. Proteger a lista de URLs de quem ESTA naquela URL seria
 * cerimonia.
 */
const props = defineProps({
  audience: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const url = computed(() => props.audience.url ?? {});
const values = computed(() => url.value.values ?? []);
const devices = computed(() => props.audience.device ?? [...DEVICES]);

const operatorOptions = computed(() =>
  URL_OPERATORS.map(value => ({
    value,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(`INBOX_WIDGET.TRIGGERS.AUDIENCE.OPERATORS.${value.toUpperCase()}`),
  }))
);

const setUrl = patch =>
  emit('update', { ...props.audience, url: { ...url.value, ...patch } });

const setValue = (indice, valor) => {
  const proximos = [...values.value];
  proximos[indice] = valor;
  setUrl({ values: proximos });
};

const addValue = () => {
  if (values.value.length >= TRIGGER_LIMITS.urlValuesMax) return;
  setUrl({
    operator: url.value.operator ?? URL_OPERATORS[0],
    values: [...values.value, ''],
  });
};

const removeValue = indice =>
  setUrl({ values: values.value.filter((_, i) => i !== indice) });

const deviceLabel = device =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.TRIGGERS.AUDIENCE.DEVICES.${device.toUpperCase()}`);

const toggleDevice = device => {
  const proximos = devices.value.includes(device)
    ? devices.value.filter(item => item !== device)
    : [...devices.value, device];
  emit('update', { ...props.audience, device: proximos });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <!-- mesma razao do aviso amber: o tom 11 da escala reprova AA no tema
         claro, e o aviso que ninguem le nao protege ninguem -->
    <Banner color="slate" data-testid="public-warning">
      <span class="text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.PUBLIC_WARNING') }}
      </span>
    </Banner>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_LABEL') }}
      </span>
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_HINT') }}
      </p>

      <div class="flex flex-col gap-2">
        <label class="block max-w-xs">
          <span class="sr-only">
            {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_LABEL') }}
          </span>
          <SelectInput
            :model-value="url.operator ?? URL_OPERATORS[0]"
            :options="operatorOptions"
            data-testid="url-operator"
            @update:model-value="setUrl({ operator: $event })"
          />
        </label>

        <div
          v-for="(value, indice) in values"
          :key="indice"
          class="flex items-center gap-2"
        >
          <Input
            class="max-w-md"
            :model-value="value"
            :placeholder="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_PLACEHOLDER')"
            :aria-label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_LABEL')"
            :data-testid="`url-value-${indice}`"
            @update:model-value="setValue(indice, $event)"
          />
          <NextButton
            faded
            slate
            :label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.REMOVE')"
            :data-testid="`url-remove-${indice}`"
            @click="removeValue(indice)"
          />
        </div>

        <div>
          <NextButton
            faded
            slate
            :label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_ADD')"
            :disabled="values.length >= TRIGGER_LIMITS.urlValuesMax"
            data-testid="url-add"
            @click="addValue"
          />
          <p
            v-if="values.length >= TRIGGER_LIMITS.urlValuesMax"
            class="mt-1 text-sm text-n-slate-11"
            data-testid="url-too-many"
          >
            {{
              t('INBOX_WIDGET.TRIGGERS.AUDIENCE.URL_TOO_MANY', {
                max: TRIGGER_LIMITS.urlValuesMax,
              })
            }}
          </p>
        </div>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.DEVICE_LABEL') }}
      </span>
      <div class="flex gap-4">
        <div
          v-for="device in DEVICES"
          :key="device"
          class="flex items-center gap-2"
        >
          <input
            :id="`device-${device}`"
            type="checkbox"
            :checked="devices.includes(device)"
            :data-testid="`device-${device}`"
            @change="toggleDevice(device)"
          />
          <label :for="`device-${device}`" class="text-sm text-n-slate-11">
            {{ deviceLabel(device) }}
          </label>
        </div>
      </div>
      <Banner v-if="!devices.length" color="amber" data-testid="device-empty">
        <span class="text-n-amber-12">
          {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.DEVICE_EMPTY') }}
        </span>
      </Banner>
    </div>
  </div>
</template>
