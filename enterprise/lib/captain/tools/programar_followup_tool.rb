class Captain::Tools::ProgramarFollowupTool < Captain::Tools::BasePublicTool
  include Captain::Tools::MomentoDoCliente

  description 'Programa um follow-up (cutucada) pra esta conversa, pra retomar caso o cliente não responda. ' \
              'Use o seu julgamento: programe só quando vale a pena manter o contato aquecido ou esclarecer algo pendente. ' \
              'NÃO programe se o cliente disse que já responde, se a conversa se encerrou naturalmente, ou se não há nada pendente. ' \
              'O tempo até a cutucada é decisão sua, tirada desta conversa: do que o cliente disse e de onde o atendimento parou. ' \
              'Quando o cliente disser um momento pro retorno (horário, período do dia ou dia), `janela` é OBRIGATÓRIA, ' \
              'com as palavras dele: sem ela o horário combinado não é cumprido, porque a cutucada sai no tempo de `minutos`. ' \
              'Programar de novo substitui o follow-up anterior.'

  param :minutos, type: 'number',
                  desc: 'Em quantos minutos cutucar, se o cliente não responder até lá: o tempo até o momento em que faz sentido ' \
                        'retomar, julgado pelo que o cliente disse e pelo estado da conversa. Não há valor padrão; decida a cada caso. ' \
                        'Valor fora do limite aceito é ajustado automaticamente. Com `janela` preenchida, é ela que define o horário.',
                  required: true
  param :motivo, type: 'string',
                 desc: 'Em que ponto a conversa parou e o que retomar na cutucada, descrito a partir do que aconteceu nesta conversa.',
                 required: true
  param :janela,
        type: 'string',
        desc: 'O momento que o PRÓPRIO cliente disse preferir pro retorno, com as palavras dele. ' \
              'Preencha só com o que ele declarou nesta conversa; se ele não disse, deixe vazio e pergunte antes — nunca deduza nem invente. ' \
              'Quando vier preenchida, ela substitui `minutos` no cálculo do horário.',
        required: false

  MIN_MINUTOS = 2
  # Cutucada preventiva: 2 dias. É sobrevida de conversa; passou disso, o lead esfriou e quem
  # retoma é gente, não um lembrete automático.
  MAX_MINUTOS = 2880
  # Compromisso (o cliente disse quando quer ser procurado): 7 dias. O teto de 2 dias era do
  # outro problema e encurtava calado o que o cliente pediu — "só semana que vem" virava uma
  # cutucada em 2 dias, antes da hora e sem ninguém saber.
  MAX_MINUTOS_COMPROMISSO = 10_080

  # Sinal de adiamento na fala do cliente. Serve pra detectar, pelo que ele REALMENTE
  # escreveu, que houve pedido de retorno — inclusive pelos botões de adiamento dos
  # disparos. Não depende do modelo declarar que houve adiamento.
  ADIAMENTO = /chama(r|e)? (mais tarde|depois)|falar depois|mais tarde|outro hor|outro momento|depois eu|eu te chamo|retomar depois/i

  def perform(tool_context, minutos:, motivo:, janela: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra programar o follow-up.' unless conversation
    return AGENDADA_NO_LUGAR if agendada_no_lugar?(janela)

    pela_janela = janela.present? ? minutos_ate(janela) : nil
    minutes = (pela_janela || minutos).to_i.clamp(MIN_MINUTOS, teto(pela_janela))

    agendar(conversation, minutes, motivo, janela)
    resposta(conversation, minutes, janela, pela_janela)
  rescue StandardError => e
    Rails.logger.warn("[ProgramarFollowupTool] #{e.message}")
    'Não consegui programar o follow-up agora.'
  end

  # Com a agendada ligada no agente (CHAT-165), o momento que o cliente deu é cumprido por ela, com
  # a mensagem pronta; a cutucada com `janela` passaria a disputar o mesmo combinado.
  AGENDADA_NO_LUGAR = 'Nada programado: o cliente disse um momento para ser procurado, e isso se faz com agendar_mensagem, ' \
                      'com a mensagem já escrita. Use-a em vez desta ferramenta.'.freeze

  private

  def agendada_no_lugar?(janela)
    janela.present? && (@assistant.config['tools'] || []).include?('agendar_mensagem')
  end

  # Só vale o teto maior quando a janela foi ENTENDIDA: janela ilegível cai no `minutos` que o
  # modelo escolheu, e aí o número é dele, não do cliente — segue no teto da cutucada.
  def teto(pela_janela)
    pela_janela.nil? ? MAX_MINUTOS : MAX_MINUTOS_COMPROMISSO
  end

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
      return "A janela que o cliente pediu (\"#{janela}\") cai além do limite de #{MAX_MINUTOS_COMPROMISSO / 1440} dias, " \
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
end
