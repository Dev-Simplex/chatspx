<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TemplatePreview from './TemplatePreview.vue';

const props = defineProps({
  inboxId: { type: Number, required: true },
});

const emit = defineEmits(['created', 'cancel']);

const { t } = useI18n();

const name = ref('');
const category = ref('UTILITY');
const language = ref('pt_BR');
const headerFormat = ref('NONE');
const headerText = ref('');
const headerExample = ref('');
const headerMediaUrl = ref('');
const body = ref('');
const bodyExamples = ref([]);
const footer = ref('');
const buttons = ref([]);
const isSubmitting = ref(false);
const errors = ref({});

const tk = key => t(`WHATSAPP_TEMPLATES_MGMT.BUILDER.${key}`);

const categoryOptions = computed(() => [
  { value: 'UTILITY', label: tk('CATEGORY_UTILITY') },
  { value: 'MARKETING', label: tk('CATEGORY_MARKETING') },
  { value: 'AUTHENTICATION', label: tk('CATEGORY_AUTHENTICATION') },
]);

const languageOptions = [
  { value: 'pt_BR', label: 'Português (BR)' },
  { value: 'en', label: 'English' },
  { value: 'en_US', label: 'English (US)' },
  { value: 'es', label: 'Español' },
];

const headerFormatOptions = computed(() => [
  { value: 'NONE', label: tk('HEADER_NONE') },
  { value: 'TEXT', label: tk('HEADER_TEXT') },
  { value: 'IMAGE', label: tk('HEADER_IMAGE') },
  { value: 'VIDEO', label: tk('HEADER_VIDEO') },
  { value: 'DOCUMENT', label: tk('HEADER_DOCUMENT') },
]);

const buttonTypeOptions = computed(() => [
  { value: 'QUICK_REPLY', label: tk('BTN_QUICK_REPLY') },
  { value: 'URL', label: tk('BTN_URL') },
  { value: 'PHONE_NUMBER', label: tk('BTN_PHONE') },
  { value: 'COPY_CODE', label: tk('BTN_COPY_CODE') },
]);

const detectVars = text => {
  const matches = (text || '').match(/\{\{\s*\d+\s*\}\}/g) || [];
  return [...new Set(matches.map(m => m.replace(/\D/g, '')))];
};

const bodyVars = computed(() => detectVars(body.value));
const headerHasVar = computed(() => detectVars(headerText.value).length > 0);
const isMediaHeader = computed(() =>
  ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(headerFormat.value)
);

const normalizedName = computed(() =>
  name.value
    .toString()
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, '_')
    .replace(/_+/g, '_')
);

const addButton = () => {
  if (buttons.value.length >= 10) return;
  buttons.value.push({ type: 'QUICK_REPLY', text: '', url: '', urlExample: '', phone: '' });
};

const removeButton = index => {
  buttons.value.splice(index, 1);
};

const buildComponents = () => {
  const components = [];

  if (headerFormat.value === 'TEXT' && headerText.value.trim()) {
    const header = { type: 'HEADER', format: 'TEXT', text: headerText.value };
    if (headerHasVar.value) {
      header.example = { header_text: [[headerExample.value || '']] };
    }
    components.push(header);
  } else if (isMediaHeader.value && headerMediaUrl.value.trim()) {
    components.push({
      type: 'HEADER',
      format: headerFormat.value,
      example: { header_handle: [headerMediaUrl.value.trim()] },
    });
  }

  const bodyComponent = { type: 'BODY', text: body.value };
  if (bodyVars.value.length) {
    bodyComponent.example = {
      body_text: [bodyVars.value.map((n, i) => bodyExamples.value[i] || '')],
    };
  }
  components.push(bodyComponent);

  if (footer.value.trim()) {
    components.push({ type: 'FOOTER', text: footer.value });
  }

  if (buttons.value.length) {
    const built = buttons.value.map(btn => {
      const out = { type: btn.type, text: btn.text };
      if (btn.type === 'URL') {
        out.url = btn.url;
        if (detectVars(btn.url).length) out.example = [btn.urlExample || ''];
      } else if (btn.type === 'PHONE_NUMBER') {
        out.phone_number = btn.phone;
      }
      return out;
    });
    components.push({ type: 'BUTTONS', buttons: built });
  }

  return components;
};

const validate = () => {
  errors.value = {};
  if (!name.value.trim()) errors.value.name = tk('REQUIRED');
  if (!body.value.trim()) errors.value.body = tk('REQUIRED');
  return Object.keys(errors.value).length === 0;
};

