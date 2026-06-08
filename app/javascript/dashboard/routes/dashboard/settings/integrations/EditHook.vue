<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { FormKit } from '@formkit/vue';
import { useBranding } from 'shared/composables/useBranding';

import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    FormKit,
    NextButton,
  },
  props: {
    integrationId: {
      type: String,
      required: true,
    },
    hook: {
      type: Object,
      required: true,
    },
  },
  emits: ['close'],
  setup(props) {
    const { integration } = useIntegrationHook(props.integrationId);
    const { replaceInstallationName } = useBranding();

    return { integration, replaceInstallationName };
  },
  data() {
    return {
      alertMessage: '',
      // Inicializa o form com os settings atuais do hook
      values: this.parseInitialValues(),
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'integrations/getUIFlags',
    }),
    formItems() {
      return this.integration.settings_form_schema || [];
    },
  },
  methods: {
    parseInitialValues() {
      // Copia settings atuais como ponto de partida do form
      const settings = this.hook?.settings || {};
      const values = {};
      // FormKit form usa string. JSON fields precisam ser stringified pro user editar.
      const formSchema = this.integration?.settings_form_schema || [];
      formSchema.forEach(item => {
        const raw = settings[item.name];
        if (raw === undefined || raw === null) {
          values[item.name] = '';
          return;
        }
        if (item.validation && item.validation.includes('JSON')) {
          values[item.name] =
            typeof raw === 'string' ? raw : JSON.stringify(raw, null, 2);
        } else {
          values[item.name] = raw;
        }
      });
      return values;
    },
    onClose() {
      this.$emit('close');
    },
    buildHookPayload() {
      const settings = {};
      Object.keys(this.values).forEach(key => {
        settings[key] = this.values[key];
      });

      this.formItems.forEach(item => {
        if (item.validation?.includes('JSON')) {
          settings[item.name] = JSON.parse(settings[item.name]);
        }
      });

      return { settings };
    },
    async submitForm() {
      try {
        await this.$store.dispatch('integrations/updateHook', {
          hookId: this.hook.id,
          hookData: this.buildHookPayload(),
        });
        this.alertMessage = this.$t(
          'INTEGRATION_APPS.EDIT.API.SUCCESS_MESSAGE'
        );
        this.onClose();
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.EDIT.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto integration-hooks">
    <woot-modal-header
      :header-title="`${integration.name} — ${$t('INTEGRATION_APPS.EDIT.TITLE')}`"
      :header-content="replaceInstallationName(integration.short_description)"
    />
    <FormKit
      v-model="values"
      type="form"
      form-class="w-full grid gap-4"
      :submit-attrs="{
        inputClass: 'hidden',
        wrapperClass: 'hidden',
      }"
      :incomplete-message="false"
      @submit="submitForm"
    >
      <FormKit v-for="item in formItems" :key="item.name" v-bind="item" />
      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('INTEGRATION_APPS.EDIT.FORM.CANCEL')"
          @click.prevent="onClose"
        />
        <NextButton
          type="submit"
          :label="$t('INTEGRATION_APPS.EDIT.FORM.SUBMIT')"
          :is-loading="uiFlags.isUpdatingHook"
        />
      </div>
    </FormKit>
  </div>
</template>

<style lang="css">
.formkit-outer {
  @apply mt-2;
}

.formkit-form > .formkit-wrapper > ul.formkit-messages {
  @apply hidden;
}

.formkit-form .formkit-help {
  @apply text-n-slate-10 text-sm font-normal mt-2 w-full;
}

.formkit-input {
  margin-bottom: 0px !important;
}

[data-invalid] .formkit-message {
  @apply text-n-ruby-9 block text-xs font-normal my-1 w-full;
}

.formkit-outer[data-type='checkbox'] .formkit-wrapper {
  @apply flex items-center gap-2 px-0.5;
}

.formkit-messages {
  @apply list-none m-0 p-0;
}

.formkit-actions {
  @apply hidden;
}
</style>
