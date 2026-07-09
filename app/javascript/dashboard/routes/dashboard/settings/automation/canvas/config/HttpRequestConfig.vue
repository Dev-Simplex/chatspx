<script setup>
// Editor de `http_request`. action_params = [{ method, url, headers, body, target, store, key }].
//   • method: get|post|put|patch|delete   • url: http(s), aceita Liquid ({{contact.name}})
//   • headers: [{ key, value }] (value aceita Liquid)   • body: string (aceita Liquid; só não-GET)
//   • target/store/key: onde gravar o corpo da resposta (opcional — sem key não grava)
// A guarda SSRF (bloqueio de IP interno/metadata, sem redirect, timeout+cap) é 100% do backend
// (Flows::SafeHttpClient) — o widget só coleta a config. Merge-patch canônico (padrão do
// SetAttributeConfig/AiClassifyConfig): cada edição reconstrói o objeto com os defaults.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
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

const DEFAULTS = {
  method: 'get',
  url: '',
  headers: [],
  body: '',
  target: 'conversation',
  store: 'custom',
  key: '',
};

const config = computed(() => {
  const params = props.node.action_params;
  const first = Array.isArray(params) && params[0] ? params[0] : {};
  return { ...DEFAULTS, ...first };
});

const patch = partial => {
  emit('update', { action_params: [{ ...config.value, ...partial }] });
};

// Verbos HTTP são universais (GET/POST/…) — exibidos direto, sem i18n.
const methodOptions = computed(() =>
  ['get', 'post', 'put', 'patch', 'delete'].map(id => ({
    id,
    name: id.toUpperCase(),
  }))
);

const methodModel = computed({
  get() {
    return (
      methodOptions.value.find(opt => opt.id === config.value.method) ||
      methodOptions.value[0]
    );
  },
  set(value) {
    patch({ method: value?.id || 'get' });
  },
});

const hasBody = computed(() => config.value.method !== 'get');

const urlModel = computed({
  get() {
    return config.value.url || '';
  },
  set(value) {
    patch({ url: value });
  },
});

const bodyModel = computed({
  get() {
    return config.value.body || '';
  },
  set(value) {
    patch({ body: value });
  },
});

const headers = computed(() =>
  Array.isArray(config.value.headers) ? config.value.headers : []
);

const updateHeader = (index, field, value) => {
  const next = headers.value.map((row, i) =>
    i === index ? { ...row, [field]: value } : row
  );
  patch({ headers: next });
};

const addHeader = () =>
  patch({ headers: [...headers.value, { key: '', value: '' }] });

const removeHeader = index =>
  patch({ headers: headers.value.filter((_, i) => i !== index) });

const targetOptions = computed(() => [
  {
    id: 'conversation',
    name: t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.TARGET_CONVERSATION'),
  },
  {
    id: 'contact',
    name: t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.TARGET_CONTACT'),
  },
]);

const targetModel = computed({
  get() {
    const id = config.value.target || 'conversation';
    return (
      targetOptions.value.find(opt => opt.id === id) || targetOptions.value[0]
    );
  },
  set(value) {
    patch({ target: value?.id || 'conversation' });
  },
});

const keyModel = computed({
  get() {
    return config.value.key || '';
  },
  set(value) {
    patch({ key: value });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="config-http-request">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.METHOD_LABEL')"
    >
      <SingleSelect
        v-model="methodModel"
        disable-search
        disable-deselect
        :options="methodOptions"
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.URL_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.URL_HINT')"
    >
      <Input
        v-model="urlModel"
        size="sm"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.URL_PLACEHOLDER')
        "
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.HEADERS_LABEL')"
    >
      <ul class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="(row, hi) in headers"
          :key="hi"
          class="flex items-center gap-1.5"
        >
          <Input
            :model-value="row.key"
            size="sm"
            class="flex-1"
            :placeholder="
              t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.HEADER_KEY_PLACEHOLDER')
            "
            @update:model-value="updateHeader(hi, 'key', $event)"
          />
          <Input
            :model-value="row.value"
            size="sm"
            class="flex-1"
            :placeholder="
              t(
                'AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.HEADER_VALUE_PLACEHOLDER'
              )
            "
            @update:model-value="updateHeader(hi, 'value', $event)"
          />
          <NextButton
            icon="i-lucide-trash"
            ghost
            ruby
            xs
            :aria-label="
              t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.HEADER_REMOVE')
            "
            @click="removeHeader(hi)"
          />
        </li>
        <li class="list-none">
          <NextButton
            icon="i-lucide-plus"
            blue
            faded
            sm
            :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.HEADER_ADD')"
            @click="addHeader"
          />
        </li>
      </ul>
    </ConfigField>

    <ConfigField
      v-if="hasBody"
      :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.BODY_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.BODY_HINT')"
    >
      <textarea
        v-model="bodyModel"
        rows="4"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y !h-auto outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.BODY_PLACEHOLDER')
        "
      />
    </ConfigField>

    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.STORE_LABEL')"
      :hint="t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.STORE_HINT')"
    >
      <div class="flex gap-1.5">
        <SingleSelect
          v-model="targetModel"
          disable-search
          disable-deselect
          class="w-40 shrink-0"
          :options="targetOptions"
        />
        <Input
          v-model="keyModel"
          size="sm"
          class="flex-1"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.HTTP_REQUEST.STORE_KEY_PLACEHOLDER')
          "
        />
      </div>
    </ConfigField>
  </div>
</template>
