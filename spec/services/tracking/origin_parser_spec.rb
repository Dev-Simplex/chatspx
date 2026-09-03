require 'rails_helper'

RSpec.describe Tracking::OriginParser do
  def parse(url)
    described_class.new(url).attributes
  end

  describe 'extração' do
    it 'lê os 6 UTM e os 6 click ids de uma URL de campanha' do
      url = 'https://loja.exemplo.com.br/tenis?utm_source=Google&utm_medium=CPC&utm_campaign=Verao_2026' \
            '&utm_term=tenis+corrida&utm_content=anuncio_a&utm_id=1234' \
            '&gclid=Cj0KAbC&gbraid=GbR1&wbraid=WbR1&fbclid=IwAR9&msclkid=MsK7&ttclid=TtC3'

      expect(parse(url)).to include(
        'utm_source' => 'google', 'utm_medium' => 'cpc', 'utm_campaign' => 'verao_2026',
        'utm_term' => 'tenis corrida', 'utm_content' => 'anuncio_a', 'utm_id' => '1234',
        'gclid' => 'Cj0KAbC', 'gbraid' => 'GbR1', 'wbraid' => 'WbR1',
        'fbclid' => 'IwAR9', 'msclkid' => 'MsK7', 'ttclid' => 'TtC3'
      )
    end

    it 'normaliza source/medium/campaign para minúsculas e PRESERVA o case dos click ids' do
      atributos = parse('https://loja.com.br/p?utm_source=GOOGLE&utm_campaign=BlackFriday&gclid=AbCdEf')

      expect(atributos['utm_source']).to eq('google')
      expect(atributos['utm_campaign']).to eq('blackfriday')
      expect(atributos['gclid']).to eq('AbCdEf')
    end

    it 'lê a chave da query sem depender do case em que o site a escreveu' do
      expect(parse('https://loja.com.br/p?UTM_Source=meta')['utm_source']).to eq('meta')
    end

    it 'ignora parâmetro presente e vazio em vez de gravar string vazia' do
      atributos = parse('https://loja.com.br/p?utm_source=&utm_medium=cpc')

      expect(atributos).not_to have_key('utm_source')
      expect(atributos['utm_medium']).to eq('cpc')
    end

    it 'trunca valor gigante no limite declarado' do
      valor = 'a' * 400
      expect(parse("https://loja.com.br/p?utm_campaign=#{valor}")['utm_campaign'].length).to eq(255)
    end

    it 'grava host e path da página em que o chat abriu, sem www' do
      atributos = parse('https://www.Loja.Exemplo.com.br/produtos/tenis?utm_source=google')

      expect(atributos['page_host']).to eq('loja.exemplo.com.br')
      expect(atributos['page_path']).to eq('/produtos/tenis')
    end

    it 'devolve "/" quando a URL não tem path' do
      expect(parse('https://loja.com.br?utm_source=google')['page_path']).to eq('/')
    end

    it 'devolve vazio para o que não é http(s)' do
      expect(parse('javascript:alert(1)')).to eq({})
      expect(parse(nil)).to eq({})
      expect(parse('')).to eq({})
    end
  end

  describe '#origin_kind' do
    {
      'https://loja.com.br/p?gclid=X' => 'busca_paga',
      'https://loja.com.br/p?gbraid=X' => 'busca_paga',
      'https://loja.com.br/p?wbraid=X' => 'busca_paga',
      'https://loja.com.br/p?msclkid=X' => 'busca_paga',
      'https://loja.com.br/p?utm_source=google&utm_medium=cpc' => 'busca_paga',
      'https://loja.com.br/p?utm_source=newsletter&utm_medium=email' => 'email',
      'https://loja.com.br/p?utm_source=chatgpt.com' => 'ia_generativa',
      'https://loja.com.br/p?utm_source=perplexity' => 'ia_generativa',
      'https://loja.com.br/p?utm_source=gemini.google.com' => 'ia_generativa',
      'https://loja.com.br/p?utm_source=claude.ai' => 'ia_generativa',
      'https://loja.com.br/p?fbclid=IwAR9' => 'social',
      'https://loja.com.br/p?ttclid=X' => 'social',
      'https://loja.com.br/p?utm_source=instagram&utm_medium=social' => 'social',
      'https://loja.com.br/p?utm_source=google&utm_medium=organic' => 'busca_organica',
      'https://loja.com.br/p?utm_source=bing' => 'busca_organica',
      'https://loja.com.br/p?utm_source=parceiro_xyz' => 'referencia',
      'https://loja.com.br/p' => 'nao_disponivel'
    }.each do |url, esperado|
      it "classifica #{url} como #{esperado}" do
        expect(parse(url)['origin_kind']).to eq(esperado)
      end
    end

    it 'NUNCA devolve "direta" — ausência de dado é nao_disponivel, não uma origem' do
      %w[https://loja.com.br/ https://loja.com.br/p?foo=bar https://loja.com.br/p?utm_source=].each do |url|
        expect(parse(url)['origin_kind']).to eq('nao_disponivel')
      end
      expect(described_class::IA_GENERATIVA_HOSTS).not_to include('direta')
      expect(Tracking::OriginAttributes::ORIGIN_KINDS).not_to include('direta')
    end

    it 'gemini.google.com não cai em busca_organica só por conter "google"' do
      expect(parse('https://loja.com.br/p?utm_source=gemini.google.com&utm_medium=referral')['origin_kind'])
        .to eq('ia_generativa')
    end

    it 'clique pago tem precedência sobre a classificação por source' do
      expect(parse('https://loja.com.br/p?utm_source=instagram&gclid=X')['origin_kind']).to eq('busca_paga')
    end

    it 'todo valor que o parser produz existe no catálogo do 1.18' do
      urls = ['https://l.com/p?gclid=X', 'https://l.com/p?utm_medium=email', 'https://l.com/p?utm_source=chatgpt.com',
              'https://l.com/p?fbclid=X', 'https://l.com/p?utm_source=bing', 'https://l.com/p?utm_source=xyz',
              'https://l.com/p']
      produzidos = urls.map { |url| parse(url)['origin_kind'] }.uniq

      expect(produzidos).to all(be_in(Tracking::OriginAttributes::ORIGIN_KINDS))
      expect(produzidos).to match_array(%w[busca_paga email ia_generativa social busca_organica referencia nao_disponivel])
    end
  end

  it 'toda chave produzida existe no catálogo de chaves de conversa do 1.18' do
    url = 'https://loja.com.br/p?utm_source=google&utm_medium=cpc&utm_campaign=c&utm_term=t&utm_content=ct' \
          '&utm_id=1&gclid=a&gbraid=b&wbraid=c&fbclid=d&msclkid=e&ttclid=f'
    chaves = parse(url).keys.map { |base| Tracking::OriginAttributes.conversation_key(base) }

    expect(chaves).to match_array(Tracking::OriginAttributes.conversation_keys)
  end
end
