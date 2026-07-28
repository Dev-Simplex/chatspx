class Captain::Tools::SalvarInfoLeadTool < Captain::Tools::BasePublicTool
  # Onde o nome dito PELO CLIENTE é guardado. Fica no contato (vale pras próximas conversas)
  # e NUNCA em `contact.name`: nessa base o campo nome é área de trabalho do time humano —
  # eles anotam ali de que se trata o contato ("Fulano / Casa do Beltrano", "Sicrano Prop.").
  # Sobrescrever apagaria a referência que o corretor usa pra saber qual imóvel é.
  CONTACT_NAME_KEY = 'nome_confirmado'.freeze
  MAX_NAME_LENGTH = 80

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

  def perform(tool_context, status: nil, sobre_cliente: nil, precisa_followup: false, nome_cliente: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra salvar as informações.' unless conversation

    attrs = conversation.custom_attributes.dup
    attrs['tozi_status_lead'] = status if status.present?
    attrs['sobre_cliente'] = sobre_cliente if sobre_cliente.present?
    conversation.update!(custom_attributes: attrs)

    salvar_nome_do_cliente(conversation, nome_cliente)
    move_funnel_by_status(conversation, status)
    mark_followup(conversation) if precisa_followup

    'Informações do lead salvas.'
  rescue StandardError => e
    Rails.logger.warn("[SalvarInfoLeadTool] #{e.message}")
    'Não consegui salvar as informações agora.'
  end

  private

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
