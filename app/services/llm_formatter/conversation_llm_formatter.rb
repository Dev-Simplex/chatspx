class LlmFormatter::ConversationLlmFormatter < LlmFormatter::DefaultLlmFormatter
  # --- Conversa de GRUPO de WhatsApp ---------------------------------------------------------
  #
  # Numa conversa de grupo o remetente do Chatwoot é sempre o contato-GRUPO, então a fala de
  # todos os participantes chegava ao LLM rotulada como "User:" — o modelo lia N pessoas como se
  # fossem um cliente só. Pior: o texto ainda carrega o prefixo que a app Chatwoot da WAHA injeta
  # no corpo ("👥 *Nome (229480102662169@lid)*"), que gasta token e enche o contexto com um
  # identificador técnico sem nenhum significado para o modelo.
  #
  # Em grupo o transcript passa a sair como "<Nome do participante>: <texto>".
  #
  # Fonte do autor, em ordem: `content_attributes['group_sender']` (contrato C2, gravado na
  # ingestão) e, para o histórico já gravado, o prefixo dentro do próprio texto. A leitura é
  # DEFENSIVA — funciona com e sem o campo — porque as duas gerações de mensagem convivem na
  # mesma conversa. Sem conseguir identificar o autor, cai no rótulo genérico de sempre: nunca
  # inventamos um nome, e nunca vaza o identificador técnico para o prompt.
  #
  # O formato ATUAL ("👥 *Nome (LID@lid)*", app Chatwoot da WAHA a partir de dez/2025) é lido
  # DELEGANDO para `Whatsapp::GroupSenderExtractor` — o mesmo serviço que a ingestão usa para
  # gravar o C2. Um segundo parser para o mesmo prefixo divergiria com o tempo.
  #
  # Formato FÓSSIL (Evolution API, até ago/2025): "**+55 (66) 9683-6077 - Sentinela:**\n\ntexto".
  # É o mais comum no histórico desta base: 4.800 mensagens de grupo, contra 513 do formato novo.
  # O `\d{2,}` no rótulo é o discriminador que evita casar um negrito legítimo ("**Resumo:**").
  FOSSIL_GROUP_PREFIX = /\A\*\*((?=[^\n]*\d\d)[^\n]{1,100}?):\*\*\n{1,2}/
  # Nome do participante dentro do rótulo fóssil: o que vem depois do último " - " (o telefone,
  # mascarado ou não, fica antes). Sem separador, o rótulo inteiro é usado.
  FOSSIL_LABEL_NAME = /\A(?<phone>.*)\s-\s(?<name>[^-]+)\z/
  LEGACY_LID_TOKEN = /\s*\(\d{8,}@lid\)/
  BIDI_MARKS = /[‎‏‪-‮⁦-⁩]/
  GROUP_NAME_SUFFIX = /\s*\((?:GROUP|Group|Grupo)\)\s*\z/

  def format(config = {})
    sections = build_header_sections(config)
    sections.concat(build_metadata_sections)

    attributes = build_attributes
    if attributes.present?
      sections << 'Conversation Attributes:'
      sections << attributes
    end

    sections.join("\n")
  end

  private

  def build_header_sections(config)
    sections = []
    sections << "Conversation ID: ##{@record.display_id}"
    sections << "Channel: #{@record.inbox.channel.name}"
    # Diz ao modelo, de forma explícita, que não há UM cliente do outro lado. Sem esta linha ele
    # trata o grupo como pessoa (foi o que aconteceu). Só aparece em grupo — conversa 1:1 sai
    # byte-a-byte igual ao que sempre saiu.
    sections << group_header if group_conversation?
    sections << 'Message History:'
    sections << (@record.messages.any? ? build_messages(config) : 'No messages in this conversation')
    sections << "Contact Details: #{@record.contact.to_llm_text}" if config[:include_contact_details]
    sections
  end

  def build_metadata_sections
    [
      "Assignee: #{field_or_default(@record.assignee&.name, 'unassigned')}",
      "Team: #{field_or_default(@record.team&.name)}",
      "Labels: #{field_or_default(@record.label_list.join(', ').presence)}",
      "Status: #{@record.status}",
      "Priority: #{field_or_default(@record.priority)}",
      "Created: #{@record.created_at.strftime('%Y-%m-%d %H:%M')}"
    ]
  end

  def field_or_default(value, fallback = 'none')
    value.presence || fallback
  end

  def build_messages(config = {})
    return "No messages in this conversation\n" if @record.messages.empty?

    messages = @record.messages.where.not(message_type: [:activity, :template])

    if config[:token_limit]
      build_limited_messages(messages, config)
    else
      build_all_messages(messages, config)
    end
  end

  def build_all_messages(messages, config)
    message_text = ''
    messages.order(created_at: :asc).each do |message|
      # Skip private messages unless explicitly included in config
      next if message.private? && !config[:include_private_messages]

      message_text << format_message(message)
    end
    message_text
  end

  def build_limited_messages(messages, config)
    selected = []
    character_count = 0

    messages.reorder(created_at: :desc).each do |message|
      # Skip private messages unless explicitly included in config
      next if message.private? && !config[:include_private_messages]

      formatted = format_message(message)
      break if character_count + formatted.length > config[:token_limit]

      selected.prepend(formatted)
      character_count += formatted.length
    end

    selected.join
  end

  def format_message(message)
    sender = default_sender_label(message)
    content = message.content_for_llm

    if group_conversation?
      participant, content = group_participant_and_content(message, content)
      sender = participant if participant.present?
    end

    sender = "[Private Note] #{sender}" if message.private?
    "#{sender}: #{content}\n"
  end

  def default_sender_label(message)
    case message.sender_type
    when 'User'
      'Support Agent'
    when 'Contact'
      'User'
    else
      'Bot'
    end
  end

  def group_conversation?
    return @group_conversation if defined?(@group_conversation)

    @group_conversation = @record.group?
  end

  # Cabeçalho do grupo: título limpo (sem os sufixos `(GROUP)`/`(Group)`/`(Grupo)` que as
  # integrações grudam no nome) e, quando o snapshot de integrantes existe (contrato C3), o
  # tamanho do grupo. Defensivo: sem snapshot, sai só o título.
  def group_header
    title = @record.contact&.name.to_s.sub(GROUP_NAME_SUFFIX, '').strip
    title = 'sem título' if title.blank?
    count = @record.additional_attributes&.dig('waha_group', 'count')
    suffix = count.to_i.positive? ? " (#{count} participantes)" : ''
    "Conversation type: WhatsApp group — \"#{title}\"#{suffix}. " \
      'Messages come from DIFFERENT participants, not from a single customer.'
  end

  # Devolve `[nome_do_participante, texto_limpo]` para uma mensagem de grupo.
  # Só mensagens de CONTATO ganham nome de participante: outgoing continua sendo o agente ou a
  # IA, que não são integrantes do grupo. O texto é saneado nos dois casos (o prefixo legado
  # aparece em qualquer mensagem que a WAHA tenha entregue).
  def group_participant_and_content(message, content)
    legacy_name, clean_content = strip_legacy_group_prefix(content)
    return [nil, clean_content] unless message.sender_type == 'Contact'

    [group_sender_name(message) || legacy_name, clean_content]
  end

  # Contrato C2 — o autor estruturado gravado na ingestão. `nil` quando o campo não existe
  # (mensagem legada) ou quando o nome não foi resolvido.
  def group_sender_name(message)
    name = message.content_attributes&.dig('group_sender', 'name')
    sanitize_participant_name(name)
  end

  # Saneia o histórico: separa o autor do texto e tira o identificador técnico de onde quer que
  # ele apareça. Cobre as DUAS gerações de prefixo que convivem na base.
  # Devolve `[nome | nil, texto]`.
  #
  # Divergência deliberada em relação ao extrator da ingestão: lá o corpo NUNCA é alterado além
  # do prefixo (é dado do cliente, tem que ficar íntegro); aqui é um prompt, e um LID solto no
  # meio da frase só gasta token e confunde o modelo — então ele sai também.
  def strip_legacy_group_prefix(content)
    text = content.to_s
    extracted = Whatsapp::GroupSenderExtractor.call(text)
    return [sanitize_participant_name(extracted.sender&.dig('name')), without_lid_token(extracted.content)] if extracted.matched?

    match = text.match(FOSSIL_GROUP_PREFIX)
    return [fossil_participant_name(match[1]), without_lid_token(text[match[0].length..])] if match

    [nil, without_lid_token(text)]
  end

  def without_lid_token(text)
    text.to_s.gsub(LEGACY_LID_TOKEN, '')
  end

  # "+55 (66) 9683-6077 - Sentinela" -> "Sentinela". Sem o separador (rótulo só com o telefone),
  # devolve o rótulo inteiro: identificar o participante pelo número ainda é melhor, para o
  # modelo, do que fundir todo mundo num "User" só.
  def fossil_participant_name(label)
    match = label.to_s.strip.match(FOSSIL_LABEL_NAME)
    sanitize_participant_name(match ? match[:name] : label)
  end

  # Nome exibível do participante: sem o identificador técnico e sem as marcas de direção
  # (LRM/RLM) que o WhatsApp embute e que quebram comparação de string. `nil` quando sobra nada.
  def sanitize_participant_name(name)
    name.to_s.gsub(LEGACY_LID_TOKEN, '').gsub(BIDI_MARKS, '').strip.presence
  end

  def build_attributes
    attributes = @record.account.custom_attribute_definitions.with_attribute_model('conversation_attribute').map do |attribute|
      "#{attribute.attribute_display_name}: #{@record.custom_attributes[attribute.attribute_key]}"
    end
    attributes.join("\n")
  end
end
