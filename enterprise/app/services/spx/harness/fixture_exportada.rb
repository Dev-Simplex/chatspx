# Monta a fixture a partir de um JSON exportado da produção por consulta somente-leitura.
#
# Por que existe: o gravador é código de branch e o dado está na VM do cliente. Rodar o
# gravador lá seria deploy — proibido nesta tarefa. Então a produção só é LIDA, o bruto fica
# FORA do repositório, e a pseudonimização acontece na minha máquina antes de qualquer byte
# entrar no versionado. A garantia é a mesma: o Escritor.
#
# Nenhum campo é inventado aqui. O que não veio da produção não aparece na fixture.
class Spx::Harness::FixtureExportada
  LIMITE_PREVIEW = 1500

  def initialize(bruto, id:)
    @bruto = bruto.deep_stringify_keys
    @id = id
  end

  def montar
    {
      'id' => @id,
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
      'mensagens' => mensagens,
      'chamadas' => chamadas
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
      { 'de' => m['de'], 'em' => m['em'], 'agente' => m['agente'],
        'agente_nome' => m['agente_nome'], 'midia' => m['midia'], 'texto' => m['texto'] }.compact
    end
  end

  def chamadas
    Array(@bruto['chamadas']).each_with_index.map do |c, i|
      { 'ordem' => i + 1, 'tool' => c['tool'], 'agente' => c['agente'], 'em' => c['em'],
        'args' => c['args'], 'status' => c['status'], 'truncado' => truncado?(c),
        'resultado' => c['resultado'].to_s, 'erro' => c['erro'] }.compact
    end
  end

  # Sem o ledger integral, uma única chamada truncada já impede a fixture de se dizer fiel.
  # Medido na conta 6 em 21/09: search_knowledge trunca 84,6%, buscar_empreendimento 58,8% e
  # buscar_imovel 22,5% — tudo o mais, zero. A truncagem não é ruído de fundo: é concentrada
  # exatamente nas tools que devolvem texto longo.
  def fidelidade
    Array(@bruto['chamadas']).any? { |c| truncado?(c) } ? 'reconstructed' : 'faithful'
  end

  def truncado?(chamada)
    chamada['resultado'].to_s.length >= LIMITE_PREVIEW
  end
end
