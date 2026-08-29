# frozen_string_literal: true

require 'rails_helper'

# BLOCO 4.11 — o lado Ruby do "som desligado por default, opcao por inbox".
#
# O consumidor ja existia antes deste arquivo: `sdk/IFrameHelper.js` so baixa o
# mp3 e so toca quando `enabledFeatures` traz `notification_sound`
# (`app/javascript/sdk/specs/notificationSound.spec.js`). O que faltava era a
# flag: `selected_feature_flags = ['notification_sound']` respondia
# `ArgumentError: Invalid flag "notification_sound"`, medido em `rails runner`
# nesta mesma base. Sem ela, "som nao toca sem opt-in" passava por
# impossibilidade — nao havia opt-in nenhum, em caminho nenhum.
#
# A ponta a ponta (tela -> PATCH -> HTML de boot) fica em
# `spec/requests/widgets/notification_sound_payload_spec.rb`; o cruzamento com a
# lista de caixas da tela fica em
# `widget/composables/specs/widgetChannelWireNames.spec.js`.
RSpec.describe Channel::WebWidget do
  let(:account) { create(:account) }

  describe 'a flag `notification_sound`' do
    it 'existe, e o `selected_feature_flags=` a aceita' do
      channel = described_class.new(account: account, website_url: 'https://exemplo.com.br')

      expect { channel.selected_feature_flags = ['notification_sound'] }.not_to raise_error
      expect(channel.notification_sound?).to be true
    end

    it 'nasce DESLIGADA — inbox nova nao toca som para o visitante' do
      channel = described_class.create!(account: account, website_url: 'https://exemplo.com.br')

      expect(channel.reload.notification_sound?).to be false
      # SIMBOLO, nao string: `selected_feature_flags` devolve os nomes do
      # `has_flags`, que sao simbolos. Escrito com string, este `not_to include`
      # passaria sempre — inclusive com a flag LIGADA —, porque simbolo nunca e
      # igual a string. Medido: a versao com string ficou verde nas duas
      # condicoes. Quem faz a conversao para o fio e o `to_json` do
      # `widgets/show.html.erb`, e e la que o
      # `spec/requests/widgets/notification_sound_payload_spec.rb` mede.
      expect(channel.selected_feature_flags).not_to include(:notification_sound)
    end

    it 'nao muda o conjunto de fabrica: continuam os tres de sempre' do
      # O default da coluna e 7 (attachments + emoji_picker + end_conversation).
      # Se o slot 6 fosse parar dentro do default, toda inbox nova sairia com som
      # sem ninguem pedir — que e o oposto da decisao Q7 do plano 22.
      channel = described_class.create!(account: account, website_url: 'https://exemplo.com.br')

      expect(channel.reload.selected_feature_flags).to contain_exactly(:attachments, :emoji_picker, :end_conversation)
    end

    it 'nao liga o som em inbox que ja existe' do
      # Trava dura: acrescentar um slot ao `has_flags` nao pode reinterpretar o
      # inteiro que ja esta gravado. 7 continua valendo 7.
      legacy = described_class.create!(account: account, website_url: 'https://legado.com.br')
      legacy.update!(feature_flags: 7)

      expect(legacy.reload.feature_flags).to eq(7)
      expect(legacy.notification_sound?).to be false
    end

    it 'liga e desliga, e o desligar persiste' do
      channel = described_class.create!(account: account, website_url: 'https://exemplo.com.br')

      channel.selected_feature_flags = %w[attachments notification_sound]
      channel.save!
      expect(channel.reload.selected_feature_flags).to contain_exactly(:attachments, :notification_sound)

      channel.selected_feature_flags = ['attachments']
      channel.save!
      expect(channel.reload.selected_feature_flags).to contain_exactly(:attachments)
    end
  end

  describe 'o slot escolhido' do
    let(:mascaras) { described_class.flag_mapping['feature_flags'] }

    it 'vale 32 — o sexto bit, e nenhum outro' do
      expect(mascaras[:notification_sound]).to eq(32)
    end

    it 'nao colide com flag nenhuma que ja existia' do
      expect(mascaras.values).to eq(mascaras.values.uniq)
      expect(mascaras).to include(attachments: 1, emoji_picker: 2, end_conversation: 4,
                                  use_inbox_avatar_for_bot: 8, allow_mobile_webview: 16)
    end

    it 'cabe na coluna: `feature_flags` e integer, e integer tem 31 bits uteis' do
      # A licao que motiva este exemplo: mascara que estoura o tipo da coluna e
      # INGRAVAVEL, e a escrita falha (ou trunca) sem nenhum aviso na tela. Aqui
      # o teto e 2**31 porque a coluna e `integer`, nao `bigint`.
      expect(described_class.columns_hash['feature_flags'].type).to eq(:integer)
      expect(mascaras.values.max).to be < 2**31
    end
  end
end
