# Empurra para o Captador o que acontece nas conversas que ele abriu (22 §1.5): resposta do lead
# (com opt_out quando é recusa), resposta do vendedor, status de entrega (o motivo da falha vem em
# content_attributes.external_error), conversa resolvida ou reaberta e troca de dono ou de time.
#
# Mesmo payload e mesma assinatura dos webhooks de conta (X-Chatwoot-Signature com o segredo do
# hook), pelo WebhookJob, com as retentativas dele. O filtro começa pelo que já está em memória
# (custom_attributes.captador_lead_id): conversa comum não custa nenhuma consulta.
#
# Cada handler tem rescue próprio: o listener roda para TODA conta no AsyncDispatcher, e uma
# exceção aqui derrubaria os listeners seguintes do EventDispatcherJob.
class Spx::CaptadorListener < BaseListener
  OWNER_ATTRIBUTES = %w[assignee_id team_id].freeze

  def message_created(event)
    safely(event) do
      message = event.data[:message]
      next if message.private? || !(message.incoming? || message.outgoing?)

      hook = captador_hook(message.conversation)
      next unless hook

      payload = message.webhook_data.merge(event: __method__.to_s)
      payload[:captador] = { opt_out: true } if message.incoming? && Contacts::OptOutDetector.opt_out?(message.content)
      deliver(hook, payload)
    end
  end

  def message_updated(event)
    safely(event) do
      message = event.data[:message]
      changed = message_changes(event)
      next unless changed_any?(changed, %w[status])

      hook = captador_hook(message.conversation)
      deliver(hook, message.webhook_data.merge(event: __method__.to_s, changed_attributes: changed)) if hook
    end
  end

  def conversation_status_changed(event)
    safely(event) { deliver_conversation(event, __method__.to_s) }
  end

  def conversation_updated(event)
    safely(event) do
      next unless changed_any?(extract_changed_attributes(event), OWNER_ATTRIBUTES)

      deliver_conversation(event, __method__.to_s)
    end
  end

  # Conversation#notify_conversation_updation não despacha conversation_updated quando o mesmo save
  # também muda o status: a troca de dono ou de time desse save só aparece nestes dois eventos, que
  # trazem o previous_changes inteiro. Sem mudança de status, o conversation_updated já entregou.
  def assignee_changed(event)
    safely(event) { deliver_owner_change_with_status(event) }
  end

  def team_changed(event)
    safely(event) do
      # Dono e time no mesmo save: o assignee_changed já entregou.
      next if changed_any?(extract_changed_attributes(event), %w[assignee_id])

      deliver_owner_change_with_status(event)
    end
  end

  private

  # Message#send_update_event despacha as mudanças em previous_changes, e não em changed_attributes
  # (o que o extract_changed_attributes lê). Aceita os dois, no formato do webhook de conta, que é o
  # que o Captador lê: [{ "status" => { previous_value:, current_value: } }].
  def message_changes(event)
    extract_changed_attributes(event) ||
      event.data[:previous_changes]&.map { |attr, (previous, current)| { attr => { previous_value: previous, current_value: current } } }
  end

  def deliver_owner_change_with_status(event)
    return unless changed_any?(extract_changed_attributes(event), %w[status])

    deliver_conversation(event, 'conversation_updated')
  end

  def deliver_conversation(event, event_name)
    conversation = event.data[:conversation]
    hook = captador_hook(conversation)
    return unless hook

    deliver(hook, conversation.webhook_data.merge(event: event_name, changed_attributes: extract_changed_attributes(event)))
  end

  def captador_hook(conversation)
    return if conversation&.custom_attributes&.dig('captador_lead_id').blank?
    return unless conversation.account.captador_integration_enabled?

    conversation.account.hooks.find_by(app_id: Spx::Captador::BaseController::APP_ID, status: 'enabled')
  end

  def deliver(hook, payload)
    settings = hook.settings
    url = "#{settings['captador_url'].to_s.chomp('/')}/webhooks/chatspx/#{settings['instance_key']}"
    # O WebhookJob é da frota e posta em qualquer destino: o filtro contra SSRF fica aqui, antes de enfileirar.
    unless Spx::Captador::Client.allowed_url?(url)
      return Rails.logger.warn("[Spx::CaptadorListener] destino recusado conta=#{hook.account_id}: #{url}")
    end
    begin
      Flows::SafeHttpClient.new(method: :post, url: url).validate_destination!
    rescue Flows::StepSkip => e
      return Rails.logger.warn("[Spx::CaptadorListener] destino recusado conta=#{hook.account_id}: #{e.message}")
    end

    WebhookJob.perform_later(url, payload, :account_webhook, secret: hook.captador_shared_secret, delivery_id: SecureRandom.uuid)
  end

  def changed_any?(changed, attributes)
    Array(changed).any? { |change| change.keys.map(&:to_s).intersect?(attributes) }
  end

  def safely(event)
    yield
  rescue StandardError => e
    Rails.logger.error("[Spx::CaptadorListener] #{event&.name}: #{e.class}: #{e.message}")
  end
end
