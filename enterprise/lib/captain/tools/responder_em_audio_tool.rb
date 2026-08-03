# Responde o cliente com uma mensagem de VOZ (voice note) em vez de texto, com a voz
# exclusiva do assistente (ElevenLabs -> OGG/Opus -> anexo :audio no pipeline nativo:
# WhatsApp Cloud manda type audio pelo link; WAHA entrega via app Chatwoot externo).
# Capability genérica multi-tenant: opt-in por assistente via config['tools'] +
# config['voice_id'] (dado por conta). QUALQUER falha instrui o agente a responder em
# texto normal — o cliente nunca fica sem resposta por causa do áudio.
class Captain::Tools::ResponderEmAudioTool < Captain::Tools::BasePublicTool
  include Captain::Tools::ProdutoApresentacao

  # A regra antiga ("chame SOMENTE quando o cliente pedir") proibia justamente o uso que se
  # quer: explicar por voz o que cansa em texto. Virou JULGAMENTO — o agente decide pela
  # conversa. O que continua sendo config, e não julgamento, é a PERMISSÃO de tomar a
  # iniciativa: áudio de empresa é mais invasivo que texto, e o que converte num público
  # irrita outro. Por isso o áudio a pedido do cliente é sempre permitido, e o proativo é
  # opt-in por produto (ou por assistente, para quem não usa catálogo de produto).
  description 'Responde o cliente com uma mensagem de voz em vez de texto. Use seu julgamento: ' \
              'a voz ajuda quando a explicação é longa ou delicada e ficaria cansativa de ler, ' \
              'e quando o próprio cliente conversa por áudio. Prefira texto quando a resposta ' \
              'precisa de dado que ele vai querer reler ou copiar, quando a pergunta é curta e ' \
              'objetiva, ou quando ele já demonstrou preferir ler. ' \
              'O áudio substitui a resposta em texto deste turno.'

  param :texto, type: 'string',
                desc: 'Texto exato que será falado no áudio — a resposta que você daria a este turno. ' \
                      'Escreva em linguagem falada natural e concisa, sem markdown, sem links e sem listas.', required: true

  param :a_pedido_do_cliente, type: 'boolean',
                              desc: 'true quando o cliente pediu áudio ou disse que não consegue ler agora; ' \
                                    'false quando responder em voz é iniciativa sua, pelo contexto da conversa.',
                              required: true

  DEFAULT_MAX_CHARS = 800

  # Sem voice_id no config do assistente a tool nem entra no toolset do agente
  # (configured_agent_tools filtra por active?).
  def active?
    @assistant&.config&.[]('voice_id').present?
  end

  def perform(tool_context, texto:, a_pedido_do_cliente: false)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa. Responda em texto normalmente.' unless conversation

    texto = texto.to_s.strip
    impedimento = impedimento_para(conversation, texto, a_pedido_do_cliente)
    return impedimento if impedimento

    tts = Captain::ElevenLabsTtsService.new(@assistant)
    return 'Resposta em áudio não está configurada pra este agente. Responda em texto normalmente.' unless tts.configured?

    send_voice_message(conversation, texto, tts.synthesize(texto))
    log_tool_usage('responder_em_audio', conversation_id: conversation.id, chars: texto.length)
    'Áudio enviado como resposta deste turno. NÃO repita o conteúdo em texto — encerre respondendo apenas [IGNORAR].'
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] #{e.class}: #{e.message}")
    'Não consegui gerar o áudio agora. Responda em texto normalmente, sem mencionar a falha ao cliente.'
  end

  private

  # Motivo para NÃO mandar o áudio, ou nil quando pode ir. Fora do perform pra manter a
  # leitura do fluxo feliz: identificou a conversa, sintetizou, enviou.
  def impedimento_para(conversation, texto, a_pedido_do_cliente)
    return 'Não recebi o texto a falar. Responda em texto normalmente.' if texto.blank?

    if texto.length > max_chars
      return "O texto passou do limite de #{max_chars} caracteres pra áudio. " \
             'Chame de novo com uma versão mais curta e falada, ou responda em texto normalmente.'
    end
    return if a_pedido_do_cliente || audio_proativo_liberado?(conversation)

    'Neste público o áudio só é permitido quando o próprio cliente pede. Responda em texto normalmente.'
  end

  # Iniciativa de mandar áudio é opt-in, e o default é NÃO. Duas portas, porque nem todo tenant
  # usa o catálogo de produto: a do produto resolvido (apresentacao.audio_proativo) e a do
  # próprio assistente (config['voice_proativo']), para quem não tem catálogo. Sem nenhuma das
  # duas, o áudio A PEDIDO do cliente continua funcionando exatamente como antes.
  def audio_proativo_liberado?(conversation)
    return true if @assistant&.config&.[]('voice_proativo') == true

    produto_do_lead(conversation)&.audio_proativo? == true
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] produto: #{e.class}: #{e.message}")
    false
  end

  def max_chars
    (@assistant&.config&.[]('voice_max_chars').presence || DEFAULT_MAX_CHARS).to_i
  end

  # Transcript no content + anexo de áudio na MESMA mensagem: dashboard e Eval enxergam
  # o que foi falado; no WhatsApp Cloud o áudio sai sem caption (o texto não duplica pro
  # cliente). Anexo construído ANTES do save — o envio dispara no after_create_commit
  # (mesmo cuidado da EnviarFotosImovelTool).
  def send_voice_message(conversation, texto, audio)
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      content: texto
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :audio,
      file: { io: audio[:io], filename: audio[:filename], content_type: audio[:content_type] }
    )
    msg.save!
  end
end
