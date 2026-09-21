# Monta a fixture a partir de um JSON exportado da produção por consulta somente-leitura.
#
# Por que existe: o gravador é código de branch e o dado está na VM do cliente. Rodar o
# gravador lá seria deploy — proibido nesta tarefa. Então a produção só é LIDA, o bruto fica
# FORA do repositório, e a pseudonimização acontece na minha máquina antes de qualquer byte
# entrar no versionado. A garantia é a mesma: o Escritor.
#
# Nenhum campo é inventado aqui. O que não veio da produção não aparece na fixture — com UMA
# exceção, e ela é declarada no próprio arquivo: a ficha do PropertyRef (ver `ficha`).
class Spx::Harness::FixtureExportada
  LIMITE_PREVIEW = 1500

  # Mensagem do banco não é turno do modelo. Entre uma e outra a produção decide TRÊS coisas,
  # e todas mudam o cenário:
  #
  #   1. se entra  — Captain::Conversation::ResponseBuilderJob#survey_message? descarta NPS/CSAT;
  #   2. com que papel — #determine_role: incoming vira 'user', o resto vira 'assistant';
  #   3. com que texto — #outgoing_content troca payload interativo e anexo por um rótulo.
  #
  # Sem registrar isso, a fixture afirmaria coisas sobre texto que o modelo nunca viu. O
  # carrossel da conv 41803 é o exemplo: o banco guarda "📷 Carrossel: 9 fotos do imóvel 9412",
  # que é rótulo de PAINEL, e o modelo recebe "[carrossel de fotos do imóvel 9412 enviado]".
  ROTULO_INTERATIVO = 'mensagem interativa enviada'.freeze
  ROTULO_ANEXO = 'foto do imóvel enviada'.freeze

  AVISO_FICHA = 'Os valores abaixo são ESCOLHA DO CENÁRIO, não fato sobre o imóvel real. ' \
                'A consulta do PropertyRef acontece fora de ferramenta e não fica no trace, ' \
                'então não há como recuperá-la da produção. O teste prova o comportamento ' \
                'DADA esta evidência; não afirma nada sobre o acervo.'.freeze

  # Ferramentas que AGEM sobre o imóvel citado. A trava anti-alucinação delas é compartilhada
  # (Captain::Tools::ImoveisConhecidos) e tem uma condição a mais do que parece:
  #
  #   if vistos.any? && !vistos.include?(cod)   # enviar_fotos_imovel_tool.rb
  #
  # `vistos.any?` significa que a trava só EXISTE depois que alguma busca registrou código
  # nesta conversa. Conversa sem busca nenhuma passa direto — a trava não recusa, ela nem
  # chega a ser avaliada. É o §3.7 da auditoria, e é fail-open por construção.
  FERRAMENTAS_DE_ENVIO = %w[enviar_fotos_imovel enviar_localizacao_imovel].freeze
  CODIGO_EM_RESULTADO = /c[óo]d\.?\s*(\d{3,6})/i
  PORQUE_FAIL_OPEN = 'a trava anti-alucinação só é avaliada quando alguma busca desta conversa ' \
                     'já registrou código (`vistos.any? && !vistos.include?(cod)` em ' \
                     'enterprise/lib/captain/tools/enviar_fotos_imovel_tool.rb). Sem busca ' \
                     'nenhuma, ela não recusa: ela não roda. Ver §3.7 da auditoria.'.freeze
  # Pior que fail-open: a ferramenta nem inclui o Captain::Tools::ImoveisConhecidos. Não há
  # condição nenhuma a satisfazer — ela age sobre qualquer código que o modelo disser, tendo
  # havido busca ou não.
  PORQUE_SEM_TRAVA = 'esta ferramenta não tem trava: ela não inclui o ' \
                     'Captain::Tools::ImoveisConhecidos e nunca confere se o código apareceu ' \
                     'em busca desta conversa. Age sobre o que o modelo disser.'.freeze

  def initialize(bruto, id:)
    @bruto = bruto.deep_stringify_keys
    @id = id
  end

  def montar
    {
      'id' => @id,
      # Por FONTE, não por arquivo. O selo único mentia: os retornos de tool estão inteiros, mas
      # a ficha que o PropertyRef injeta vem de uma consulta PRÓPRIA ao Vista, fora de tool e
      # ausente do trace — para o replay ela tem de ser fabricada. Um `faithful` no topo
      # escondia isso atrás do pedaço que por acaso estava íntegro.
      'fidelidade' => fidelidade,
      'origem' => @bruto['origem'].merge('gravado_em' => Time.current.iso8601),
      # A conversa vai de 11/09 a 15/09 e tem mensagem depois do fechamento. Um relógio
      # congelado no primeiro minuto mudaria o cenário: cada mensagem e cada chamada carrega o
      # SEU instante, e aqui fica só a janela.
      'relogio' => @bruto['relogio'],
      'episodios' => @bruto['episodios'],
      'conta' => { 'flags' => @bruto['flags'] || {} },
      # Plural: a conversa teve DOIS agentes. A chamada 3 transfere, e as 4 e 5 rodam num
      # toolset que o primeiro agente nem tem. Fixture com um agente só não descreve o caso.
      'agentes' => @bruto['agentes'],
      'cache' => { 'estado' => 'vazio' },
      # O que o modelo VIU sem passar por ferramenta. Não está no trace e muda o cenário.
      'contexto_injetado' => contexto_injetado,
      'mensagens' => mensagens,
      'chamadas' => chamadas,
      'asseveracoes' => asseveracoes,
      'envios_sem_busca' => envios_sem_busca
    }
  end

  def gravar!(caminho, parafrasear: true)
    escritor.gravar!(montar, caminho, parafrasear: parafrasear)
  end

  private

  # O original vai junto para a checagem de preservação: é contra ele que se confere se algum
  # código ou valor se perdeu na pseudonimização.
  def escritor
    @escritor ||= Spx::Harness::Escritor.new(id: @id, nomes: Array(@bruto['nomes']),
                                             marca: @bruto['marca'],
                                             original: original_para_conferir)
  end

  # Só o que o cenário assevera: fala e retorno de ferramenta. Nome e telefone do original não
  # entram nem aqui — a checagem compara código e valor, não texto.
  def original_para_conferir
    (Array(@bruto['mensagens']).pluck('texto') +
      Array(@bruto['chamadas']).map { |c| [c['args'].to_json, c['resultado']] }).flatten.join("\n")
  end

  def mensagens
    Array(@bruto['mensagens']).map do |m|
      apresentado = apresentado_ao_modelo(m)
      ao_modelo = texto_ao_modelo(m)
      { 'de' => m['de'], 'em' => m['em'], 'agente' => m['agente'],
        'agente_nome' => m['agente_nome'], 'midia' => m['midia'],
        'marcador' => m['marcador'],
        'apresentado_ao_modelo' => apresentado,
        # Só quando DIFERE do texto guardado. Igual, seria ruído em toda linha.
        'texto_ao_modelo' => (ao_modelo if ao_modelo != m['texto'].to_s),
        'fala_do_agente' => fala_do_agente?(m),
        'texto' => m['texto'] }.compact
    end
  end

  # 'omitido' | 'user' | 'assistant' — o papel com que a mensagem chega ao modelo.
  #
  # O `meta_lead_ads_initial` cai em 'assistant' e isso NÃO é engano do gravador: nada o filtra,
  # e o template da campanha entra no contexto como fala do próprio agente. Ver a dívida
  # nomeada no doc 06 da auditoria.
  def apresentado_ao_modelo(mensagem)
    return 'omitido' if mensagem['marcador'].to_s == 'nps_survey'

    mensagem['direcao'].to_s == 'incoming' ? 'user' : 'assistant'
  end

  # Espelha ResponseBuilderJob#outgoing_content. Só o lado de SAÍDA: o de entrada passa por
  # multimodal e contexto de citação, que dependem de anexo e de mensagem citada — dado que
  # esta exportação não carrega. Mensagem de entrada fica com o texto do banco, e a fixture
  # não afirma nada sobre o que o modelo viu além disso.
  def texto_ao_modelo(mensagem)
    return mensagem['texto'].to_s if mensagem['direcao'].to_s == 'incoming'
    return "[#{rotulo(mensagem, ROTULO_INTERATIVO, 'carrossel de fotos do imóvel %<codigo>s enviado')}]" if
      mensagem['interativo']
    return mensagem['texto'].to_s if mensagem['texto'].to_s.present?
    return '' unless mensagem['anexos'].to_i.positive?

    "[#{rotulo(mensagem, ROTULO_ANEXO, 'foto do imóvel %<codigo>s enviada')}]"
  end

  def rotulo(mensagem, generico, com_codigo)
    codigo = mensagem['property_code'].to_s
    codigo.present? ? format(com_codigo, codigo: codigo) : generico
  end

  # Fala GERADA pelo agente — a única coisa que pode carregar afirmação dele.
  #
  # Fica de fora o que chega ao modelo como turno do assistente sem ser fala: rótulo de payload
  # interativo, placeholder de anexo e template de campanha. Cobrar do agente um preço escrito
  # pela campanha, ou um código escrito pelo próprio sistema ao registrar um envio confirmado,
  # acusaria invenção onde não houve nenhuma.
  def fala_do_agente?(mensagem)
    mensagem['de'].to_s == 'ia' &&
      mensagem['marcador'].blank? &&
      !mensagem['interativo'] &&
      mensagem['anexos'].to_i.zero? &&
      mensagem['texto'].to_s.present?
  end

  def chamadas
    Array(@bruto['chamadas']).each_with_index.map do |c, i|
      { 'ordem' => i + 1, 'tool' => c['tool'], 'agente' => c['agente'], 'em' => c['em'],
        'args' => c['args'], 'status' => c['status'], 'truncado' => truncado?(c),
        'resultado' => c['resultado'].to_s, 'erro' => c['erro'] }.compact
    end
  end

  # A ÚNICA coisa da fixture que não veio da produção, e por isso sai carimbada: `fabricado`,
  # com o aviso por extenso, os valores escolhidos e a lista de campos que a ficha REAL traz.
  # Essa lista é o que explica, sem depender de escolha nenhuma, por que "1 suíte" e "2 vagas"
  # não têm fonte possível: o PropertyRef nunca pede esses campos ao Vista.
  def contexto_injetado
    Array(@bruto['contexto_injetado']).map do |fonte|
      next fonte unless fonte['fonte'] == 'property_ref_ficha' && ficha.present?

      fonte.merge('fidelidade' => 'fabricado', 'aviso' => AVISO_FICHA,
                  'campos_que_a_ficha_traz' => Captain::PropertyRefContextService::FIELDS,
                  'valores' => ficha, 'nota_no_contexto' => nota_da_ficha)
    end
  end

  def ficha
    @ficha ||= (@bruto.dig('ficha_fabricada', 'valores') || {}).deep_stringify_keys
  end

  # Gerada pelo formatador REAL, não por cópia do formato. Se a produção mudar a redação da
  # ficha, a fixture muda junto na próxima gravação em vez de envelhecer em silêncio.
  def nota_da_ficha
    Captain::PropertyRefContextService.new(message: nil).send(:format_note, ficha)
  end

  # Sem o ledger integral, uma única chamada truncada já impede a fixture de se dizer fiel.
  # Medido na conta 6 em 21/09: search_knowledge trunca 84,6%, buscar_empreendimento 58,8% e
  # buscar_imovel 22,5% — tudo o mais, zero. A truncagem não é ruído de fundo: é concentrada
  # exatamente nas tools que devolvem texto longo.
  def fidelidade
    fontes = { 'chamadas' => Array(@bruto['chamadas']).any? { |c| truncado?(c) } ? 'reconstructed' : 'faithful',
               'mensagens' => 'faithful' }
    contexto_injetado.each { |c| fontes[c['fonte']] = c['fidelidade'] }
    fontes
  end

  # O que cada fala do agente AFIRMOU, que evidência existia naquele instante, e o veredito de
  # CADA afirmação — não o da mensagem. Na 41803 a mesma fala afirma preço, quartos, suíte e
  # vagas: com a ficha no contexto, uma delas é permitida e três não, por três motivos
  # diferentes. Um veredito só por mensagem apagaria essa diferença.
  def asseveracoes
    Array(@bruto['mensagens']).each_with_index.filter_map do |m, i|
      next unless fala_do_agente?(m)

      afirmacoes = julgar(Spx::Harness::Afirmacoes.extrair(m['texto']), m['em'])
      next if afirmacoes.empty?

      evidencia = Spx::Harness::Afirmacoes.evidencia_antes(@bruto['chamadas'], m['em'])
      { 'mensagem' => i, 'agente' => m['agente'], 'em' => m['em'],
        'evidencia_no_atendimento' => evidencia.presence || 'nenhuma',
        'esperado' => afirmacoes.any? { |a| a['esperado'] == 'bloquear' } ? 'bloquear' : 'permitir',
        'afirmacoes' => afirmacoes }
    end
  end

  def julgar(afirmacoes, instante)
    afirmacoes.map do |afirmacao|
      esperado, motivo = Spx::Harness::Afirmacoes.esperado(afirmacao, @bruto['chamadas'], instante, ficha: ficha)
      afirmacao.merge('esperado' => esperado, 'motivo' => motivo)
    end
  end

  # Ação sobre imóvel executada ANTES de qualquer busca desta conversa ter devolvido código.
  # Só este caso entra: é o único em que dá para afirmar, pelo trace e nada mais, que a trava
  # não chegou a ser avaliada. Envio de código ausente das buscas DEPOIS de haver busca fica de
  # fora — o código pode ser o ImoCodigo do mesmo imóvel, que a trava conhece pelo mapa de urls
  # e que o `result_preview` não mostra (conv 19863, código 9746). Acusar esse caso seria
  # inventar defeito a partir de evidência que a fixture não tem.
  def envios_sem_busca
    havia_busca = false
    Array(@bruto['chamadas']).each_with_index.filter_map do |chamada, i|
      havia_busca ||= busca_com_codigo?(chamada)
      next if havia_busca || FERRAMENTAS_DE_ENVIO.exclude?(chamada['tool'].to_s)

      envio_sem_trava(chamada, i + 1)
    end
  end

  def envio_sem_trava(chamada, ordem)
    codigo = chamada['args'].is_a?(Hash) ? chamada['args']['codigo'].to_s : ''
    aconteceu = envio_confirmado?(chamada)
    { 'ordem' => ordem, 'tool' => chamada['tool'], 'codigo' => codigo, 'em' => chamada['em'],
      'codigo_veio_de' => origem_do_codigo(codigo, chamada['em']),
      'esperado' => 'bloquear', 'observado' => aconteceu ? 'enviado' : 'nao_enviado',
      'estado' => aconteceu ? 'vermelho' : 'verde',
      'porque' => tem_trava?(chamada['tool']) ? PORQUE_FAIL_OPEN : PORQUE_SEM_TRAVA }
  end

  # Perguntado à própria classe, não a uma lista escrita aqui: lista envelhece calada quando
  # alguém arma uma ferramenta de ação nova.
  def tem_trava?(tool)
    classe = "Captain::Tools::#{tool.to_s.camelize}Tool".safe_constantize
    classe.present? && classe.include?(Captain::Tools::ImoveisConhecidos)
  end

  def busca_com_codigo?(chamada)
    Spx::Harness::Afirmacoes::FONTES_DE_EVIDENCIA.include?(chamada['tool'].to_s) &&
      chamada['resultado'].to_s.match?(CODIGO_EM_RESULTADO)
  end

  # Mesmo critério do Afirmacoes: `status: ok` não prova envio, só o texto do retorno prova.
  def envio_confirmado?(chamada)
    texto = chamada['resultado'].to_s
    chamada['status'].to_s == 'ok' && texto.match?(/\benvi\w+\b/i) &&
      !texto.match?(/N[ÃA]O envie|n[ãa]o apareceu/i)
  end

  # De onde o modelo tirou o código, já que busca nenhuma o devolveu. É a parte que interessa:
  # nas duas conversas em que isso aconteceu, veio de texto que o agente não escreveu — o link
  # que o cliente colou e o template da campanha, que entra como fala do próprio agente.
  def origem_do_codigo(codigo, instante)
    return 'desconhecida' if codigo.blank?

    # A PRIMEIRA menção, não a última: o que interessa é de onde o código entrou na conversa.
    # Pela última, o pin do 9412 sairia como vindo do rótulo do carrossel que o próprio sistema
    # escreveu um segundo antes — verdade inútil que esconde a origem, que é o link colado.
    anteriores = Array(@bruto['mensagens']).select { |m| m['em'].to_s < instante.to_s }
    fonte = anteriores.find { |m| m['texto'].to_s.include?(codigo) }
    return 'nenhuma fala anterior cita este código' if fonte.nil?
    return 'template_de_campanha' if fonte['marcador'].to_s == 'meta_lead_ads_initial'

    fonte['direcao'].to_s == 'incoming' ? 'mensagem_do_cliente' : 'fala_anterior_do_agente'
  end

  def truncado?(chamada)
    chamada['resultado'].to_s.length >= LIMITE_PREVIEW
  end
end
