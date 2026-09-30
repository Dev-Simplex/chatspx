# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Catalog::CustomFields do
  subject(:campos) { described_class.new(account) }

  let(:account) { create(:account) }

  def campo(chave, tipo, **extras)
    create(:custom_attribute_definition, account: account, attribute_model: 'catalog_attribute', attribute_key: chave,
                                         attribute_display_name: chave.humanize, attribute_display_type: tipo, **extras)
  end

  before do
    campo('bairro', 'text')
    campo('dormitorios', 'number')
    campo('valor_venda', 'currency')
    campo('site', 'link')
    campo('entrega', 'date')
    campo('finalidade', 'list', attribute_values: %w[Venda Aluguel])
    campo('mobiliado', 'checkbox')
    campo('captador', 'text', hidden: true)
  end

  describe '#normalizar' do
    it 'converte o texto do FormData para o tipo de cada campo' do
      resultado = campos.normalizar(
        'bairro' => ' Centro ', 'dormitorios' => '3', 'valor_venda' => '2.500,50', 'site' => 'https://exemplo.com',
        'entrega' => '2026-12-31', 'finalidade' => 'Venda', 'mobiliado' => 'true'
      )

      expect(resultado).to eq(
        'bairro' => 'Centro', 'dormitorios' => 3, 'valor_venda' => 2500.5, 'site' => 'https://exemplo.com',
        'entrega' => '2026-12-31', 'finalidade' => 'Venda', 'mobiliado' => true
      )
    end

    it 'guarda o mesmo valor para "3" e 3, para a sincronização não ver mudança onde não há' do
      expect(campos.normalizar('dormitorios' => '3')).to eq(campos.normalizar('dormitorios' => 3))
    end

    it 'aceita data no formato brasileiro' do
      expect(campos.normalizar('entrega' => '31/12/2026')).to eq('entrega' => '2026-12-31')
    end

    it 'descarta chave sem definição na conta' do
      expect(campos.normalizar('inexistente' => 'x', 'bairro' => 'Centro')).to eq('bairro' => 'Centro')
    end

    it 'ignora definição de contato ou conversa com a mesma chave' do
      create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'cpf_cliente')

      expect(campos.normalizar('cpf_cliente' => '123')).to eq({})
    end

    it 'remove valor em branco e mantém a caixa desmarcada' do
      expect(campos.normalizar('bairro' => '  ', 'dormitorios' => nil, 'mobiliado' => 'false')).to eq('mobiliado' => false)
    end

    it 'recusa valor que não converte, dizendo qual campo' do
      expect { campos.normalizar('dormitorios' => 'três') }
        .to raise_error(CustomExceptions::Catalog::InvalidCustomField, /Dormitorios/)
      expect { campos.normalizar('entrega' => '2026-13-45') }.to raise_error(CustomExceptions::Catalog::InvalidCustomField)
      expect { campos.normalizar('finalidade' => 'Permuta') }.to raise_error(CustomExceptions::Catalog::InvalidCustomField)
      expect { campos.normalizar('mobiliado' => 'talvez') }.to raise_error(CustomExceptions::Catalog::InvalidCustomField)
    end

    it 'só aceita valor escalar' do
      expect { campos.normalizar('bairro' => { 'a' => 1 }) }.to raise_error(CustomExceptions::Catalog::InvalidCustomField)
      expect { campos.normalizar('bairro' => %w[a b]) }.to raise_error(CustomExceptions::Catalog::InvalidCustomField)
    end
  end

  describe '#para_exibir' do
    it 'formata cada tipo, na ordem de criação, sem campo interno nem valor vazio' do
      resultado = campos.para_exibir(
        'captador' => 'João', 'mobiliado' => true, 'entrega' => '2026-12-31', 'valor_venda' => 2500.5,
        'dormitorios' => 3, 'bairro' => 'Centro', 'site' => ''
      )

      expect(resultado).to eq(
        [
          { 'label' => 'Bairro', 'value' => 'Centro' },
          { 'label' => 'Dormitorios', 'value' => '3' },
          { 'label' => 'Valor venda', 'value' => 'R$ 2.500,50' },
          { 'label' => 'Entrega', 'value' => '31/12/2026' },
          { 'label' => 'Mobiliado', 'value' => 'Yes' }
        ]
      )
    end

    it 'não mostra caixa desmarcada' do
      expect(campos.para_exibir('mobiliado' => false)).to eq([])
    end
  end
end
