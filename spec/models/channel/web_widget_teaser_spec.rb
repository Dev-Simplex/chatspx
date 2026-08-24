# frozen_string_literal: true

# BLOCO 4.05 — a mensagem do convite: o que o cliente escreve é o que o visitante lê.
#
# O compositor da Tela 2 (`TeaserComposer.vue`) não cria campanha: ele EDITA a campanha de
# chat ao vivo da inbox, porque "campanha é mensagem, gatilho é momento". O teaser do host
# mostrava `welcome_tagline`, que é outro campo, de outra tela — então editar o convite não
# mudava nada do lado do visitante, e o preview da própria tela (4.07, que já mostra
# `campanha.message`) mentia.
#
# ESTE SPEC ACUSA. O caso central não pergunta "o método devolve alguma coisa": ele SALVA um
# texto na campanha, lê, SALVA outro e lê de novo. Um teste que só conferisse a presença do
# campo passaria com a junção quebrada, bastando `welcome_tagline` estar preenchido — e por
# isso todo exemplo aqui mantém `welcome_tagline` preenchido com um texto DIFERENTE.
require 'rails_helper'

RSpec.describe Channel::WebWidget do
  let(:account) { create(:account) }
  let(:web_widget) do
    create(:channel_widget, account: account, welcome_tagline: 'Estamos online', welcome_title: 'Ola!')
  end
  let(:inbox) { web_widget.inbox }

  describe '#teaser_text' do
    it 'devolve a MENSAGEM da campanha vinculada, não o welcome_tagline' do
      create(:campaign, account: account, inbox: inbox, title: 'Convite', message: 'Frete gratis hoje')

      expect(web_widget.teaser_text).to eq('Frete gratis hoje')
    end

    it 'acompanha a edição da campanha — o aceite do bloco' do
      campanha = create(:campaign, account: account, inbox: inbox, message: 'Frete gratis hoje')

      expect(web_widget.teaser_text).to eq('Frete gratis hoje')

      # O cliente volta ao compositor e salva outro texto. É ISTO que precisa chegar ao
      # visitante: se a junção estiver quebrada, as duas leituras devolvem 'Estamos online'
      # e a igualdade abaixo reprova.
      campanha.update!(message: 'Ultimas unidades com 20% off')

      expect(web_widget.reload.teaser_text).to eq('Ultimas unidades com 20% off')
    end

    it 'cai no welcome_tagline quando a inbox não tem campanha — não há regressão' do
      expect(web_widget.teaser_text).to eq('Estamos online')
    end

    it 'cai no welcome_title quando não há campanha nem tagline' do
      web_widget.update!(welcome_tagline: '')

      expect(web_widget.teaser_text).to eq('Ola!')
    end

    it 'devolve string vazia quando não há nada — nunca nil' do
      # O valor entra num literal JavaScript e é lido por `canal.teaserText || ''` no host.
      # `nil` viraria `null`, que funciona por acidente; string é o contrato explícito.
      web_widget.update!(welcome_tagline: '', welcome_title: '')

      expect(web_widget.teaser_text).to eq('')
    end

    it 'ignora campanha de OUTRA inbox da mesma conta' do
      outra = create(:channel_widget, account: account).inbox
      create(:campaign, account: account, inbox: outra, message: 'Convite da outra caixa')

      expect(web_widget.teaser_text).to eq('Estamos online')
    end

    it 'ignora linha one_off na mesma inbox — disparo em massa não é a mensagem do convite' do
      campanha = create(:campaign, account: account, inbox: inbox, message: 'Promocao para a lista')
      # Pela porta da frente a inbox web nunca produz `one_off`: o
      # `ensure_correct_campaign_attributes` do `Campaign` força `ongoing` em todo canal que
      # não seja SMS/Twilio/WhatsApp — passar `campaign_type: :one_off` no factory é
      # silenciosamente revertido. A linha é escrita direto no banco justamente para que o
      # filtro `ongoing` deste método seja MEDIDO, e não apenas presumido pela coerção alheia:
      # se amanhã aquele callback mudar, é este exemplo que reprova.
      campanha.update_column(:campaign_type, Campaign.campaign_types[:one_off]) # rubocop:disable Rails/SkipsModelValidations

      expect(web_widget.reload.teaser_text).to eq('Estamos online')
    end

    it 'com campanha de mensagem em branco, o balão mostra a tagline em vez de nada' do
      campanha = create(:campaign, account: account, inbox: inbox, message: 'Frete gratis hoje')
      # `message` é `not null` com validação de presença; a coluna aceita espaço em branco.
      campanha.update_column(:message, '   ') # rubocop:disable Rails/SkipsModelValidations

      expect(web_widget.reload.teaser_text).to eq('Estamos online')
    end
  end

  describe '#teaser_campaign' do
    it 'é a campanha ongoing de menor id, o mesmo critério da tela' do
      # `getLiveChatCampaigns` ordena por `id` e a tela pega a desta inbox: a PRIMEIRA.
      # Se o servidor escolhesse outra, o cliente editaria uma campanha e o visitante
      # receberia a outra — o defeito que o bloco existe para não ter.
      primeira = create(:campaign, account: account, inbox: inbox, message: 'A primeira')
      create(:campaign, account: account, inbox: inbox, message: 'A segunda')

      expect(web_widget.teaser_campaign).to eq(primeira)
    end

    it 'não filtra por `enabled` — o interruptor é do motor legado, não do teaser' do
      # `enabled` governa o DISPARO da campanha legada (4.22). Quem liga e desliga o teaser
      # é `widget_triggers.enabled`. Se este método filtrasse por `enabled`, o texto que o
      # cliente acabou de salvar sumiria por causa de um interruptor de outra tela.
      create(:campaign, account: account, inbox: inbox, message: 'Frete gratis hoje', enabled: false)

      expect(web_widget.teaser_text).to eq('Frete gratis hoje')
    end
  end
end
