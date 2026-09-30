# == Schema Information
#
# Table name: campaigns
#
#  id                                 :bigint           not null, primary key
#  audience                           :jsonb
#  campaign_status                    :integer          default("active"), not null
#  campaign_type                      :integer          default("ongoing"), not null
#  description                        :text
#  enabled                            :boolean          default(TRUE)
#  message                            :text             not null
#  scheduled_at                       :datetime
#  template_params                    :jsonb
#  title                              :string           not null
#  trigger_only_during_business_hours :boolean          default(FALSE)
#  trigger_rules                      :jsonb
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  account_id                         :bigint           not null
#  display_id                         :integer          not null
#  inbox_id                           :bigint           not null
#  sender_id                          :integer
#
# Indexes
#
#  index_campaigns_on_account_id       (account_id)
#  index_campaigns_on_campaign_status  (campaign_status)
#  index_campaigns_on_campaign_type    (campaign_type)
#  index_campaigns_on_inbox_id         (inbox_id)
#  index_campaigns_on_scheduled_at     (scheduled_at)
#
class Campaign < ApplicationRecord
  include UrlHelper
  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :title, presence: true
  validates :message, presence: true
  validate :validate_campaign_inbox
  validate :validate_url
  validate :prevent_completed_campaign_from_update, on: :update
  validate :sender_must_belong_to_account
  validate :inbox_must_belong_to_account
  validate :dispatch_assignee_must_belong_to_account
  # CHAT-155: so na criacao/troca de caixa -- uma campanha antiga precisa continuar mudando de status.
  validate :inbox_not_read_only, if: :will_save_change_to_inbox_id?

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true
  # Time que a conversa recebe no disparo em massa (fica fechada e sem agente).
  belongs_to :target_team, class_name: 'Team', optional: true
  # Dono do disparo (opcional): quem atende as respostas DESTA campanha. Sem ele,
  # a conversa fecha sem agente e o reply reabre pra fila do time.
  # ATENCAO: so em inbox SEM IA — atribuir humano dispara o
  # `reset_agent_bot_when_assignee_present` e cala o agente. Ver migration
  # 20260731120100 e, pra inbox com IA, a designacao da frente spx/rodizio.
  belongs_to :dispatch_assignee, class_name: 'User', optional: true

  enum campaign_type: { ongoing: 0, one_off: 1 }
  # TODO : enabled attribute is unneccessary . lets move that to the campaign status with additional statuses like draft, disabled etc.
  enum campaign_status: { active: 0, completed: 1 }
  # Estado da engine de disparo em massa (Campaigns::Whatsapp::*). Independente
  # do campaign_status nativo. Prefixo evita colisao com :completed do campaign_status.
  enum dispatch_status: { draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4, failed: 5 },
       _prefix: :dispatch

  has_many :conversations, dependent: :nullify, autosave: true
  has_many :campaign_recipients, dependent: :destroy

  before_validation :ensure_correct_campaign_attributes
  before_validation :derive_dispatch_template
  after_commit :set_display_id, unless: :display_id?

  def trigger!
    return unless one_off?
    return if completed?
    return if inbox.read_only? # CHAT-155: campanha criada antes de a caixa virar somente leitura

    execute_campaign
  end

  # Disparo em massa WhatsApp dirigido pela engine (template HSM + lista). O
  # blaster nativo (execute_campaign) segue no-op p/ WhatsApp; quem dispara e o
  # Campaigns::Whatsapp::DispatchSchedulerJob.
  def whatsapp_blast?
    inbox&.inbox_type == 'Whatsapp' && template_name.present?
  end

  # O que impede o disparo de começar, ou nil. Regra ÚNICA do botão Iniciar
  # (CampaignsController#start) e do agendamento (DispatchSchedulerJob): se as duas
  # divergissem, a campanha agendada sairia sem o que o botão exige. O time entra porque,
  # sem ele, a conversa nasce sem time e a resposta do lead cai sem dono.
  def dispatch_start_blocker
    return 'Campanha sem destinatários' if campaign_recipients.empty?
    return 'Defina o template do disparo' if template_name.blank?

    'Defina o time que recebe as conversas' if target_team_id.blank?
  end

  private

  def execute_campaign
    case inbox.inbox_type
    when 'Twilio SMS'
      Twilio::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Sms'
      Sms::OneoffSmsCampaignService.new(campaign: self).perform
    when 'Whatsapp'
      # Disparo de WhatsApp e feito pelo orquestrador SPX (Spx::Tozi / DisparoLeadJob):
      # pacing, atribuicao round-robin por corretor e rotacao de template. O blaster
      # nativo (loop sem pacing) fica DESATIVADO para nao atropelar a operacao nem a
      # qualidade/tier do WABA. Campanhas WhatsApp existem so como ancora/registro.
      Rails.logger.warn("[Campaign ##{id}] WhatsApp one-off nativo desativado — envio via orquestrador SPX.")
    end
  end

  def set_display_id
    reload
  end

  def validate_campaign_inbox
    return unless inbox

    errors.add :inbox, 'Unsupported Inbox type' unless ['Website', 'Twilio SMS', 'Sms', 'Whatsapp'].include? inbox.inbox_type
  end

  # TO-DO we clean up with better validations when campaigns evolve into more inboxes
  def ensure_correct_campaign_attributes
    return if inbox.blank?

    if ['Twilio SMS', 'Sms', 'Whatsapp'].include?(inbox.inbox_type)
      self.campaign_type = 'one_off'
      self.scheduled_at ||= Time.now.utc
    else
      self.campaign_type = 'ongoing'
      self.scheduled_at = nil
    end
  end

  # A tela escolhe o template no formato nativo (`template_params.name/language`) e o motor
  # dispara por `template_name`. Derivar aqui, e não no formulário, vale para qualquer
  # criador — inclusive um front antigo em cache depois do deploy. Só preenche o vazio:
  # o que o console gravou explicitamente continua valendo.
  def derive_dispatch_template
    return unless inbox&.inbox_type == 'Whatsapp' && template_name.blank?

    name = template_params.is_a?(Hash) ? template_params['name'].presence : nil
    return if name.blank?

    self.template_name = name
    self.template_language = template_params['language'].presence || template_language
  end

  def validate_url
    return unless trigger_rules['url']

    use_http_protocol = trigger_rules['url'].starts_with?('http://') || trigger_rules['url'].starts_with?('https://')
    errors.add(:url, 'invalid') if inbox.inbox_type == 'Website' && !use_http_protocol
  end

  def inbox_not_read_only
    errors.add(:base, I18n.t('errors.read_only_inbox.campaign_blocked')) if inbox&.read_only?
  end

  def inbox_must_belong_to_account
    return unless inbox

    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account as the campaign')
  end

  def sender_must_belong_to_account
    return unless sender

    return if account.users.exists?(id: sender.id)

    errors.add(:sender_id, 'must belong to the same account as the campaign')
  end

  # Dono de fora da conta seria descartado em silencio pelo AssignmentService
  # (que so resolve usuarios da conta) — e o disparo inteiro nasceria sem dono.
  def dispatch_assignee_must_belong_to_account
    return if dispatch_assignee.blank?
    return if account.users.exists?(id: dispatch_assignee_id)

    errors.add(:dispatch_assignee_id, 'must belong to the same account as the campaign')
  end

  def prevent_completed_campaign_from_update
    errors.add :status, 'The campaign is already completed' if !campaign_status_changed? && completed?
  end

  # creating db triggers
  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end
end
