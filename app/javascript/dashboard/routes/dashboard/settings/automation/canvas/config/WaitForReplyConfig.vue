<script setup>
// Editor do nó `wait_for_reply` (F2): suspende o fluxo esperando a resposta do contato e
// RAMIFICA por opção. Persiste em:
//   node.replies      = [{ key, label }]              // uma saída por resposta esperada
//   node.timeout      = { enabled, value, unit }      // saída extra quando o prazo expira
//   node.fallback_key = 'fallback'                    // saída "sem correspondência"
// Acoplamento EXATO com o backend (plano/F2-contrato-wait-for-reply.md):
//   • reply.key = o `value` da opção do send_interactive anterior = o id que o WhatsApp devolve
//     na resposta = `edge.branch`. Por isso o canvas pré-preenche as respostas a partir do bloco
//     send_interactive (FlowCanvasView#addNode), mas aqui elas são editáveis.
//   • timeout ⇒ aresta com branch 'timeout'. unit ∈ minutes|hours|days.
//   • fallback ⇒ aresta SEM branch (o RunnerService cai na aresta sem rótulo quando a resposta
//     não casa nenhuma porta). O fallback não aparece como linha editável — é uma saída fixa.
// Espelha o padrão de hidratação/emite do RouterConfig e o toggle de tempo do WaitConfig.
import { ref, computed, nextTick, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
  // Opções do bloco `send_interactive` que desemboca neste nó (NodeConfigPanel deriva via
  // interactiveOptionsForWait). Havendo opções, o campo "valor" vira um SELECT — o `key` tem de
  // ser byte-a-byte igual ao `value` enviado, e digitá-lo à mão é a fonte clássica de erro
  // (um acento, um espaço no fim) que joga a resposta certa no fallback.
  sourceOptions: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const TIMEOUT_DEFAULTS = { enabled: false, value: 1, unit: 'hours' };
const UNITS = ['minutes', 'hours', 'days'];

const replies = ref([]);
const timeout = ref({ ...TIMEOUT_DEFAULTS });
const fallbackKey = ref('fallback');
// Trava a emissão durante a (re)hidratação a partir do nó, evitando eco de update.
let isHydrating = false;

// Próximo key estável reply_N para respostas adicionadas MANUALMENTE (sem opção correspondente):
// garante um id de porta não-vazio. As respostas pré-preenchidas já trazem key = value da opção.
const nextReplyKey = () => {
  const used = replies.value
    .map(reply => parseInt(String(reply.key).replace(/\D/g, ''), 10) || 0)
    .concat(0);
  return `reply_${Math.max(...used) + 1}`;
};

const hydrateFromNode = () => {
  isHydrating = true;
  const stored = Array.isArray(props.node.replies) ? props.node.replies : [];
  replies.value = stored.map(reply => ({
    key: String(reply.key ?? ''),
    label: reply.label || '',
  }));
  timeout.value = { ...TIMEOUT_DEFAULTS, ...(props.node.timeout || {}) };
  fallbackKey.value = props.node.fallback_key || 'fallback';
  nextTick(() => {
    isHydrating = false;
  });
};

const addReply = () => {
  replies.value = [...replies.value, { key: nextReplyKey(), label: '' }];
};

const removeReply = index => {
  replies.value = replies.value.filter((_, i) => i !== index);
};

// Reordena uma resposta (delta -1 sobe, +1 desce). A ordem aqui é a ordem das PORTAS de saída
// desenhadas no nó; trocar de lugar não mexe em `key`, então nenhuma aresta conectada se perde.
const moveReply = (index, delta) => {
  const target = index + delta;
  if (target < 0 || target >= replies.value.length) return;
  const next = [...replies.value];
  [next[index], next[target]] = [next[target], next[index]];
  replies.value = next;
};

const hasSourceOptions = computed(() => props.sourceOptions.length > 0);

// Chaves já usadas nas OUTRAS linhas: a mesma opção não pode virar duas portas (o Runner casaria
// sempre a primeira e a segunda porta ficaria morta).
const keysUsedElsewhere = index =>
  new Set(
    replies.value.filter((_, i) => i !== index).map(reply => String(reply.key))
  );

// Opções do select de uma linha: as do bloco interativo (menos as já usadas em outras linhas) +
// a chave ATUAL da linha, mesmo que não exista mais no bloco — nunca descartamos em silêncio um
// valor já salvo, senão a aresta conectada a ele sumiria ao abrir o editor.
const keyOptionsFor = index => {
  const used = keysUsedElsewhere(index);
  const current = String(replies.value[index]?.key ?? '');
  const options = props.sourceOptions
    .filter(option => !used.has(String(option.key)))
    .map(option => ({
      id: String(option.key),
      name: option.label
        ? `${option.label} — ${option.key}`
        : String(option.key),
    }));
  if (current && !options.some(option => option.id === current)) {
    options.unshift({
      id: current,
      name: t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.KEY_CUSTOM', {
        key: current,
      }),
    });
  }
  return options;
};

