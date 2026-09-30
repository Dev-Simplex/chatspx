# Envia ao cliente um contato de telefone da unidade que atende a conversa — decisão de 29/09: a IA
# NÃO escreve telefone. Ela escolhe QUAL contato, pelo rótulo do cadastro; quem envia o número é o
# sistema. Nenhum retorno desta ferramenta traz número, para o modelo não ter o que copiar.
#
# A unidade vem da caixa (`inboxes.unit_id`). Caixa sem vínculo só herda unidade quando a conta tem
# exatamente uma ativa; com várias, não há como saber qual é, e a resposta manda passar para humano.
#
# No WhatsApp (Cloud e WAHA) sai cartão de contato, pelo mesmo formato do compartilhamento manual.
# Nos outros canais sai o número numa mensagem de texto só com ele — o app do Instagram transforma
# número em cartão com "WhatsApp" e "Ligar" (teste do Paulo, 29/09). Isso é comportamento do app,
# não contrato da API, e está isolado em `enviar_em_texto` para ser trocado depois.
class Captain::Tools::EnviarContatoUnidadeTool < Captain::Tools::BasePublicTool
  description 'Envia ao cliente um contato de telefone da unidade que atende esta conversa. O número ' \
              'sai do cadastro e quem o envia é o sistema: você nunca vê nem escreve número de ' \
              'telefone. Chame quando a pessoa pedir telefone, número ou contato. Informe o rótulo ' \
              'do contato que corresponde ao que ela pediu; sem rótulo, ou com um que não existe, o ' \
              'retorno traz os rótulos disponíveis para você escolher e chamar de novo.'

  param :rotulo, type: 'string',
                 desc: 'Um dos rótulos de contato devolvidos por esta ferramenta ou pela consulta de ' \
                       'unidades, escrito como veio lá. Vazio devolve a lista de rótulos.',
                 required: false

  ID = 'enviar_contato_unidade'.freeze
  # Opção extra, só em caixa de WhatsApp: o número por onde a própria conversa acontece.
  ROTULO_CAIXA = 'WhatsApp deste atendimento'.freeze

  SEM_CONVERSA = 'Não consegui identificar a conversa pra enviar o contato.'.freeze
  SEM_UNIDADE = 'Esta conversa não está vinculada a uma unidade, então não há contato de cadastro pra ' \
                'enviar. Isto é resposta do cadastro, não falha. Não escreva número de telefone: ' \
                'ofereça passar a conversa para uma pessoa do time.'.freeze
  FALHA = 'Não consegui enviar o contato agora. Isto é falha de envio: não escreva número de telefone ' \
          'na resposta; ofereça passar a conversa para uma pessoa do time.'.freeze

  # O `buscar_unidades` precisa saber se o número pode sair da vista da IA: só pode quando esta
  # ferramenta está na lista do agente (`config['tools']`, a mesma que `configured_agent_tools` lê).
  def self.armada?(assistant)
    Array(assistant.config&.dig('tools')).map(&:to_s).include?(ID)
  end

  # Linha de telefone de cada unidade no retorno do `buscar_unidades`. Com esta ferramenta armada,
  # a IA recebe só os rótulos; sem ela, o telefone continua como antes, senão a conta perderia o
  # contato.
  def self.linha_de_telefone(unidade, assistant)
    return ("Telefone: #{unidade.telefone}" if unidade.telefone.present?) unless armada?(assistant)

    rotulos = unidade.contatos_rotulados.map { |contato| "\"#{contato[:rotulo]}\"" }
    return nil if rotulos.empty?

    "Contatos de telefone: #{rotulos.join(', ')}. O número não aparece aqui: para passar um deles, use a " \
      "ferramenta #{ID} com o rótulo."
  end

  # Mesmo gate da BuscarUnidadesTool: sem unidade ativa na conta, a ferramenta nem entra no toolset.
  def active?
    ::Unit.ativas.exists?(account_id: @assistant.account_id)
  rescue StandardError => e
    Rails.logger.warn("[EnviarContatoUnidade] active? indisponível: #{e.class} #{e.message}")
    false
  end

  def perform(tool_context, rotulo: nil)
    conversation = find_conversation(tool_context&.state)
    return SEM_CONVERSA unless conversation

    unidade = ::Unit.da_caixa(conversation.inbox)
    return SEM_UNIDADE unless unidade

    escolher_e_enviar(conversation, unidade, rotulo)
  rescue StandardError => e
    Rails.logger.warn("[EnviarContatoUnidade] #{e.class} #{e.message}")
    FALHA
  end

  private

  def escolher_e_enviar(conversation, unidade, rotulo)
    opcoes = opcoes(unidade, conversation.inbox)
    return sem_contato(unidade) if opcoes.empty?

    escolhida = opcoes.find { |opcao| ::Unit.normalizar(opcao[:rotulo]) == ::Unit.normalizar(rotulo) }
    escolhida ? enviar(conversation, unidade, escolhida) : lista(unidade, opcoes, rotulo)
  end

  def opcoes(unidade, inbox)
    contatos = unidade.contatos_rotulados.map { |contato| contato.merge(source: 'unit', ref: unidade.id) }
    contatos << { rotulo: ROTULO_CAIXA, caixa: true, source: 'inbox', ref: inbox.id } if whatsapp?(inbox)
    contatos
  end

  def enviar(conversation, unidade, opcao)
    telefone = opcao[:caixa] ? numero_da_caixa(conversation.inbox) : opcao[:telefone]
    return FALHA if telefone.blank?

    marca = { 'contato_enviado' => { 'rotulo' => opcao[:rotulo] } }
    if whatsapp?(conversation.inbox)
      nome = nome_do_cartao(unidade, opcao)
      contato = { name: nome, phone: e164(telefone), source: opcao[:source], ref: opcao[:ref] }
      ::Messages::ContactCardBuilder.new(conversation: conversation, sender: @assistant, contact: contato,
                                         additional_attributes: marca).perform
      registrar(conversation, opcao)
      "Cartão de contato \"#{nome}\" enviado à pessoa pelo sistema. Ela já recebeu o número: não escreva " \
        'número de telefone na resposta, só confirme o envio.'
    else
      enviar_em_texto(conversation, telefone, marca)
      registrar(conversation, opcao)
      "O número do contato \"#{opcao[:rotulo]}\" da unidade #{unidade.nome} foi enviado à pessoa numa " \
        'mensagem separada, escrita pelo sistema. Não escreva número de telefone na resposta, só confirme o envio.'
    end
  end

  # Canal sem cartão de contato: o número vai sozinho numa mensagem, formatado pelo sistema.
  def enviar_em_texto(conversation, telefone, marca)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: @assistant,
      content: legivel(e164(telefone)),
      additional_attributes: marca
    )
  end

  def registrar(conversation, opcao)
    log_tool_usage(ID, conversation_id: conversation.id, rotulo: opcao[:rotulo])
  end

  def whatsapp?(inbox)
    inbox.whatsapp? || (inbox.api? && inbox.waha_session_name.present?)
  end

  def nome_do_cartao(unidade, opcao)
    opcao[:caixa] ? unidade.nome : "#{unidade.nome} — #{opcao[:rotulo]}"
  end

  # Cloud guarda o número no canal; no WAHA ele é o `me` da sessão, com o mesmo cache que a tela de
  # Conexões usa (Api::V1::Accounts::WahaConnectionsController#format_connection).
  def numero_da_caixa(inbox)
    return inbox.channel.phone_number if inbox.whatsapp?

    sessao = inbox.waha_session_name
    me = Rails.cache.fetch("waha/me/#{inbox.account_id}/#{inbox.id}/#{sessao}", expires_in: 10.minutes) do
      ::Waha::ApiService.new.get_session_me(sessao)
    end
    me&.dig('id').to_s.split('@').first.presence
  rescue ::Waha::ApiService::Error => e
    Rails.logger.warn("[EnviarContatoUnidade] número da sessão #{sessao} indisponível: #{e.message}")
    nil
  end

  # Número brasileiro sem DDI ganha o +55 (a gramática é a das listas de disparo). Número com DDI de
  # outro país fica como veio: tratar como brasileiro inventaria um número.
  def e164(telefone)
    bruto = telefone.to_s.strip
    digitos = bruto.gsub(/\D/, '')
    return "+#{digitos}" if bruto.start_with?('+') && !digitos.start_with?('55')

    ddd, assinante = ::Campaigns::Whatsapp::CanonicalPhone.new.split_number(digitos)
    ddd ? "+55#{ddd}#{assinante}" : "+#{digitos}"
  end

  def legivel(numero)
    casamento = numero.match(/\A\+55(\d{2})(\d{4,5})(\d{4})\z/)
    casamento ? "+55 (#{casamento[1]}) #{casamento[2]}-#{casamento[3]}" : numero
  end

  def sem_contato(unidade)
    "A unidade #{unidade.nome} não tem contato de telefone cadastrado. Isto é resposta do cadastro, não " \
      'falha. Não escreva número de telefone: ofereça passar a conversa para uma pessoa do time.'
  end

  def lista(unidade, opcoes, rotulo)
    pedido = rotulo.to_s.strip
    abertura = pedido.present? ? "\"#{pedido}\" não é um dos contatos desta unidade. " : ''
    itens = opcoes.map { |opcao| item(opcao) }.join(', ')
    "#{abertura}Contatos que posso enviar da unidade #{unidade.nome}: #{itens}. Escolha o que corresponde ao " \
      'que a pessoa pediu e chame esta ferramenta de novo com o rótulo. O número não aparece aqui de ' \
      'propósito: quem o envia é o sistema.'
  end

  def item(opcao)
    return "\"#{opcao[:rotulo]}\" (o número por onde esta conversa está acontecendo)" if opcao[:caixa]

    "\"#{opcao[:rotulo]}\""
  end
end
