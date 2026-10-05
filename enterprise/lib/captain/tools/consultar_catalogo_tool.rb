# Lê o catálogo da conta (`CatalogProduct`) para a IA. É fonte de FATO, por isso a busca é
# determinística: nada de embedding nem fuzzy, e a descrição do item não é pesquisada (é ela que
# gera acerto falso). Tudo o que varia por cliente vem de `assistant.config['catalogo']`:
#
# - `campos_busca`: chaves de campos personalizados pesquisados além de nome, código e categoria.
#   Valor com `;` vale como lista (apelidos).
# - `campos_ia`: allowlist dos campos personalizados que voltam para a IA. Ausente = todos os
#   campos não internos. É o único jeito de um campo interno (`hidden`) chegar à IA.
# - `mostrar_preco`: só com `true` a ferramenta lê preço e promoção.
# - `categorias`: se preenchida, a IA só enxerga itens dessas categorias.
class Captain::Tools::ConsultarCatalogoTool < Captain::Tools::BasePublicTool
  description 'Consulta o catálogo de serviços e produtos desta empresa, cadastrado na conta. Sem nenhum parâmetro, lista as ' \
              'categorias com a quantidade de itens de cada uma. Com termo, procura pelo nome, pelo código, pela categoria e ' \
              'pelos campos de busca da conta; com um resultado só, ou com código, traz o detalhe do item. O que não vier daqui ' \
              'não existe: não afirme item, característica, inclusão ou exclusão que não esteja no retorno.'

  param :termo, type: 'string',
                desc: 'As palavras com que o cliente se referiu ao serviço ou produto, do jeito que ele disse.',
                required: false
  param :categoria, type: 'string',
                    desc: 'Nome de uma categoria que apareceu num retorno desta ferramenta, para restringir a busca ou listar os itens dela.',
                    required: false
  param :codigo, type: 'string',
                 desc: 'Código de um item que apareceu num retorno desta ferramenta nesta conversa, para trazer o detalhe dele.',
                 required: false

  LIMITE_BUSCA = 5
  LIMITE_LISTA = 30
  LIMITE_RASTRO = 40
  PALAVRAS_VAZIAS = %w[a o as os e de da do das dos em na no nas nos um uma para pra pro com por].freeze
  NADA = 'Não afirme que a empresa faz nem que não faz.'.freeze

  def perform(tool_context, termo: nil, categoria: nil, codigo: nil)
    termo = termo.to_s.strip
    categoria = categoria.to_s.strip
    codigo = codigo.to_s.strip

    return por_codigo(tool_context, codigo) if codigo.present?
    return lista_categorias if termo.blank? && categoria.blank?

    busca(tool_context, termo, categoria)
  rescue StandardError => e
    Rails.logger.warn("[ConsultarCatalogo] #{e.message}")
    'Não consegui consultar o catálogo agora.'
  end

  private

  def config_catalogo
    @config_catalogo ||= begin
      valor = (@assistant.config || {})['catalogo']
      valor.is_a?(Hash) ? valor : {}
    end
  end

  def itens
    escopo = account_scoped(::CatalogProduct).visiveis.includes(:category)
    permitidas = Array(config_catalogo['categorias']).map { |nome| normalizar(nome) }.compact_blank
    return escopo.to_a if permitidas.empty?

    escopo.to_a.select { |item| item.category && permitidas.include?(normalizar(item.category.name)) }
  end

  def lista_categorias
    contagem = itens.group_by { |item| item.category&.name }.transform_values(&:size)
    return 'O catálogo desta empresa não tem nenhum item disponível.' if contagem.empty?

    linhas = contagem.sort_by { |nome, _| ordem_categoria(nome) }.map { |nome, total| linha_categoria(nome, total) }
    "Categorias do catálogo:\n#{linhas.join("\n")}"
  end

  # "Sem categoria" vai por último.
  def ordem_categoria(nome)
    nome.nil? ? [1, ''] : [0, normalizar(nome)]
  end

  def linha_categoria(nome, total)
    "- #{nome || 'Sem categoria'}: #{total} #{total == 1 ? 'item' : 'itens'}"
  end

  def por_codigo(tool_context, codigo)
    item = itens.find { |produto| produto.sku.present? && produto.sku.casecmp?(codigo) }
    return "Nenhum item do catálogo tem o código \"#{codigo}\". #{NADA}" unless item

    rastrear(tool_context, [item])
    detalhe(item)
  end

  def busca(tool_context, termo, categoria)
    candidatos = categoria.present? ? da_categoria(categoria) : itens
    return sem_categoria(categoria) if categoria.present? && candidatos.empty?
    return listar(tool_context, ordenar(candidatos), LIMITE_LISTA) if termo.blank?

    procurar(tool_context, candidatos, termo)
  end

  def sem_categoria(categoria)
    "Nenhuma categoria do catálogo corresponde a \"#{categoria}\". #{lista_categorias}"
  end

  def procurar(tool_context, candidatos, termo)
    achados = ranquear(candidatos, termo)
    return "Nada no catálogo corresponde a \"#{termo}\". #{NADA}" if achados.empty?

    exatos = achados.select { |_, nivel| nivel.zero? }.map(&:first)
    listar(tool_context, exatos.one? ? exatos : achados.map(&:first), LIMITE_BUSCA)
  end

  def da_categoria(categoria)
    itens.select { |item| item.category && confere_categoria?(item.category.name, categoria) }
  end

  # Um item só é resposta clara: vai o detalhe. Mais de um: o resumo, para a IA pedir pelo código.
  def listar(tool_context, lista, limite)
    return resumo(tool_context, lista, limite) if lista.size > 1

    rastrear(tool_context, lista)
    detalhe(lista.first)
  end

  def confere_categoria?(nome, pedido)
    palavras_nome = palavras(nome)
    alvo = palavras(pedido)
    normalizar(nome) == normalizar(pedido) || (alvo.any? && alvo.all? { |palavra| contem?(palavras_nome, palavra) })
  end

  # Nível 0: o termo é o nome, um apelido ou o código. Nível 1: todas as palavras no nome ou num
  # apelido só. Nível 2: todas as palavras espalhadas pelos campos pesquisados. Fora disso, não acha.
  def ranquear(candidatos, termo)
    alvo = normalizar(termo)
    return [] if alvo.empty?

    termos = palavras(termo)
    termos = alvo.split if termos.empty?

    ranqueados = candidatos.filter_map do |item|
      nivel = nivel(item, alvo, termos)
      [item, nivel] if nivel
    end
    ranqueados.sort_by { |item, nivel| [nivel, item.featured ? 0 : 1, normalizar(item.name), item.id] }
  end

  def nivel(item, alvo, termos)
    nomes = [item.name, *apelidos(item)].map { |texto| normalizar(texto) }
    return 0 if [*nomes, normalizar(item.sku)].include?(alvo)
    return 1 if nomes.any? { |nome| todas?(nome.split, termos) }

    2 if todas?(palavras_pesquisadas(item, nomes), termos)
  end

  def palavras_pesquisadas(item, nomes)
    [item.sku, item.category&.name, *nomes].flat_map { |texto| normalizar(texto).split }
  end

  def apelidos(item)
    Array(config_catalogo['campos_busca']).flat_map do |chave|
      item.custom_attributes.to_h[chave.to_s].to_s.split(';')
    end.compact_blank
  end

  def todas?(palavras_campo, termos)
    termos.all? { |termo| contem?(palavras_campo, termo) }
  end

  # Palavra do termo casa com o INÍCIO de uma palavra do campo: o cliente que escreve só o radical
  # acha a forma cadastrada, mas um pedaço do meio de outra palavra não casa.
  def contem?(palavras_campo, termo)
    palavras_campo.any? { |palavra| palavra.start_with?(termo) }
  end

  def palavras(texto)
    normalizar(texto).split.reject { |palavra| palavra.size < 2 || PALAVRAS_VAZIAS.include?(palavra) }
  end

  # Sem `unaccent` no banco: minúsculas, sem acento e sem pontuação, aqui em Ruby.
  def normalizar(texto)
    I18n.transliterate(texto.to_s.downcase).downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end

  def ordenar(lista)
    lista.sort_by { |item| [item.featured ? 0 : 1, normalizar(item.name), item.id] }
  end

  def resumo(tool_context, lista, limite)
    mostrados = lista.first(limite)
    rastrear(tool_context, mostrados)
    linhas = mostrados.map { |item| "- #{titulo(item)}" }
    cabecalho = "#{lista.size} itens do catálogo correspondem"
    cabecalho += " (mostrando #{mostrados.size}; refine a busca para ver os outros)" if lista.size > mostrados.size
    "#{cabecalho}. Para o detalhe de um deles, consulte pelo código:\n#{linhas.join("\n")}"
  end

  def titulo(item)
    codigo = item.sku.present? ? "código #{item.sku}" : 'sem código'
    "#{item.name} (#{codigo}, categoria: #{item.category&.name || 'sem categoria'})"
  end

  def detalhe(item)
    linhas = ["Item: #{titulo(item)}"]
    linhas << "Descrição: #{item.description.strip}" if item.description.present?
    campos.para_ia(item.custom_attributes, campos_ia).each { |campo| linhas << "#{campo['label']}: #{campo['value']}" }
    linhas << "Preço: #{preco(item)}" if config_catalogo['mostrar_preco'] == true && item.preco_atual_cents
    linhas.join("\n")
  end

  def campos
    @campos ||= Catalog::CustomFields.new(@assistant.account)
  end

  def campos_ia
    config_catalogo.key?('campos_ia') ? Array(config_catalogo['campos_ia']) : nil
  end

  def preco(item)
    return dinheiro(item.preco_atual_cents, item.currency) unless item.em_promocao?

    "#{dinheiro(item.promo_price_cents, item.currency)} em promoção (de #{dinheiro(item.price_cents, item.currency)})"
  end

  # Mesma régua do `Catalog::ProductMessageBuilder#formatar`.
  def dinheiro(centavos, moeda)
    inteiro, decimais = format('%.2f', centavos.to_i / 100.0).split('.')
    inteiro = inteiro.reverse.scan(/\d{1,3}/).join('.').reverse
    moeda.to_s.upcase == 'BRL' ? "R$ #{inteiro},#{decimais}" : "#{moeda} #{inteiro},#{decimais}"
  end

  # Códigos que a IA viu nesta conversa, no molde do `codigos_buscados` da buscar_empreendimento:
  # é a trava que uma ferramenta de ENVIO de item vai exigir.
  def rastrear(tool_context, lista)
    conversa = find_conversation(tool_context&.state)
    return unless conversa

    novos = lista.filter_map { |item| item.sku.presence }
    return if novos.empty?

    vistos = Array(conversa.custom_attributes['catalogo_consultados']).map(&:to_s)
    conversa.update!(custom_attributes: conversa.custom_attributes.merge('catalogo_consultados' => (vistos + novos).uniq.last(LIMITE_RASTRO)))
  rescue StandardError => e
    Rails.logger.warn("[ConsultarCatalogo] rastrear: #{e.message}")
  end
end
