require 'rails_helper'

RSpec.describe Suggestion do
  let(:account) { create(:account) }

  def anexo(nome, tipo, tamanho = 10.kilobytes)
    { io: StringIO.new('x' * tamanho), filename: nome, content_type: tipo }
  end

  describe 'validacoes' do
    it 'exige texto, nome e empresa' do
      suggestion = described_class.new(account: account)

      expect(suggestion).not_to be_valid
      expect(suggestion.errors.attribute_names).to include(:content, :name, :company)
    end

    it 'recusa texto acima de 5000 caracteres' do
      suggestion = build(:suggestion, account: account, content: 'a' * 5001)

      expect(suggestion).not_to be_valid
      expect(suggestion.errors.attribute_names).to include(:content)
    end

    # account/user nullable de proposito: o link publico da SUG-02 nao tem conta, e apagar uma
    # conta nao pode levar a sugestao junto nem travar a exclusao.
    it 'aceita sugestao sem conta e sem usuario (link publico)' do
      suggestion = described_class.new(name: 'Anonimo', company: 'Empresa', content: 'ideia', source: :public_link)

      expect(suggestion).to be_valid
    end
  end

  describe 'anexo' do
    it 'aceita imagem' do
      suggestion = build(:suggestion, account: account)
      suggestion.media.attach(anexo('print.png', 'image/png'))

      expect(suggestion).to be_valid
    end

    it 'recusa um tipo que nao e foto nem video' do
      suggestion = build(:suggestion, account: account)
      suggestion.media.attach(anexo('contrato.pdf', 'application/pdf'))

      expect(suggestion).not_to be_valid
      expect(suggestion.errors.attribute_names).to include(:media)
    end

    it 'recusa arquivo acima de 100 MB' do
      suggestion = build(:suggestion, account: account)
      suggestion.media.attach(anexo('video.mp4', 'video/mp4'))
      allow(suggestion.media).to receive(:byte_size).and_return(101.megabytes)

      expect(suggestion).not_to be_valid
      expect(suggestion.errors.attribute_names).to include(:media)
    end
  end

  describe 'conta apagada' do
    it 'sobrevive com a coluna vazia, sem travar a exclusao' do
      conta = create(:account)
      suggestion = create(:suggestion, account: conta, user: nil)

      expect { conta.destroy! }.not_to raise_error
      expect(suggestion.reload.account_id).to be_nil
    end
  end
end