const submit = async () => {
  if (!validate()) return;
  isSubmitting.value = true;
  try {
    await InboxesAPI.createMessageTemplate(props.inboxId, {
      name: name.value,
      language: language.value,
      category: category.value,
      components: buildComponents(),
    });
    useAlert(t('WHATSAPP_TEMPLATES_MGMT.CREATE.SUCCESS'));
    emit('created');
  } catch (error) {
    const data = error?.response?.data || {};
    useAlert(data.error || data.details || t('WHATSAPP_TEMPLATES_MGMT.CREATE.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ tk('TITLE') }}
      </h3>
      <Button variant="ghost" color="slate" size="sm" icon="i-lucide-x" @click="emit('cancel')" />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- FORM -->
      <div class="flex flex-col gap-5 min-w-0">
        <!-- Basics -->
        <div class="flex flex-col gap-3">
          <Input
            v-model="name"
            :label="tk('NAME')"
            :placeholder="tk('NAME_PLACEHOLDER')"
            :message="errors.name || (name ? `${tk('NAME_HINT')} ${normalizedName}` : tk('NAME_HINT_EMPTY'))"
            :message-type="errors.name ? 'error' : 'info'"
          />
          <div class="grid grid-cols-2 gap-3">
            <div class="flex flex-col gap-1">
              <label class="text-sm font-medium text-n-slate-12">{{ tk('CATEGORY') }}</label>
              <Select v-model="category" :options="categoryOptions" class="!w-full" />
            </div>
            <div class="flex flex-col gap-1">
              <label class="text-sm font-medium text-n-slate-12">{{ tk('LANGUAGE') }}</label>
              <Select v-model="language" :options="languageOptions" class="!w-full" />
            </div>
          </div>
        </div>

        <!-- Header -->
        <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
          <label class="text-sm font-medium text-n-slate-12">{{ tk('HEADER') }}</label>
          <Select v-model="headerFormat" :options="headerFormatOptions" class="!w-full" />
          <Input
            v-if="headerFormat === 'TEXT'"
            v-model="headerText"
            :placeholder="tk('HEADER_TEXT_PLACEHOLDER')"
          />
          <Input
            v-if="headerFormat === 'TEXT' && headerHasVar"
            v-model="headerExample"
            :label="tk('HEADER_EXAMPLE')"
            placeholder="Maria"
          />
          <Input
            v-if="isMediaHeader"
            v-model="headerMediaUrl"
            :placeholder="tk('HEADER_MEDIA_PLACEHOLDER')"
            :message="tk('HEADER_MEDIA_HINT')"
          />
        </div>

        <!-- Body -->
        <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
          <TextArea
            v-model="body"
            :label="tk('BODY')"
            :placeholder="tk('BODY_PLACEHOLDER')"
            :max-length="1024"
            show-character-count
            auto-height
            :message="errors.body || tk('BODY_HINT')"
            :message-type="errors.body ? 'error' : 'info'"
          />
          <div v-if="bodyVars.length" class="flex flex-col gap-2">
            <span class="text-xs text-n-slate-11">{{ tk('BODY_EXAMPLES') }}</span>
            <Input
              v-for="(varNum, i) in bodyVars"
              :key="varNum"
              v-model="bodyExamples[i]"
              size="sm"
              :placeholder="`${tk('EXAMPLE_FOR')} {{${varNum}}}`"
            />
          </div>
        </div>

        <!-- Footer -->
        <div class="flex flex-col gap-2 pt-3 border-t border-n-weak">
          <Input
            v-model="footer"
            :label="tk('FOOTER')"
            :placeholder="tk('FOOTER_PLACEHOLDER')"
          />
        </div>

        <!-- Buttons -->
        <div class="flex flex-col gap-3 pt-3 border-t border-n-weak">
          <label class="text-sm font-medium text-n-slate-12">{{ tk('BUTTONS') }}</label>
          <div
            v-for="(btn, idx) in buttons"
            :key="idx"
            class="flex flex-col gap-2 p-3 rounded-lg bg-n-solid-2 border border-n-weak"
          >
            <div class="flex items-center gap-2">
              <Select
                v-model="btn.type"
                :options="buttonTypeOptions"
                class="!w-full"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="sm"
                icon="i-lucide-trash-2"
                @click="removeButton(idx)"
              />
            </div>
            <Input v-model="btn.text" size="sm" :placeholder="tk('BTN_TEXT_PLACEHOLDER')" />
            <Input
              v-if="btn.type === 'URL'"
              v-model="btn.url"
              size="sm"
              placeholder="https://..."
            />
            <Input
              v-if="btn.type === 'URL' && detectVars(btn.url).length"
              v-model="btn.urlExample"
              size="sm"
              :placeholder="tk('BTN_URL_EXAMPLE')"
            />
            <Input
              v-if="btn.type === 'PHONE_NUMBER'"
              v-model="btn.phone"
              size="sm"
              placeholder="+5566..."
            />
          </div>
          <Button
            variant="faded"
            color="blue"
            size="sm"
            icon="i-lucide-plus"
            :label="tk('ADD_BUTTON')"
            :disabled="buttons.length >= 10"
            @click="addButton"
          />
        </div>
      </div>

      <!-- PREVIEW -->
      <div class="lg:sticky lg:top-4 h-fit">
        <TemplatePreview
          :header-format="headerFormat"
          :header-text="headerText"
          :body="body"
          :footer="footer"
          :buttons="buttons"
        />
      </div>
    </div>

    <!-- Actions -->
    <div class="flex items-center justify-end gap-3 pt-4 border-t border-n-weak">
      <Button
        variant="faded"
        color="slate"
        :label="tk('CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        :label="tk('SUBMIT')"
        :is-loading="isSubmitting"
        :disabled="isSubmitting"
        @click="submit"
      />
    </div>
  </div>
</template>
