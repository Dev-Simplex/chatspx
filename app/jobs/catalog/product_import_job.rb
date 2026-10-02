# frozen_string_literal: true

# Import de catálogo por planilha (C5) — para o cliente pequeno que não tem ERP, que é a maioria.
#
# Duas diferenças para o import de contato, e são o motivo deste job existir:
#
# - **casa pelo SKU**: linha com SKU que já existe ATUALIZA, não duplica. É a mesma idempotência
#   da porta do ERP (C3), então reimportar a planilha corrigida é seguro.
# - **preço em reais**, não em centavos: quem monta a planilha é gente, no Excel. `89,90` e
#   `1.234,56` entram certo. Quem quiser ser explícito usa a coluna `preco_centavos`.
#
# O relatório de erro sai LINHA A LINHA, num CSV anexado ao próprio import, com a linha original
# mais a coluna `erros` — é o que permite ao cliente corrigir e reimportar só o que falhou.
class Catalog::ProductImportJob < ApplicationJob
  queue_as :low
  retry_on ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3

  # Cada campo aceita os nomes que o cliente costuma usar, em português e em inglês.
  COLUNAS = {
    sku: %w[sku codigo código cod],
    name: %w[nome name produto titulo título],
    description: %w[descricao descrição description],
    price: %w[preco preço price valor],
    price_cents: %w[preco_centavos price_cents],
    promo_price: %w[preco_promocional preço_promocional promocional promo],
    promo_price_cents: %w[preco_promocional_centavos promo_price_cents],
    stock: %w[estoque stock quantidade qtd],
    category: %w[categoria category],
    visible: %w[visivel visível visible ativo],
    featured: %w[destaque featured]
  }.freeze

  VERDADEIROS = %w[1 sim s true t yes y verdadeiro].freeze

  def perform(data_import_id)
    return unless (@import = DataImport.find_by(id: data_import_id))

    @conta = @import.account
    processar
  rescue CSV::MalformedCSVError
    @import.update!(status: :failed)
  end

  private

  def processar
    @import.update!(status: :processing)
    gravados = 0
    recusados = []
    cabecalho = nil

    com_arquivo do |arquivo|
      leitor(arquivo).each_with_index do |linha, indice|
        cabecalho ||= linha.headers
        erro = gravar(linha.to_h)
        if erro
          recusados << linha.to_h.merge('linha' => indice + 2, 'erros' => erro)
        else
          gravados += 1
        end
      end
    end

    @import.update!(status: :completed, processed_records: gravados, total_records: gravados + recusados.size)
    anexar_recusados(cabecalho, recusados)
  end

  # Devolve nil quando gravou, ou a mensagem de erro daquela linha. Nenhuma linha derruba as
  # outras: planilha de cliente vem torta, e o valor deste import é justamente dizer ONDE.
  def gravar(linha)
    atributos = montar(linha)
    return 'SKU é obrigatório' if atributos[:sku].blank?

    produto = @conta.catalog_products.find_or_initialize_by(sku: atributos[:sku])
    # Nome só é obrigatório para produto NOVO. A planilha de reajuste que o cliente manda toda
    # semana tem três colunas — sku, preço, estoque —, e exigir nome nela recusava 100% das linhas.
    return 'Nome é obrigatório' if produto.new_record? && atributos[:name].blank?

    campos = campos_da_linha(linha)
    atributos[:custom_attributes] = produto.custom_attributes.merge(campos) if campos.present?
    produto.update!(atributos)
    nil
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.join(', ')
  rescue ArgumentError, CustomExceptions::Catalog::InvalidCustomField => e
    e.message
  end

  # Coluna com o cabeçalho igual à CHAVE ou ao RÓTULO de um campo personalizado preenche o campo.
  # Célula vazia não apaga, pelo mesmo motivo das colunas padrão: planilha parcial não zera cadastro.
  def campos_da_linha(linha)
    valores = linha.transform_keys { |k| k.to_s.strip.downcase }
    brutos = campos_personalizados.definicoes.each_with_object({}) do |definicao, resultado|
      valor = valores[definicao.attribute_key.downcase].presence || valores[definicao.attribute_display_name.downcase].presence
      resultado[definicao.attribute_key] = valor if valor
    end
    campos_personalizados.normalizar(brutos)
  end

  def campos_personalizados
    @campos_personalizados ||= Catalog::CustomFields.new(@conta)
  end

  def montar(linha)
    valores = linha.transform_keys { |k| k.to_s.strip.downcase }
    atributos = {
      # `.presence` no fim é o que faz coluna ausente virar nil e sumir no `compact`. Sem ele,
      # `nil.to_s` vira string VAZIA, o compact não tira, e o update grava nome em branco.
      sku: pegar(valores, :sku).to_s.strip.presence,
      name: pegar(valores, :name).to_s.strip.presence,
      description: pegar(valores, :description),
      price_cents: centavos(valores, :price_cents, :price),
      promo_price_cents: centavos(valores, :promo_price_cents, :promo_price),
      stock: inteiro(pegar(valores, :stock)),
      visible: booleano(valores, :visible, padrao: true),
      featured: booleano(valores, :featured, padrao: false)
    }
    atributos[:catalog_category_id] = categoria_id(pegar(valores, :category))
    # Coluna ausente na planilha não pode APAGAR o que já está cadastrado: quem manda só preço e
    # estoque não quer zerar a descrição do produto.
    atributos.compact
  end

  def pegar(valores, campo)
    COLUNAS[campo].each { |nome| return valores[nome] if valores.key?(nome) && valores[nome].present? }
    nil
  end

  def centavos(valores, campo_centavos, campo_reais)
    explicito = pegar(valores, campo_centavos)
    return inteiro(explicito) if explicito.present?

    reais = pegar(valores, campo_reais)
    return nil if reais.blank?

    (decimal(reais) * 100).round
  end

  # "1.234,56" (como o Excel brasileiro escreve) e "1234.56" viram o mesmo número. Com os dois
  # separadores, o ponto é milhar; com um só, ele é decimal.
  def decimal(valor)
    texto = valor.to_s.strip.gsub(/[^\d,.-]/, '')
    texto = if texto.include?(',') && texto.include?('.')
              texto.tr('.', '').tr(',', '.')
            else
              texto.tr(',', '.')
            end
    raise ArgumentError, "Preço inválido: #{valor}" if texto.blank? || !texto.match?(/\A-?\d+(\.\d+)?\z/)

    BigDecimal(texto)
  end

  def inteiro(valor)
    return nil if valor.blank?
    raise ArgumentError, "Número inválido: #{valor}" unless valor.to_s.strip.match?(/\A-?\d+\z/)

    valor.to_s.strip.to_i
  end

  # Coluna AUSENTE da planilha devolve nil e o `compact` tira do update: sem isso, a planilha de
  # reajuste (sku, preço, estoque) reativaria todo produto desativado e apagaria todo destaque.
  # Coluna presente e vazia é outra coisa — aí vale o padrão.
  def booleano(valores, campo, padrao:)
    return nil unless coluna_presente?(valores, campo)

    valor = pegar(valores, campo)
    return padrao if valor.blank?

    VERDADEIROS.include?(valor.to_s.strip.downcase)
  end

  def coluna_presente?(valores, campo)
    COLUNAS[campo].any? { |nome| valores.key?(nome) }
  end

  # Categoria pelo NOME, criada na hora — mesma regra da porta do ERP: obrigar o cliente a
  # cadastrar categoria antes de importar transformaria um passo em dois.
  def categoria_id(nome)
    return nil if nome.blank?

    @conta.catalog_categories.find_or_create_by!(name: nome.to_s.strip).id
  end

  def anexar_recusados(cabecalho, recusados)
    return if recusados.blank?

    colunas = (cabecalho || []) + %w[linha erros]
    csv = CSV.generate do |saida|
      saida << colunas
      recusados.each { |linha| saida << colunas.map { |coluna| linha[coluna] } }
    end
    @import.failed_records.attach(io: StringIO.new(csv), filename: "catalogo_erros_#{Time.zone.today.strftime('%Y%m%d')}.csv",
                                  content_type: 'text/csv')
  end

  def leitor(arquivo)
    arquivo.rewind
    limpo = em_utf8(arquivo.read)
    CSV.new(StringIO.new(limpo), headers: true, col_sep: separador(limpo))
  end

  # O Excel em português salva CSV com PONTO E VÍRGULA, porque a vírgula já é o separador decimal
  # do preço. Sem isto a planilha inteira vira uma coluna só e TODA linha é recusada por falta de
  # SKU — medido: 0 de 2 linhas gravadas.
  def separador(texto)
    cabecalho = texto.lines.first.to_s
    cabecalho.count(';') > cabecalho.count(',') ? ';' : ','
  end

  # O Excel também salva em Windows-1252, e não em UTF-8. Reinterpretar os bytes é o que preserva
  # o acento: apenas remover o byte inválido transformava "Camisão" em "Camiso", em silêncio.
  def em_utf8(bruto)
    utf8 = bruto.dup.force_encoding('UTF-8')
    return utf8 if utf8.valid_encoding?

    bruto.dup.force_encoding('Windows-1252').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  end

  def com_arquivo(&)
    pasta = Rails.root.join('tmp/imports')
    FileUtils.mkdir_p(pasta)
    @import.import_file.open(tmpdir: pasta) do |arquivo|
      arquivo.binmode
      yield arquivo
    end
  end
end