// SingleSelect trabalha com o OBJETO da opção ({ id, name }), não com o id cru.
const keyOptionFor = index => {
  const current = String(replies.value[index]?.key ?? '');
  return (
    keyOptionsFor(index).find(option => option.id === current) || {
      id: '',
      name: '',
    }
  );
};

const setKey = (index, option) => {
  const key = String(option?.id ?? '');
  replies.value = replies.value.map((reply, i) =>
    i === index ? { ...reply, key } : reply
  );
};

// Repõe as respostas a partir das opções do bloco interativo ligado (o mesmo pré-preenchimento
// que o canvas faz ao criar o nó logo depois de um `send_interactive`). Serve para quando o
// usuário edita as opções DEPOIS de já ter criado o wait — sem isso, sobra chave órfã.
const syncFromSource = () => {
  if (!hasSourceOptions.value) return;
  const labelByKey = new Map(
    replies.value.map(reply => [String(reply.key), reply.label])
  );
  replies.value = props.sourceOptions.map(option => ({
    key: String(option.key),
    label: labelByKey.get(String(option.key)) || option.label || '',
  }));
};

const unitOptions = computed(() => [
  { id: 'minutes', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_MINUTES') },
  { id: 'hours', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_HOURS') },
  { id: 'days', name: t('AUTOMATION.CANVAS.CONFIG.WAIT.UNIT_DAYS') },
]);

const timeoutEnabled = computed({
  get() {
    return Boolean(timeout.value.enabled);
  },
  set(value) {
    timeout.value = { ...timeout.value, enabled: Boolean(value) };
  },
});

const timeoutValue = computed({
  get() {
    return timeout.value.value;
  },
  set(value) {
    const parsed = Number.parseInt(value, 10);
    timeout.value = {
      ...timeout.value,
      value: Number.isNaN(parsed) || parsed < 1 ? 1 : parsed,
    };
  },
});

const unitModel = computed({
  get() {
    return (
      unitOptions.value.find(opt => opt.id === timeout.value.unit) ||
      unitOptions.value[1]
    );
  },
  set(value) {
    timeout.value = { ...timeout.value, unit: value?.id || 'hours' };
  },
});

onMounted(() => hydrateFromNode());

// Troca de nó selecionado: re-hidrata a partir do novo nó.
watch(
  () => props.node.id,
  () => hydrateFromNode()
);

// Qualquer edição (respostas ou timeout) → persiste a forma canônica no nó.
const persist = () => {
  if (isHydrating) return;
  emit('update', {
    replies: replies.value.map(reply => ({
      key: String(reply.key ?? ''),
      label: (reply.label || '').trim(),
    })),
    timeout: {
      enabled: Boolean(timeout.value.enabled),
      value:
        Number.isInteger(timeout.value.value) && timeout.value.value >= 1
          ? timeout.value.value
          : 1,
      unit: UNITS.includes(timeout.value.unit) ? timeout.value.unit : 'hours',
    },
    fallback_key: fallbackKey.value || 'fallback',
  });
};

watch(replies, persist, { deep: true });
watch(timeout, persist, { deep: true });
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-wait-for-reply">
    <p class="text-xs leading-snug text-n-slate-10">
      {{ t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.HINT') }}
    </p>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.REPLIES_LABEL')"
    >
      <ul class="flex flex-col gap-2.5 p-0 m-0 list-none">
        <li
          v-for="(reply, ri) in replies"
          :key="ri"
          class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
          :data-testid="`wait-for-reply-item-${ri}`"
        >
          <div class="flex items-center gap-1.5">
            <span
              class="text-[10px] font-bold tracking-wider uppercase text-n-slate-10 shrink-0"
            >
              {{
                t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.REPLY_N', {
                  n: ri + 1,
                })
              }}
            </span>
            <span class="flex-1" />
            <NextButton
              icon="i-lucide-arrow-up"
              ghost
              slate
              xs
              :disabled="ri === 0"
              :aria-label="t('AUTOMATION.CANVAS.MOVE_UP')"
              :title="t('AUTOMATION.CANVAS.MOVE_UP')"
              :data-testid="`wait-for-reply-up-${ri}`"
              @click="moveReply(ri, -1)"
            />
            <NextButton
              icon="i-lucide-arrow-down"
              ghost
              slate
              xs
              :disabled="ri === replies.length - 1"
              :aria-label="t('AUTOMATION.CANVAS.MOVE_DOWN')"
              :title="t('AUTOMATION.CANVAS.MOVE_DOWN')"
              :data-testid="`wait-for-reply-down-${ri}`"
              @click="moveReply(ri, 1)"
            />
            <NextButton
              icon="i-lucide-trash"
              ghost
              ruby
              xs
              :aria-label="
                t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.REMOVE_REPLY')
              "
              :data-testid="`wait-for-reply-remove-${ri}`"
              @click="removeReply(ri)"
            />
          </div>

          <Input
            v-model="reply.label"
            size="sm"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.LABEL_PLACEHOLDER')
            "
          />
          <template v-if="hasSourceOptions">
            <SingleSelect
              :model-value="keyOptionFor(ri)"
              disable-deselect
              :options="keyOptionsFor(ri)"
              :data-testid="`wait-for-reply-key-select-${ri}`"
              @update:model-value="setKey(ri, $event)"
            />
            <span class="text-xs leading-snug text-n-slate-10">
              {{ t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.KEY_SELECT_HINT') }}
            </span>
          </template>
          <Input
            v-else
            v-model="reply.key"
            size="sm"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.KEY_PLACEHOLDER')
            "
            :message="t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.KEY_HINT')"
            message-type="info"
          />
        </li>
      </ul>

      <div class="flex flex-wrap gap-2 mt-2.5">
        <NextButton
          icon="i-lucide-plus"
          blue
          faded
          sm
          :label="t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.ADD_REPLY')"
          data-testid="wait-for-reply-add"
          @click="addReply"
        />
        <NextButton
          v-if="hasSourceOptions"
          icon="i-lucide-refresh-cw"
          slate
          faded
          sm
          :label="
            t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.SYNC_FROM_INTERACTIVE')
          "
          :title="
            t(
              'AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.SYNC_FROM_INTERACTIVE_HINT'
            )
          "
          data-testid="wait-for-reply-sync"
          @click="syncFromSource"
        />
      </div>
    </ConfigField>

    <div class="flex flex-col gap-3 pt-1 border-t border-n-weak">
      <label
        class="flex items-center justify-between gap-3 pt-3 cursor-pointer"
        data-testid="wait-for-reply-timeout-toggle"
      >
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.TIMEOUT_LABEL') }}
        </span>
        <Switch v-model="timeoutEnabled" />
      </label>
      <span class="text-xs leading-snug text-n-slate-10">
        {{ t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.TIMEOUT_HINT') }}
      </span>

      <div v-if="timeoutEnabled" class="flex gap-2">
        <Input
          v-model="timeoutValue"
          type="number"
          size="sm"
          min="1"
          class="w-24"
          :placeholder="
            t(
              'AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.TIMEOUT_VALUE_PLACEHOLDER'
            )
          "
        />
        <div class="flex-1">
          <SingleSelect
            v-model="unitModel"
            disable-search
            disable-deselect
            :options="unitOptions"
          />
        </div>
      </div>
    </div>

    <div
      class="flex items-start gap-2 px-3 py-2 text-xs border border-dashed rounded-lg text-n-slate-11 border-n-weak"
      data-testid="wait-for-reply-outputs-hint"
    >
      <span class="mt-1 rounded-full size-1.5 shrink-0 bg-n-slate-8" />
      {{ t('AUTOMATION.CANVAS.CONFIG.WAIT_FOR_REPLY.OUTPUTS_HINT') }}
    </div>
  </div>
</template>
