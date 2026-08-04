# Responde o cliente com uma mensagem de VOZ (voice note) em vez de texto, com a voz
# exclusiva do assistente (ElevenLabs -> OGG/Opus -> anexo :audio no pipeline nativo:
# WhatsApp Cloud manda type audio pelo link; WAHA entrega via app Chatwoot externo).
# Capability genérica multi-tenant: opt-in por assistente via config['tools'] +
# config['voice_id'] (dado por conta). QUALQUER falha instrui o agente a responder em
# texto normal — o cliente nunca fica sem resposta por causa do áudio.
#
# O gatilho é o TIPO DE CONTEÚDO (resposta longa e explicativa), não um pedido do
# cliente. Os portões abaixo não são conselho no prompt: a tool recusa sozinha, porque
# o modelo cumpre o que é chamada de ferramenta e esquece o que é texto solto.
class Captain::Tools::ResponderEmAudioTool < Captain::Tools::BasePublicTool
  description 'Responde o cliente com uma mensagem de voz (áudio) em vez de texto. ' \
              'Use quando a resposta for LONGA E EXPLICATIVA: explicar como funciona algo, por que uma opção compensa, ' \
              'como é um lugar. NÃO use em atendimento padrão nem para responder um dado pontual. ' \
              'Regra que manda em tudo: áudio é para o que se entende uma vez, texto é para o que se relê. ' \
              'Valor, endereço, código, data, link e horário combinado vão SEMPRE em texto, porque a pessoa rola a conversa ' \
              'pra trás procurando e áudio não é pesquisável nem copiável. ' \
              'Nunca só áudio: mande junto, em `resumo_texto`, a linha curta com esses dados. ' \
              'A ferramenta recusa sozinha quando o cliente nunca mandou áudio nesta conversa ou já pediu pra não receber áudio.'

  param :texto, type: 'string',
                desc: 'Texto exato que será falado no áudio — a explicação que você daria a este turno. ' \
                      'Escreva em linguagem falada natural e concisa, sem markdown, sem links e sem listas.', required: true
  param :resumo_texto,
        type: 'string',
        desc: 'Linha curta que vai em TEXTO junto do áudio, com os dados que o cliente vai querer reler ou copiar depois. ' \
              'Preencha sempre que a explicação citar valor, endereço, código, data, link ou horário combinado.',
        required: false

  DEFAULT_MAX_CHARS = 800

  # ATENÇÃO: os padrões abaixo rodam sobre texto SEM ACENTO e em minúscula (ver #sem_acento).
  # O /i do Ruby não dobra maiúscula acentuada dentro de classe de caracteres — "NÃO MANDA
  # ÁUDIO" escapava de /[ãa]/i. Normalizar é o que faz caps e acento pararem de importar.

  # Dado que a pessoa volta pra procurar: se aparece na fala, tem que existir em texto.
  DADO_QUE_SE_RELE = %r{r\$\s*[\d.,]+|https?://|\bcod(?:igo)?\b[^.!?]{0,15}\d|\b\d{1,2}/\d{1,2}|\b\d{1,2}\s*h\b|\b\d{1,2}:\d{2}\b}

  # Recusa do cliente vale pra conversa inteira, e manda mais que os dois portões.
  RECUSA_DE_AUDIO = Regexp.union(
    /nao\s+(?:manda?e?|quero|gosto|consigo|posso|escuto|ouco)[^.!?]{0,20}audio/,
    /audio\s+nao\b/,
    /sem\s+audio/,
    /odeio\s+audio/,
    /prefiro\s+(?:por\s+)?(?:texto|escrito)/,
    /manda?e?\s+por\s+escrito/
  )

  # Sem voice_id no config do assistente a tool nem entra no toolset do agente
  # (configured_agent_tools filtra por active?).
  def active?
    @assistant&.config&.[]('voice_id').present?
  end

  def perform(tool_context, texto:, resumo_texto: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa. Responda em texto normalmente.' unless conversation

    texto = texto.to_s.strip
    return 'Não recebi o texto a falar. Responda em texto normalmente.' if texto.blank?

    bloqueio = motivo_para_nao_mandar_audio(conversation, texto, resumo_texto)
    return bloqueio if bloqueio

    enviar(conversation, texto, resumo_texto)
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] #{e.class}: #{e.message}")
    'Não consegui gerar o áudio agora. Responda em texto normalmente, sem mencionar a falha ao cliente.'
  end

  private

  MSG_PRODUTO = 'Este produto não está liberado pra resposta proativa em áudio. Responda em texto normalmente.'.freeze

  def enviar(conversation, texto, resumo_texto)
    tts = Captain::ElevenLabsTtsService.new(@assistant)
    return 'Resposta em áudio não está configurada pra este agente. Responda em texto normalmente.' unless tts.configured?

    com_resumo = resumo_texto.to_s.strip.present?
    send_voice_message(conversation, texto, tts.synthesize(texto))
    enviar_linha_de_registro(conversation, resumo_texto)
    log_tool_usage('responder_em_audio', conversation_id: conversation.id, chars: texto.length, com_resumo: com_resumo)
    "Áudio enviado como resposta deste turno#{com_resumo ? ', com a linha de registro em texto' : ''}. " \
      'NÃO repita o conteúdo em texto — encerre respondendo apenas [IGNORAR].'
  end

  # nil = pode mandar. String = o porquê de não mandar, já no formato de instrução ao agente.
  def motivo_para_nao_mandar_audio(conversation, texto, resumo_texto)
    if texto.length > max_chars
      return "O texto passou do limite de #{max_chars} caracteres pra áudio. " \
             'Chame de novo com uma versão mais curta e falada, ou responda em texto normalmente.'
    end

    if recusou_audio?(conversation)
      return 'O cliente já pediu pra não receber áudio nesta conversa. NÃO mande áudio aqui nunca mais — ' \
             'responda em texto normalmente.'
    end

    unless cliente_mandou_audio?(conversation)
      return 'O cliente ainda não mandou nenhum áudio nesta conversa, então não dá pra saber se ele é confortável ' \
             'com áudio. Responda em texto normalmente. Se ele mandar um áudio em algum momento, aí sim vale usar.'
    end

    return MSG_PRODUTO unless produto_permite_audio?(conversation)

    return nil unless sem_acento(texto).match?(DADO_QUE_SE_RELE) && resumo_texto.to_s.strip.blank?

    'A explicação cita dado que o cliente vai querer reler (valor, endereço, código, data, link ou horário) e você não ' \
      'mandou o `resumo_texto`. Áudio não é pesquisável nem copiável: chame de novo com a linha curta em `resumo_texto`, ' \
      'ou responda em texto normalmente.'
  end

  # Reciprocidade: permissão demonstrada pela ação do cliente, não suposta pelo perfil.
  def cliente_mandou_audio?(conversation)
    conversation.messages.incoming
                .joins(:attachments)
                .exists?(attachments: { file_type: Attachment.file_types[:audio] })
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] reciprocidade: #{e.message}")
    false
  end

  def recusou_audio?(conversation)
    conversation.messages.incoming.where.not(content: [nil, '']).pluck(:content)
                .any? { |c| sem_acento(c).match?(RECUSA_DE_AUDIO) }
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] recusa: #{e.message}")
    false
  end

  def sem_acento(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
  end

  # Portão de produto: lê `audio_proativo?` do catálogo quando ele existir. Enquanto o
  # catálogo não estiver populado (ou o vínculo não existir), não bloqueia — senão a
  # capability fica morta esperando um dado que ainda não é gravado.
  def produto_permite_audio?(conversation)
    produto = produto_da_conversa(conversation)
    return true if produto.nil? || !produto.respond_to?(:audio_proativo?)

    produto.audio_proativo?
  end

  def produto_da_conversa(conversation)
    return nil unless defined?(Produto)
    return conversation.produto if conversation.respond_to?(:produto)

    nil
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] produto: #{e.message}")
    nil
  end

  # Áudio explica, texto registra: a linha curta vai como mensagem de texto normal,
  # logo depois da voz, pra ficar pesquisável e copiável na conversa.
  def enviar_linha_de_registro(conversation, resumo_texto)
    linha = resumo_texto.to_s.strip
    return if linha.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      content: linha
    )
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
