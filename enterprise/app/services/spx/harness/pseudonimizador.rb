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

  # `marca` é o nome do negócio dono da conta. Serve de EXCLUSÃO: os pedaços dele não são
  # identidade de pessoa neste texto, ainda que um sócio se chame assim. Sem isso, trocar o
  # sobrenome do dono apagaria "Tozi Imóveis" de toda fala da conversa.
  def initialize(semente:, marca: nil)
    @semente = semente.to_s
    @marca = marca.to_s
    @nomes = {}
  end

  # `nomes` são os nomes próprios conhecidos da conversa (contato, atendentes). Vêm de fora
  # porque o serviço não adivinha nome: sem a lista, "Bruna" no meio do texto é indistinguível
  # de uma palavra qualquer, e trocar por heurística estragaria o corpus.
  def aplicar(texto, nomes: [])
    return texto if texto.blank?

    t = texto.to_s.dup
    t = trocar_nomes(t, nomes)
    t = t.gsub(URL) { |u| url_neutra(u) }
    t = trocar_documentos(t)
    t = t.gsub(EMAIL) { |v| "#{apelido('email', v)}@exemplo.invalido" }
    t = t.gsub(LOGRADOURO) { |v| "Rua Fictícia, #{numero(v)}" }
    t = t.gsub(TELEFONE) { |v| telefone_falso(v) }
    t.gsub(CREDENCIAL) { "#{Regexp.last_match(1)}REDIGIDO" }
  end

  # Percorre a estrutura inteira (hash/array/string) — a fixture é um hash aninhado, e um
  # telefone escondido num argumento de tool vazaria igual.
  def aplicar_em(valor, nomes: [])
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
        v.include?('.') ? '000.000.000-00' : '00000000000'
      else
        v
      end
    end
    t = t.gsub(Spx::Harness::Documento::CNPJ_BRUTO) do |v|
      if Spx::Harness::Documento.cnpj?(v)
        v.include?('.') ? '00.000.000/0000-00' : '00000000000000'
      else
        v
      end
    end
    t = t.gsub(Spx::Harness::Documento::RG_FORMATADO, '00.000.000-0')
    t.gsub(Spx::Harness::Documento::RG_ROTULADO, 'RG 00.000.000-0')
  end

  # Ordem decrescente de tamanho: sem isso, trocar "Ana" antes de "Ana Paula" deixaria "Paula".
  def trocar_nomes(texto, nomes)
    variantes(nomes).reduce(texto) do |t, (alvo, pessoa, isolado)|
      t.gsub(padrao_de_nome(alvo, isolado)) { apelido('nome', pessoa) }
    end
  end

  # Cada pessoa entra várias vezes: o nome inteiro e cada pedaço dele. O nome inteiro quase
  # nunca aparece na conversa — quem se apresenta escreve o primeiro nome ("Me chamo Evellyn"),
  # e foi assim que o nome de uma funcionária real sobreviveu à primeira gravação da conv 41803,
  # com a lista dos 34 usuários da conta carregada e tudo.
  #
  # Pedaço que também é pedaço da MARCA fica de fora: é nome do negócio, não da pessoa.
  def variantes(nomes)
    pares = nomes.compact.map(&:to_s).reject { |n| n.strip.length < 3 }
                 .flat_map { |nome| variantes_de(nome) }
    pares.uniq { |alvo, _, _| alvo.downcase }.sort_by { |alvo, _, _| -alvo.length }
  end

  def variantes_de(nome)
    soltos = pedacos(nome).reject { |p| pedacos_da_marca.include?(p.downcase) }
    [[nome, nome, false]] + soltos.map { |p| [p, nome, true] }
  end

  def pedacos_da_marca
    @pedacos_da_marca ||= pedacos(@marca).to_set(&:downcase)
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

  def apelido(tipo, valor)
    @nomes[[tipo, valor.downcase]] ||=
      case tipo
      when 'nome' then "CONTATO-#{indice(valor)}"
      else "contato-#{indice(valor)}"
      end
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
