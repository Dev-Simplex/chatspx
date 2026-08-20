# Responde o cliente com uma mensagem de VOZ (voice note) em vez de texto, com a voz
# exclusiva do assistente (ElevenLabs -> OGG/Opus -> anexo :audio no pipeline nativo:
# WhatsApp Cloud manda type audio pelo link; WAHA entrega via app Chatwoot externo).
# Capability genérica multi-tenant: opt-in por assistente via config['tools'] +
# config['voice_id'] (dado por conta). QUALQUER falha instrui o agente a responder em
# texto normal — o cliente nunca fica sem resposta por causa do áudio.
#
# Os portões abaixo não são conselho no prompt: a tool recusa sozinha, porque o modelo
# cumpre o que é chamada de ferramenta e esquece o que é texto solto.
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
              'e quando o próprio cliente conversa por áudio. Prefira texto quando a pergunta é curta ' \
              'e objetiva, ou quando ele já demonstrou preferir ler. ' \
              'Regra que manda em tudo: áudio é para o que se entende uma vez, texto é para o que se relê. ' \
              'Valor, endereço, código, data, link e horário combinado vão SEMPRE em texto, porque a pessoa ' \
              'rola a conversa pra trás procurando e áudio não é pesquisável nem copiável — quando a fala ' \
              'citar algum desses, mande junto a linha curta em `resumo_texto`. ' \
              'O áudio substitui a resposta em texto deste turno.'

  param :texto, type: 'string',
                desc: 'Texto exato que será falado no áudio — a resposta que você daria a este turno. ' \
                      'Escreva em linguagem falada natural e concisa, sem markdown, sem links e sem listas.', required: true

  param :a_pedido_do_cliente, type: 'boolean',
                              desc: 'true quando o cliente pediu áudio ou disse que não consegue ler agora; ' \
                                    'false quando responder em voz é iniciativa sua, pelo contexto da conversa.',
                              required: true

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

  # Recusa do cliente vale pra conversa inteira, e manda mais que qualquer permissão.
  RECUSA_DE_AUDIO = Regexp.union(
    /nao\s+(?:manda?e?|quero|gosto|consigo|posso|escuto|ouco)[^.!?]{0,20}audio/,
    /audio\s+nao\b/,
    /sem\s+audio/,
    /odeio\s+audio/,
    /prefiro\s+(?:por\s+)?(?:texto|escrito)/,
    /manda?e?\s+por\s+escrito/
  ).freeze

  # Sem voice_id no config do assistente a tool nem entra no toolset do agente
  # (configured_agent_tools filtra por active?).
  def active?
    @assistant&.config&.[]('voice_id').present?
  end

  def perform(tool_context, texto:, a_pedido_do_cliente: false, resumo_texto: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa. Responda em texto normalmente.' unless conversation

    texto = texto.to_s.strip
    impedimento = impedimento_para(conversation, texto, a_pedido_do_cliente, resumo_texto)
    return impedimento if impedimento

    enviar(conversation, texto, resumo_texto)
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] #{e.class}: #{e.message}")
    'Não consegui gerar o áudio agora. Responda em texto normalmente, sem mencionar a falha ao cliente.'
  end

  private

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

  # Motivo para NÃO mandar o áudio, ou nil quando pode ir. Fora do perform pra manter a
  # leitura do fluxo feliz: identificou a conversa, sintetizou, enviou.
  def impedimento_para(conversation, texto, a_pedido_do_cliente, resumo_texto)
    return 'Não recebi o texto a falar. Responda em texto normalmente.' if texto.blank?

    if texto.length > max_chars
      return "O texto passou do limite de #{max_chars} caracteres pra áudio. " \
             'Chame de novo com uma versão mais curta e falada, ou responda em texto normalmente.'
    end

    # A recusa vence até o pedido: o modelo pode marcar `a_pedido_do_cliente` por engano, e
    # mandar áudio pra quem pediu pra não receber irrita de verdade. O custo do falso
    # positivo aqui é uma resposta em texto — falha benigna, do lado certo.
    if recusou_audio?(conversation)
      return 'O cliente já pediu pra não receber áudio nesta conversa. NÃO mande áudio aqui nunca mais — ' \
             'responda em texto normalmente.'
    end

    return permissao_negada_msg unless a_pedido_do_cliente || audio_proativo_liberado?(conversation)

    falta_resumo_msg(texto, resumo_texto)
  end

  def permissao_negada_msg
    'Neste público o áudio só é permitido quando o próprio cliente pede, ou depois que ele mesmo mandar um áudio. ' \
      'Responda em texto normalmente.'
  end

  def falta_resumo_msg(texto, resumo_texto)
    return nil unless sem_acento(texto).match?(DADO_QUE_SE_RELE) && resumo_texto.to_s.strip.blank?

    'A explicação cita dado que o cliente vai querer reler (valor, endereço, código, data, link ou horário) e você não ' \
      'mandou o `resumo_texto`. Áudio não é pesquisável nem copiável: chame de novo com a linha curta em `resumo_texto`, ' \
      'ou responda em texto normalmente.'
  end

  # Iniciativa de mandar áudio é opt-in, e o default é NÃO. Três portas, porque nem todo tenant
  # usa o catálogo de produto: a do produto resolvido (apresentacao.audio_proativo), a do próprio
  # assistente (config['voice_proativo']) e a RECIPROCIDADE — quem já mandou áudio nesta conversa
  # demonstrou conforto com o formato pela própria ação, não por suposição de perfil. Sem nenhuma
  # das três, o áudio A PEDIDO do cliente continua funcionando exatamente como antes.
  def audio_proativo_liberado?(conversation)
    return true if @assistant&.config&.[]('voice_proativo') == true
    return true if cliente_mandou_audio?(conversation)

    produto_do_lead(conversation)&.audio_proativo? == true
  rescue StandardError => e
    Rails.logger.warn("[ResponderEmAudioTool] produto: #{e.class}: #{e.message}")
    false
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
  #
  # `identify: false` é obrigatório: sem ele o ActiveStorage re-detecta o MIME pelo
  # conteúdo (Marcel) e troca o `audio/ogg` declarado por `audio/opus`. Como o Chatwoot
  # entrega mídia à Cloud API por LINK, a Meta busca a URL, lê esse content-type e
  # rejeita com `131053: Media upload error` — `audio/opus` não está na lista aceita
  # (audio/aac, audio/amr, audio/mpeg, audio/mp4, audio/ogg). O arquivo sempre esteve
  # certo (Ogg/Opus mono 48 kHz); só o rótulo é que a Meta não conhece.
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
      file: { io: audio[:io], filename: audio[:filename], content_type: audio[:content_type], identify: false }
    )
    msg.save!
  end
end
