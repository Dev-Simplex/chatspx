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
  # Palavra que começa com maiúscula dentro do resultado de uma busca. Não monta o nome
  # completo do bairro porque não precisa: a proteção do Pseudonimizador é por PEDAÇO, então
  # "Parque" e "Amazonas" separados protegem "Parque Amazonas" igual.
  PALAVRA_PROPRIA = /(?<![[:alpha:]])[[:upper:]][[:alpha:]]{2,}/
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

  # De onde um código PODE vir sem ser invenção. A regra não é "só busca": o cliente que cola
  # o link escolheu aquele imóvel, e o anúncio que ele clicou identifica qual imóvel interessa.
  # Mandar foto nos dois casos é correto — o que falta é a ferramenta RECONHECER a fonte em vez
  # de agir sem olhar.
  #
  # Limite do template de campanha: ele identifica QUAL imóvel, nunca prova preço nem condição
  # comercial. "Entrada facilitada" escrita no anúncio não vira fato confirmado (ver §15 da
  # auditoria e a regra do FactGuard).
  FONTES_ACEITAVEIS = %w[busca mensagem_do_cliente template_de_campanha].freeze

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
      'acoes_sem_trava' => acoes_sem_trava
    }
  end

  def gravar!(caminho, parafrasear: true)
    escritor.gravar!(montar, caminho, parafrasear: parafrasear)
  end

  private

  # O original vai junto para a checagem de preservação: é contra ele que se confere se algum
  # código ou valor se perdeu na pseudonimização.
  def escritor
    @escritor ||= Spx::Harness::Escritor.new(id: @id, nomes: @bruto['nomes'] || {},
                                             marca: @bruto['marca'],
                                             protegidos: termos_de_negocio,
                                             original: original_para_conferir)
  end

  # Vocabulário que NUNCA pode ser trocado nem perdido. Três fontes, todas derivadas do que já
  # está no cenário — nenhuma lista escrita à mão, que envelheceria calada:
  #
  #   1. os nomes das agentes de IA da conta (a conta 6 tem nove, entre elas Bruna, Clara e
  #      Júlia — nomes que uma atendente pode ter também);
  #   2. os nomes próprios que aparecem no RESULTADO das ferramentas de evidência: é dado do
  #      Vista, e é lá que moram bairro, condomínio e empreendimento;
  #   3. bairro e cidade da ficha injetada.
  #
  # O limite: um bairro que não aparece em nenhum resultado desta conversa não é protegido —
  # mas também não está na fixture, então não há o que estragar.
  def termos_de_negocio
    @termos_de_negocio ||= begin
      evidencias = Array(@bruto['chamadas']).filter_map do |c|
        c['resultado'] if Spx::Harness::Afirmacoes::FONTES_DE_EVIDENCIA.include?(c['tool'].to_s)
      end
      dos_resultados = evidencias.flat_map { |texto| texto.scan(PALAVRA_PROPRIA) }
      (Array(@bruto['agentes_da_conta']) + dos_resultados + ficha.values_at('Bairro', 'Cidade')).compact.uniq
    end
  end

  # Só o que o cenário assevera: fala e retorno de ferramenta. Nome e telefone do original não
  # entram nem aqui — a checagem compara código e valor, não texto.
  def original_para_conferir
    (Array(@bruto['mensagens']).pluck('texto') +
      Array(@bruto['chamadas']).map { |c| [c['args'].to_json, c['resultado']] }).flatten.join("\n")
  end

  def mensagens
    Array(@bruto['mensagens']).map do |m|
      ao_modelo = Spx::Harness::Apresentacao.texto(m)
      { 'de' => m['de'], 'em' => m['em'], 'agente' => m['agente'],
        'agente_nome' => m['agente_nome'], 'midia' => m['midia'],
        'marcador' => m['marcador'],
        'apresentado_ao_modelo' => Spx::Harness::Apresentacao.papel(m),
        # Só quando DIFERE do texto guardado. Igual, seria ruído em toda linha.
        'texto_ao_modelo' => (ao_modelo if ao_modelo != m['texto'].to_s),
        'fala_do_agente' => Spx::Harness::Apresentacao.fala_do_agente?(m),
        'texto' => m['texto'] }.compact
    end
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
      next unless Spx::Harness::Apresentacao.fala_do_agente?(m)

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

  # Ação sobre imóvel executada ANTES de qualquer busca desta conversa ter devolvido código —
  # ou seja, com a trava PROVADAMENTE não avaliada.
  #
  # O defeito NÃO é a foto ter saído. Mandar foto do imóvel que o cliente pediu, ou do imóvel
  # que ele clicou no anúncio, é o comportamento certo. O defeito é a ferramenta não ter
  # AVALIADO de onde veio o código: hoje ela acerta por acidente, e acertaria igual se o
  # código tivesse sido inventado pelo modelo.
  #
  # Só este caso entra: é o único em que dá para afirmar, pelo trace e nada mais, que a trava
  # não chegou a rodar. Envio de código ausente das buscas DEPOIS de haver busca fica de fora —
  # o código pode ser o ImoCodigo do mesmo imóvel, que a trava conhece pelo mapa de urls e que
  # o `result_preview` não mostra (conv 19863, código 9746). Acusar esse caso seria inventar
  # defeito a partir de evidência que a fixture não tem.
  def acoes_sem_trava
    havia_busca = false
    Array(@bruto['chamadas']).each_with_index.filter_map do |chamada, i|
      havia_busca ||= busca_com_codigo?(chamada)
      next if havia_busca || FERRAMENTAS_DE_ENVIO.exclude?(chamada['tool'].to_s)

      acao_sem_trava(chamada, i + 1)
    end
  end

  def acao_sem_trava(chamada, ordem)
    codigo = chamada['args'].is_a?(Hash) ? chamada['args']['codigo'].to_s : ''
    fonte = origem_do_codigo(codigo, chamada['em'])
    aceitavel = FONTES_ACEITAVEIS.include?(fonte)
    { 'ordem' => ordem, 'tool' => chamada['tool'], 'codigo' => codigo, 'em' => chamada['em'],
      'fonte_do_codigo' => fonte, 'fonte_aceitavel' => aceitavel,
      'trava_avaliada' => false,
      'esperado' => aceitavel ? 'reconhecer_fonte' : 'bloquear',
      'observado' => envio_confirmado?(chamada) ? 'agiu_sem_avaliar' : 'nao_agiu',
      'estado' => 'vermelho',
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
    return 'nenhuma' if fonte.nil?
    return 'template_de_campanha' if fonte['marcador'].to_s == 'meta_lead_ads_initial'

    fonte['direcao'].to_s == 'incoming' ? 'mensagem_do_cliente' : 'fala_anterior_do_agente'
  end

  def truncado?(chamada)
    chamada['resultado'].to_s.length >= LIMITE_PREVIEW
  end
end
