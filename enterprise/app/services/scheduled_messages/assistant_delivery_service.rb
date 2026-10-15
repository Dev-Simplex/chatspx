# frozen_string_literal: true

# Disparo da AGENDADA escrita pela IA (CHAT-165; engrenagem 2 do docs/contratos/eixo-followup.md).
#
# Sai em nome da IA, nunca de um usuário: fala de usuário conta como resposta humana
# (Message#human_response?) e soltaria o espelho da IA na conversa.
#
# A forma é decidida AGORA, no disparo, e não no agendamento — a janela é medida pela última fala
# do cliente, que pode mudar até lá. Janela aberta: sai o texto pronto. Fechada: texto livre não
# passa no canal, então sai o template que o agente configurou em
# behavior['agendada']['template_fora_janela'] ({ 'name', 'language', 'variaveis' }); sem template, não sai e
# a conversa ganha um aviso.
#
# Não olha handoff nem atribuição: o compromisso foi com o cliente. Quem não quer que ela saia
# cancela a agendada. A única exceção é a IA ainda ser a dona da conversa e o cliente ter escrito
# DEPOIS do agendamento: aí o texto pode ter envelhecido, e a IA o revisa no horário — envia,
# ajusta ou desiste (`descartada?`). Com humano atribuído ou handoff pendente, sai como foi escrito.
class ScheduledMessages::AssistantDeliveryService
  # Origens que uma variável do template fora da janela pode ter.
  VARIABLE_SOURCES = %w[primeiro_nome texto].freeze

  attr_reader :error

  def descartada?
    @descartada == true
  end

  def initialize(scheduled_message:)
    @scheduled_message = scheduled_message
    @conversation = scheduled_message.conversation
    @assistant = scheduled_message.captain_assistant
  end

  def perform
    return revisar_com_a_ia if revisao_pela_ia?
    return create_message(@scheduled_message.message) if @conversation.can_reply?

    deliver_template
  end

  private

  # Fora da janela a IA não pode mandar texto livre, então não há o que revisar: vale o template.
  def revisao_pela_ia?
    @conversation.can_reply? && ia_dona_da_conversa? &&
      @conversation.custom_attributes&.dig('aguardando_humano_desde').blank? &&
      @conversation.messages.incoming.exists?(['messages.created_at > ?', @scheduled_message.created_at])
  end

  def ia_dona_da_conversa?
    mirror = @conversation.assignee_agent_bot
    @conversation.assignee_id.nil? && mirror&.captain? && mirror.captain_assistant_id == @assistant.id
  end

  # A mensagem que a IA mandar neste turno é a agendada cumprida; se ela não mandar nada, desistiu.
  def revisar_com_a_ia
    ultima = @conversation.messages.maximum(:id).to_i
    Captain::Conversation::ResponseBuilderJob.perform_now(@conversation, @assistant, directive: diretiva_de_revisao)
    enviada = @conversation.messages.outgoing.where(sender: @assistant).where('messages.id > ?', ultima).order(:id).first
    return enviada if enviada

    @descartada = true
    @error = I18n.t('scheduled_messages.errors.discarded_by_assistant_review')
    nil
  end

  def diretiva_de_revisao
    '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] Chegou o horário da mensagem que você agendou ' \
      "nesta conversa, com este texto: \"#{@scheduled_message.message}\". O cliente escreveu depois que você a agendou. " \
      'Se ela ainda faz sentido, envie-a agora, ajustada ao que ele disse depois se for preciso. Se o cliente combinou outro ' \
      'momento, agende de novo com agendar_mensagem e responda só [IGNORAR]. Se o que ela retoma já foi resolvido na ' \
      'conversa, responda só [IGNORAR].'
  end

  # Cada variável do corpo do template é preenchida por uma ORIGEM que o agente declara em
  # template_fora_janela['variaveis'] ({ '1' => 'primeiro_nome', '2' => 'texto' }), de uma lista
  # fechada (VARIABLE_SOURCES). Sem 'variaveis', vale o caso mais simples: {{1}} = primeiro nome.
  # Variável sem origem, ou origem sem valor, não sai pela metade: a agendada falha com o motivo.
  def deliver_template
    template = configured_template
    return fail_with(:window_closed_no_template) if template.nil?

    body = template_body(template)
    sources = variable_sources
    params = {}
    body.scan(/\{\{(\d+)\}\}/).flatten.uniq.each do |variable|
      return fail_with(:template_unsupported_variables) unless VARIABLE_SOURCES.include?(sources[variable])

      value = variable_value(sources[variable])
      return fail_with(:"template_without_#{sources[variable]}") if value.blank?

      params[variable] = value
    end

    content = body.gsub(/\{\{(\d+)\}\}/) { params[Regexp.last_match(1)] }
    create_message(content, template_params: template_params(template, params))
  end

  def variable_sources
    @assistant.behavior.dig('agendada', 'template_fora_janela', 'variaveis').presence || { '1' => 'primeiro_nome' }
  end

  # Parâmetro de template do WhatsApp não aceita quebra de linha, tabulação nem espaços em
  # sequência: o texto pronto vai numa linha só.
  def variable_value(source)
    case source
    when 'primeiro_nome' then @conversation.contact&.name.to_s.split.first
    when 'texto' then @scheduled_message.message.to_s.gsub(/\s+/, ' ').strip
    end
  end

  def template_params(template, body_params)
    { 'name' => template['name'], 'language' => template['language'], 'processed_params' => { 'body' => body_params } }
  end

  def configured_template
    config = @assistant.behavior&.dig('agendada', 'template_fora_janela')
    return if config.blank? || !@conversation.inbox.channel.respond_to?(:message_templates)

    Array(@conversation.inbox.channel.message_templates).find do |t|
      t['name'] == config['name'] &&
        t['language'].to_s.casecmp?(config['language'].to_s) &&
        t['status'].to_s.casecmp?('approved')
    end
  end

  def template_body(template)
    Array(template['components']).find { |c| c['type'].to_s.casecmp?('BODY') }&.dig('text').to_s
  end

  def create_message(content, template_params: nil)
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: content,
      content_attributes: {
        'scheduled_at' => @scheduled_message.scheduled_at&.iso8601,
        'scheduled_by' => { 'id' => @assistant.id, 'name' => @assistant.name }
      },
      additional_attributes: template_params ? { 'template_params' => template_params } : {}
    )
  end

  def fail_with(reason)
    @error = I18n.t("scheduled_messages.errors.#{reason}")
    I18n.with_locale(@conversation.account.locale) do
      @conversation.messages.create!(
        message_type: :activity,
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        content: I18n.t('scheduled_messages.activity.assistant_not_sent',
                        reason: I18n.t("scheduled_messages.errors.#{reason}"))
      )
    end
    nil
  end
end
