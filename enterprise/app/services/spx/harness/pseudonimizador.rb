# Troca dado identificável por substituto estável, ANTES de a fixture tocar o disco.
#
# Estável e não aleatório de propósito: o mesmo telefone vira sempre o mesmo pseudônimo dentro
# da mesma fixture, então a conversa continua fazendo sentido ("o número que você mandou" segue
# sendo o mesmo número) sem que o real apareça. A semente é o id da fixture — duas fixturas
# diferentes não compartilham pseudônimo, e o mapa não precisa ser guardado em lugar nenhum.
#
# O que sai: telefone, e-mail, nome de contato, logradouro com número e credencial.
# Endereço entra na lista porque endereço exato de imóvel de terceiro é informação comercial
# sensível, não só dado de contato.
#
# Isto NÃO é a garantia — é a primeira rede. A garantia é o Spx::Harness::Vazamento, que roda
# depois e levanta se algum padrão sobreviveu.
class Spx::Harness::Pseudonimizador
  TELEFONE = /(?:\+?55[\s.-]?)?(?:\(?\d{2}\)?[\s.-]?)?9?\d{4}[\s.-]?\d{4}\b/
  EMAIL = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
  LOGRADOURO = /\b(?:rua|av\.?|avenida|travessa|alameda|rodovia|estrada|pra[çc]a)\b[^,;\n]{2,60},?\s*
                (?:n[º°o]?\.?\s*)?\d{1,6}\b/ix
  CREDENCIAL = /(\b(?:senha|password|passwd|pwd|api[_-]?key|token|secret|client[_-]secret)\b\s*[:=]\s*)\S+/i
  # O slug da página do imóvel pode carregar rua e número SEM a palavra "Rua"
  # (`casa-tarumas-1007-sinop-9412`), e aí a trava de logradouro não pega. Em vez de tentar
  # reconhecer nome de rua dentro do slug, o caminho inteiro é normalizado: sobra o host (que o
  # fix_property_links precisa casar) e o código no fim (que é o dado de negócio do cenário).
  URL = %r{https?://[^\s<>"']+}i
  # Código do imóvel no fim do caminho — é o único pedaço do slug que o cenário precisa.
  CODIGO_NA_URL = %r{(\d{3,6})(?=[/?#]|\z)}

  # `marca` é o nome do negócio dono da conta e `protegidos` é o vocabulário de NEGÓCIO —
  # nomes das agentes de IA, bairro, condomínio, empreendimento. Os dois servem de EXCLUSÃO
  # para os PEDAÇOS de nome, e a razão é concreta: sobrenome brasileiro costuma ser nome de
  # bairro (Oliveira, Campos, Rocha, Lima), e a conta 6 tem nove agentes chamadas Letícia,
  # Bruna, Marina, Helena, Clara, Júlia, Feirão, Sofia e Rafa. Sem a exclusão, uma atendente
  # chamada Clara faria a agente Clara virar pseudônimo e a transferência perderia o sentido.
  #
  # A exclusão vale só para o PEDAÇO solto. O nome cadastrado inteiro continua sendo trocado:
  # "Clara Fernandes" vira ATENDENTE-n, e só um "Clara" sozinho sobrevive — que numa conversa
  # da Tozi é, quase sempre, a agente.
  def initialize(semente:, marca: nil, protegidos: [])
    @semente = semente.to_s
    @marca = marca.to_s
    @protegidos = Array(protegidos).compact.map(&:to_s)
    @nomes = {}
    @contagem = Hash.new(0)
  end

  # O que foi trocado, para quem revisa a fixture. Só TIPO e PSEUDÔNIMO — o original fica de
  # fora de propósito: um registro que guardasse os dois seria a tabela de desanonimização.
  def substituicoes
    @contagem.map { |(tipo, pseudonimo), n| { 'tipo' => tipo, 'pseudonimo' => pseudonimo, 'ocorrencias' => n } }
             .sort_by { |s| [s['tipo'], s['pseudonimo']] }
  end

  # `nomes` são os nomes próprios conhecidos da conversa, POR PAPEL:
  # `{ 'atendente' => [...], 'contato' => [...] }`. O papel entra no pseudônimo porque a
  # conversa perde a leitura sem ele — quem transferiu para quem, quem é o lead. Array simples
  # continua aceito e é tratado como contato.
  #
  # Vêm de fora porque o serviço não adivinha nome: sem a lista, "Bruna" no meio do texto é
  # indistinguível de uma palavra qualquer, e trocar por heurística estragaria o corpus.
  def aplicar(texto, nomes: {})
    return texto if texto.blank?

    t = texto.to_s.dup
    t = trocar_nomes(t, nomes)
    t = t.gsub(URL) { |u| registrar('url', url_neutra(u)) }
    t = trocar_documentos(t)
    t = t.gsub(EMAIL) { |v| registrar('email', "#{apelido('email', v)}@exemplo.invalido") }
    t = t.gsub(LOGRADOURO) { |v| registrar('endereco', "Rua Fictícia, #{numero(v)}") }
    t = t.gsub(TELEFONE) { |v| registrar('telefone', telefone_falso(v)) }
    t.gsub(CREDENCIAL) { registrar('credencial', "#{Regexp.last_match(1)}REDIGIDO") }
  end

  # Percorre a estrutura inteira (hash/array/string) — a fixture é um hash aninhado, e um
  # telefone escondido num argumento de tool vazaria igual.
  def aplicar_em(valor, nomes: {})
    case valor
    when String then aplicar(valor, nomes: nomes)
    when Array then valor.map { |v| aplicar_em(v, nomes: nomes) }
    when Hash then valor.transform_values { |v| aplicar_em(v, nomes: nomes) }
    else valor
    end
  end

  private

  # UMA passada só. Antes eram duas — a segunda regra reescrevia a saída da primeira e o código
  # do imóvel, que é o dado de negócio do cenário, sumia junto com o slug. Descoberto conferindo
  # a primeira gravação real (conv 41803): o link virou `/pagina-ficticia` e levou o 9412 embora.
  def url_neutra(url)
    # Pontuação colada no fim não é parte da URL. Sem tirá-la, `...-9412)` não casa o código e
    # o link perde o 9412 — foi o que aconteceu no argumento do atualizar_resumo da conv 41803.
    limpa = url.sub(/[),.;:\]}>]+\z/, '')
    sufixo = url[limpa.length..].to_s
    host = limpa[%r{https?://[^\s/]+}]
    "#{host}#{caminho_neutro(limpa)}#{sufixo}"
  end

  # O código do imóvel é o ÚLTIMO grupo de 3 a 6 dígitos do CAMINHO (não da query: `?utm=2026`
  # roubaria o lugar dele). É o único pedaço do slug que o cenário precisa.
  def caminho_neutro(url)
    caminho = url.sub(%r{\Ahttps?://[^\s/]+}, '').split('?').first.to_s
    codigo = caminho.scan(/\d{3,6}/).last
    codigo ? "/imovel/imovel-ficticio-#{codigo}" : '/pagina-ficticia'
  end

  # Substituto com dígito verificador INVÁLIDO de propósito (sequência repetida), para a trava
  # não acusar a própria saída. Preserva a forma — pontuada continua pontuada.
  def trocar_documentos(texto)
    t = texto.gsub(Spx::Harness::Documento::CPF_BRUTO) do |v|
      if Spx::Harness::Documento.cpf?(v)
        registrar('cpf', v.include?('.') ? '000.000.000-00' : '00000000000')
      else
        v
      end
    end
    t = t.gsub(Spx::Harness::Documento::CNPJ_BRUTO) do |v|
      if Spx::Harness::Documento.cnpj?(v)
        registrar('cnpj', v.include?('.') ? '00.000.000/0000-00' : '00000000000000')
      else
        v
      end
    end
    t = t.gsub(Spx::Harness::Documento::RG_FORMATADO) { registrar('rg', '00.000.000-0') }
    t.gsub(Spx::Harness::Documento::RG_ROTULADO) { registrar('rg', 'RG 00.000.000-0') }
  end

  # Ordem decrescente de tamanho: sem isso, trocar "Ana" antes de "Ana Paula" deixaria "Paula".
  def trocar_nomes(texto, nomes)
    variantes(nomes).reduce(texto) do |t, v|
      t.gsub(padrao_de_nome(v[:alvo], v[:isolado])) { registrar(v[:papel], apelido(v[:papel], v[:pessoa])) }
    end
  end

  # Cada pessoa entra várias vezes: o nome inteiro e cada pedaço dele. O nome inteiro quase
  # nunca aparece na conversa — quem se apresenta escreve o primeiro nome ("Me chamo Evellyn"),
  # e foi assim que o nome de uma funcionária real sobreviveu à primeira gravação da conv 41803,
  # com a lista dos 34 usuários da conta carregada e tudo.
  #
  # Pedaço que também é pedaço da MARCA fica de fora: é nome do negócio, não da pessoa.
  def variantes(nomes)
    pares = por_papel(nomes).flat_map do |papel, lista|
      Array(lista).compact.map(&:to_s).reject { |n| n.strip.length < 3 }
                  .flat_map { |nome| variantes_de(nome, papel) }
    end
    pares.uniq { |v| v[:alvo].downcase }.sort_by { |v| -v[:alvo].length }
  end

  def por_papel(nomes)
    return { 'contato' => Array(nomes) } unless nomes.is_a?(Hash)

    nomes.transform_keys(&:to_s)
  end

  def variantes_de(nome, papel)
    todos = pedacos(nome)
    soltos = todos.reject { |p| pedacos_protegidos.include?(p.downcase) }
    # Nome cadastrado de UM pedaço só, e esse pedaço é vocabulário de negócio: trocá-lo apaga o
    # bairro. Aconteceu de verdade na conv 36940 — a conta tem um usuário cadastrado só com o
    # primeiro nome, e o mesmo nome é bairro ("Jardim São Paulo"). Aqui a proteção vence, e o
    # preço é conhecido: esse nome NÃO é pseudonimizado.
    return [] if todos.size == 1 && soltos.empty?

    [{ alvo: nome, pessoa: nome, papel: papel, isolado: false }] +
      soltos.map { |p| { alvo: p, pessoa: nome, papel: papel, isolado: true } }
  end

  # Marca + vocabulário de negócio, em pedaços. Só barra PEDAÇO solto — o nome cadastrado
  # inteiro é trocado de qualquer forma.
  def pedacos_protegidos
    @pedacos_protegidos ||= (pedacos(@marca) + @protegidos.flat_map { |p| pedacos(p) }).to_set(&:downcase)
  end

  # Pedaço solto precisa de fronteira, senão "Ana" acerta "Banana". `[[:alpha:]]` é ciente de
  # acento em string UTF-8; `\b` do Ruby é ASCII e erraria em "José".
  def padrao_de_nome(alvo, isolado)
    return /#{Regexp.escape(alvo)}/i unless isolado

    /(?<![[:alpha:]])#{Regexp.escape(alvo)}(?![[:alpha:]])/i
  end

  def pedacos(texto)
    texto.to_s.split(/[^[:alpha:]]+/).select { |p| p.length >= 3 }
  end

  # O pseudônimo PRESERVA O PAPEL. Atendente que vira CONTATO-n apaga a distinção entre quem
  # atende e quem é atendido, e a conversa deixa de fazer sentido como cenário.
  PAPEIS = { 'atendente' => 'ATENDENTE', 'contato' => 'CONTATO' }.freeze

  def apelido(tipo, valor)
    @nomes[[tipo, valor.downcase]] ||=
      if PAPEIS.key?(tipo)
        "#{PAPEIS.fetch(tipo)}-#{indice(valor)}"
      else
        "contato-#{indice(valor)}"
      end
  end

  def registrar(tipo, pseudonimo)
    @contagem[[tipo, pseudonimo]] += 1
    pseudonimo
  end

  # Dois dígitos bastam: fixture com mais de 100 entidades distintas não é fixture, é dump.
  def indice(valor)
    Digest::MD5.hexdigest("#{@semente}:#{valor.downcase}")[0, 4].to_i(16) % 100
  end

  def telefone_falso(valor)
    "(66) 90000-#{format('%<n>04d', n: indice(valor) * 37 % 10_000)}"
  end

  # Preserva a ORDEM de grandeza do número original sem preservar o número: "1646" continua
  # com 4 dígitos, então a fixture não muda de forma quando o endereço sai.
  def numero(valor)
    original = valor[/\d{1,6}\b/].to_s
    format("%<n>0#{[original.length, 1].max}d", n: indice(valor) % (10**[original.length, 4].min))
  end
end
