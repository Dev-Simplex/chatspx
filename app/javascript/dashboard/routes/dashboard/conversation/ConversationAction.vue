<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import { useMapGetter } from 'dashboard/composables/store';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ConversationLabels from './labels/LabelBox.vue';
import { CONVERSATION_PRIORITY } from '../../../../shared/constants/messages';
import { CONVERSATION_EVENTS } from '../../../helper/AnalyticsHelper/events';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TeamSelectionModal from 'dashboard/components/widgets/conversation/TeamSelectionModal.vue';
import AttendanceWarningDialog from 'dashboard/components-next/NewConversation/components/AttendanceWarningDialog.vue';
import { ATTENDANCE_VARIANT } from 'dashboard/composables/useAttendanceGate';
import { losesConversationAccess } from 'dashboard/helper/conversationAccessHelper';

export default {
  components: {
    MultiselectDropdown,
    ConversationLabels,
    NextButton,
    TeamSelectionModal,
    AttendanceWarningDialog,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList();
    const { isAssignmentGateEnabled } = useReplyAssignmentGate();
    const captainAssistants = useMapGetter('captainAssistants/getRecords');
    return {
      agentsList,
      isAssignmentGateEnabled,
      captainAssistants,
    };
  },
  data() {
    return {
      agentTeamsForModal: [],
      priorityOptions: [
        {
          id: null,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.NONE'),
          thumbnail: `/assets/images/dashboard/priority/none.svg`,
        },
        {
          id: CONVERSATION_PRIORITY.URGENT,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.URGENT'),
          thumbnail: `/assets/images/dashboard/priority/${CONVERSATION_PRIORITY.URGENT}.svg`,
        },
        {
          id: CONVERSATION_PRIORITY.HIGH,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.HIGH'),
          thumbnail: `/assets/images/dashboard/priority/${CONVERSATION_PRIORITY.HIGH}.svg`,
        },
        {
          id: CONVERSATION_PRIORITY.MEDIUM,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM'),
          thumbnail: `/assets/images/dashboard/priority/${CONVERSATION_PRIORITY.MEDIUM}.svg`,
        },
        {
          id: CONVERSATION_PRIORITY.LOW,
          name: this.$t('CONVERSATION.PRIORITY.OPTIONS.LOW'),
          thumbnail: `/assets/images/dashboard/priority/${CONVERSATION_PRIORITY.LOW}.svg`,
        },
      ],
      showTransferTeamModal: false,
      pendingTransferAgent: null,
      // Gate D1: quando a atribuição pelo dropdown bate no takeover_request_gate, o
      // backend devolve 422 error_code 'takeover_request_required' + meta (dono/time/
      // pedido). Em vez de "Falha ao atribuir", oferecemos "Solicitar atendimento".
      takeoverGate: null,
      isRequestingTakeover: false,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUser: 'getCurrentUser',
      currentRole: 'getCurrentRole',
      teams: 'teams/getTeams',
      myTeams: 'teams/getMyTeams',
    }),
    hasAnAssignedTeam() {
      return Boolean(this.currentChat?.meta?.team || this.currentChat?.team_id);
    },
    teamsList() {
      if (this.hasAnAssignedTeam) {
        return [
          { id: 0, name: this.$t('TEAMS_SETTINGS.LIST.NONE') },
          ...this.teams,
        ];
      }
      return this.teams;
    },
    assignedAgent() {
      const assignee = this.currentChat?.meta?.assignee;
      // IA (espelho captain) não aparece no dropdown humano — DC-3
      return assignee && assignee.type !== 'agent_bot' ? assignee : null;
    },
    isAdminUser() {
      return this.currentRole === 'administrator';
    },
    aiAgentsList() {
      const inboxId = this.currentChat?.inbox_id;
      return (this.captainAssistants || [])
        .filter(
          assistant =>
            assistant.agent_bot_id &&
            (assistant.inbox_ids || []).includes(inboxId)
        )
        .map(assistant => ({
          id: assistant.agent_bot_id,
          name: assistant.name,
          thumbnail: assistant.avatar_url,
          assistantId: assistant.id,
        }));
    },
    assignedAIAgent() {
      const assignee = this.currentChat?.meta?.assignee;
      return assignee?.type === 'agent_bot' ? assignee : null;
    },
    // F4: um único campo de "agente atribuído" — bloco "Agentes IA" no topo
    // (admin-only, D-3) + agentes humanos. Selecionar uma IA limpa o humano e
    // vice-versa (exclusividade garantida no backend).
    // As IAs (espelhos) saíram do dropdown de atribuição — o humano não escolhe
    // "qual IA" na mão. A devolução virou o botão "Devolver para a IA" (re-triagem
    // via Clara). Aqui só agentes HUMANOS. A IA atribuída ainda APARECE como
    // selecionada (selectedAssignee), só não é uma opção escolhível.
    assigneeOptions() {
      return this.agentsList.map(agent => ({ ...agent }));
    },
    showAssigneeGroups() {
      return false;
    },
    isAssignedToMe() {
      return Boolean(
        this.assignedAgent && this.assignedAgent.id === this.currentUser?.id
      );
    },
    // "Devolver para a IA" é o par do "Atribuir a mim": só aparece quando a
    // conversa já é minha (não faz sentido devolver o que não é meu) e há IA
    // atribuível na inbox. O backend valida se há triagem de fato.
    canRetriage() {
      return this.isAssignedToMe && this.aiAgentsList.length > 0;
    },
    selectedAssignee() {
      return this.assignedAIAgent || this.assignedAgent;
    },
    assignedTeam: {
      get() {
        return this.currentChat.meta.team;
      },
      set(team) {
        const conversationId = this.currentChat.id;
        const teamId = team ? team.id : 0;
        const previousTeam = this.currentChat.meta.team;
        this.$store.dispatch('setCurrentChatTeam', { team, conversationId });
        this.$store
          .dispatch('assignTeam', { conversationId, teamId, rethrow: true })
          .then(() => {
            useAlert(this.$t('CONVERSATION.CHANGE_TEAM'));
            this.leaveConversationIfAccessLost({
              conversationId,
              teamId: team ? team.id : null,
              assigneeId: null,
            });
          })
          .catch(() => {
            this.$store.dispatch('setCurrentChatTeam', {
              team: previousTeam,
              conversationId,
            });
            useAlert(this.$t('CONVERSATION.CHANGE_TEAM_FAILED'));
          });
      },
    },
    assignedPriority: {
      get() {
        const selectedOption = this.priorityOptions.find(
          opt => opt.id === this.currentChat.priority
        );

        return selectedOption || this.priorityOptions[0];
      },
      set(priorityItem) {
        const conversationId = this.currentChat.id;
        const oldValue = this.currentChat?.priority;
        const priority = priorityItem ? priorityItem.id : null;

        this.$store.dispatch('setCurrentChatPriority', {
          priority,
          conversationId,
        });
        this.$store
          .dispatch('assignPriority', { conversationId, priority })
          .then(() => {
            useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
              oldValue,
              newValue: priority,
              from: 'Conversation Sidebar',
            });
            useAlert(
              this.$t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
                priority: priorityItem.name,
                conversationId,
              })
            );
          });
      },
    },
    currentTeamId() {
      return (
        this.currentChat?.meta?.team?.id || this.currentChat?.team_id || null
      );
    },
    showSelfAssign() {
      // "Atribuir a mim" some quando a conversa já é minha (vira "Devolver
      // para a IA"). Aparece quando não atribuída ou atribuída a outro.
      return !this.isAssignedToMe;
    },
  },
  mounted() {
    if (this.isAdminUser) {
      // A action re-lança o erro; uma conta sem Captain não pode quebrar a
      // sidebar (mesmo padrão defensivo do ChatList.vue).
      this.$store.dispatch('captainAssistants/get').catch(() => {});
    }
  },
  methods: {
    async onClickAssignAIAgent(item) {
      // sem "None" aqui (D-11); re-selecionar o mesmo agente é no-op
      if (!item?.id || this.assignedAIAgent?.id === item.id) return;
      try {
        // NUNCA reusar onConfirmTransferTeam: saves separados quebram a
        // invariante humano×IA (achado Fase A) — o backend troca num save só.
        await this.$store.dispatch('assignAIAgent', {
          conversationId: this.currentChat.id,
          agentBotId: item.id,
          rethrow: true,
        });
        useAlert(this.$t('CONVERSATION.CHANGE_AI_AGENT'));
      } catch (error) {
        useAlert(this.$t('CONVERSATION.CHANGE_AI_AGENT_FAILED'));
      }
    },

    onSelfAssign() {
      const {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        avatar_url,
        team_ids,
      } = this.currentUser;
      const selfAssign = {
        account_id,
        availability_status,
        available_name,
        email,
        id,
        name,
        role,
        thumbnail: avatar_url,
        team_ids: team_ids || [],
      };

      this.handleAgentTeamSync(selfAssign);
    },

    closeTransferTeamModal() {
      this.showTransferTeamModal = false;
      this.pendingTransferAgent = null;
      this.agentTeamsForModal = [];
    },

    leaveConversationIfAccessLost({ conversationId, teamId, assigneeId }) {
      // The user may have switched conversations while the request was in
      // flight — never navigate away from an unrelated conversation.
      if (this.currentChat?.id !== conversationId) return;
      // An empty teams store right after a team assignment means it has not
      // loaded yet — fail open instead of ejecting a legitimate member.
      if (!this.teams.length) return;
      const lostAccess = losesConversationAccess({
        isAdmin: this.currentRole === 'administrator',
        userId: this.currentUser.id,
        userTeamIds: this.myTeams.map(team => team.id),
        teamId,
        assigneeId,
      });
      if (lostAccess) {
        useAlert(this.$t('CONVERSATION.ASSIGNMENT_ACCESS_LOST'));
        this.$router.push(
          `/app/accounts/${this.$route.params.accountId}/dashboard`
        );
      }
    },

    async assignAgentDirect(agent = null) {
      const conversationId = this.currentChat.id;
      try {
        await this.$store.dispatch('assignAgent', {
          conversationId,
          agentId: agent?.id || null,
          rethrow: true,
        });
        useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
        this.leaveConversationIfAccessLost({
          conversationId,
          teamId: this.currentChat?.meta?.team?.id || null,
          assigneeId: agent?.id || null,
        });
      } catch (error) {
        if (this.offerTakeoverRequest(error, conversationId)) return;
        useAlert(this.$t('CONVERSATION.CHANGE_AGENT_FAILED'));
      }
    },

    // Se o erro é o 422 do gate, monta o estado do diálogo a partir do meta e o
    // abre (retorna true p/ o chamador NÃO mostrar o alerta genérico).
    offerTakeoverRequest(error, conversationId) {
      if (error?.response?.data?.error_code !== 'takeover_request_required') {
        return false;
      }
      const meta = error.response.data.meta || {};
      this.takeoverGate = {
        variant: ATTENDANCE_VARIANT.HUMAN,
        attendance: {
          id: conversationId,
          assignee: meta.current_assignee
            ? { name: meta.current_assignee.name, type: 'user' }
            : null,
          team: meta.team || null,
          // já estamos NA conversa → esconde "Ir para a conversa"
          canOpen: false,
          canRequest: !meta.existing_request,
          myPendingRequestId: meta.existing_request?.id || null,
        },
      };
      this.$refs.attendanceDialogRef?.open();
      return true;
    },

    async onTakeoverRequest(reason) {
      const conversationId = this.takeoverGate?.attendance?.id;
      if (!conversationId || this.isRequestingTakeover) return;
      this.isRequestingTakeover = true;
      try {
        await this.$store.dispatch('takeoverRequests/create', {
          conversationId,
          reason,
        });
        useAlert(this.$t('CONVERSATION.TAKEOVER_REQUEST.SENT'));
        this.$refs.attendanceDialogRef?.close();
        this.takeoverGate = null;
      } catch (error) {
        useAlert(this.takeoverErrorMessage(error));
      } finally {
        this.isRequestingTakeover = false;
      }
    },

    onTakeoverCancel() {
      this.$refs.attendanceDialogRef?.close();
      this.takeoverGate = null;
    },

    // Traduz o error_code do pedido; cai no erro genérico se a chave não existir.
    // O vue-i18n 9 devolve a própria chave quando falta (o `{ default }` de 2 args
    // é ignorado), então detectamos ausência por igualdade em vez de mostrar a
    // string pontilhada crua na tela.
    takeoverErrorMessage(error) {
      const generic = this.$t('CONVERSATION.REPLY_GATE_DIALOG.ERROR');
      const code = error?.response?.data?.error_code;
      if (!code) return generic;
      const key = `CONVERSATION.TAKEOVER_REQUEST.ERRORS.${code.toUpperCase()}`;
      const translated = this.$t(key);
      return translated === key ? generic : translated;
    },

    async onConfirmTransferTeam(teamId) {
      if (!this.pendingTransferAgent?.id) {
        this.closeTransferTeamModal();
        return;
      }

      const conversationId = this.currentChat.id;
      // Capturado ANTES: se a atribuição do agente bater no gate, desfazemos a
      // troca de time (que é comitada primeiro) de volta para este valor.
      const previousTeamId = this.currentChat?.meta?.team?.id || null;
      let teamApplied = false;
      try {
        await this.$store.dispatch('assignTeam', {
          conversationId,
          teamId,
          rethrow: true,
        });
        teamApplied = true;
        await this.$store.dispatch('assignAgent', {
          conversationId,
          agentId: this.pendingTransferAgent.id,
          rethrow: true,
        });
        useAlert(this.$t('CONVERSATION.CHANGE_AGENT'));
        this.leaveConversationIfAccessLost({
          conversationId,
          teamId,
          assigneeId: this.pendingTransferAgent.id,
        });
      } catch (error) {
        // Gate D1: assignTeam não tem gate, mas assignAgent sim. Se a atribuição do
        // agente exige pedido (422), oferece "Solicitar" — e DESFAZ a troca de time
        // já comitada, para não mexer na conversa do colega numa tentativa barrada.
        if (this.offerTakeoverRequest(error, conversationId)) {
          if (teamApplied) {
            this.$store
              .dispatch('assignTeam', {
                conversationId,
                teamId: previousTeamId || 0,
              })
              .catch(() => {});
          }
          return;
        }
        if (teamApplied) {
          useAlert(this.$t('CONVERSATION.CHANGE_AGENT_FAILED'));
          // The team change was committed before the failure; the backend may
          // have cleared the assignee, so check access with the new team only.
          this.leaveConversationIfAccessLost({
            conversationId,
            teamId,
            assigneeId: null,
          });
        } else {
          useAlert(this.$t('CONVERSATION.CHANGE_TEAM_FAILED'));
        }
      } finally {
        this.closeTransferTeamModal();
      }
    },

    handleAgentTeamSync(agent) {
      const agentTeamIds = agent.team_ids || [];

      // Agent has no teams (admin or empty) — assign directly, keep current team
      if (!agentTeamIds.length) {
        this.assignAgentDirect(agent);
        return;
      }

      // Agent has exactly 1 team
      if (agentTeamIds.length === 1) {
        if (this.currentTeamId && agentTeamIds[0] === this.currentTeamId) {
          // Matches current team — assign directly
          this.assignAgentDirect(agent);
        } else {
          // Different or no current team — auto-assign both
          this.pendingTransferAgent = agent;
          this.onConfirmTransferTeam(agentTeamIds[0]);
        }
        return;
      }

      // Agent has multiple teams
      if (this.currentTeamId && agentTeamIds.includes(this.currentTeamId)) {
        // One matches current team — assign directly
        this.assignAgentDirect(agent);
        return;
      }

      // No match or no current team — show modal with only agent's teams
      const agentTeams = this.teams.filter(t => agentTeamIds.includes(t.id));
      this.agentTeamsForModal = agentTeams;
      this.pendingTransferAgent = agent;
      this.showTransferTeamModal = true;
    },

    // F4: roteia a seleção do campo unificado de agente para IA ou humano.
    onClickAssignAssignee(selectedItem) {
      if (selectedItem?.type === 'agent_bot') {
        this.onClickAssignAIAgent(selectedItem);
        return;
      }
      this.onClickAssignAgent(selectedItem);
    },

    onClickAssignAgent(selectedItem) {
      const selectedAgentId = selectedItem?.id;
      const isSameAgent =
        this.assignedAgent && this.assignedAgent.id === selectedAgentId;

      if (isSameAgent || !selectedAgentId) {
        this.assignAgentDirect(null);
        return;
      }

      this.handleAgentTeamSync(selectedItem);
    },

    onClickAssignTeam(selectedItemTeam) {
      if (this.assignedTeam && this.assignedTeam.id === selectedItemTeam.id) {
        this.assignedTeam = null;
      } else {
        this.assignedTeam = selectedItemTeam;
      }
    },

    onClickAssignPriority(selectedPriorityItem) {
      const isSamePriority =
        this.assignedPriority &&
        this.assignedPriority.id === selectedPriorityItem.id;

      this.assignedPriority = isSamePriority ? null : selectedPriorityItem;
    },

    // "Devolver para a IA": re-tria a conversa (Clara, time limpo). Confirma antes
    // pra evitar clique acidental que tira a conversa do humano.
    async onRetriage() {
      const conversationId = this.currentChat?.id;
      if (!conversationId) return;
      // eslint-disable-next-line no-alert
      if (!window.confirm(this.$t('CONVERSATION_SIDEBAR.RETRIAGE_CONFIRM'))) {
        return;
      }
      try {
        await this.$store.dispatch('retriage', {
          conversationId,
          rethrow: true,
        });
        useAlert(this.$t('CONVERSATION_SIDEBAR.RETRIAGE_SUCCESS'));
      } catch (error) {
        useAlert(
          error?.response?.data?.error ||
            this.$t('CONVERSATION_SIDEBAR.RETRIAGE_ERROR')
        );
      }
    },
  },
};
</script>

