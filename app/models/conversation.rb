# == Schema Information
#
# Table name: conversations
#
#  id                     :integer          not null, primary key
#  additional_attributes  :jsonb
#  agent_last_seen_at     :datetime
#  assignee_last_seen_at  :datetime
#  cached_label_list      :text
#  contact_last_seen_at   :datetime
#  custom_attributes      :jsonb
#  first_reply_created_at :datetime
#  identifier             :string
#  last_activity_at       :datetime         not null
#  priority               :integer
#  snoozed_until          :datetime
#  status                 :integer          default("open"), not null
#  uuid                   :uuid             not null
#  waiting_since          :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :integer          not null
#  assignee_agent_bot_id  :bigint
#  assignee_id            :integer
#  campaign_id            :bigint
#  contact_id             :bigint
#  contact_inbox_id       :bigint
#  display_id             :integer          not null
#  inbox_id               :integer          not null
#  sla_policy_id          :bigint
#  team_id                :bigint
#
# Indexes
#
#  conv_acid_inbid_stat_asgnid_idx                    (account_id,inbox_id,status,assignee_id)
#  index_conversations_on_account_id                  (account_id)
#  index_conversations_on_account_id_and_display_id   (account_id,display_id) UNIQUE
#  index_conversations_on_assignee_id_and_account_id  (assignee_id,account_id)
#  index_conversations_on_campaign_id                 (campaign_id)
#  index_conversations_on_contact_id                  (contact_id)
#  index_conversations_on_contact_inbox_id            (contact_inbox_id)
#  index_conversations_on_first_reply_created_at      (first_reply_created_at)
#  index_conversations_on_id_and_account_id           (account_id,id)
#  index_conversations_on_identifier_and_account_id   (identifier,account_id)
#  index_conversations_on_inbox_id                    (inbox_id)
#  index_conversations_on_priority                    (priority)
#  index_conversations_on_status_and_account_id       (status,account_id)
#  index_conversations_on_status_and_priority         (status,priority)
#  index_conversations_on_team_id                     (team_id)
#  index_conversations_on_uuid                        (uuid) UNIQUE
#  index_conversations_on_waiting_since               (waiting_since)
#

