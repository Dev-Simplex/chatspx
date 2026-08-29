<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import {
  DEFAULT_VISITOR,
  DEVICES,
  TRIGGER_LIMITS,
  URL_OPERATORS,
  UTM_PARAMS,
  VISITOR_KINDS,
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

/**
 * UTM (T3.2). O que fica GRAVADO e `{ utm_source: ['newsletter'], ... }` — a forma
 * que o schema aceita. O que a tela edita e uma LISTA DE LINHAS, porque
 * `origem = newsletter` e a frase que o administrador tem na cabeca; ninguem pensa
 * em "um objeto de arrays".
 *
 * As linhas sao estado LOCAL, e nao um computed sobre a prop, por um motivo
 * medido: `minLength: 1` no schema recusa valor vazio, entao uma linha recem
 * acrescentada NAO PODE entrar no rascunho enquanto estiver em branco — ela
 * derrubaria o PATCH inteiro com 422 num campo que o administrador ainda esta
 * preenchendo. A linha vazia existe na tela e nao existe no payload.
 */
const linhasUtm = ref([]);

/**
 * Reconstroi as linhas a partir do que esta no rascunho — E PRESERVA as em
 * branco. Sem essa segunda metade a tela ficava impossivel de usar: acrescentar
 * uma linha emite `update`, o `update` muda a prop, o watch dispara e a linha
 * recem-criada (que, por ser vazia, nao esta no payload) desaparecia no mesmo
 * quadro. O botao "adicionar" nao fazia nada visivel.
 */
const sincronizarUtm = () => {
  const gravado = props.audience.utm ?? {};
  const doRascunho = UTM_PARAMS.flatMap(param =>
    (gravado[param] ?? []).map(value => ({ param, value }))
  );
  const emBranco = linhasUtm.value.filter(linha => !linha.value);
  linhasUtm.value = [...doRascunho, ...emBranco];
};

watch(() => props.audience.utm, sincronizarUtm, {
  immediate: true,
  deep: true,
});

/** Escreve so o que tem valor: linha em branco fica na tela, fora do rascunho. */
const gravarUtm = linhas => {
  linhasUtm.value = linhas;
  const proximo = {};
  linhas.forEach(({ param, value }) => {
    if (!param || !value) return;
    proximo[param] = [...(proximo[param] ?? []), value];
  });
  emit('update', { ...props.audience, utm: proximo });
};

const utmOptions = computed(() =>
  UTM_PARAMS.map(value => ({
    value,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.PARAMS.${value.toUpperCase()}`
    ),
  }))
);

const setUtmRow = (indice, patch) =>
  gravarUtm(
    linhasUtm.value.map((linha, i) =>
      i === indice ? { ...linha, ...patch } : linha
    )
  );

const addUtmRow = () => {
  if (linhasUtm.value.length >= TRIGGER_LIMITS.utmValuesMax) return;
  gravarUtm([...linhasUtm.value, { param: UTM_PARAMS[0], value: '' }]);
};

const removeUtmRow = indice =>
  gravarUtm(linhasUtm.value.filter((_, i) => i !== indice));

/**
 * Visitante novo ou recorrente (T3.2). `any` NAO e gravado: a ausencia de
 * criterio nao merece uma chave no banco, e gravar `'any'` faria toda inbox
 * que abriu esta tela carregar um filtro que nao filtra nada.
 */
const visitor = computed(() => props.audience.visitor ?? DEFAULT_VISITOR);

const setVisitor = kind => {
  const proximo = { ...props.audience };
  if (kind === DEFAULT_VISITOR) delete proximo.visitor;
  else proximo.visitor = kind;
  emit('update', proximo);
};

const visitorLabel = kind =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.TRIGGERS.AUDIENCE.VISITOR.KINDS.${kind.toUpperCase()}`);
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
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.LABEL') }}
      </span>
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.HINT') }}
      </p>

      <div class="flex flex-col gap-2">
        <div
          v-for="(linha, indice) in linhasUtm"
          :key="`utm-${indice}`"
          class="flex items-center gap-2"
          :data-testid="`utm-row-${indice}`"
        >
          <label class="block w-40">
            <span class="sr-only">
              {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.PARAM_LABEL') }}
            </span>
            <SelectInput
              :model-value="linha.param"
              :options="utmOptions"
              :data-testid="`utm-param-${indice}`"
              @update:model-value="setUtmRow(indice, { param: $event })"
            />
          </label>
          <Input
            class="max-w-xs"
            :model-value="linha.value"
            :placeholder="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.PLACEHOLDER')"
            :aria-label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.VALUE_LABEL')"
            :data-testid="`utm-value-${indice}`"
            @update:model-value="setUtmRow(indice, { value: $event })"
          />
          <NextButton
            faded
            slate
            :label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.REMOVE')"
            :data-testid="`utm-remove-${indice}`"
            @click="removeUtmRow(indice)"
          />
        </div>

        <div>
          <NextButton
            faded
            slate
            :label="t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.ADD')"
            :disabled="linhasUtm.length >= TRIGGER_LIMITS.utmValuesMax"
            data-testid="utm-add"
            @click="addUtmRow"
          />
          <p
            v-if="linhasUtm.length >= TRIGGER_LIMITS.utmValuesMax"
            class="mt-1 text-sm text-n-slate-11"
            data-testid="utm-too-many"
          >
            {{
              t('INBOX_WIDGET.TRIGGERS.AUDIENCE.UTM.TOO_MANY', {
                max: TRIGGER_LIMITS.utmValuesMax,
              })
            }}
          </p>
        </div>
      </div>
    </div>

    <!-- fieldset/legend, e nao um <span> solto: os tres radios sao UMA
         pergunta, e o leitor de tela precisa anunciar a pergunta antes das
         respostas. E o mesmo motivo do `aria-labelledby` que o RadioCard ganhou
         no 1.06 — aqui o elemento nativo ja resolve, sem componente. -->
    <fieldset class="flex flex-col gap-2" data-testid="visitor-field">
      <legend class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.VISITOR.LABEL') }}
      </legend>
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_WIDGET.TRIGGERS.AUDIENCE.VISITOR.HINT') }}
      </p>
      <div class="flex flex-wrap gap-4">
        <div
          v-for="kind in VISITOR_KINDS"
          :key="kind"
          class="flex items-center gap-2"
        >
          <input
            :id="`visitor-${kind}`"
            type="radio"
            name="audience-visitor"
            :value="kind"
            :checked="visitor === kind"
            :data-testid="`visitor-${kind}`"
            class="w-4 h-4 border-n-slate-6 text-n-brand focus:ring-n-brand focus:ring-offset-0"
            @change="setVisitor(kind)"
          />
          <label :for="`visitor-${kind}`" class="text-sm text-n-slate-11">
            {{ visitorLabel(kind) }}
          </label>
        </div>
      </div>
    </fieldset>

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
