# frozen_string_literal: true

# Funde os dois overrides existentes do ActionService num só. A base ActionService já
# traz ~13 ações compartilhadas + o mixin enterprise (add_sla/assign_ai_agent via
# ActionService.include_mod_with, action_service.rb:113); aqui unificamos o que divergia
# entre AutomationRules::ActionService (autor = nil + anti-loop) e Macros::ExecutionService
# (autor = actor + 'self'). A semântica depende do `actor`:
#   • actor presente  → macro-like  (disparo manual: autor = actor, permite assign_agent 'self')
#   • actor ausente   → automation-like (por evento: autor = nil, anti-loop via flow_id)
# O loop sobre os nós fica no Flows::RunnerService; aqui executamos UM nó por vez.
# Ver plano §2.4.
class Flows::ActionService < ActionService
  def initialize(flow:, conversation:, actor: nil)
    super(conversation)
    @flow = flow
    @account = flow.account
    @actor = actor
    actor ? (Current.user = actor) : (Current.executed_by = flow)
  end

  # Executa UM nó `type:"action"`. Best-effort por nó (padrão de
  # automation_rules/action_service.rb:13-17): um erro num nó não derruba o fluxo — o
  # Runner segue para o próximo. Dispatch via `send` (métodos de ação são privados),
  # nunca `public_send`.
  def execute(node)
    @conversation.reload
    action = node.with_indifferent_access
    send(action[:action_name], action[:action_params])
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    nil
  end

  private

  # nil no modo automação (mensagem "do sistema"); o actor no modo manual.
  def author
    @actor
  end

  # Anti-loop: marca as mensagens do motor com flow_id para o listener não re-disparar.
  # Generaliza automation_rules/action_service.rb:46. No modo manual (autor humano) não
  # há loop a evitar, então fica vazio (paridade com o macro, que não marca nada).
  def message_content_attributes
    @actor ? {} : { flow_id: @flow.id }
  end

  # 'self' só faz sentido no modo manual (macros/execution_service.rb:31-34); no modo
  # automação vira nil e é descartado.
  def assign_agent(agent_ids)
    agent_ids = agent_ids.filter_map { |id| id == 'self' ? @actor&.id : id }
    super(agent_ids)
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false, content_attributes: message_content_attributes }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true, content_attributes: message_content_attributes }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Fonte do anexo é @flow.files (era @rule.files / @macro.files).
  def send_attachment(blob_ids)
    return if conversation_a_tweet?
    return unless @flow.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)
    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  def send_webhook_event(webhook_url)
    payload = @conversation.webhook_data.merge(event: webhook_event_name)
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  # Exclusivo da automação hoje (automation_rules/action_service.rb:57); no Flow vale para
  # ambos os modos porque a base é uma só.
  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])
    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  def webhook_event_name
    event_name = @flow.trigger_config['event_name'].presence
    return 'flow.executed' if @actor || event_name.nil?

    "flow_event.#{event_name}"
  end

  # Envia um template WhatsApp aprovado (gap-BR nº1). A infra de envio já existe: basta
  # criar a mensagem outgoing com `template_params` — o Message resolve o Liquid dos
  # processed_params (Liquidable) e o SendOnWhatsappService entrega como template, dentro
  # OU fora da janela de 24h. Precedente: scheduled_messages/send_service.rb:43. Guards:
  # inbox whatsapp_cloud e template aprovado (no-op silencioso se ausente, padrão add_sla).
  def send_template(action_params)
    return if conversation_a_tweet?

    template = action_params[0].to_h.with_indifferent_access
    return unless whatsapp_cloud_inbox?
    return unless approved_template?(template)

    params = {
      message_type: 'outgoing',
      content: template['content'],
      template_params: {
        'name' => template['name'],
        'language' => template['language'],
        'processed_params' => template['processed_params'] || {}
      },
      content_attributes: message_content_attributes
    }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Grava um atributo na conversa ou no contato (custom_attributes por padrão, ou
  # additional_attributes). O valor aceita Liquid ({{contact.name}}). Sem infra nova.
  # (set_attribute é um action_name do vocabulário, não um writer method.)
  def set_attribute(action_params) # rubocop:disable Naming/AccessorMethodName
    config = action_params[0].to_h.with_indifferent_access
    target = config['target'].to_s == 'contact' ? @conversation.contact : @conversation.reload
    key = config['key'].to_s
    return if target.blank? || key.blank?

    store = config['store'].to_s == 'additional' ? :additional_attributes : :custom_attributes
    current = target.public_send(store) || {}
    target.update!(store => current.merge(key => render_liquid(config['value'])))
  end

  def whatsapp_cloud_inbox?
    channel = @conversation.inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def approved_template?(template)
    templates = @conversation.inbox.channel.message_templates
    templates.present? && templates.any? { |candidate| template_matches?(candidate, template) }
  end

  def template_matches?(candidate, template)
    candidate['name'] == template['name'] &&
      candidate['language']&.downcase == template['language']&.downcase &&
      candidate['status']&.downcase == 'approved'
  end

  def render_liquid(value)
    return value unless value.is_a?(String) && value.include?('{{')

    Liquid::Template.parse(value).render(liquid_drops)
  rescue Liquid::Error
    value
  end

  def liquid_drops
    {
      'contact' => ContactDrop.new(@conversation.contact),
      'conversation' => ConversationDrop.new(@conversation),
      'account' => AccountDrop.new(@account)
    }
  end
end