class Conversation < ApplicationRecord
  include Labelable
  include LlmFormattable
  include AssignmentHandler
  include AutoAssignmentHandler
  include ActivityMessageHandler
  include UrlHelper
  include SortHandler
  include PushDataHelper
  include ConversationMuteHelpers

  # Sufixo de JID que o WhatsApp usa para grupos (ver #group?).
  WHATSAPP_GROUP_JID_SUFFIX = '@g.us'.freeze

  attr_accessor :skip_team_required_for_resolution_validation

  # F1 (modo FILA): no handoff "pull" da IA, a conversa é SOLTA na fila do time (sem dono),
  # então o round-robin NÃO pode empurrá-la pra um agente. Setado pelo HandoffTool quando
  # reply_assignment_gate está ON; modo Clássico nunca seta (auto-assign segue normal).
  attr_accessor :skip_auto_assignment

  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :contact_id, presence: true
  before_validation :validate_additional_attributes
  before_validation :reset_agent_bot_when_assignee_present
  validates :additional_attributes, jsonb_attributes_length: true
  validates :custom_attributes, jsonb_attributes_length: true
  validates :uuid, uniqueness: true
  validate :validate_referer_url
  validate :team_required_for_resolution
  validate :pending_status_allowed_by_inbox

  enum status: { open: 0, resolved: 1, pending: 2, snoozed: 3 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  scope :unassigned, -> { where(assignee_id: nil) }
  scope :assigned, -> { where.not(assignee_id: nil) }
  scope :assigned_to, ->(agent) { where(assignee_id: agent.id) }
  # Conversas atendidas por IA (espelho captain). EXISTS compõe com qualquer join/distinct do finder
  # e ignora bot webhook atribuído via coluna (não é "atendente").
  scope :assigned_to_captain, lambda {
    where('EXISTS (SELECT 1 FROM agent_bots WHERE agent_bots.id = conversations.assignee_agent_bot_id ' \
          'AND agent_bots.bot_type = 1)')
  }
  scope :without_captain_assignee, lambda {
    where('NOT EXISTS (SELECT 1 FROM agent_bots WHERE agent_bots.id = conversations.assignee_agent_bot_id ' \
          'AND agent_bots.bot_type = 1)')
  }
  # "Aguardando atendimento": a IA fez handoff e segue dona, mas marcou que já é hora de
  # um humano assumir (custom attribute setado pelo HandoffTool). Continua atribuída à IA
  # (responde), porém aparece nesta fila e some do filtro IA. O concern limpa o marcador
  # quando um humano assume/responde ou a conversa resolve.
  scope :awaiting_human, lambda {
    where("conversations.custom_attributes->>'aguardando_humano_desde' IS NOT NULL")
  }
  # "Aguardando encerramento": conversa parada/encerrada que o roteador de auto-resolve marcou
  # para um humano JULGAR se fecha. A IA segue dona (responde se o cliente voltar), some do
  # filtro IA e aparece nesta fila. O concern limpa o marcador quando um humano assume, o
  # cliente volta a falar (waiting_since repopulado) ou a conversa resolve.
  scope :awaiting_closure, lambda {
    where("conversations.custom_attributes->>'aguardando_encerramento_desde' IS NOT NULL")
  }
  scope :unattended, -> { where(first_reply_created_at: nil).or(where.not(waiting_since: nil)) }
  # Conversas com mensagem recebida (incoming) ainda nao vista pelo agente:
  # existe incoming criada depois do agent_last_seen_at (ou nunca aberta). Espelha
  # memoized_unread_count > 0 em forma de scope, para filtragem da lista.
  scope :unread, lambda {
    where(
      'EXISTS (SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id ' \
      'AND messages.message_type = ? ' \
      'AND (conversations.agent_last_seen_at IS NULL OR messages.created_at > conversations.agent_last_seen_at))',
      Message.message_types[:incoming]
    )
  }
  scope :resolvable_not_waiting, lambda { |auto_resolve_after|
    return none if auto_resolve_after.to_i.zero?

    open.where('last_activity_at < ? AND waiting_since IS NULL', Time.now.utc - auto_resolve_after.minutes)
  }
  scope :resolvable_all, lambda { |auto_resolve_after|
    return none if auto_resolve_after.to_i.zero?

    open.where('last_activity_at < ?', Time.now.utc - auto_resolve_after.minutes)
  }

  scope :last_user_message_at, lambda {
    joins(
      "INNER JOIN (#{last_messaged_conversations.to_sql}) AS grouped_conversations
      ON grouped_conversations.conversation_id = conversations.id"
    ).sort_on_last_user_message_at
  }

  belongs_to :account
  belongs_to :inbox
  belongs_to :assignee, class_name: 'User', optional: true, inverse_of: :assigned_conversations
  belongs_to :assignee_agent_bot, class_name: 'AgentBot', optional: true
  belongs_to :contact
  belongs_to :contact_inbox
  belongs_to :team, optional: true
  belongs_to :campaign, optional: true

  has_many :mentions, dependent: :destroy_async
  has_many :messages, lambda { |conversation| # rubocop:disable Rails/InverseOf
    # Filtragem por team_id so se aplica quando a regra ALCANCA esta conversa:
    # `Inbox#isolation_applies_to_team?` = flag ligada + conversa COM time + time dentro
    # da lista escolhida (lista vazia = todos os times = comportamento historico).
    # Caso contrario (default), retorna todas as mensagens — alinhando o backend com o frontend
    # (Message.vue isRestrictedByTeam) e com a expectativa do admin que desabilita o setting.
    # Quando isolation esta ON e a conv pertence a um time, mensagens com team_id NULL ainda
    # aparecem (publicas) mais as do time atual. Mensagens com team_id stale (de team anterior)
    # ficam ocultas — o UpdateMessagesTeamIdJob deve sincroniza-las. Foi esse "ficam ocultas"
    # que derrubou em silencio o no de mensagem do flow, CSAT, NPS e o encerramento automatico:
    # quem precisa da conversa INTEIRA usa `all_messages` (ver message_window_service.rb).
    if conversation.inbox&.isolation_applies_to_team?(:team_message_isolation, conversation.team_id)
      where('messages.team_id IS NULL OR messages.team_id = ?', conversation.team_id)
    else
      all
    end
  }, dependent: :destroy_async, autosave: true
  has_many :all_messages, class_name: 'Message', dependent: :destroy_async, autosave: true
  has_one :csat_survey_response, dependent: :destroy_async
  has_many :nps_responses, dependent: :destroy_async
  has_one :nps_response, -> { order(created_at: :desc) }, class_name: 'NpsResponse', # rubocop:disable Rails/HasManyOrHasOneDependent
                                                          inverse_of: :conversation
  has_many :conversation_participants, dependent: :destroy_async
  has_many :notifications, as: :primary_actor, dependent: :destroy_async
  has_many :conversation_takeover_requests, dependent: :destroy_async
  has_many :attachments, through: :messages
  has_many :reporting_events, dependent: :destroy_async
  has_many :funnel_items, dependent: :destroy
  has_many :scheduled_messages, dependent: :destroy_async

  before_save :ensure_snooze_until_reset
  before_create :determine_conversation_status
  before_create :ensure_waiting_since

  # Status changes must use update! or save! (never update_column) so these callbacks run and
  # CONVERSATION_STATUS_CHANGED is dispatched (e.g. for NPS survey).
  after_update :record_team_id_change
  after_update_commit :execute_after_update_commit_callbacks
  after_update_commit :move_to_automated_stage, if: :saved_change_to_status?
  after_update_commit :move_to_team_funnel, if: :saved_change_to_team_id?
  # D1 (Fase 3): callback NOVO e INDEPENDENTE (não pendurar no
  # process_assignment_changes — reentrância). Se a conversa foi reatribuída por
  # QUALQUER outro caminho, os pedidos pendentes contra o dono antigo ficam
  # obsoletos. `if:` barato p/ não custar nada em toda atualização.
  after_update_commit :supersede_stale_takeover_requests, if: :saved_change_to_assignee_id?
  after_create_commit :notify_conversation_creation
  after_create_commit :load_attributes_created_by_db_triggers
  after_create_commit :add_to_appropriate_funnel

  delegate :auto_resolve_after, to: :account

  def can_reply?
    Conversations::MessageWindowService.new(self).can_reply?
  end

  def language
    additional_attributes&.dig('conversation_language')
  end

  # Conversa de GRUPO de WhatsApp. Ponto único de verdade — qualquer guard novo
  # (CSAT, NPS, IA, automação) deve perguntar aqui, nunca reimplementar a heurística.
  #
  # A WAHA não seta `additional_attributes['type'] = 'group'` (sinal padrão do Chatwoot);
  # ela identifica o grupo pelo JID do contato terminando em `@g.us`. Cobrimos os dois
  # caminhos e as variações de custom_attributes por integração.
  # Este predicado passou a ser consultado em caminhos críticos (abertura de
  # conversa, CSAT, NPS, IA). Registro jsonb torto — um `update_all` mal escrito
  # grava String onde deveria haver Hash — não pode derrubar a tela inteira, por
  # isso os acessos são tolerantes ao tipo em vez de assumir Hash.
  def group?
    return true if jsonb_hash(additional_attributes)['type'] == 'group'
    return false if contact.blank?
    return true if contact.identifier.to_s.end_with?(WHATSAPP_GROUP_JID_SUFFIX)

    jsonb_hash(contact.custom_attributes)
      .values_at('waha_whatsapp_chat_id', 'waha_whatsapp_jid')
      .any? { |jid| jid.to_s.end_with?(WHATSAPP_GROUP_JID_SUFFIX) }
  end

  # Be aware: The precision of created_at and last_activity_at may differ from Ruby's Time precision.
  # Our DB column (see schema) stores timestamps with second-level precision (no microseconds), so
  # if you assign a Ruby Time with microseconds, the DB will truncate it. This may cause subtle differences
  # if you compare or copy these values in Ruby, also in our specs
  # So in specs rely on to be_with(1.second) instead of to eq()
  # TODO: Migrate to use a timestamp with microsecond precision
  def last_activity_at
    self[:last_activity_at] || created_at
  end

  def last_incoming_message
    messages.where(account_id: account_id)&.incoming&.last
  end

  def toggle_status
    # FIXME: implement state machine with aasm
    self.status = open? ? :resolved : :open
    self.status = :open if pending? || snoozed?
    save
  end

  def toggle_priority(priority = nil)
    self.priority = priority.presence
    save
  end

  def bot_handoff!
    update(waiting_since: Time.current) if waiting_since.blank?
    open!
    dispatcher_dispatch(CONVERSATION_BOT_HANDOFF)
  end

  def unread_messages
    agent_last_seen_at.present? ? messages.created_since(agent_last_seen_at) : messages
  end

  def assignee_unread_messages
    assignee_last_seen_at.present? ? messages.created_since(assignee_last_seen_at) : messages
  end

  def unread_incoming_messages
    unread_messages.incoming.last(10)
  end

  def memoized_unread_count
    @memoized_unread_count ||= begin
      base = messages.incoming
      agent_last_seen_at.present? ? base.where('created_at > ?', agent_last_seen_at).count : base.count
    end
  end

  def cached_label_list_array
    (cached_label_list || '').split(',').map(&:strip)
  end

  def notifiable_assignee_change?
    return false unless saved_change_to_assignee_id?
    return false if assignee_id.blank?
    return false if self_assign?(assignee_id)

    true
  end

  # Virtual attribute till we switch completely to polymorphic assignee
  def assignee_type
    return 'AgentBot' if assignee_agent_bot_id.present?
    return 'User' if assignee_id.present?

    nil
  end

  def assigned_entity
    assignee_agent_bot || assignee
  end

  def tweet?
    inbox.inbox_type == 'Twitter' && additional_attributes['type'] == 'tweet'
  end

  def recent_messages
    messages.chat.last(5)
  end

  def csat_survey_link
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{uuid}"
  end

  def dispatch_conversation_updated_event(previous_changes = nil)
    dispatcher_dispatch(CONVERSATION_UPDATED, previous_changes)
  end

  # Per-user settings stored in additional_attributes.user_settings.{user_id}.
  # Namespace introduced em PR B4 (jsonb additivo). Webapp Vue ignora este nó.
  def user_setting_for(user_id)
    return {} if user_id.blank?

    (additional_attributes || {}).dig('user_settings', user_id.to_s) || {}
  end

  def mark_as_unread!
    last_incoming_message = messages.incoming.last
    last_seen_at = last_incoming_message.present? ? (last_incoming_message.created_at - 1.second) : nil
    update_columns(agent_last_seen_at: last_seen_at, assignee_last_seen_at: last_seen_at) # rubocop:disable Rails/SkipsModelValidations
    dispatcher_dispatch(CONVERSATION_UPDATED, { 'agent_last_seen_at' => true, 'assignee_last_seen_at' => true })
  rescue StandardError => e
    Rails.logger.warn("Conversation#mark_as_unread! failed for conversation #{id}: #{e.message}")
  end

  private

  def execute_after_update_commit_callbacks
    handle_resolved_status_change
    notify_status_change
    create_activity
    notify_conversation_updation
    update_messages_team_id
  end

  # Reetiqueta as mensagens (team_message_isolation) quando o time da conversa muda. NAO usa
  # saved_change_to_team_id? aqui: este metodo roda no after_COMMIT, que reflete so o ULTIMO save
  # da transacao. O flow muda o time e depois salva a conversa de novo na MESMA transacao (ex.:
  # assign_team seguido de outro update dentro do with_lock do ReplyResumeService) -> o 2o save
  # zera saved_change_to_team_id? -> o job nunca era enfileirado -> as mensagens da fase anterior
  # ficavam com o team velho e SUMIAM para o time novo (bug do "sumiu tudo" na AGN). O flag
  # #record_team_id_change captura a mudanca no after_UPDATE (que roda por save) e sobrevive ate o
  # commit. A rake messages:reconcile_team_id continua como rede de seguranca.
  def update_messages_team_id
    return unless @team_id_changed_for_retag

    @team_id_changed_for_retag = false
    Conversations::UpdateMessagesTeamIdJob.perform_later(id, team_id)
  end

  # after_update roda uma vez POR save (dentro da transacao). Marca o flag quando o time muda; um
  # save posterior sem mudanca de time nao mexe na marca (o `if` so atribui na mudanca). Consumido
  # no after_commit por #update_messages_team_id.
  def record_team_id_change
    @team_id_changed_for_retag = true if saved_change_to_team_id?
  end

  def handle_resolved_status_change
    # When conversation is resolved, clear waiting_since using update_column to avoid callbacks
    return unless saved_change_to_status? && status == 'resolved'

    # rubocop:disable Rails/SkipsModelValidations
    update_column(:waiting_since, nil)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def ensure_snooze_until_reset
    self.snoozed_until = nil unless snoozed?
  end

  def ensure_waiting_since
    self.waiting_since = created_at
  end

  def validate_additional_attributes
    self.additional_attributes = {} unless additional_attributes.is_a?(Hash)
  end

  def reset_agent_bot_when_assignee_present
    return if assignee_id.blank?

    self.assignee_agent_bot_id = nil if assignee_agent_bot_id.present?
  end

  def team_required_for_resolution
    return if skip_team_required_for_resolution_validation
    return unless status_changed? && status == 'resolved'
    return if team_id.present?

    errors.add(:team_id, I18n.t('conversations.errors.team_required_for_resolution'))
  end

  def pending_status_allowed_by_inbox
    return unless will_save_change_to_status? && status == 'pending'
    return if inbox&.pending_status_enabled?

    errors.add(:status, I18n.t('errors.conversation.pending_status_disabled_for_inbox',
                               default: 'cannot be Pending — feature disabled for this inbox'))
  end

  def determine_conversation_status
    self.status = :resolved and return if contact&.blocked?

    return handle_campaign_status if campaign.present?

    self.status = :pending if inbox.active_bot? && inbox.pending_status_enabled?
  end

  def handle_campaign_status
    # If campaign has no sender (bot-initiated) and inbox has active bot, let bot handle it
    self.status = :pending if campaign.sender_id.nil? && inbox.active_bot? && inbox.pending_status_enabled?
  end

  def notify_conversation_creation
    dispatcher_dispatch(CONVERSATION_CREATED)
  end

  # Reatribuída por outro caminho → pedidos pendentes contra o dono antigo viram
  # `superseded`. EXCEÇÃO: se o novo dono é justamente o solicitante, o pedido é
  # aprovado (system) — a transferência aconteceu, só não passou pelo fluxo.
  # A própria aprovação seta takeover_approval_in_progress, então NÃO reprocessa
  # aqui (senão fecharia o pedido duas vezes).
  def supersede_stale_takeover_requests
    return if Current.takeover_approval_in_progress
    return unless conversation_takeover_requests.pending.exists?

    new_owner_id = assignee_id
    conversation_takeover_requests.pending.find_each do |request|
      if new_owner_id.present? && request.requester_id == new_owner_id
        # O novo dono é o próprio solicitante: ele já ganhou a conversa por outro
        # caminho, então não precisa de aviso.
        request.close!(status: :approved, source: :system)
      else
        request.close!(status: :superseded, source: :system)
        # Avisa o solicitante perdedor (só broadcast) — senão fica preso em
        # "Pedido enviado" até um refetch manual.
        Conversations::TakeoverRequestNotifier.new(request).notify_superseded
      end
    end
  end

  def notify_conversation_updation
    return unless previous_changes.keys.present? && allowed_keys?
    # Skip generic CONVERSATION_UPDATED only for status changes (which have dedicated events:
    # CONVERSATION_OPENED, CONVERSATION_RESOLVED, CONVERSATION_STATUS_CHANGED).
    # Assignee/team changes still need CONVERSATION_UPDATED for automation rules.
    return if saved_change_to_status?

    dispatch_conversation_updated_event(previous_changes)
  end

  def list_of_keys
    %w[team_id assignee_id assignee_agent_bot_id status snoozed_until custom_attributes label_list waiting_since
       first_reply_created_at priority]
  end

  def allowed_keys?
    (
      previous_changes.keys.intersect?(list_of_keys) ||
      (previous_changes['additional_attributes'].present? && previous_changes['additional_attributes'][1].keys.intersect?(%w[conversation_language]))
    )
  end

  def load_attributes_created_by_db_triggers
    # Display id is set via a trigger in the database
    # So we need to specifically fetch it after the record is created
    # We can't use reload because it will clear the previous changes, which we need for the dispatcher
    attrs = self.class.where(id: id).pick(:display_id, :uuid)
    self[:display_id] = attrs[0]
    self[:uuid] = attrs[1]
  end

  def notify_status_change
    {
      CONVERSATION_OPENED => -> { saved_change_to_status? && open? },
      CONVERSATION_RESOLVED => -> { saved_change_to_status? && resolved? },
      CONVERSATION_STATUS_CHANGED => -> { saved_change_to_status? },
      CONVERSATION_READ => -> { saved_change_to_contact_last_seen_at? },
      CONVERSATION_CONTACT_CHANGED => -> { saved_change_to_contact_id? }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, status_change)
    end
  end

  # Coluna jsonb lida com tolerancia: devolve sempre Hash, mesmo quando o registro
  # guarda uma String JSON (dado gravado torto) ou nil.
  def jsonb_hash(value)
    return value if value.is_a?(Hash)
    return {} if value.blank?

    parsed = JSON.parse(value.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def dispatcher_dispatch(event_name, changed_attributes = nil, extra_data = {})
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, {
      conversation: self,
      notifiable_assignee_change: notifiable_assignee_change?,
      changed_attributes: changed_attributes,
      performed_by: Current.executed_by
    }.merge(extra_data))
  end

  def conversation_status_changed_to_open?
    return false unless open?
    # saved_change_to_status? method only works in case of update
    return true if previous_changes.key?(:id) || saved_change_to_status?
  end

  def create_label_change(user_name)
    return unless user_name

    previous_labels, current_labels = previous_changes[:label_list]
    return unless (previous_labels.is_a? Array) && (current_labels.is_a? Array)

    create_label_added(user_name, current_labels - previous_labels)
    create_label_removed(user_name, previous_labels - current_labels)
  end

  def validate_referer_url
    return unless additional_attributes['referer']

    self['additional_attributes']['referer'] = nil unless url_valid?(additional_attributes['referer'])
  end

  def add_to_appropriate_funnel # rubocop:disable Metrics/AbcSize
    funnels = Kanban::FunnelLookupService.new(account_id: account_id, inbox_id: inbox_id, team_id: team_id).perform

    funnels.each do |funnel|
      target_stage = if status == 'open'
                       funnel.funnel_stages.find_by(automation_type: 'open')
                     elsif status == 'resolved'
                       funnel.funnel_stages.find_by(automation_type: 'resolved')
                     else
                       funnel.funnel_stages.ordered.first
                     end

      next unless target_stage

      FunnelItem.find_or_create_by(funnel_id: funnel.id, conversation_id: id) do |item|
        item.funnel_stage_id = target_stage.id
      end
    end
  rescue StandardError => e
    Rails.logger.error "Error adding conversation #{id} to funnel: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def move_to_automated_stage
    Kanban::MoveConversationToAutomatedStageService.new(
      conversation: self,
      status: status
    ).perform
  end

  def move_to_team_funnel
    Kanban::MoveConversationToTeamFunnelService.new(
      conversation: self,
      team: team_id.present? ? team : nil
    ).perform
  end

  # creating db triggers
  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end
end

Conversation.include_mod_with('Audit::Conversation')
Conversation.include_mod_with('Concerns::Conversation')
Conversation.prepend_mod_with('Conversation')
