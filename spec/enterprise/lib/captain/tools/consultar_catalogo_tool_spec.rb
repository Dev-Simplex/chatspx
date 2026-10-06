require 'rails_helper'

RSpec.describe Captain::Tools::ConsultarCatalogoTool, type: :model do
  let(:account) { create(:account) }
  let(:config_catalogo) { { 'campos_busca' => ['apelidos'] } }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'catalogo' => config_catalogo }) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  let(:limpeza) { create(:catalog_category, account: account, name: 'Limpeza') }
  let(:protecao) { create(:catalog_category, account: account, name: 'Proteção') }

  def campo(chave, nome, hidden: false)
    create(:custom_attribute_definition, account: account, attribute_model: 'catalog_attribute', attribute_key: chave,
                                         attribute_display_name: nome, attribute_display_type: 'text', hidden: hidden)
  end

  def item(nome, sku, categoria, atributos, **extras)
    create(:catalog_product, account: account, name: nome, sku: sku, category: categoria, custom_attributes: atributos,
                             description: 'Texto livre sobre cerâmica e brilho', price_cents: 15_000, **extras)
  end

  before do
    campo('apelidos', 'Apelidos', hidden: true)
    campo('inclui', 'Inclui')
    campo('quando_transferir', 'Quando transferir', hidden: true)

    item('Lavagem Técnica', 'LAV-1', limpeza,
         { 'apelidos' => 'lavada; ducha', 'inclui' => 'Motor e chassi', 'quando_transferir' => 'Pedido de orçamento' })
    item('Higienização Interna', 'HIG-1', limpeza, { 'apelidos' => 'limpeza de banco' })
    item('Vitrificação de Pintura', 'VIT-1', protecao, { 'apelidos' => 'coating' })
    item('Polimento Técnico', 'POL-1', protecao, { 'apelidos' => 'espelhamento' }, visible: false)
  end

  describe 'contrato' do
    it 'descreve a ferramenta e os parâmetros sem exemplo copiável nem valor concreto' do
      textos = [described_class.description, *tool.parameters.values.map(&:description)]

      textos.each do |texto|
        expect(texto).not_to match(/\bex(emplo)?[.:]|por exemplo|\d/i)
      end
      expect(described_class.description).to include('O que não vier daqui não existe')
    end

    it 'está registrada como tool de código' do
      expect(Captain::Assistant.resolve_tool_class('consultar_catalogo')).to eq(described_class)
    end
  end

  describe 'busca' do
    it 'acha pelo nome com e sem acento' do
      expect(tool.perform(tool_context, termo: 'higienização interna')).to include('Item: Higienização Interna')
      expect(tool.perform(tool_context, termo: 'HIGIENIZACAO')).to include('Item: Higienização Interna')
    end

    it 'acha pelo apelido de um campo configurado em campos_busca' do
      expect(tool.perform(tool_context, termo: 'ducha')).to include('Item: Lavagem Técnica')
    end

    it 'não pesquisa campo fora de campos_busca' do
      config_catalogo.delete('campos_busca')

      expect(tool.perform(tool_context, termo: 'ducha')).to start_with('Nada no catálogo corresponde')
    end

    it 'não pesquisa a descrição' do
      expect(tool.perform(tool_context, termo: 'cerâmica')).to start_with('Nada no catálogo corresponde')
    end

    it 'nunca devolve item oculto, nem pelo apelido, nem pelo código' do
      expect(tool.perform(tool_context, termo: 'espelhamento')).to start_with('Nada no catálogo corresponde')
      expect(tool.perform(tool_context, codigo: 'POL-1')).to start_with('Nenhum item do catálogo tem o código')
      expect(tool.perform(tool_context, categoria: 'Proteção')).not_to include('Polimento')
    end

    it 'restringe pela categoria' do
      resposta = tool.perform(tool_context, categoria: 'limpeza')

      expect(resposta).to include('Lavagem Técnica', 'Higienização Interna')
      expect(resposta).not_to include('Vitrificação')
    end

    it 'diz quando a categoria não existe e mostra as que existem' do
      resposta = tool.perform(tool_context, categoria: 'Mecânica')

      expect(resposta).to start_with('Nenhuma categoria do catálogo corresponde')
      expect(resposta).to include('- Limpeza: 2 itens')
    end

    it 'traz o detalhe pelo código e registra o código na conversa' do
      resposta = tool.perform(tool_context, codigo: 'vit-1')

      expect(resposta).to include('Item: Vitrificação de Pintura (código VIT-1, categoria: Proteção)')
      expect(conversation.reload.custom_attributes['catalogo_consultados']).to eq(['VIT-1'])
    end

    it 'lista as categorias com a contagem quando vem vazia, sem contar item oculto' do
      resposta = tool.perform(tool_context)

      expect(resposta).to eq("Categorias do catálogo:\n- Limpeza: 2 itens\n- Proteção: 1 item")
    end

    it 'diz explicitamente que nada foi encontrado' do
      expect(tool.perform(tool_context, termo: 'blindagem')).to eq(
        'Nada no catálogo corresponde a "blindagem". Não afirme que a empresa faz nem que não faz.'
      )
    end

    it 'não enxerga item de outra conta' do
      create(:catalog_product, name: 'Blindagem', sku: 'BLI-1')

      expect(tool.perform(tool_context, termo: 'blindagem')).to start_with('Nada no catálogo corresponde')
    end
  end

  describe 'o que volta para a IA' do
    it 'devolve descrição e só os campos não internos por padrão' do
      resposta = tool.perform(tool_context, codigo: 'LAV-1')

      expect(resposta).to include('Descrição: Texto livre sobre cerâmica e brilho', 'Inclui: Motor e chassi')
      expect(resposta).not_to include('Quando transferir', 'Apelidos')
    end

    it 'devolve campo interno só quando ele está em campos_ia' do
      config_catalogo['campos_ia'] = %w[inclui quando_transferir]

      resposta = tool.perform(tool_context, codigo: 'LAV-1')

      expect(resposta).to include('Inclui: Motor e chassi', 'Quando transferir: Pedido de orçamento')
      expect(resposta).not_to include('Apelidos')
    end

    it 'não devolve preço por padrão' do
      expect(tool.perform(tool_context, codigo: 'LAV-1')).not_to match(/preço|R\$/i)
    end

    it 'devolve preço e promoção quando mostrar_preco é true' do
      config_catalogo['mostrar_preco'] = true
      CatalogProduct.find_by(sku: 'LAV-1').update!(promo_price_cents: 12_000)

      expect(tool.perform(tool_context, codigo: 'LAV-1')).to include('Preço: R$ 120,00 em promoção (de R$ 150,00)')
    end
  end
end
