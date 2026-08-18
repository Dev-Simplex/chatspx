require 'rails_helper'

describe UrlHelper do
  describe '#url_valid' do
    context 'when url valid called' do
      it 'return if valid url passed' do
        expect(helper.url_valid?('https://app.chatwoot.com/')).to be true
      end

      it 'return false if invalid url passed' do
        expect(helper.url_valid?('javascript:alert(document.cookie)')).to be false
      end
    end
  end

  # Bloco 1.20 — parar de destruir o dado na escrita.
  # `url_valid?` reprova URL de site real que só está mal escapada (espaço cru, colchete cru no
  # path). Antes deste bloco, reprovar significava `referer = nil` e a origem do lead sumia.
  describe '#sanitized_url' do
    it 'preserva a origem quando a URL tem espaço não escapado' do
      raw = 'https://loja.exemplo.com.br/produtos/tenis nike?utm_source=google&utm_medium=cpc'

      expect(helper.url_valid?(raw)).to be false
      expect(helper.sanitized_url(raw)).to eq(
        'https://loja.exemplo.com.br/produtos/tenis%20nike?utm_source=google&utm_medium=cpc'
      )
    end

    it 'preserva a origem quando a URL tem colchete cru no path' do
      raw = 'https://loja.exemplo.com.br/produtos/[promo]/tenis?utm_source=google'

      expect(helper.url_valid?(raw)).to be false
      expect(helper.sanitized_url(raw)).to eq(
        'https://loja.exemplo.com.br/produtos/%5Bpromo%5D/tenis?utm_source=google'
      )
    end

    it 'devolve a URL intacta quando ela já é válida (não normaliza o que não precisa)' do
      raw = 'https://loja.exemplo.com.br/ok?utm_source=google&gclid=X'

      expect(helper.sanitized_url(raw)).to eq(raw)
    end

    it 'devolve nil para esquema que não é http(s), mesmo depois de escapar' do
      expect(helper.sanitized_url('javascript:alert(document.cookie)')).to be_nil
      expect(helper.sanitized_url('data:text/html,<script>alert(1)</script>')).to be_nil
      expect(helper.sanitized_url('file:///etc/passwd')).to be_nil
    end

    it 'devolve nil para texto que não é URL' do
      expect(helper.sanitized_url('nao e uma url')).to be_nil
      expect(helper.sanitized_url('')).to be_nil
      expect(helper.sanitized_url(nil)).to be_nil
    end
  end

  describe '#sanitize_referer_attribute!' do
    it 'reescreve a chave referer com a versão saneada' do
      attributes = { 'referer' => 'https://loja.exemplo.com.br/a b?utm_source=google' }

      helper.sanitize_referer_attribute!(attributes)

      expect(attributes['referer']).to eq('https://loja.exemplo.com.br/a%20b?utm_source=google')
      expect(attributes).not_to have_key('referer_raw')
    end

    it 'move para referer_raw o que não valida nem depois de escapar — nunca nil silencioso' do
      attributes = { 'referer' => 'javascript:alert(document.cookie)' }

      helper.sanitize_referer_attribute!(attributes)

      expect(attributes['referer']).to be_nil
      expect(attributes['referer_raw']).to eq('javascript:alert(document.cookie)')
    end

    it 'não cria referer_raw quando não há nada para preservar' do
      attributes = { 'referer' => '' }

      helper.sanitize_referer_attribute!(attributes)

      expect(attributes['referer']).to be_nil
      expect(attributes).not_to have_key('referer_raw')
    end

    it 'limpa um referer_raw antigo quando a URL passa a validar' do
      attributes = { 'referer' => 'https://loja.exemplo.com.br/ok', 'referer_raw' => 'lixo antigo' }

      helper.sanitize_referer_attribute!(attributes)

      expect(attributes['referer']).to eq('https://loja.exemplo.com.br/ok')
      expect(attributes).not_to have_key('referer_raw')
    end

    it 'trunca o valor cru para não virar vetor de crescimento do jsonb' do
      attributes = { 'referer' => "nao-e-url-#{'x' * 5000}" }

      helper.sanitize_referer_attribute!(attributes)

      expect(attributes['referer_raw'].length).to eq(UrlHelper::REFERER_RAW_MAX_LENGTH)
    end
  end
end
