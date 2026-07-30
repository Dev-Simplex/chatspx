class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  MAX_MESSAGE_LENGTH = 10_000
  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant, directive: nil)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant
    @directive = directive

    return unless captain_can_respond?

    reset_followup_state if @directive.nil?

    Current.executed_by = @assistant

    if captain_v2_enabled?
      generate_response_with_v2
    else
      generate_and_process_response
    end
  rescue ActiveStorage::FileNotFoundError, Faraday::BadRequestError => e
    handle_error(e)
    raise e
  rescue StandardError => e
    handle_error(e)
  ensure
    Current.executed_by = nil
  end

  private

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    @response = Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def generate_response_with_v2
    @response = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def process_response
    return unless captain_can_respond?

    if handoff_requested?
      process_action('handoff')
    else
      # Sem transacao envolvendo a rajada: cada bolha precisa COMMITAR pra disparar o
      # SendReplyJob (after_create_commit). Dentro de uma transacao os sends so disparariam
      # no commit final, TODOS juntos -> corriam soltos e chegavam fora de ordem. Commitando
      # uma a uma, o wait_for_dispatch (espera o source_id) serializa o envio.
      create_messages
      Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
      account.increment_response_usage
      ensure_handoff_if_promised
      auto_schedule_followup if @did_send
    end
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .reject { |message| survey_message?(message) }
      .map do |message|
      # Blocos de imagem so podem ir em turnos de USER (a API rejeita 'image' em
      # assistant turns); outgoing com anexo vira placeholder textual.
      content = if message.incoming?
                  with_reply_context(message, prepare_multimodal_message_content(message))
                else
                  message.content.presence || outgoing_attachment_placeholder(message)
                end
      with_forwardable_agent_name({ content: content, role: determine_role(message) }, message)
    end.tap do |history|
      # Reentrada pós-atendimento humano encerrado: o agente precisa saber que houve gente
      # antes dele e quem foi, senão trata continuidade de caso como assunto novo. Uma vez
      # por turno (não por mensagem do histórico), e só quando é reentrada de verdade.
      nota_humana = Captain::Conversation::HumanHistoryNote.new(conversation: @conversation).text
      history << { content: nota_humana, role: 'user' } if nota_humana.present?
      # Diretiva interna de follow-up (cutucada): entra como último turno pro agente decidir.
      history << { content: @directive, role: 'user' } if @directive.present?
    end
  end

  # Mensagens de pesquisa (NPS/CSAT) NÃO são conversa real — são artefato do sistema. No
  # WhatsApp o NPS vai como content_type=text MARCADO com content_attributes.nps_survey
  # (ver MessageTemplates::Template::NpsSurvey), então filtrar só por content_type não pega
  # o caso do WhatsApp. Se entra no histórico, o LLM enxerga como turno "assistant" e
  # MIMETIZA — passa a responder "De 0 a 10..." em vez de atender (ex.: conv 3040). A
  # pesquisa real segue intacta no fluxo de NPS/CSAT; só não vai pro contexto do LLM.
  def survey_message?(message)
    return true if %w[input_csat input_nps].include?(message.content_type)

    message.content_attributes&.dig('nps_survey').present?
  end

  # Quando o cliente volta a responder (resposta normal, sem diretiva), a cadência
  # de cutucada zera: lead reengajado começa do zero.
  def reset_followup_state
    attrs = @conversation.custom_attributes || {}
    return if attrs['followup_token'].blank? && attrs['followup_count'].to_i.zero?

    @conversation.update!(custom_attributes: attrs.merge('followup_token' => nil, 'followup_count' => 0, 'followup_status' => nil))
  rescue StandardError => e
    Rails.logger.warn("[ResponseBuilderJob] reset_followup: #{e.message}")
  end

  # Auto-agendamento de follow-up (cutucada): na prática o LLM quase nunca chama a
  # ferramenta programar_followup, então depois de CADA resposta em que a IA de fato
  # falou e a bola ficou com o cliente (IA segue dona, sem handoff/aguardando/resolvido),
  # agenda-se uma cutucada preventiva. Se o cliente responder antes, o próprio FollowupJob
  # a descarta (lead_replied?); a cada turno o token é substituído. A decisão FINAL de
  # cutucar (ou responder [IGNORAR]) é do agente no disparo — aqui só se garante o gatilho.
  def auto_schedule_followup
    return unless auto_followup_enabled?

    attrs = @conversation.reload.custom_attributes || {}
    return if attrs['aguardando_humano_desde'].present?
    return if @conversation.resolved?
    return unless captain_can_respond?
    return if attrs['followup_count'].to_i > Captain::Conversation::FollowupJob::MAX_FOLLOWUPS

    minutes = followup_auto_minutes
    token = SecureRandom.hex(8)
    @conversation.update!(custom_attributes: attrs.merge(
      'followup_token' => token,
      'followup_status' => "cutucada auto-programada em ~#{minutes} min"
    ))
    Captain::Conversation::FollowupJob.set(wait: minutes.minutes).perform_later(@conversation, token)
  rescue StandardError => e
    Rails.logger.warn("[ResponseBuilderJob] auto_followup: #{e.message}")
  end

  # Opt-in implícito: só agentes que já têm a ferramenta de follow-up. Desligável por
  # conta/agente via behavior['followup']['auto'] = false.
  def auto_followup_enabled?
    return false unless (@assistant.config['tools'] || []).include?('programar_followup')

    @assistant.behavior.dig('followup', 'auto') != false
  end

  def followup_auto_minutes
    (@assistant.behavior.dig('followup', 'auto_minutes').presence || 120).to_i.clamp(2, 2880)
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  # Foto sai como outgoing de conteudo vazio; sem o codigo, todas viram o MESMO placeholder
  # no historico e o modelo nao sabe qual imovel e qual ("esse e qual?"). Carimbado pela
  # EnviarFotosImovelTool em additional_attributes['property_code'].
  def outgoing_attachment_placeholder(message)
    return '' unless message.attachments.any?

    code = message.additional_attributes&.dig('property_code')
    code.present? ? "[foto do imóvel #{code} enviada]" : '[foto do imóvel enviada]'
  end

  # Forward do agent_name das additional_attributes para o histórico da gem.
  # C7.4 (gap AD-11/B4): agent_name de OUTRA IA (transferência C7) ou de cenário
  # legado não pode rotear persona — a gem cairia no agente default silenciosamente.
  # Mensagem com nome alheio entra no histórico sem agent_name.
  def with_forwardable_agent_name(message_hash, message)
    agent_name = message.additional_attributes&.dig('agent_name')
    message_hash[:agent_name] = agent_name if agent_name.present? && own_agent_name?(agent_name)
    message_hash
  end

  # Nomes que pertencem ao assistant ATUAL: o agent_name dele (espelha o privado
  # Captain::Assistant#agent_name — name.parameterize('_')) e os handoff_keys dos
  # cenários habilitados (personas legítimas deste assistant no runner).
  def own_agent_name?(agent_name)
    @own_agent_names ||= ([@assistant.name.parameterize(separator: '_')] +
                          @assistant.scenarios.enabled.map(&:handoff_key)).to_set
    @own_agent_names.include?(agent_name)
  end

  # Quando o cliente responde (reply) a uma mensagem específica do WhatsApp,
  # injeta o texto citado no contexto pra o agente saber a qual imóvel/mensagem
  # ele se refere. Sem isso, "é essa" / "quero essa" ficavam sem referência.
  def with_reply_context(message, content)
    attrs = message.content_attributes || {}
    reply_id = attrs['in_reply_to']
    reply_ext = attrs['in_reply_to_external_id']
    quoted = nil
    quoted = @conversation.messages.find_by(id: reply_id) if reply_id.present?
    quoted ||= @conversation.messages.find_by(source_id: reply_ext) if reply_ext.present?
    return content if quoted.nil?

    desc = quoted_description(quoted)
    return content if desc.blank?

    prefix = "[Respondendo a esta mensagem anterior: \"#{desc}\"] "
    case content
    when String then prefix + content
    when Array then [{ type: 'text', text: prefix }] + content
    else content
    end
  end

  # A msg citada pode ser uma FOTO (outgoing de conteudo vazio). Antes, content.blank?
  # descartava a citacao e o "esse e qual?" ficava sem referencia — resolve pelo
  # property_code carimbado na foto; senao, ao menos sinaliza que e uma foto.
  def quoted_description(quoted)
    text = quoted.content.to_s.gsub(/\s+/, ' ').strip
    return text[0, 180] if text.present?

    code = quoted.additional_attributes&.dig('property_code')
    return "foto do imóvel #{code}" if code.present?

    quoted.attachments.any? ? 'uma foto enviada anteriormente' : ''
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def handoff_requested?
    @response['response'] == 'conversation_handoff'
  end

  # Rede de seguranca (P10): o modelo as vezes ESCREVE que vai passar pro consultor/time sem
  # ACIONAR o handoff (a resposta nao veio como 'conversation_handoff'), deixando o cliente
  # orfao esperando um humano que nunca vem (visto na conv 18973). Se o texto ja enviado promete
  # handoff e nenhum disparou, dispara a mecanica AQUI — sem reenviar o template (o modelo ja avisou).
  # Deteccao conservadora; loga 'handoff_auto_fired' pra medir e afinar. Mantem o time atual da
  # conversa (nao aplica o override de recepcao), entregando ao humano do time que ja atendia.
  HANDOFF_PROMISE_PATTERNS = [
    /\b(vou|irei|vamos|já vou)\b.{0,30}\b(passar|chamar|encaminhar|acionar|transferir|pedir)\b.{0,40}\b(consultor|time|atendente|humano|equipe|colega)\b/i,
    /\b(consultor|atendente|humano|equipe|algu[ée]m do time)\b.{0,30}\bvai\b.{0,25}\b(assumir|continuar|dar sequ[êe]ncia|te atender|te ajudar)\b/i
  ].freeze

  def promised_handoff?(text)
    return false if text.blank?

    HANDOFF_PROMISE_PATTERNS.any? { |re| re.match?(text.to_s) }
  end

  def ensure_handoff_if_promised
    return unless promised_handoff?(@response['response'])
    return unless captain_can_respond?

    log_behavior_event('handoff_auto_fired', { snippet: @response['response'].to_s[0, 160] })
    I18n.with_locale(@assistant.account.locale) { @conversation.bot_handoff! }
  rescue StandardError => e
    Rails.logger.warn("[Captain] ensure_handoff_if_promised falhou: #{e.message}")
  end

  def process_action(action)
    case action
    when 'handoff'
      I18n.with_locale(@assistant.account.locale) do
        create_handoff_message
        @conversation.bot_handoff!
        send_out_of_office_message_if_applicable
      end
    end
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end

  def create_handoff_message
    create_outgoing_message(
      @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')
    )
  end

  def create_messages
    content = normalize_response_content(@response['response'])
    return log_ignored(content) if no_reply?(content)

    if unknown_marker?(content)
      return unless regenerate_after_unknown_marker(content)

      content = normalize_response_content(@response['response'])
      return if no_reply?(content)
    end

    if skip_duplicate?(content)
      return unless regenerate_to_avoid_repeat

      content = normalize_response_content(@response['response'])
      return log_ignored(content) if no_reply?(content)
      return if skip_duplicate?(content)
    end

    send_response(content)
  end

  # Silêncio deliberado do agente ([IGNORAR]) deixa rastro auditável: sem isso, uma
  # conversa silenciada (ex.: falso positivo de spam) fica invisível no painel e no
  # diagnóstico — nenhuma mensagem, nenhum log (caso real: conv sem resposta por 16h).
  def log_ignored(content)
    log_behavior_event('ignored', { raw: content.to_s[0, 120] })
    nil
  rescue StandardError
    nil
  end

  # O agente decide quando NÃO responder (ex: cliente só mandou "ok"/"blz" e não há
  # nada pendente). Sinaliza com [IGNORAR] ou resposta vazia -> não envia nada.
  def no_reply?(content)
    return true if content.blank?

    content.to_s.strip.match?(/\A\[?\s*(ignorar|sem[\s_-]?resposta|no[\s_-]?reply)\s*\]?\z/i)
  end

  # O modelo às vezes devolve a PRÓPRIA estrutura de saída como texto, no formato cru do
  # inspect ({"response"=>"...", "reasoning"=>"..."}), em vez de só o texto do campo response.
  # Isso escapa das duas redes existentes — não é blank e não casa com UNKNOWN_MARKER (não
  # está entre colchetes) — e o cliente recebe o hash cru. O JSON.parse do fallback de handoff
  # também não pega, porque hash-rocket não é JSON válido. Aqui desembrulha pro texto real;
  # se o campo interno vier vazio, o agente quis silêncio.
  # Abre com a chave e traz o campo response logo em seguida, em hash-rocket ou JSON.
  LEAKED_STRUCT = /\A\{.*["']response["']\s*(?:=>|:)/m
  # Captura o valor do campo response, respeitando aspas escapadas dentro do texto.
  LEAKED_RESPONSE_FIELD = /["']response["']\s*(?:=>|:)\s*"((?:[^"\\]|\\.)*)"/m

  def normalize_response_content(content)
    return unwrapped_or_silence(content['response'] || content[:response]) if content.is_a?(Hash)

    str = content.to_s
    return content unless str.strip.match?(LEAKED_STRUCT)

    unwrapped_or_silence(str.match(LEAKED_RESPONSE_FIELD)&.captures&.first)
  end

  # Campo response vazio depois de desembrulhar significa que o agente quis silêncio.
  def unwrapped_or_silence(value)
    text = value.to_s
    text.strip.empty? ? '[IGNORAR]' : text
  end

  # A resposta INTEIRA virou um marcador entre colchetes que o pipeline não conhece. O agente
  # inventa isso no estilo do [IGNORAR] que existe de verdade — visto em produção como
  # "[foto do imóvel enviada]". Não é resposta nem silêncio deliberado, e hoje dá nos dois
  # piores resultados: em julho o marcador foi ENVIADO ao cliente 4 vezes, e na conv 18753 foi
  # engolido e o cliente ficou sem retorno. Marcador conhecido ([IGNORAR] e variantes) sai
  # antes daqui, no no_reply?.
  UNKNOWN_MARKER = /\A\[[^\]\n]{1,80}\]\z/

  def unknown_marker?(content)
    content.to_s.strip.match?(UNKNOWN_MARKER)
  end

  # Re-roda UMA vez cobrando texto de verdade. Se insistir no marcador, chama gente em vez de
  # deixar a conversa muda — a mensagem do cliente segue sem resposta e alguém precisa ver.
  def regenerate_after_unknown_marker(content)
    log_behavior_event('unknown_marker', { content: content.to_s.strip.first(80) })
    return false if @marker_regenerated

    @marker_regenerated = true
    @directive = 'IMPORTANTE: sua resposta anterior foi só um marcador entre colchetes, que o cliente nao pode receber. ' \
                 'Responda de novo com uma mensagem de verdade, escrita pro cliente ler. Se a acao ja foi feita por ferramenta, ' \
                 'diga em palavras o que aconteceu e conduza a conversa pro proximo passo.'
    @response = if captain_v2_enabled?
                  Captain::Assistant::AgentRunnerService.new(assistant: @assistant,
                                                             conversation: @conversation).generate_response(message_history: collect_previous_messages)
                else
                  Captain::Llm::AssistantChatService.new(assistant: @assistant,
                                                         conversation: @conversation).generate_response(message_history: collect_previous_messages)
                end
    return true if @response.present? && !unknown_marker?(@response['response'])

    escalate_after_unknown_marker
    false
  rescue StandardError => e
    Rails.logger.warn("[Captain][unknown_marker] #{e.message}")
    escalate_after_unknown_marker
    false
  end

  def escalate_after_unknown_marker
    Captain::Conversation::HumanHandoffService.new(
      conversation: @conversation, assistant: @assistant,
      reason: 'A IA não conseguiu produzir uma resposta enviável para a última mensagem do cliente. Precisa de atendimento humano.'
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Captain][unknown_marker][handoff] #{e.message}")
  end

  # Backstop anti-repeticao: se a resposta saiu identica a uma recente (dedup),
  # re-roda o agente UMA vez pedindo pra variar/avancar, em vez de silenciar.
  def regenerate_to_avoid_repeat
    return false if @repeat_regenerated

    @repeat_regenerated = true
    @directive = 'IMPORTANTE: voce acabou de enviar exatamente essa mesma resposta nesta conversa. NAO repita. Responda de outro jeito, mais direto, ou avance a conversa pro proximo passo. Se a pergunta for sobre presenca (tem alguem? quem atende?), diga que voce esta aqui pra ajudar agora.'
    log_behavior_event('dedup_regenerate', {})
    @response = if captain_v2_enabled?
                  Captain::Assistant::AgentRunnerService.new(assistant: @assistant,
                                                             conversation: @conversation).generate_response(message_history: collect_previous_messages)
                else
                  Captain::Llm::AssistantChatService.new(assistant: @assistant,
                                                         conversation: @conversation).generate_response(message_history: collect_previous_messages)
                end
    @response.present?
  rescue StandardError => e
    Rails.logger.warn('[Captain][regenerate_to_avoid_repeat] ' + e.message)
    false
  end

  def skip_duplicate?(content)
    return false unless dedup_enabled?

    dedup = Captain::Behavior::DedupService.new(assistant: @assistant, conversation: @conversation)
    return false unless dedup.duplicate?(content)

    log_behavior_event('dedup_skip', { content_hash: Digest::MD5.hexdigest(content) })
    true
  end

  def send_response(content)
    @did_send = true
    content = sanitize_for_whatsapp(content)
    if humanizer_enabled?
      send_humanized_response(content)
    else
      create_outgoing_message(content, agent_name: @response['agent_name'])
    end
  end

  # WhatsApp não renderiza markdown; alguns LLMs (ex: gpt-5-mini) insistem em
  # **negrito** mesmo instruídos a não usar. Remove a formatação markdown comum
  # antes de enviar, pra não aparecer literal pro cliente.
  def sanitize_for_whatsapp(content)
    return content if content.blank?

    content = fix_property_links(content)
    content.gsub(/\[\s*(ignorar|sem[\s_-]?resposta|no[\s_-]?reply)\s*\]/i, '') # sentinela de silêncio que o LLM às vezes anexa a uma resposta real -> nunca enviar literal
           .gsub(/\[\s*fotos?[^\]]*enviad[ao]s?\s*\]/i, '') # placeholder de foto do histórico que o LLM às vezes ecoa -> remove
           .gsub(/\*\*(.*?)\*\*/m, '\1')   # **negrito** -> negrito
           .gsub(/__(.*?)__/m, '\1')        # __negrito__ -> negrito
           .gsub(/^\s{0,3}#+\s+/, '')        # ## títulos -> texto
           .gsub(/^\s{0,3}[-*]\s+/, '')      # - bullets -> texto
           .gsub(/\s*[—―]\s*/, ', ')         # travessão/barra (pausa) -> vírgula (humano no WhatsApp não usa —)
           .tr('–', '-')                   # en-dash -> hífen comum (preserva intervalos: 7-11, R$3.200-5.000)
           .gsub(/ +,/, ',')                 # " ," -> ","
           .gsub(/,\s*([.!?;:])/, '\1')      # ", ." -> "."
           .gsub(/,(\s*,)+/, ',')            # ",," -> ","
  end

  # A URL de um imóvel só vem da buscar_imovel (build_url, que resolve o link pela
  # API do site). O LLM às vezes monta uma URL na mão, com número inventado — o
  # formato até parece certo, o código é que não é. Aqui, toda URL da Tozi na resposta
  # é trocada pela que a busca realmente retornou (casando o código no fim da
  # URL); se nenhum código bater, é inventada -> remove. Sem busca na conversa,
  # nenhuma URL da Tozi é legítima. Só toca a saída da IA (não a de humano).
  def fix_property_links(content)
    return content unless content.match?(/toziimoveis/i)

    mapa = @conversation.reload.custom_attributes&.dig('urls_imoveis') || {}
    content.gsub(%r{https?://[^\s)\]]*toziimoveis\.com\.br[^\s)\]]*}i) do |url|
      match = url.scan(/\d+/).find { |n| mapa.key?(n) }
      match ? mapa[match] : ''
    end
  end

  def send_humanized_response(content)
    chunks = Captain::Behavior::HumanizerService.new(config: @assistant.behavior['humanizer']).split(content)

    sent = 0
    chunks.each do |chunk|
      next if chunk.blank? # bolha vazia (ex: sobra de sentinela [IGNORAR] removido) -> não envia

      # "digitando..." em rajada curta antes de CADA mensagem (proporcional ao
      # tamanho do texto), com pausa entre elas — em vez de typing continuo desde a
      # chegada. Tambem espaca o envio, impedindo as mensagens de chegarem fora de ordem.
      trigger_typing_indicator
      sleep(humanizer_typing_delay(chunk))
      # Re-check POR CHUNK, depois do sleep e imediatamente antes do envio: humano (ou
      # outra IA) assumiu no meio da rajada -> para AQUI. TOCTOU residual de ms (entre o
      # pick e o create!) aceito — lock pessimista por mensagem seria desproporcional.
      break unless captain_can_respond?

      message = create_outgoing_message(chunk, agent_name: @response['agent_name'])
      wait_for_dispatch(message)
      sent += 1
    end
    log_behavior_event('humanizer_split', { chunks: chunks.size, sent: sent }) if chunks.size > 1
  end

  # Espera a bolha ser despachada pro WhatsApp (ganhar source_id) antes de criar a proxima,
  # pra garantir a ORDEM de chegada. O envio real e um job async; sem isso as bolhas correm
  # soltas no Sidekiq e chegam fora de ordem pro cliente. So WhatsApp Cloud (onde o source_id
  # e setado no envio); timeout curto pra nao segurar o worker se o envio demorar/falhar.
  def wait_for_dispatch(message, timeout: 6.0, interval: 0.2)
    return if message.nil?
    return unless @inbox.channel.is_a?(Channel::Whatsapp)

    waited = 0.0
    while waited < timeout
      return if Message.where(id: message.id).pick(:source_id).present?

      sleep(interval)
      waited += interval
    end
  end

  # "Digitando..." pro cliente (best-effort; so WhatsApp Cloud responde de fato).
  # Usa o source_id da ultima mensagem recebida — o typing_indicator da Meta precisa
  # referenciar uma mensagem do cliente pra marcar como lida.
  def trigger_typing_indicator
    source_id = @conversation.messages.where(message_type: :incoming).where.not(source_id: nil)
                             .order(created_at: :desc).limit(1).pick(:source_id)
    return if source_id.blank?

    @conversation.inbox.channel.try(:send_typing_indicator, source_id)
  rescue StandardError => e
    Rails.logger.warn("[Captain] typing falhou: #{e.message}")
  end

  # Atraso proporcional ao tamanho do proximo pedaco (~velocidade de digitacao), com
  # piso e teto. Configuravel via humanizer.{delay_per_char_ms, delay_ms, min_delay_s, max_delay_s}.
  def humanizer_typing_delay(chunk)
    cfg = @assistant.behavior['humanizer'] || {}
    per_char = (cfg['delay_per_char_ms'].presence&.to_f || 45) / 1000.0
    base = (cfg['delay_ms'].presence&.to_f || 600) / 1000.0
    min_s = cfg['min_delay_s'].presence&.to_f || 1.5
    max_s = cfg['max_delay_s'].presence&.to_f || 7.0
    [[base + (chunk.to_s.length * per_char), min_s].max, max_s].min
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?
  end

  def create_outgoing_message(message_content, agent_name: nil)
    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs
    )
  end

  def handle_error(error)
    log_error(error)
    process_action('handoff') if conversation_pending?
    true
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def captain_v2_enabled?
    account.feature_enabled?('captain_integration_v2')
  end

  def dedup_enabled?
    @assistant.behavior.dig('dedup', 'enabled') == true
  end

  def humanizer_enabled?
    @assistant.behavior.dig('humanizer', 'enabled') == true
  end

  def log_behavior_event(event_type, payload = {})
    Captain::AssistantLog.create!(
      captain_assistant: @assistant,
      conversation: @conversation,
      event_type: event_type,
      payload: payload
    )
  end

  def conversation_pending?
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end

  # Captain responde em pending E em open (fork), e SOMENTE se a conversa ainda está
  # atribuída ao espelho DESTE assistant (gate por atribuição, D-6). Compara com o
  # assistant do ARGUMENTO (serializado via GlobalID) — job em voo de IA antiga cala.
  def captain_can_respond?
    status, mirror_id = Conversation.uncached do
      Conversation.where(id: @conversation.id).pick(:status, :assignee_agent_bot_id)
    end
    return false unless [Conversation.statuses[:pending], Conversation.statuses[:open], 'pending', 'open'].include?(status)

    mirror_id.present? && mirror_id == assistant_mirror_id
  end

  def assistant_mirror_id
    @assistant_mirror_id ||= AgentBot.captain.where(captain_assistant_id: @assistant.id).pick(:id)
  end
end
