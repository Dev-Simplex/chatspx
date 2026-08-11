# Disparo em massa do lançamento (1 lead). Cria Contact + Conversation na inbox 91,
# atribui ao corretor (round-robin decidido pelo orquestrador) e envia o HSM aprovado
# personalizado ({{1}} = primeiro nome). Idempotente por telefone (ContactInbox reusa
# o contato; conversa nova por disparo). Best-effort: rescue + log, não derruba a fila.
#
# Enfileirado espaçado em ~2h pelo rake `spx:tozi:disparo` -> respeita rate-limit da Meta.
class Spx::Tozi::DisparoLeadJob < ApplicationJob
  queue_as :low

  INBOX_ID = 91
  LANGUAGE = 'pt_BR'.freeze

  # Texto que o cliente vê (= corpo do template aprovado). O envio real é HSM via
  # template_params; este content é o espelho na transcrição do Chatwoot.
  PREVIEWS = {
    'tozi_lancamento_interagir' =>
      'Oi %<n>s, tudo bem? Você está podendo conversar agora?',
    'tozi_lancamento_qualifica' =>
      "Oi %<n>s, recebemos um alto volume de clientes todos os meses em busca de imóvel para alugar com 3 quartos. Vamos participar de um lançamento com apartamentos de 3 suítes e priorizamos nossos clientes nessa informação.\n\nÉ do seu interesse saber mais e ampliar sua carteira, ou até comprar para moradia?",
    'tozi_lancamento_curiosidade' =>
      "Oi %<n>s, quero compartilhar com você um dado rápido sobre Sinop:\n\nA oferta de apartamentos de 3 suítes na cidade é baixa, e a procura por esse perfil não para de crescer, o que favorece a liquidez na locação.\n\nPor isso, tem um lançamento chegando que vai criar uma boa oportunidade. Você tem interesse?",
    'tozi_lanc_prioridade' =>
      "Oi %<n>s! Sou %<a>s, da Tozi Imóveis. Vamos ter um lançamento esse mês e antes de abrir ao público, estou avisando primeiro os proprietários que já confiam na gente pra locação.\n\nSão apartamentos de 3 suítes no Aquarela das Artes, com as melhores condições reservadas pra quem entra agora, na pré-venda.\n\nÉ do seu interesse estar recebendo mais informações?",
    'tozi_lanc_portfolio' =>
      "Oi %<n>s! Aqui é %<a>s. Você tem pensado em ampliar seu portfólio de imóveis pra locação? Pergunto porque está chegando um lançamento que está com a procura altíssima pra aluguel na região do Aquarela das Artes, apartamentos de 3 suítes.\n\nÉ interesse seu receber mais informações?",
    'tozi_lanc_investidor' =>
      "Oi %<n>s! Aqui é %<a>s. Estou entrando em contato com alguns proprietários porque vamos participar de um lançamento que combina muito com quem já investe em locação: apartamentos de 3 suítes na região do Aquarela das Artes.\n\nÉ um perfil de altíssima procura pra alugar na região. Você quer receber mais informações?",
    'tozi_venda_prioridade' =>
      "Oi %<n>s, aqui é o %<a>s da Tozi Imóveis. Tudo bem? Vamos lançar um empreendimento de apartamento de 3 suítes agora em junho e antes de abrir para o público estou dando prioridade para clientes que tiveram casa para venda conosco.\n\nÉ do seu interesse saber mais?",
    'tozi_venda_investidor' =>
      "Oi %<n>s, tudo bem? %<a>s aqui, da Tozi. Selecionei alguns clientes nossos para contar que vai sair um lançamento com um perfil de investimento muito forte, tipo de imóvel que valoriza rápido e ainda gera aluguel. Como você já teve imóvel para venda com a gente, achei que valia te mostrar antes de ser aberto a público em geral.\n\nÉ do seu interesse mais informações?",
    'tozi_venda_condicoes' =>
      "Oi %<n>s, %<a>s da Tozi. Estamos com previsão para um lançamento esse mês, com condições especiais nas primeiras unidades. Estou fazendo contato antecipado pros clientes da casa.\n\nÉ do seu interesse mais informações?",
    'tozi_venda_abertura' =>
      'Oi %<n>s, tudo bem? Aqui é %<a>s, da Tozi Imóveis. Tá podendo falar agora?',
    'tozi_venda_condicao' =>
      'Oi %<n>s, aqui é %<a>s, da Tozi. Vai sair um lançamento esse mês com condição especial nas primeiras unidades, e estou avisando os clientes da casa antes de abrir. É do seu interesse saber mais?',
    'tozi_venda_invest' =>
      'Oi %<n>s, aqui é %<a>s, da Tozi. Vai sair um lançamento com perfil forte de investimento, que valoriza rápido e ainda gera aluguel. Como você já teve imóvel pra venda com a gente, quis te mostrar antes de abrir ao público. É do seu interesse saber mais?',
    'tozi_venda_suites' =>
      'Oi %<n>s, aqui é %<a>s, da Tozi Imóveis. Vamos lançar um apartamento de 3 suítes agora em junho e, antes de abrir ao público, estou dando prioridade pra quem já teve casa pra venda com a gente. É do seu interesse saber mais?',
    'tozi_venda_oportunidade' =>
      'Oi %<n>s, aqui é %<a>s da Tozi. Separei uma oportunidade boa pra você antes de abrir ao público — um imóvel que tende a valorizar rápido e que ainda dá pra alugar. Quer que eu te conte como funciona?',
    'tozi_venda_lembrei' =>
      'Oi %<n>s, aqui é %<a>s da Tozi. Apareceu uma oportunidade que combina com quem já é cliente da casa e lembrei de você — algo que valoriza e gera renda. Vale 2 minutos seu pra eu explicar?',
    'tozi_inq_lancamento' =>
      'Tá chegando o lançamento mais esperado de Sinop: apartamentos de até 3 suítes do lado da UNEMAT, com entrada parcelada na obra. Tô avisando os clientes da casa antes de abrir ao público — quem se antecipa garante as melhores condições. Quer saber mais?',
    'tozi_inq_invest' =>
      'Quis te mostrar uma oportunidade antes de abrir ao público: lançamento de apartamentos de até 3 suítes na região do Aquarela das Artes, do lado da UNEMAT — uma das que mais valorizam em Sinop. Entrada parcelada na obra, ótima pra morar ou investir. Faz sentido pra você?',
    'tozi_inq_cliente' =>
      'Como você foi cliente da Tozi, quis te avisar em primeira mão: tá chegando um lançamento de apartamentos de até 3 suítes na região do Aquarela das Artes, com entrada parcelada na obra. Posso te passar os detalhes e reservar sua prioridade antes de abrir ao público?'
  }.freeze

  INQ_IMAGE_URL = 'https://tozi.chatspx.app/inq-mapa.jpeg'.freeze
  INQ_IMAGE_HEADER = { 'media_url' => INQ_IMAGE_URL, 'media_type' => 'image' }.freeze
  # templates de inquilinos: corpo SEM variavel; valor = :image (header de imagem) ou :text
  NO_BODY_VAR = {
    'tozi_inq_lancamento' => :image,
    'tozi_inq_invest' => :image,
    'tozi_inq_cliente' => :text
  }.freeze

  def perform(nome:, telefone:, assignee_id:, template:, campaign_id: nil, dry_run: false)
    inbox = Inbox.find(INBOX_ID)
    first = first_name(nome)
    phone = normalize_phone(telefone)
    return Rails.logger.warn("[Disparo] telefone inválido: #{telefone.inspect}") if phone.blank?

    if dry_run
      Rails.logger.info("[Disparo][DRY] #{phone} #{first} -> corretor##{assignee_id} | #{template}")
      return
    end

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        # Sem nome na lista, o contato fica SEM NOME (string vazia, nunca nil — nil vira
        # apelido aleatório no builder). `first` só serve pro template; usá-lo aqui
        # gravava a saudação neutra como nome do contato. Ver RecipientDispatchService.
        name: nome.to_s.strip,
        phone_number: phone,
        additional_attributes: { source: 'disparo_lancamento' }
      },
      # Reconcilia variantes 12d/13d (9o digito) e reusa a ficha que o WhatsApp ja
      # usa pros replies -> nao cria ficha duplicada (causa do reply orfao).
      source_id: resolved_source_id(inbox, phone)
    ).perform

    conversation = find_or_create_conversation(inbox, contact_inbox, assignee_id, campaign_id, template)

    send_hsm(conversation, template, first, agent_first_name(assignee_id))
  rescue StandardError => e
    Rails.logger.error("[Disparo] falha tel=#{telefone.inspect}: #{e.class}: #{e.message}")
  end

  private

  # Token de saudação do TEMPLATE (o {{1}}), não o nome do contato. A saudação neutra é
  # correta aqui — "Oi tudo bem!" — e errada como nome de pessoa.
  def first_name(nome)
    nome.to_s.strip.split.first.presence || 'tudo bem'
  end

  def normalize_phone(raw)
    d = raw.to_s.gsub(/\D/, '')
    return nil if d.blank?

    d = "55#{d}" if d.length.between?(10, 11)
    formatted = "+#{d}"
    Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted
  end

  # Reusa a ficha existente do contato reconciliando o 9o digito (variantes 12d/13d).
  # Se o contato ja existe em qualquer forma, devolve o source_id daquela ficha;
  # senao cai no nosso wa_id so-digitos (contato novo).
  def resolved_source_id(inbox, phone)
    waid = phone.delete('+')
    Whatsapp::PhoneNumberNormalizationService.new(inbox)
                                             .normalize_and_find_contact_by_provider(waid, :cloud)
  end

  # Honra o lock_to_single da inbox 91: reusa a conversa unica do contato (em
  # qualquer ficha), reabrindo se resolvida e atribuindo ao corretor do disparo.
  # Cria conversa nova so quando o contato nunca teve uma.
  def find_or_create_conversation(inbox, contact_inbox, assignee_id, campaign_id, template)
    base = Conversation.where(inbox_id: inbox.id, contact_id: contact_inbox.contact_id)
    conversation = base.where.not(status: :resolved).order(created_at: :desc).first ||
                   base.order(created_at: :desc).first

    if conversation
      # Fase E/E2: atribuição SEMPRE pelo trilho canônico — o AssignmentService zera o
      # espelho captain no MESMO save (invariante humano×IA da Fase A).
      Conversations::AssignmentService.new(conversation: conversation, assignee_id: assignee_id).perform if conversation.assignee_id != assignee_id
      conversation.update!(campaign_id: campaign_id) if campaign_id && conversation.campaign_id.nil?
      conversation.open! unless conversation.open?
      return conversation
    end

    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      status: 'open',
      assignee_id: assignee_id,
      campaign_id: campaign_id,
      additional_attributes: { source: 'disparo_lancamento', template: template }
    )
  end

  def agent_first_name(assignee_id)
    User.find_by(id: assignee_id)&.name.to_s.strip.split.first.presence || 'Guilherme'
  end

  def send_hsm(conversation, template, first, agent)
    ::Whatsapp::SendTemplateService.new(
      conversation: conversation, name: template, language: LANGUAGE,
      # Templates de inquilinos tem o corpo SEM variavel; os demais usam
      # {{1}}=lead e {{2}}=corretor.
      body_params: NO_BODY_VAR.key?(template) ? {} : { '1' => first, '2' => agent },
      header: (INQ_IMAGE_HEADER if NO_BODY_VAR[template] == :image),
      mirror: mirror_for(template, first, agent)
    ).perform
  end

  # Espelho de RESERVA da transcricao: so entra quando o template nao esta
  # sincronizado no canal. Com ele sincronizado, o espelho sai do corpo aprovado —
  # e a divergencia que produziu o "Oi Adriana!" deixa de ser possivel.
  def mirror_for(template, first, agent)
    return PREVIEWS[template] if NO_BODY_VAR.key?(template)

    # format ignora chaves nao-usadas, entao n+a serve pros templates de 1 ou 2 vars.
    format(PREVIEWS.fetch(template, 'Oi %<n>s!'), n: first, a: agent)
  end
end
