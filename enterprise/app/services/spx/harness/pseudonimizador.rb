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

  def initialize(semente:)
    @semente = semente.to_s
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
    host = url[%r{https?://[^\s/]+}]
    codigo = url[CODIGO_NA_URL, 1]
    codigo ? "#{host}/imovel/imovel-ficticio-#{codigo}" : "#{host}/pagina-ficticia"
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
    nomes.compact.map(&:to_s).reject { |n| n.strip.length < 3 }.sort_by { |n| -n.length }
         .reduce(texto) { |t, nome| t.gsub(/#{Regexp.escape(nome)}/i, apelido('nome', nome)) }
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
