# Diz com QUEM está a chave de um imóvel, lendo o cadastro do Vista.
#
# O Vista guarda isso no campo `Chave` (lista fechada: Imobiliária, Proprietário(a),
# Inquilino(a), Corretor(a), Construtor(a), Guarita, No local, Agendar). É um
# DESCRITOR de posse, não um estado ao vivo de empréstimo: não há data de retirada,
# prazo nem devolução na API. Por isso a tool nunca promete reserva — quando a chave
# está na imobiliária, é atendimento presencial por ordem de chegada, e ela pode ter
# saído entre a consulta e a ida do cliente.
#
# Campo em branco é o caso mais comum: responde "não registrado" e manda confirmar
# com o time. Nunca deduzir a partir do tipo/status do imóvel.
class Captain::Tools::ConsultarChaveImovelTool < Captain::Tools::BasePublicTool
  include Captain::Tools::IntegrationCredentials

  description 'Consulta com quem está a chave de um imóvel (imobiliária, proprietário, guarita, etc.) para orientar uma visita. ' \
              'Chame quando o cliente perguntar se dá pra visitar/ver o imóvel, se a chave está aí, ou como faz pra entrar.'

  param :codigo, type: 'string',
                 desc: 'Código do imóvel, exatamente como veio no resultado da busca daquele imóvel. Nunca invente.',
                 required: true

  TIMEOUT = 15

  # Como o cliente deve ser orientado em cada posse registrada no Vista.
  ORIENTACAO = {
    'imobiliaria' => 'A chave está na imobiliária. AVISE SEMPRE, com naturalidade: o atendimento é presencial e por ordem de chegada, ' \
                     'não dá pra reservar a chave nem garantir que ela vai estar disponível na hora — outra pessoa pode ter pegado antes. ' \
                     'Ofereça combinar com um corretor pra não perder a viagem.',
    'proprietario' => 'A chave está com o proprietário: a visita precisa ser combinada antes. Ofereça acionar um corretor pra alinhar o horário.',
    'inquilino' => 'O imóvel está ocupado e a chave está com o inquilino: a visita precisa ser agendada com antecedência. ' \
                   'Ofereça acionar um corretor.',
    'corretor' => 'A chave está com um corretor: ofereça acionar o time pra combinar o horário da visita.',
    'construtor' => 'A chave está com a construtora: a visita passa por ela. Ofereça acionar um corretor pra agendar.',
    'guarita' => 'A chave fica na guarita/portaria do condomínio. A entrada costuma exigir autorização prévia — ' \
                 'ofereça acionar um corretor pra liberar.',
    'no local' => 'A chave fica no próprio imóvel. Ainda assim, confirme com um corretor antes de o cliente ir.',
    'agendar' => 'A visita a este imóvel é sob agendamento. Ofereça acionar um corretor pra marcar.'
  }.freeze

  def perform(_tool_context, codigo:)
    cod = codigo.to_s.gsub(/\D/, '')
    return 'Preciso do código do imóvel pra consultar a chave.' if cod.blank?

    log_tool_usage('consultando_chave', { codigo: cod })
    posse = fetch_chave(cod)
    return "Não consegui consultar a chave do imóvel #{cod} agora. Ofereça confirmar com o time." if posse.nil?

    if posse.blank?
      return "O imóvel #{cod} não tem a posse da chave registrada no sistema. NÃO deduza onde ela está nem diga que está na imobiliária: " \
             'diga que vai confirmar com o time e ofereça combinar a visita com um corretor.'
    end

    "Chave do imóvel #{cod}: #{posse}. #{orientacao_para(posse)}"
  rescue StandardError => e
    Rails.logger.warn("[ConsultarChaveImovelTool] #{e.message}")
    'Não consegui consultar a chave agora.'
  end

  private

  # nil = falha na consulta; '' = imóvel sem registro de chave.
  def fetch_chave(codigo)
    base = vista_base_url.to_s.chomp('/')
    base = "https://#{base}" unless base.start_with?('http')
    resp = HTTParty.get(
      "#{base}/imoveis/detalhes",
      query: { key: vista_api_key, imovel: codigo, pesquisa: { fields: %w[Codigo Chave] }.to_json },
      headers: { 'Accept' => 'application/json' },
      timeout: TIMEOUT
    )
    return nil unless resp.code == 200

    body = resp.parsed_response
    body = JSON.parse(body) if body.is_a?(String)
    body.is_a?(Hash) ? body['Chave'].to_s.strip : nil
  end

  # Casa pelo começo do rótulo, sem acento, pra tolerar variação de cadastro
  # ("Proprietário(a)", "Proprietaria", ...).
  def orientacao_para(posse)
    normalizada = posse.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    _, texto = ORIENTACAO.find { |chave, _| normalizada.start_with?(chave) }
    texto || 'Confirme com um corretor como fica o acesso pra visita.'
  end
end
