class Captain::Tools::SalvarInfoLeadTool < Captain::Tools::BasePublicTool
  # Onde o nome dito PELO CLIENTE é guardado. Fica no contato (vale pras próximas conversas)
  # e NUNCA em `contact.name`: nessa base o campo nome é área de trabalho do time humano —
  # eles anotam ali de que se trata o contato ("Fulano / Casa do Beltrano", "Sicrano Prop.").
  # Sobrescrever apagaria a referência que o corretor usa pra saber qual imóvel é.
  CONTACT_NAME_KEY = 'nome_confirmado'.freeze
  MAX_NAME_LENGTH = 80

  # Prioridade é dimensão NOVA e ortogonal ao status: mede chance de aprovação de
  # crédito, não estágio do lead. Um lead pode ser `qualificado` + `morno`.
  PRIORIDADES = %w[quente morno frio].freeze
  # A escala de negócio tem um 4º nível, "lixo", que NÃO é prioridade — é o status
  # `nao_qualificado`. O modelo tenta mandá-lo aqui; aceitar e rotear custa menos que
  # recusar (recusa queima turno e às vezes ele desiste em vez de reformular).
  PRIORIDADE_LIXO = 'lixo'.freeze
  LABEL_PREFIXO = 'prioridade-'.freeze
  TERNARIO = %w[sim nao nao_perguntado].freeze

  description 'Salva informações do lead na conversa: status do lead e uma descrição curta sobre o cliente. ' \
              'Chame quando entender o perfil/situação do cliente, ou quando o lead esfriar e precisar de reabordagem futura. ' \
              'Atualiza o que já existir, sem apagar o resto.'

  param :status, type: 'string',
        desc: 'Status do lead: novo, em_contato, qualificado, esfriado, perdido, nao_qualificado ou convertido.', required: false
  param :sobre_cliente, type: 'string',
        desc: 'Descrição curta (1 a 2 frases) sobre o cliente: o que procura, perfil e situação.', required: false
  param :precisa_followup, type: 'boolean',
        desc: 'true quando a conversa precisa de reabordagem depois (cliente esfriou, pediu pra pensar, sem resposta).', required: false
  param :nome_cliente, type: 'string',
        desc: 'Como a pessoa disse que se chama, quando ela informou o nome NESTA conversa. ' \
              'Só o que veio da própria pessoa — nunca o nome que aparece no cadastro do contato, ' \
              'que costuma ser anotação interna da equipe. Vazio se ela não disse o nome.', required: false
  param :prioridade,
        type: 'string',
        desc: 'Chance de aprovação de crédito deste lead: quente quando ele declarou renda comprovável e não ' \
              'mencionou restrição; morno quando falta um dos dois mas ele apontou um caminho possível; frio quando ' \
              'respondeu mas resiste a informar, ou não apareceu caminho nenhum. ' \
              'Baseie-se só no que o cliente disse NESTA conversa. Deixe vazio enquanto não souber — ' \
              'não deduza pelo perfil nem pelo produto.',
        required: false
  param :renda_comprovavel,
        type: 'string',
        desc: 'O que o cliente disse sobre conseguir comprovar renda: sim, nao, ou nao_perguntado enquanto o ' \
              'assunto não tiver vindo na conversa.',
        required: false
  param :restricao_nome,
        type: 'string',
        desc: 'O que o cliente disse sobre ter restrição no nome: sim, nao, ou nao_perguntado enquanto o ' \
              'assunto não tiver vindo na conversa.',
        required: false
  param :caminho_alternativo,
        type: 'string',
        desc: 'Em uma frase, o caminho que o PRÓPRIO cliente apontou pra viabilizar a compra quando algo não fecha. ' \
              'Só o que ele disse; vazio se ele não apontou nenhum.',
        required: false

  # **args em vez de 9 keywords nomeadas: o schema que o LLM enxerga vem do DSL `param`
  # acima, não da assinatura.
  def perform(tool_context, **args)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra salvar as informações.' unless conversation

    prioridade, status, virou_lixo = resolver_prioridade(conversation, args[:prioridade], args[:status])
    conversation.update!(custom_attributes: montar_attrs(conversation, args, prioridade, status))
    aplicar_efeitos(conversation, args, prioridade, status)

    retorno(prioridade, virou_lixo)
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] #{e.message}")
    'Não consegui salvar as informações agora.'
  end

  private

  def montar_attrs(conversation, args, prioridade, status)
    attrs = conversation.custom_attributes.dup
    attrs['tozi_status_lead'] = status if status.present?
    attrs['sobre_cliente'] = args[:sobre_cliente] if args[:sobre_cliente].present?
    attrs.merge(atributos_de_prioridade(prioridade, args[:renda_comprovavel], args[:restricao_nome],
                                        args[:caminho_alternativo]))
  end

  def aplicar_efeitos(conversation, args, prioridade, status)
    salvar_nome_do_cliente(conversation, args[:nome_cliente])
    move_funnel_by_status(conversation, status)
    aplicar_label_de_prioridade(conversation, prioridade)
    mark_followup(conversation) if args[:precisa_followup]
  end

  # "lixo" chega como prioridade mas É status: rotear pra nao_qualificado (que já cancela
  # cadência e etiqueta) em vez de recusar a chamada. Logado pra medir a frequência.
  def resolver_prioridade(conversation, prioridade, status)
    valor = prioridade.to_s.strip.downcase
    return [nil, status, false] if valor.blank?
    return [valor, status, false] if PRIORIDADES.include?(valor)

    if valor == PRIORIDADE_LIXO
      log_tool_usage('prioridade_lixo_roteada', conversation_id: conversation.id, status_original: status)
      return [nil, 'nao_qualificado', true]
    end

    [nil, status, false]
  end

  def atributos_de_prioridade(prioridade, renda, restricao, caminho)
    out = {}
    out['prioridade'] = prioridade if prioridade.present?
    out['renda_comprovavel'] = normalizar_ternario(renda) if normalizar_ternario(renda)
    out['restricao_nome'] = normalizar_ternario(restricao) if normalizar_ternario(restricao)
    out['caminho_alternativo'] = caminho.to_s.strip if caminho.to_s.strip.present?
    out
  end

  def normalizar_ternario(valor)
    v = valor.to_s.strip.downcase.tr('ã', 'a').tr('ç', 'c')
    return 'sim' if %w[sim true yes].include?(v)
    return 'nao' if %w[nao false no].include?(v)

    TERNARIO.include?(v) ? v : nil
  end

  # Uma prioridade por conversa: troca a anterior em vez de acumular rótulos.
  # `add_labels` SOMA (labels + new_labels) — quem substitui a lista é `update_labels`.
  def aplicar_label_de_prioridade(conversation, prioridade)
    return if prioridade.blank?

    demais = conversation.label_list.reject { |l| l.to_s.start_with?(LABEL_PREFIXO) }
    conversation.update_labels((demais + ["#{LABEL_PREFIXO}#{prioridade}"]).uniq)
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] label prioridade: #{e.message}")
  end

  def retorno(prioridade, virou_lixo)
    if virou_lixo
      return 'Lead marcado como NÃO QUALIFICADO (a escala chama isso de "lixo"): cadência cancelada e etiquetado. ' \
             'Não re-aborde este lead.'
    end
    return 'Informações do lead salvas.' if prioridade.blank?

    "Informações do lead salvas, com prioridade #{prioridade}. O handoff vai levar isso pro corretor."
  end

  # Grava o nome no contato, em campo próprio — `name` fica intocado (ver CONTACT_NAME_KEY).
  # Só escreve quando muda, pra não sujar o histórico do contato a cada chamada da tool.
  def salvar_nome_do_cliente(conversation, nome)
    limpo = nome.to_s.strip.gsub(/\s+/, ' ').first(MAX_NAME_LENGTH)
    return if limpo.blank?

    contact = conversation.contact
    return if contact.nil?

    atuais = contact.custom_attributes || {}
    return if atuais[CONTACT_NAME_KEY].to_s.casecmp(limpo).zero?

    contact.update!(custom_attributes: atuais.merge(CONTACT_NAME_KEY => limpo))
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] nome contact=#{conversation.contact_id}: #{e.message}")
  end

  # Bloco 3 (funil Tozi): espelha o status do lead no estágio do Kanban.
  def move_funnel_by_status(conversation, status)
    case status
    when 'qualificado', 'convertido'
      Spx::Tozi::ReactivationCadenceService.cancel_pending(conversation)
      Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'qualificado')
    when 'esfriado', 'perdido'
      Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
      Spx::Tozi::ReactivationCadenceService.new(conversation: conversation).perform
    when 'nao_qualificado'
      # Sem perfil pro financiamento (renda por auxilio temporario INSS, ou abaixo do piso sem
      # composicao) e sem caminho alternativo. NAO re-aborda (nao gasta HSM nem tempo do corretor):
      # cancela cadencia, tira do funil ativo e marca com label pro time filtrar.
      Spx::Tozi::ReactivationCadenceService.cancel_pending(conversation)
      Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
      conversation.add_labels((conversation.label_list + ['nao-qualificado']).uniq)
    end
  end

  def mark_followup(conversation)
    conversation.add_labels((conversation.label_list + ['followup-ativo']).uniq)
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] label: #{e.message}")
  end
end
