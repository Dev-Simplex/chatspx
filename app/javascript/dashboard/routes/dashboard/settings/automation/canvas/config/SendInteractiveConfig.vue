<script setup>
// Editor de `send_interactive` (WhatsApp lista/botões). action_params = [{ content, items }].
//   • content: corpo da mensagem — obrigatório, máx 1024, aceita Liquid ({{contact.name}}).
//   • items:   1..10 opções { title, value, description }. O CANAL decide o formato:
//              ≤3 opções → botões, >3 → lista (Whatsapp::Providers::BaseService). A
//              `description` só aparece em lista; em botões a Meta a ignora.
// Formato EXATO consumido pelo Flows::ActionService#send_interactive:
//   { content: '…', items: [{ title, value, description }, …] }
// Merge-patch canônico (padrão SetAttributeConfig/HttpRequestConfig): cada edição reconstrói
// action_params[0] inteiro a partir dos valores atuais — componente controlado, sem estado
// local/hydration (o nó recém-criado tem action_params vazio; o editor mostra 1 linha vazia
// via fallback e só persiste quando o usuário digita, sem emitir update fantasma ao abrir).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

// Limites oficiais Meta (também validados no backend — última linha de defesa é o canal).
const MAX_ITEMS = 10;
const BODY_MAX = 1024;
const VALUE_MAX = 200;
const DESCRIPTION_MAX = 72;
const TITLE_MAX_BUTTONS = 20; // ≤3 itens → botões
const TITLE_MAX_LIST = 24; // >3 itens → lista

const makeItem = () => ({ title: '', value: '', description: '' });

const config = computed(() => {
  const params = props.node.action_params;
  const first = Array.isArray(params) && params[0] ? params[0] : {};
  return { content: '', items: [], ...first };
});

// Sempre ao menos 1 linha visível (nó novo → action_params vazio).
const items = computed(() => {
  const stored = config.value.items;
  return Array.isArray(stored) && stored.length ? stored : [makeItem()];
});

// >3 itens viram lista (title máx 24 + description); ≤3 viram botões (title máx 20, sem desc).
const isList = computed(() => items.value.length > 3);
const titleMaxlength = computed(() =>
  isList.value ? TITLE_MAX_LIST : TITLE_MAX_BUTTONS
);
const canAddItem = computed(() => items.value.length < MAX_ITEMS);
const canRemoveItem = computed(() => items.value.length > 1);

// Reescreve action_params[0] no formato EXATO { content, items:[{title,value,description}] }.
const patch = partial => {
  emit('update', {
    action_params: [
      { content: config.value.content || '', items: items.value, ...partial },
    ],
  });
};

const content = computed({
  get() {
    return config.value.content || '';
  },
  set(value) {
    patch({ content: value });
  },
});

const updateItem = (index, field, value) => {
  const next = items.value.map((row, i) =>
    i === index ? { ...row, [field]: value } : row
  );
  patch({ items: next });
};

const addItem = () => {
  if (!canAddItem.value) return;
  patch({ items: [...items.value, makeItem()] });
};

const removeItem = index => {
  if (!canRemoveItem.value) return;
  patch({ items: items.value.filter((_, i) => i !== index) });
};

// Reordena uma opção (delta -1 = sobe, +1 = desce). A ORDEM importa duas vezes: é a ordem em
// que o contato vê os botões/linhas da lista e é a ordem das portas de saída do bloco
// `wait_for_reply` seguinte (que deriva as respostas dessas opções). Trocar de lugar NÃO
// mexe em `value`, então nenhuma aresta já conectada se perde.
const moveItem = (index, delta) => {
  const target = index + delta;
  if (target < 0 || target >= items.value.length) return;
  const next = [...items.value];
  [next[index], next[target]] = [next[target], next[index]];
  patch({ items: next });
};

