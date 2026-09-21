# O cano único por onde TODA fixture passa: pseudonimiza → confere a trava → confere a
# preservação → só então escreve.
#
# Existe separado do gravador porque a fonte do dado varia e a garantia não pode variar junto.
# Hoje há duas fontes: ao vivo, de um `Conversation` no banco; e exportada, de um JSON lido da
# produção por consulta somente-leitura — porque o gravador é código de branch e o dado está na
# VM do cliente, e rodar o gravador lá seria deploy.
#
# SÓ A FALA DO CLIENTE vira paráfrase. A fala da IA é o OBJETO DO TESTE: é nela que mora o
# preço afirmado sem busca, a promessa que não foi cumprida, a ausência declarada que era
# falha. Parafrasear a IA apagava justamente o que a fixture precisa provar — foi o defeito da
# primeira gravação da conv 41803, onde o R$ 2.400 inventado pelo agente sumiu do arquivo.
class Spx::Harness::Escritor
  PARAFRASEAR = '<PARAFRASEAR: escreva a intenção, não a fala>'.freeze
  # SHA1 de string vazia. Mensagem com este digesto não é fala: é mídia (carrossel, pin, áudio)
  # cujo conteúdo textual é vazio. Marcá-la para paráfrase pedia que se reescrevesse o nada.
  SHA_VAZIO = 'da39a3ee5e6b'.freeze

  # `nomes` vem POR PAPEL (`{ 'atendente' => [...], 'contato' => [...] }`) e `protegidos` é o
  # vocabulário de negócio que não pode ser trocado nem perdido — nomes das agentes de IA,
  # bairro, condomínio, empreendimento. A mesma lista serve às duas checagens opostas: o
  # Pseudonimizador não troca, a Preservacao exige que tenha sobrevivido.
  def initialize(id:, nomes: {}, original: nil, marca: nil, protegidos: [])
    @id = id
    @nomes = nomes
    @original = original
    @protegidos = Array(protegidos)
    @pseudo = Spx::Harness::Pseudonimizador.new(semente: id, marca: marca, protegidos: @protegidos)
  end

  def preparar(bruto)
    seguro = @pseudo.aplicar_em(bruto.deep_stringify_keys, nomes: @nomes)
    Spx::Harness::Vazamento.conferir!(seguro.to_yaml, origem: @id)
    seguro
  end

  def gravar!(bruto, caminho, parafrasear: true)
    dados = preparar(bruto)
    dados = marcar_para_parafrase(dados) if parafrasear
    # Depois de tudo trocado: quem revisa a fixture precisa ver O QUE foi substituído. Só tipo
    # e pseudônimo — guardar o par original→pseudônimo seria a tabela de desanonimização.
    dados = dados.merge('pseudonimos' => @pseudo.substituicoes)
    conteudo = Spx::Harness::Vazamento.conferir!(dados.to_yaml, origem: "#{@id} (#{caminho})")
    # A trava garante que nada VAZOU; esta garante que nada se PERDEU. São perguntas opostas, e
    # a primeira gravação da 41803 passou na primeira e falharia na segunda.
    conferir_preservacao(dados)
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, conteudo)
    dados
  end

  private

  # Confere sobre o TEXTO das folhas, não sobre o YAML. No YAML uma quebra de linha dentro de
  # string vira os dois caracteres `\` e `n`, e aí a palavra seguinte fica colada num `n`:
  # `\nLavanderia`. A fronteira de palavra da Preservacao não casava, e a checagem acusava
  # perda de cinco termos que estavam lá — na conv 21743, na descrição do anúncio.
  def conferir_preservacao(dados)
    return if @original.blank?

    Spx::Harness::Preservacao.conferir!(folhas(dados), original: @original, origem: @id,
                                                       termos: @protegidos)
  end

  # Todo texto que vai para o arquivo, com as quebras de linha reais. É o que a fixture DIZ,
  # sem a escapagem do serializador no meio.
  def folhas(valor)
    case valor
    when String then valor
    when Array then valor.map { |v| folhas(v) }.join("\n")
    when Hash then valor.values.map { |v| folhas(v) }.join("\n")
    else valor.to_s
    end
  end

  def marcar_para_parafrase(dados)
    copia = dados.deep_dup
    Array(copia['mensagens']).each { |m| tratar_mensagem(m) }
    copia
  end

  def tratar_mensagem(mensagem)
    digesto = digesto(mensagem['texto'])
    mensagem['texto_sha'] = digesto
    return marcar_midia(mensagem) if digesto == formatar(SHA_VAZIO)
    # A fala da IA fica, pseudonimizada. É o objeto do teste.
    return unless mensagem['de'].to_s == 'cliente'

    mensagem['texto'] = PARAFRASEAR
  end

  def marcar_midia(mensagem)
    mensagem['texto'] = nil
    mensagem['midia'] ||= 'desconhecida'
    mensagem.delete('texto_sha')
  end

  # Grupos de 4 separados por `_`, e não o hex corrido. Não é estética: um SHA hexadecimal pode
  # sair com 10 dígitos seguidos, e aí ele casa como TELEFONE e a trava derruba a gravação — foi
  # o que aconteceu na primeira gravação real da 41803. `_` fica FORA da classe de separadores
  # que o padrão de telefone aceita (`[\s.-]`), então a maior sequência de dígitos possível aqui
  # é 4: abaixo do piso de todo padrão da trava. Estrutural, não lista de exceção.
  def digesto(texto)
    formatar(Digest::SHA1.hexdigest(texto.to_s)[0, 12])
  end

  def formatar(hex)
    hex.scan(/.{4}/).join('_')
  end
end
