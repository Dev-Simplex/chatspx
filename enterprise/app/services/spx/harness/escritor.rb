# O cano único por onde TODA fixture passa: pseudonimiza → confere a trava → só então escreve.
#
# Existe separado do gravador porque a fonte do dado varia e a garantia não pode variar junto.
# Hoje há duas fontes:
#
#   - ao vivo, de um `Conversation` no banco (Spx::Harness::GravadorDeFixtures);
#   - exportada, de um JSON lido da produção por consulta somente-leitura.
#
# A segunda existe por uma restrição real: o gravador é código de branch e o dado está na VM do
# cliente. Rodar o gravador lá seria deploy — proibido. Então a produção é só LIDA (SELECT), o
# bruto fica fora do repositório, e a pseudonimização acontece aqui, na minha máquina, antes de
# qualquer byte entrar no versionado.
class Spx::Harness::Escritor
  PARAFRASEAR = '<PARAFRASEAR: escreva a intenção, não a fala>'.freeze

  def initialize(id:, nomes: [])
    @id = id
    @nomes = nomes
    @pseudo = Spx::Harness::Pseudonimizador.new(semente: id)
  end

  # Devolve o hash já pseudonimizado e conferido. NÃO escreve.
  def preparar(bruto)
    seguro = @pseudo.aplicar_em(bruto.deep_stringify_keys, nomes: @nomes)
    Spx::Harness::Vazamento.conferir!(seguro.to_yaml, origem: @id)
    seguro
  end

  def gravar!(bruto, caminho, parafrasear: true)
    dados = preparar(bruto)
    dados = marcar_para_parafrase(dados) if parafrasear
    # Segunda conferida sobre o que de fato vai ao disco. O marcador não muda nada, mas gravar
    # confiando na etapa anterior seria a mesma fé cega que este harness existe para tirar.
    conteudo = Spx::Harness::Vazamento.conferir!(dados.to_yaml, origem: "#{@id} (#{caminho})")
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, conteudo)
    dados
  end

  private

  def marcar_para_parafrase(dados)
    copia = dados.deep_dup
    Array(copia['mensagens']).each do |m|
      m['texto_sha'] = digesto(m['texto'])
      m['texto'] = PARAFRASEAR
    end
    copia
  end

  # Grupos de 4 separados por `_`, e não o hex corrido. Não é estética: um SHA hexadecimal pode
  # sair com 10 dígitos seguidos, e aí ele casa como TELEFONE e a trava derruba a gravação — foi
  # o que aconteceu na primeira gravação real da 41803. `_` fica FORA da classe de separadores
  # que o padrão de telefone aceita (`[\s.-]`), então a maior sequência de dígitos possível aqui
  # é 4: abaixo do piso de todo padrão da trava. Estrutural, não lista de exceção.
  def digesto(texto)
    hex = Digest::SHA1.hexdigest(texto.to_s)[0, 12]
    hex.scan(/.{4}/).join('_')
  end
end
