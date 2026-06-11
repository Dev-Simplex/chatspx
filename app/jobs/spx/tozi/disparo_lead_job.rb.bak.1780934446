# Disparo em massa do lançamento (1 lead). Cria Contact + Conversation na inbox 91,
# atribui ao corretor (round-robin decidido pelo orquestrador) e envia o HSM aprovado
# personalizado ({{1}} = primeiro nome). Idempotente por telefone (ContactInbox reusa
# o contato; conversa nova por disparo). Best-effort: rescue + log, não derruba a fila.
#
# Enfileirado espaçado em ~2h pelo rake `spx:tozi:disparo` -> respeita rate-limit da Meta.
module Spx
  module Tozi
    class DisparoLeadJob < ApplicationJob
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
          'Oi %<n>s, aqui é %<a>s da Tozi. Apareceu uma oportunidade que combina com quem já é cliente da casa e lembrei de você — algo que valoriza e gera renda. Vale 2 minutos seu pra eu explicar?'
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
            name: nome.to_s.strip.presence || first,
            phone_number: phone,
            additional_attributes: { source: 'disparo_lancamento' }
          },
          source_id: phone.delete('+') # inbox Cloud API exige source_id só-dígitos (wa_id)
        ).perform

        conversation = Conversation.create!(
          account_id: inbox.account_id,
          inbox_id: inbox.id,
          contact_id: contact_inbox.contact_id,
          contact_inbox_id: contact_inbox.id,
          status: 'open',
          assignee_id: assignee_id,
          campaign_id: campaign_id,
          additional_attributes: { source: 'disparo_lancamento', template: template }
        )

        send_hsm(conversation, template, first, agent_first_name(assignee_id))
      rescue StandardError => e
        Rails.logger.error("[Disparo] falha tel=#{telefone.inspect}: #{e.class}: #{e.message}")
      end

      private

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

      def agent_first_name(assignee_id)
        User.find_by(id: assignee_id)&.name.to_s.strip.split.first.presence || 'Guilherme'
      end

      def send_hsm(conversation, template, first, agent)
        # format ignora chaves nao-usadas, entao passar n+a serve pros templates de 1 ou 2 vars.
        preview = format(PREVIEWS.fetch(template, 'Oi %<n>s!'), n: first, a: agent)
        params = {
          content: preview,
          content_type: :text,
          message_type: 'outgoing',
          private: false,
          template_params: {
            'name' => template,
            'language' => LANGUAGE,
            'processed_params' => { 'body' => { '1' => first, '2' => agent } }
          }
        }
        Messages::MessageBuilder.new(nil, conversation, params.with_indifferent_access).perform
      end
    end
  end
end
