<script setup>
// Editor de `send_email_to_team`. action_params = [{ team_ids: [id,...], message }].
// O backend notifica cada time por e-mail via
// TeamNotifications::AutomationNotificationMailer.conversation_creation, respeitando o rate-limit
// de e-mail da conta. Ver Flows::ActionService#send_email_to_team (action_service.rb:128-136):
// `Team.where(id: params[0][:team_ids])` + `params[0][:message]`. Merge-patch canônico (padrão do
// SetAttributeConfig/HttpRequestConfig): cada edição reconstrói o objeto params[0] com os defaults.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const teams = useMapGetter('teams/getTeams');

const config = computed(() => {
  const params = props.node.action_params;
  return Array.isArray(params) && params[0] ? params[0] : {};
});

const patch = partial => {
  emit('update', {
    action_params: [{ team_ids: [], message: '', ...config.value, ...partial }],
  });
};

const teamOptions = computed(() =>
  teams.value.map(team => ({ id: team.id, name: team.name }))
);

const selectedTeams = computed({
  get() {
    const ids = Array.isArray(config.value.team_ids)
      ? config.value.team_ids
      : [];
    return ids.map(
      id =>
        teamOptions.value.find(opt => String(opt.id) === String(id)) || {
          id,
          name: String(id),
        }
    );
  },
  set(value) {
    patch({ team_ids: Array.isArray(value) ? value.map(item => item.id) : [] });
  },
});

const message = computed({
  get() {
    return config.value.message || '';
  },
  set(value) {
    patch({ message: value });
  },
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TO_TEAM.TEAMS_LABEL')"
    >
      <MultiSelect v-model="selectedTeams" :options="teamOptions" />
      <p v-if="!teamOptions.length" class="mt-1 text-xs text-n-slate-10">
        {{ t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TO_TEAM.NO_TEAMS') }}
      </p>
    </ConfigField>
    <ConfigField
      :label="t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TO_TEAM.MESSAGE_LABEL')"
    >
      <textarea
        v-model="message"
        rows="4"
        class="w-full px-3 py-2 text-sm rounded-lg resize-y outline outline-1 text-n-slate-12 bg-n-alpha-1 outline-n-weak dark:outline-n-strong focus:outline-n-brand"
        :placeholder="
          t('AUTOMATION.CANVAS.CONFIG.SEND_EMAIL_TO_TEAM.MESSAGE_PLACEHOLDER')
        "
        data-testid="config-email-to-team-message"
      />
    </ConfigField>
  </div>
</template>
