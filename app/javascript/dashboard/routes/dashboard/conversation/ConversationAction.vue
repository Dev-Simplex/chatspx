<!-- eslint-disable vue/v-slot-style -->
<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useAgentsList } from 'dashboard/composables/useAgentsList';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import ConversationLabels from './labels/LabelBox.vue';
import { CONVERSATION_PRIORITY } from '../../../../shared/constants/messages';
import { CONVERSATION_EVENTS } from '../../../helper/AnalyticsHelper/events';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TeamSelectionModal from 'dashboard/components/widgets/conversation/TeamSelectionModal.vue';
import { losesConversationAccess } from 'dashboard/helper/conversationAccessHelper';

export default {
  components: {
    MultiselectDropdown,
    ConversationLabels,
    NextButton,
    TeamSelectionModal,
  },
  props: {
    conversationId: {
      type: [Number, String],
      required: true,
    },
  },
  setup() {
    const { agentsList } = useAgentsList();
    return {
      agentsList,
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
      return this.currentChat?.meta?.assignee || null;
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
      if (!this.assignedAgent) {
        return true;
      }
      if (this.assignedAgent.id !== this.currentUser.id) {
        return true;
      }
      return false;
    },
  },
  methods: {
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
        useAlert(this.$t('CONVERSATION.CHANGE_AGENT_FAILED'));
      }
    },

    async onConfirmTransferTeam(teamId) {
      if (!this.pendingTransferAgent?.id) {
        this.closeTransferTeamModal();
        return;
      }

      const conversationId = this.currentChat.id;
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
        if (teamApplied) {
          useAlert(this.$t('CONVERSATION.CHANGE_AGENT_FAILED'));
        } else {
          useAlert(this.$t('CONVERSATION.CHANGE_TEAM_FAILED'));
        }
        if (teamApplied) {
          // The team change was committed before the failure; the backend may
          // have cleared the assignee, so check access with the new team only.
          this.leaveConversationIfAccessLost({
            conversationId,
            teamId,
            assigneeId: null,
          });
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
        :options="agentsList"
        :selected-item="assignedAgent"
        :multiselector-title="$t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
        :multiselector-placeholder="$t('AGENT_MGMT.MULTI_SELECTOR.PLACEHOLDER')"
        :no-search-result="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
        "
        :input-placeholder="
          $t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
        "
        @select="onClickAssignAgent"
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
  </div>
</template>