// A Meta RECUSA uma interativa sem corpo ("The parameter interactive.body.text is required")
// e a mensagem nunca chega ao contato — o fluxo fica esperando uma resposta a uma pergunta
// que ninguém viu. Por isso o corpo é obrigatório aqui e bloqueia o salvamento no canvas
// (ver flowValidation.js).
const isBodyMissing = computed(() => !content.value.trim());
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-send-interactive">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.BODY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.VARIABLES_HINT')"
    >
      <textarea
        v-model="content"
        rows="4"
        :maxlength="BODY_MAX"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.BODY_PLACEHOLDER')
        "
        data-testid="config-send-interactive-body"
        :class="
          isBodyMissing
            ? 'outline-n-ruby-8 focus:outline-n-ruby-8'
            : 'outline-n-weak dark:outline-n-strong focus:outline-n-brand'
        "
      />
      <p
        v-if="isBodyMissing"
        class="mt-1 mb-0 text-label-small text-n-ruby-11"
        data-testid="config-send-interactive-body-error"
      >
        {{ t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.BODY_REQUIRED') }}
      </p>
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.ITEMS_LABEL')"
    >
      <ul class="flex flex-col gap-2.5 p-0 m-0 list-none">
        <li
          v-for="(item, ii) in items"
          :key="ii"
          class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
          :data-testid="`send-interactive-item-${ii}`"
        >
          <div class="flex items-center gap-1.5">
            <span
              class="text-[10px] font-bold tracking-wider uppercase text-n-slate-10 shrink-0"
            >
              {{
                t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.OPTION_N', {
                  n: ii + 1,
                })
              }}
            </span>
            <span class="flex-1" />
            <NextButton
              icon="i-lucide-arrow-up"
              ghost
              slate
              xs
              :disabled="ii === 0"
              :aria-label="t('AUTOMATION.CANVAS.MOVE_UP')"
              :title="t('AUTOMATION.CANVAS.MOVE_UP')"
              :data-testid="`send-interactive-up-${ii}`"
              @click="moveItem(ii, -1)"
            />
            <NextButton
              icon="i-lucide-arrow-down"
              ghost
              slate
              xs
              :disabled="ii === items.length - 1"
              :aria-label="t('AUTOMATION.CANVAS.MOVE_DOWN')"
              :title="t('AUTOMATION.CANVAS.MOVE_DOWN')"
              :data-testid="`send-interactive-down-${ii}`"
              @click="moveItem(ii, 1)"
            />
            <NextButton
              icon="i-lucide-trash"
              ghost
              ruby
              xs
              :disabled="!canRemoveItem"
              :aria-label="
                t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.REMOVE_OPTION')
              "
              :data-testid="`send-interactive-remove-${ii}`"
              @click="removeItem(ii)"
            />
          </div>

          <Input
            :model-value="item.title"
            size="sm"
            :maxlength="titleMaxlength"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.TITLE_PLACEHOLDER')
            "
            :message="
              item.title
                ? ''
                : t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.TITLE_REQUIRED')
            "
            :message-type="item.title ? 'info' : 'error'"
            @update:model-value="updateItem(ii, 'title', $event)"
          />
          <Input
            :model-value="item.value"
            size="sm"
            :maxlength="VALUE_MAX"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.VALUE_PLACEHOLDER')
            "
            :message="
              item.value
                ? ''
                : t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.VALUE_REQUIRED')
            "
            :message-type="item.value ? 'info' : 'error'"
            @update:model-value="updateItem(ii, 'value', $event)"
          />
          <Input
            v-if="isList"
            :model-value="item.description"
            size="sm"
            :maxlength="DESCRIPTION_MAX"
            :placeholder="
              t(
                'AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.DESCRIPTION_PLACEHOLDER'
              )
            "
            @update:model-value="updateItem(ii, 'description', $event)"
          />
        </li>
      </ul>

      <NextButton
        icon="i-lucide-plus"
        blue
        faded
        sm
        class="mt-2.5"
        :disabled="!canAddItem"
        :label="t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.ADD_OPTION')"
        data-testid="send-interactive-add-option"
        @click="addItem"
      />
    </ConfigField>

    <div
      class="flex items-center gap-2 px-3 py-2 text-xs border border-dashed rounded-lg text-n-slate-11 border-n-weak"
      data-testid="send-interactive-format-hint"
    >
      <span class="rounded-full size-1.5 shrink-0 bg-n-slate-8" />
      {{ t('AUTOMATION.CANVAS.CONFIG.SEND_INTERACTIVE.FORMAT_HINT') }}
    </div>
  </div>
</template>
