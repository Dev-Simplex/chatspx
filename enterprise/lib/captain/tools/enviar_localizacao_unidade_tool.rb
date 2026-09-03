# Envia o pin de localizacao de uma UNIDADE pelo pipeline nativo do SPX.
#
# Irma da EnviarLocalizacaoTool (escritorio) e da EnviarLocalizacaoImovelTool (Vista): mesma
# mecanica de anexo `file_type: :location`, mudando so de onde vem a coordenada. Aqui ela vem do
# cadastro de unidades, que e dado carregado e conferido — nao geocoding em tempo de atendimento.
class Captain::Tools::EnviarLocalizacaoUnidadeTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente o pin no mapa de uma unidade desta empresa pelo WhatsApp. ' \
              'Chame quando a pessoa pedir a localização, o mapa ou como chegar numa loja. ' \
              'Informe a cidade que ela citou. Só envia unidade que existe no cadastro e que ' \
              'tenha coordenada; se não tiver, o retorno diz isso e você responde pelo endereço.'

  param :cidade, type: 'string',
                 desc: 'O município da unidade que a pessoa quer, como ela escreveu nesta conversa.',
                 required: true

  SEM_CONVERSA = 'Não consegui identificar a conversa pra enviar a localização.'.freeze

  # Mesmo gate multi-tenant da BuscarUnidadesTool, e pelo mesmo motivo: a migration entra VM a VM,
  # e montar o agente numa box ainda nao migrada nao pode derrubar o atendimento da frota.
  def active?
    ::Spx::Unidade.ativas.com_coordenada.exists?(account_id: @assistant.account_id)
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoUnidade] active? indisponível: #{e.class} #{e.message}")
    false
  end

  def perform(tool_context, cidade:)
    conversation = find_conversation(tool_context&.state)
    return SEM_CONVERSA unless conversation

    unidade = encontrar(cidade)
    return sem_unidade(cidade) unless unidade
    return sem_coordenada(unidade) unless unidade.coordenada?

    enviar(conversation, unidade)
    log_tool_usage('enviar_localizacao_unidade', conversation_id: conversation.id, unidade: unidade.slug)
    "Pin da unidade #{unidade.nome} enviado. Não repita o endereço como se fosse outra coisa: " \
      'a pessoa acabou de receber o mapa.'
  rescue StandardError => e
    Rails.logger.warn("[EnviarLocalizacaoUnidade] #{e.class} #{e.message}")
    'Não consegui enviar o pin agora. Isto é falha de envio, não ausência de unidade: ' \
      'responda pelo endereço em texto.'
  end

  private

  def escopo
    ::Spx::Unidade.ativas.where(account_id: @assistant.account_id)
  end

  # Mesma regra de casamento da BuscarUnidadesTool (sem acento, sem caixa, continência nos dois
  # sentidos com piso de 3 letras). Duplicar a comparação aqui seria o caminho para as duas
  # ferramentas discordarem sobre qual é a loja de uma cidade.
  def encontrar(cidade)
    alvo = ::Spx::Unidade.normalizar(cidade)
    return nil if alvo.blank?

    unidades = escopo.to_a
    exatas = unidades.select { |unidade| ::Spx::Unidade.normalizar(unidade.cidade) == alvo }
    return exatas.first if exatas.any? || alvo.length < 3

    unidades.find { |unidade| contem?(unidade, alvo) }
  end

  def contem?(unidade, alvo)
    nome = ::Spx::Unidade.normalizar(unidade.cidade)
    nome.present? && (nome.include?(alvo) || alvo.include?(nome))
  end

  def sem_unidade(cidade)
    cidades = escopo.filter_map { |unidade| unidade.cidade.presence }.uniq
    "Não há unidade cadastrada em \"#{cidade.to_s.strip}\", então não há pin pra enviar. Isto é " \
      'resposta confirmada do cadastro, não falha: não mande o mapa de outra cidade como se fosse ' \
      "dessa. Cidades que têm unidade: #{cidades.first(25).join(', ')}."
  end

  def sem_coordenada(unidade)
    "A unidade #{unidade.nome} existe, mas não tem coordenada cadastrada — não há pin pra enviar. " \
      'NÃO invente o ponto no mapa: responda com o endereço em texto, que está no cadastro.'
  end

  # Anexo construido ANTES do save: o envio dispara no after_create_commit, e criar em duas etapas
  # seria corrida (mesmo cuidado da EnviarFotosImovelTool e da EnviarLocalizacaoTool).
  def enviar(conversation, unidade)
    msg = conversation.messages.build(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant
    )
    msg.attachments.build(
      account_id: conversation.account_id,
      file_type: :location,
      coordinates_lat: unidade.latitude.to_f,
      coordinates_long: unidade.longitude.to_f,
      fallback_title: [unidade.nome, unidade.cidade].compact_blank.uniq.join(' — ')
    )
    msg.save!
  end
end
