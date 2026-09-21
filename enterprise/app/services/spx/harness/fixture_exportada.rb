# Monta a fixture a partir de um JSON exportado da produção por consulta somente-leitura.
#
# Por que existe: o gravador é código de branch e o dado está na VM do cliente. Rodar o
# gravador lá seria deploy — proibido nesta tarefa. Então a produção só é LIDA, o bruto fica
# FORA do repositório (scratchpad da sessão), e a pseudonimização acontece na minha máquina,
# antes de qualquer byte entrar no versionado. A garantia é a mesma: o Escritor.
#
# O JSON de entrada é o que o exportador emite — mensagens, chamadas, flags e digests. Nenhum
# campo é inventado aqui: o que não veio da produção não aparece na fixture.
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
      'relogio' => @bruto['relogio'],
      'conta' => { 'flags' => @bruto['flags'] || {} },
      'assistente' => @bruto['assistente'] || {},
      'cache' => { 'estado' => 'vazio' },
      'mensagens' => Array(@bruto['mensagens']),
      'chamadas' => chamadas
    }
  end

  def gravar!(caminho, parafrasear: true)
    escritor.gravar!(montar, caminho, parafrasear: parafrasear)
  end

  private

  def escritor
    @escritor ||= Spx::Harness::Escritor.new(id: @id, nomes: Array(@bruto['nomes']))
  end

  def chamadas
    Array(@bruto['chamadas']).each_with_index.map do |c, i|
      { 'ordem' => i + 1, 'tool' => c['tool'], 'args' => c['args'], 'status' => c['status'],
        'truncado' => truncado?(c), 'resultado' => c['resultado'].to_s, 'erro' => c['erro'] }.compact
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
