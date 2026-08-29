require 'rails_helper'

# Bloco 4.13 — o segredo de assinatura dos emissores de webhook.
#
# Ate aqui so o `Webhook` tinha o concern. `AgentBot` e `Channel::Api` tinham a COLUNA
# populada (migrada por uma versao antiga) e nenhum codigo: `agent_bot.secret` devolvia o
# ciphertext CRU, `{"p":"..."}`, e assinar com ele seria assinar com o envelope em vez do
# segredo combinado com o destino.
RSpec.describe WebhookSecretable do
  # A leitura do dado ANTIGO e o risco real de acrescentar `encrypts` a uma coluna que ja
  # tem conteudo. Linha gravada antes do `encrypts` esta em texto claro; se o
  # `support_unencrypted_data` estiver desligado, a leitura levanta excecao e o registro
  # fica inacessivel — o exemplo do meio forca essa condicao para provar que quem sustenta
  # a leitura e a guarda, e nao alguma coincidencia do ambiente.
  shared_examples 'um portador de segredo de assinatura' do
    def valor_cru(record)
      record.class.connection.select_value(
        record.class.sanitize_sql_array(["SELECT secret FROM #{record.class.table_name} WHERE id = ?", record.id])
      )
    end

    # A linha legada precisa ser escrita por SQL cru. `update_column` NAO serve: medido
    # nesta arvore, ele passa pelo tipo do atributo e grava CIFRADO — escrever com ele
    # produziria uma linha normal e o teste de dado antigo nao testaria nada.
    def grava_texto_claro(record, valor)
      record.class.connection.execute(
        record.class.sanitize_sql_array(["UPDATE #{record.class.table_name} SET secret = ? WHERE id = ?", valor, record.id])
      )
    end

    it 'nasce com segredo' do
      expect(record.reload.secret).to be_present
    end

    it 'guarda cifrado em repouso' do
      expect(Chatwoot.encryption_configured?).to be(true)
      expect(record.class.encrypted_attributes).to include(:secret)

      cru = valor_cru(record)

      expect(cru).not_to eq(record.secret)
      expect(cru).to start_with('{"p":')
    end

    it 'reset_secret! troca o valor e o novo tambem chega cifrado' do
      anterior = record.reload.secret

      record.reset_secret!

      expect(record.secret).to be_present
      expect(record.secret).not_to eq(anterior)
      expect(valor_cru(record)).to start_with('{"p":')
    end

    it 'ainda le o dado antigo gravado em texto claro' do
      grava_texto_claro(record, 'segredo-antigo-em-texto-claro')

      expect(valor_cru(record)).to eq('segredo-antigo-em-texto-claro')
      expect(record.reload.secret).to eq('segredo-antigo-em-texto-claro')
    end

    it 'e quem sustenta essa leitura e o support_unencrypted_data: desligado, ela quebra' do
      grava_texto_claro(record, 'segredo-antigo-em-texto-claro')
      original = ActiveRecord::Encryption.config.support_unencrypted_data

      begin
        ActiveRecord::Encryption.config.support_unencrypted_data = false
        expect { record.reload.secret }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)
      ensure
        ActiveRecord::Encryption.config.support_unencrypted_data = original
      end
    end

    it 'com a guarda de volta, o mesmo dado antigo volta a ser legivel' do
      grava_texto_claro(record, 'segredo-antigo-em-texto-claro')

      expect(ActiveRecord::Encryption.config.support_unencrypted_data).to be(true)
      expect(record.reload.secret).to eq('segredo-antigo-em-texto-claro')
    end
  end

  describe AgentBot do
    let(:record) { create(:agent_bot) }

    it_behaves_like 'um portador de segredo de assinatura'
  end

  describe Channel::Api do
    let(:record) { create(:channel_api) }

    it_behaves_like 'um portador de segredo de assinatura'
  end

  describe Webhook do
    let(:record) { create(:webhook, account: create(:account)) }

    it_behaves_like 'um portador de segredo de assinatura'
  end
end
