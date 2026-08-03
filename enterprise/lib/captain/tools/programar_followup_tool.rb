class Captain::Tools::ProgramarFollowupTool < Captain::Tools::BasePublicTool
  description 'Programa um follow-up (cutucada) pra esta conversa, pra retomar caso o cliente não responda. ' \
              'Use o seu julgamento: programe só quando vale a pena manter o lead aquecido ou esclarecer algo pendente. ' \
              'NÃO programe se o cliente disse que já responde, se a conversa se encerrou naturalmente, ou se não há nada pendente. ' \
              'Você escolhe o tempo: poucos minutos pra um lead quente que sumiu no meio, algumas horas ou 1-2 dias pra quem ficou de pensar. ' \
              'Quando o cliente disser quando quer ser procurado, mande isso em `janela` — é ela que passa a mandar no horário. ' \
              'Programar de novo substitui o follow-up anterior.'

  param :minutos, type: 'number',
        desc: 'Em quantos minutos cutucar, se o cliente não responder até lá. Ex: 5 a 15 pra lead quente; 120-480 pra algumas horas; até 2880 (2 dias).', required: true
  param :motivo, type: 'string',
        desc: 'Em que ponto a conversa parou e o que retomar na cutucada. Ex: "estava escolhendo entre as duas casas que mandei".', required: true
  param :janela,
        type: 'string',
        desc: 'O momento que o PRÓPRIO cliente disse preferir pro retorno, com as palavras dele. ' \
              'Preencha só com o que ele declarou nesta conversa; se ele não disse, deixe vazio e pergunte antes — nunca deduza nem invente. ' \
              'Quando vier preenchida, ela substitui `minutos` no cálculo do horário.',
        required: false

  MIN_MINUTOS = 2
  MAX_MINUTOS = 2880

  # Sinal de adiamento na fala do cliente. Serve pra detectar, pelo que ele REALMENTE
  # escreveu, que houve pedido de retorno — inclusive pelos botões de adiamento dos
  # disparos. Não depende do modelo declarar que houve adiamento.
  ADIAMENTO = /chama(r|e)? (mais tarde|depois)|falar depois|mais tarde|outro hor|outro momento|depois eu|eu te chamo|retomar depois/i

  DIAS_SEMANA = { 'domingo' => 0, 'segunda' => 1, 'terca' => 2, 'quarta' => 3,
                  'quinta' => 4, 'sexta' => 5, 'sabado' => 6 }.freeze
  # Hora de referência de cada período do dia.
  PERIODOS = { 'manha' => 9, 'almoco' => 12, 'tarde' => 14, 'noite' => 19 }.freeze

  def perform(tool_context, minutos:, motivo:, janela: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra programar o follow-up.' unless conversation

    pela_janela = janela.present? ? minutos_ate(janela) : nil
    minutes = (pela_janela || minutos).to_i.clamp(MIN_MINUTOS, MAX_MINUTOS)

    agendar(conversation, minutes, motivo, janela)
    resposta(conversation, minutes, janela, pela_janela)
  rescue StandardError => e
    Rails.logger.warn("[ProgramarFollowupTool] #{e.message}")
    'Não consegui programar o follow-up agora.'
  end

  private

  def agendar(conversation, minutes, motivo, janela)
    token = SecureRandom.hex(8)
    atributos = {
      'followup_token' => token,
      'followup_motivo' => motivo.to_s,
      'followup_status' => "cutucada programada em ~#{minutes} min"
    }
    atributos['followup_janela'] = janela.to_s if janela.present?
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(atributos))
    # Bloco 3 (funil Tozi): lead silenciou e foi programada cutucada -> card "Em Silêncio".
    Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'em_silencio')
    Captain::Conversation::FollowupJob.set(wait: minutes.minutes).perform_later(conversation, token)
  end

  # O retorno é o canal que o modelo enxerga no contexto. Quando o cliente pediu pra
  # falar depois e a janela não veio, dizer isso de volta é o que faz a falta aparecer —
  # em vez de depender de ele lembrar de uma linha do prompt.
  def resposta(conversation, minutes, janela, pela_janela)
    if janela.blank?
      return 'Follow-up programado.' unless adiamento?(conversation)

      return "Follow-up programado em ~#{minutes} min, mas num horário que VOCÊ escolheu. " \
             'O cliente pediu pra falar depois e não disse quando: pergunte AGORA, nesta mesma resposta, qual o melhor dia e ' \
             'período pra ele, e chame esta ferramenta de novo com `janela` preenchida. Não crave dia nem horário que ele não ' \
             'pediu e não deixe por conta dele voltar a procurar.'
    end

    if pela_janela.nil?
      return "Follow-up programado em ~#{minutes} min. Não consegui entender \"#{janela}\" como data/horário, então usei o tempo " \
             'que você passou. Se o cliente foi vago, confirme com ele o dia e o período e reprograme.'
    end

    if minutes < pela_janela
      return "A janela que o cliente pediu (\"#{janela}\") cai além do limite de #{MAX_MINUTOS / 1440} dias da cutucada, " \
             "então programei pro máximo (~#{minutes} min) — vai chegar ANTES do que ele pediu. " \
             'Se o retorno precisa mesmo cair só naquela data, deixe isso combinado com o time em vez de confiar na cutucada.'
    end

    "Follow-up programado para a janela que o cliente pediu (\"#{janela}\"), em ~#{minutes} min."
  end

  def adiamento?(conversation)
    id = conversation.messages.incoming.maximum(:id)
    return false if id.blank?

    Message.find_by(id: id)&.content.to_s.match?(ADIAMENTO)
  end

  # Converte a janela declarada pelo cliente em minutos a partir de agora.
  # nil quando o texto não traz dia nem hora reconhecíveis — aí quem manda é `minutos`.
  def minutos_ate(janela)
    texto = sem_acento(janela)
    dia = data_alvo(texto)
    hora = hora_alvo(texto)
    return nil if dia.nil? && hora.nil?

    momento = momento_de(dia || Time.current.to_date, hora || PERIODOS['manha'])
    ((momento - Time.current) / 60).round
  end

  # Janela já vencida hoje (pediu "de manhã" à tarde) cai no dia seguinte.
  def momento_de(dia, hora)
    momento = Time.zone.local(dia.year, dia.month, dia.day, hora)
    momento <= Time.current ? momento + 1.day : momento
  end

  def data_alvo(texto)
    hoje = Time.current.to_date
    return hoje if texto.match?(/\bhoje\b|agora a (tarde|noite)|mais tarde/)
    return hoje + 2 if texto.include?('depois de amanha')
    return hoje + 1 if texto.match?(/\bamanha\b/)

    dia_da_semana(texto, hoje)
  end

  def dia_da_semana(texto, hoje)
    nome, alvo = DIAS_SEMANA.find { |n, _| texto.include?(n) }
    return nil if nome.nil?

    delta = (alvo - hoje.wday) % 7
    hoje + (delta.zero? ? 7 : delta)
  end

  def hora_alvo(texto)
    explicita = texto[/\b(\d{1,2})\s*(?:h|:\d{2}|horas)\b/, 1]&.to_i
    return explicita if explicita&.between?(0, 23)

    # Fronteira de palavra é obrigatória: "amanha" CONTÉM "manha", e sem \b
    # "amanhã à tarde" era agendado de manhã.
    _, hora = PERIODOS.find { |p, _| texto.match?(/\b#{p}\b/) }
    hora
  end

  def sem_acento(str)
    str.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
  end
end
