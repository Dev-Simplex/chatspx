require 'rails_helper'

RSpec.describe LeadCampaigns::TemplateCatalog do
  let(:account) { create(:account) }

  def catalogo_com(templates)
    canal = create(:channel_whatsapp, account: account, sync_templates: false,
                                      validate_provider_config: false, message_templates: templates)
    described_class.new(canal.inbox)
  end

  def corpo(texto, extras = {})
    montar([{ 'type' => 'BODY', 'text' => texto }], extras)
  end

  def montar(componentes, extras = {})
    { 'name' => 'abertura', 'status' => 'APPROVED', 'language' => 'pt_BR',
      'components' => componentes }.merge(extras)
  end

  describe '#disponivel?' do
    it 'is false for a channel that does not keep templates' do
      expect(described_class.new(create(:inbox, account: account))).not_to be_disponivel
    end

    it 'is false without an inbox at all' do
      expect(described_class.new(nil)).not_to be_disponivel
    end
  end

  describe '#aprovados' do
    it 'leaves out what Meta has not approved' do
      catalogo = catalogo_com([corpo('Oi {{1}}'), corpo('Oi', 'name' => 'espera', 'status' => 'PENDING')])

      expect(catalogo.nomes).to eq(['abertura'])
    end

    it 'reads the status regardless of case' do
      catalogo = catalogo_com([corpo('Oi {{1}}', 'status' => 'approved')])

      expect(catalogo.nomes).to eq(['abertura'])
    end

    # É esta contagem que a validação usa para recusar o #132000 — o mesmo `{{1}}` repetido
    # é UM parâmetro para a Meta, não dois.
    it 'counts each variable once, in the order they appear' do
      catalogo = catalogo_com([corpo('Oi {{1}}, sobre {{2}}. Até logo, {{1}}!')])

      expect(catalogo.aprovados.first[:variaveis]).to eq(%w[1 2])
    end

    it 'reports no variables for a template without them' do
      catalogo = catalogo_com([corpo('Oi! Somos da equipe.')])

      expect(catalogo.aprovados.first[:variaveis]).to be_empty
    end
  end

  # A abertura do lead envia SÓ os parâmetros do corpo. Tudo que o template exija além
  # disso chega vazio e a Meta recusa a mensagem inteira.
  describe 'the reason a template cannot be used' do
    it 'flags a media header' do
      catalogo = catalogo_com([montar([{ 'type' => 'HEADER', 'format' => 'IMAGE' },
                                       { 'type' => 'BODY', 'text' => 'Oi {{1}}' }])])

      expect(catalogo.aprovados.first[:impedimento]).to eq(:cabecalho_de_midia)
    end

    it 'flags a variable in a text header' do
      catalogo = catalogo_com([montar([{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Sobre {{1}}' },
                                       { 'type' => 'BODY', 'text' => 'Oi {{1}}' }])])

      expect(catalogo.aprovados.first[:impedimento]).to eq(:cabecalho_com_variavel)
    end

    it 'flags a button with a variable' do
      catalogo = catalogo_com([montar([{ 'type' => 'BODY', 'text' => 'Oi {{1}}' },
                                       { 'type' => 'BUTTONS',
                                         'buttons' => [{ 'type' => 'URL', 'url' => 'https://exemplo.com/{{1}}' }] }])])

      expect(catalogo.aprovados.first[:impedimento]).to eq(:botao_com_variavel)
    end

    # A engine numera os parâmetros do corpo; template nomeado espera a chave com o nome.
    it 'flags named parameters' do
      catalogo = catalogo_com([corpo('Oi {{nome}}', 'parameter_format' => 'NAMED')])

      expect(catalogo.aprovados.first[:impedimento]).to eq(:parametro_nomeado)
    end

    it 'lets a plain text-and-body template through' do
      catalogo = catalogo_com([montar([{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Novidade' },
                                       { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
                                       { 'type' => 'FOOTER', 'text' => 'Equipe' }])])

      expect(catalogo.aprovados.first[:impedimento]).to be_nil
    end
  end

  # A Meta trata (nome, idioma) como templates diferentes: escolher só o nome não é uma
  # escolha completa, e chutar o idioma derruba o envio do mesmo jeito que o #132000.
  describe '#encontrar' do
    let(:catalogo) do
      catalogo_com([corpo('Oi {{1}}'), corpo('Hi {{1}}', 'language' => 'en_US')])
    end

    it 'matches by name and language, ignoring case' do
      expect(catalogo.encontrar('abertura', 'PT_br')[:idioma]).to eq('pt_BR')
    end

    it 'refuses to guess when the name is approved in more than one language' do
      expect(catalogo.encontrar('abertura')).to be_nil
      expect(catalogo).to be_ambiguo('abertura')
    end

    it 'answers by name alone when there is only one' do
      unico = catalogo_com([corpo('Oi {{1}}')])

      expect(unico.encontrar('abertura')[:idioma]).to eq('pt_BR')
    end
  end
end