<template>
  <div class="wa-assign-section">
    <div class="wa-assign-row">
      <span class="wa-assign-label">
        {{ $t('CONVERSATION_SIDEBAR.ASSIGNEE_LABEL') }}
      </span>
      <NextButton
        v-if="showSelfAssign"
        link
        xs
        icon="i-lucide-arrow-right"
        class="!gap-1"
        :label="$t('CONVERSATION_SIDEBAR.SELF_ASSIGN')"
        @click="onSelfAssign"
      />
    </div>
    <div class="wa-assign-value-wrap">
      <MultiselectDropdown
        :options="assigneeOptions"
        :selected-item="selectedAssignee"
        :grouped="showAssigneeGroups"
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
        "
        @select="onClickAssignAssignee"
      />
    </div>
    <div v-if="canRetriage" class="wa-assign-value-wrap">
      <NextButton
        link
        sm
        icon="i-lucide-sparkles"
        class="!gap-1"
        :label="$t('CONVERSATION_SIDEBAR.RETRIAGE')"
        @click="onRetriage"
      />
    </div>
    <div class="wa-assign-row">
      <span class="wa-assign-label">
        {{ $t('CONVERSATION_SIDEBAR.TEAM_LABEL') }}
      </span>
    </div>
    <div class="wa-assign-value-wrap">
      <MultiselectDropdown
        :options="teamsList"
        :selected-item="assignedTeam"
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.TEAM')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.TEAM')
        "
        @select="onClickAssignTeam"
      />
    </div>
    <div class="wa-assign-row">
      <span class="wa-assign-label">
        {{ $t('CONVERSATION.PRIORITY.TITLE') }}
      </span>
    </div>
    <div class="wa-assign-value-wrap">
      <MultiselectDropdown
        :options="priorityOptions"
        :selected-item="assignedPriority"
        :multiselector-title="$t('CONVERSATION.PRIORITY.TITLE')"
        :multiselector-placeholder="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SELECT_PLACEHOLDER')
        "
        :no-search-result="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.NO_RESULTS')
        "
        :input-placeholder="
          $t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.INPUT_PLACEHOLDER')
        "
        @select="onClickAssignPriority"
      />
    </div>
    <div class="wa-assign-row">
      <span class="wa-assign-label">
        {{ $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS') }}
      </span>
    </div>
    <div class="wa-assign-value-wrap">
      <ConversationLabels :conversation-id="conversationId" />
    </div>
    <TeamSelectionModal
      :show="showTransferTeamModal"
      :teams="agentTeamsForModal.length ? agentTeamsForModal : teams"
      :title="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_TITLE')"
      :description="$t('CONVERSATION.SELECT_TEAM_FOR_TRANSFER_DESCRIPTION')"
      @confirm="onConfirmTransferTeam"
      @close="closeTransferTeamModal"
    />
    <AttendanceWarningDialog
      ref="attendanceDialogRef"
      context="conversation"
      :variant="takeoverGate?.variant"
      :attendance="takeoverGate?.attendance"
      :can-request="Boolean(takeoverGate?.attendance?.canRequest)"
      :has-pending-request="
        Boolean(takeoverGate?.attendance?.myPendingRequestId)
      "
      :allow-send-anyway="false"
      :is-requesting="isRequestingTakeover"
      @request-attendance="onTakeoverRequest"
      @go-to-conversation="onTakeoverCancel"
      @cancel="onTakeoverCancel"
    />
  </div>
</template>
