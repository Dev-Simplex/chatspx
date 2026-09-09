require 'rails_helper'

# O que estes testes protegem: o valor de um template sigiloso nao pode existir em texto
# puro em lugar nenhum que va para o navegador, e um blob que nao decifra tem que FALHAR o
# envio em vez de mandar a mascara como se fosse o codigo.
RSpec.describe Spx::SecretTemplateParams do
  let(:crus) do
    {
      'name' => 'modelodeautorizacao',
      'category' => 'AUTHENTICATION',
      'language' => 'pt_BR',
      'processed_params' => {
        'body' => { '1' => '324074' },
        'buttons' => [{ 'type' => 'url', 'parameter' => '324074' }]
      }
    }
  end

  describe '.protect' do
    subject(:protegidos) { described_class.protect(crus) }

    it 'troca o valor pela mascara e preserva a estrutura' do
      expect(protegidos['processed_params']['body']['1']).to eq(described_class::MASK)
      expect(protegidos['processed_params']['buttons'].first['parameter']).to eq(described_class::MASK)
    end

    it 'mantem as chaves estruturais, sem as quais a Meta recusa o envio' do
      expect(protegidos['processed_params']['buttons'].first['type']).to eq('url')
    end

    it 'nao deixa o valor em lugar nenhum do que vai ser serializado' do
      # A varredura e no JSON inteiro de proposito: e exatamente isso que o
      # `_message.json.jbuilder` serializa e o `push_event_data` empurra pelo websocket.
      legivel = protegidos.except(described_class::SECRET_KEY).to_json
      expect(legivel).not_to include('324074')
    end

    it 'preserva nome, categoria e idioma, que sao o rastro' do
      expect(protegidos.slice('name', 'category', 'language')).to eq(crus.slice('name', 'category', 'language'))
    end

    it 'nao altera o hash recebido' do
      described_class.protect(crus)
      expect(crus['processed_params']['body']['1']).to eq('324074')
    end
  end

  describe '.reveal' do
    it 'devolve o valor real e some com o blob' do
      revelados = described_class.reveal(described_class.protect(crus))

      expect(revelados['processed_params']).to eq(crus['processed_params'])
      expect(revelados).not_to have_key(described_class::SECRET_KEY)
    end

    it 'e no-op para template comum, que nao tem blob' do
      expect(described_class.reveal(crus)).to eq(crus)
    end

    it 'levanta RevealError quando o blob nao decifra, em vez de devolver a mascara' do
      corrompido = described_class.protect(crus).merge(described_class::SECRET_KEY => 'nao sou um blob')

      expect { described_class.reveal(corrompido) }.to raise_error(described_class::RevealError)
    end
  end

  describe '.secret?' do
    let(:inbox) { create(:inbox) }

    it 'e verdadeiro so quando a caixa marcou aquele nome' do
      inbox.update!(additional_attributes: { 'secret_template_names' => ['modelodeautorizacao'] })

      expect(described_class.secret?(inbox, crus)).to be(true)
      expect(described_class.secret?(inbox, crus.merge('name' => 'outro'))).to be(false)
    end

    it 'e falso sem lista, sem caixa e sem nome' do
      expect(described_class.secret?(inbox, crus)).to be(false)
      expect(described_class.secret?(nil, crus)).to be(false)
      expect(described_class.secret?(inbox, crus.except('name'))).to be(false)
    end
  end

  describe '.forget!' do
    let(:message) { create(:message, additional_attributes: { 'template_params' => described_class.protect(crus) }) }

    it 'apaga o blob e deixa a mascara' do
      expect(described_class.forget!(message)).to be(true)

      params = message.reload.additional_attributes['template_params']
      expect(params).not_to have_key(described_class::SECRET_KEY)
      expect(params['processed_params']['body']['1']).to eq(described_class::MASK)
    end

    it 'e no-op quando nao ha blob' do
      comum = create(:message, additional_attributes: { 'template_params' => crus })

      expect(described_class.forget!(comum)).to be(false)
    end
  end
end
