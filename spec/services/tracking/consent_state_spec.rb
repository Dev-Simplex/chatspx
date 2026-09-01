# frozen_string_literal: true

require 'rails_helper'
require_relative 'fake_http_client'

# Bloco 5.09 (T-C7.4/T-C7.6) — o consentimento CHEGA ao payload server-side.
#
# O DEFEITO QUE ESTE ARQUIVO FECHA, medido antes da correcao: `Ga4Mp#consent_block` devolvia
# `{ ad_user_data: 'GRANTED', ad_personalization: 'GRANTED' }` LITERAL, e nenhum outro ponto do
# servidor lia consentimento. Consequencia pratica: um visitante que recusou tudo na CMP tinha o
# gate do navegador respeitado (5.09 client-side, ja medido) e, mesmo assim, o evento saia pela
# CAPI e pelo Measurement Protocol carimbado como concedido. O bloco server-side mandava o evento
# sem base legal, e o carimbo dizia o contrario do que o visitante respondeu.
#
# O QUE ESTES EXEMPLOS EXIGEM, e por que cada um:
#
#  · o RETRATO viaja com o fato (`TrackingEvent#consent`), e nao e lido "agora" na entrega — entre
#    o fato e a entrega cabe o visitante mudar de ideia, e a base legal e a do momento do fato;
#  · o `consent_block` do GA4 reflete o retrato, nos dois sentidos;
#  · os destinos de ANUNCIO nao enviam sob negativa (`skipped`/`consent_denied`), porque ali o
#    envio E o tratamento do dado pessoal;
#  · e o modo `disabled` — o default de toda a frota — continua se comportando EXATAMENTE como
#    antes deste bloco. Sem esta ultima garantia, ligar o consentimento desligaria a medicao de
#    todo cliente que nunca ouviu falar de Consent Mode.
RSpec.describe Tracking::ConsentState do
  let(:account) { create(:account) }
  # As chaves que o SDK escreve (`sdk/tracking/consent.js`, `consentAttributes`). Escritas por
  # extenso, e nao geradas a partir de `Tracking::ConsentState::PURPOSES`: derivar do codigo sob
  # teste faria o spec seguir uma renomeacao em silencio, e o nome da chave E o contrato entre os
  # dois lados. Se o navegador mudar o prefixo, este arquivo tem de ficar vermelho.
  let(:tudo_negado) do
    { 'consent_ad_storage' => 'denied', 'consent_ad_user_data' => 'denied',
      'consent_ad_personalization' => 'denied', 'consent_analytics_storage' => 'denied' }
  end
  let(:tudo_concedido) do
    { 'consent_ad_storage' => 'granted', 'consent_ad_user_data' => 'granted',
      'consent_ad_personalization' => 'granted', 'consent_analytics_storage' => 'granted' }
  end
  let(:client) { FakeHttpClient.new }
  let(:settings) do
    Tracking::CredentialResolver::Settings.new(
      meta_pixel_id: '999', meta_access_token: 'token',
      ga4_measurement_id: 'G-XYZ', ga4_api_secret: 'segredo',
      google_ads_customer_id: '4444', google_ads_conversion_action_id: '55',
      google_ads_developer_token: 'dev', google_ads_access_token: 'ya29'
    )
  end

  # A inbox com (ou sem) modo de consentimento. `widget_tracking` e o mesmo objeto que o schema do
  # 5.01 valida e que a projecao publica entrega ao widget — nao um campo inventado para o teste.
  def inbox_com(mode)
    inbox = create(:inbox, account: account)
    inbox.update!(widget_tracking: mode.nil? ? {} : { 'consent_mode' => mode })
    inbox
  end

  # A conversa carrega o consentimento em `custom_attributes`, que e por onde o SDK o entrega
  # (`set-conversation-custom-attributes`, o mesmo evento de bridge que o 5.08 usa para a origem).
  def conversa_com(inbox, consent_attrs)
    conv = create(:conversation, account: account, inbox: inbox)
    conv.update!(custom_attributes: conv.custom_attributes.merge(consent_attrs),
                 additional_attributes: conv.additional_attributes.merge('browser' => { 'user_agent' => 'UA/1.0' }))
    conv
  end

  def evento(inbox:, conversation:, name: 'chatspx_lead')
    Tracking::EventRecorder.record!(
      name: name, account: account, inbox: inbox, conversation: conversation,
      contact: conversation.contact, properties: { 'value' => 350.0, 'currency' => 'BRL' },
      dedup_key: "c509-#{SecureRandom.hex(4)}", deliver: false
    )
  end

  describe 'o retrato junto do fato (T-C7.6)' do
    it 'grava em `consent` o estado vigente quando o fato acontece' do
      inbox = inbox_com('basic')

      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_concedido))

      expect(registro.consent).to eq(
        'ad_storage' => 'granted', 'ad_user_data' => 'granted',
        'ad_personalization' => 'granted', 'analytics_storage' => 'granted'
      )
    end

    # O CORACAO do bloco. Se o retrato fosse relido na entrega, aceitar as 15h04 reescreveria a base
    # legal do evento das 15h02 — e o registro passaria a afirmar um consentimento que nao existia
    # quando o dado saiu. Auditoria de LGPD pergunta pelo momento do tratamento, nao pelo de hoje.
    it 'NAO reescreve o retrato quando o visitante muda de ideia depois' do
      inbox = inbox_com('basic')
      conversa = conversa_com(inbox, tudo_negado)
      registro = evento(inbox: inbox, conversation: conversa)

      conversa.update!(custom_attributes: conversa.custom_attributes.merge(tudo_concedido))

      expect(registro.reload.consent['ad_user_data']).to eq('denied')
      expect(described_class.for_event(registro).granted?('ad_user_data')).to be(false)
    end

    # O CAMINHO DO `POST /api/v1/widget/events` (5.05/5.16): ele registra o fato com `contact:` e
    # SEM `conversation:` — ver `events_controller.rb`, que passa so o contato. Se o consentimento
    # morasse apenas na conversa, TODO evento dessa porta nasceria sem retrato e, com o modo ativo,
    # seria descartado como negado — inclusive o do visitante que ACEITOU. Falso negativo silencioso,
    # que e o defeito mais caro deste bloco: some conversao e ninguem ve erro.
    it 'resolve pelo CONTATO quando o fato nao tem conversa' do
      inbox = inbox_com('basic')
      contato = create(:contact, account: account)
      contato.update!(custom_attributes: tudo_concedido)

      registro = Tracking::EventRecorder.record!(
        name: 'chatspx_widget_opened', account: account, inbox: inbox,
        contact: contato, dedup_key: "c509-sem-conversa-#{SecureRandom.hex(4)}", deliver: false
      )

      expect(registro.consent['ad_user_data']).to eq('granted')
      expect(described_class.for_event(registro).granted?('ad_user_data')).to be(true)
    end

    it 'com o modo `disabled` nao inventa retrato — ausencia tem significado (regra A4)' do
      inbox = inbox_com(nil)

      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_concedido))

      expect(registro.consent).to eq({})
    end
  end

  describe 'GA4 Measurement Protocol — o campo `consent` (T-C7.4)' do
    it 'leva DENIED quando o visitante negou' do
      inbox = inbox_com('advanced')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      Tracking::Destinations::Ga4Mp.new(event: registro, settings: settings, http_client: client).deliver!

      expect(client.last_body[:consent]).to eq(ad_user_data: 'DENIED', ad_personalization: 'DENIED')
    end

    it 'leva GRANTED quando o visitante concedeu' do
      inbox = inbox_com('advanced')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_concedido))

      Tracking::Destinations::Ga4Mp.new(event: registro, settings: settings, http_client: client).deliver!

      expect(client.last_body[:consent]).to eq(ad_user_data: 'GRANTED', ad_personalization: 'GRANTED')
    end

    # O evento NEGADO ainda VAI para o GA4 — de proposito. E o desenho do Consent Mode: o ping chega
    # marcado como negado, o Google nao personaliza e modela o resto. Nao enviar apagaria do
    # relatorio do cliente uma visita que ele tem o direito de contar.
    it 'ainda ENVIA sob negativa, marcado — o GA4 modela, e nao personaliza' do
      inbox = inbox_com('advanced')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      resultado = Tracking::Destinations::Ga4Mp.new(event: registro, settings: settings, http_client: client).deliver!

      expect(resultado.status).to eq(:sent)
      expect(client.called?).to be(true)
    end

    # A GRAFIA e o defeito silencioso mais provavel desta junta: o navegador escreve `granted` e o
    # Measurement Protocol espera `GRANTED`. Um lado comparando com a grafia do outro nega tudo,
    # para sempre, sem erro nenhum.
    it 'traduz a grafia do navegador (`granted`) para a do MP (`GRANTED`)' do
      inbox = inbox_com('basic')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_concedido))

      expect(registro.consent['ad_user_data']).to eq('granted')
      expect(described_class.for_event(registro).ga4_value('ad_user_data')).to eq('GRANTED')
    end
  end

  describe 'destinos de anuncio — respeito ao estado (T-C7.4)' do
    it 'a CAPI da Meta NAO envia sob negativa, e o motivo e legivel no painel' do
      inbox = inbox_com('basic')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      resultado = Tracking::Destinations::MetaCapi.new(event: registro, settings: settings, http_client: client).deliver!

      expect(resultado.status).to eq(:skipped)
      expect(resultado.reason).to eq('consent_denied')
      expect(client.called?).to be(false)
    end

    it 'o Google Ads NAO envia sob negativa — mesma categoria de tratamento' do
      inbox = inbox_com('basic')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      resultado = Tracking::Destinations::GoogleAds.new(event: registro, settings: settings,
                                                        http_client: client).deliver!

      expect(resultado.status).to eq(:skipped)
      expect(resultado.reason).to eq('consent_denied')
      expect(client.called?).to be(false)
    end

    it 'a CAPI VOLTA a enviar quando o visitante concede' do
      inbox = inbox_com('basic')
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_concedido))

      resultado = Tracking::Destinations::MetaCapi.new(event: registro, settings: settings, http_client: client).deliver!

      expect(resultado.status).to eq(:sent)
      expect(client.called?).to be(true)
    end

    # Com o modo ativo, o SILENCIO e negativa. Sem este exemplo, um visitante de quem nunca se
    # perguntou nada seria tratado como quem disse sim — que e o defeito original com outra roupa.
    it 'sem nenhum registro de consentimento, o modo ativo trata como NEGADO' do
      inbox = inbox_com('basic')
      conversa = create(:conversation, account: account, inbox: inbox)

      registro = evento(inbox: inbox, conversation: conversa)
      resultado = Tracking::Destinations::MetaCapi.new(event: registro, settings: settings, http_client: client).deliver!

      expect(registro.consent).to eq({})
      expect(resultado.status).to eq(:skipped)
      expect(resultado.reason).to eq('consent_denied')
    end
  end

  # A TRAVA DE REGRESSAO. `disabled` e o valor de TODA inbox da frota hoje, porque a coluna nasceu
  # sem backfill. Se qualquer exemplo abaixo ficar vermelho, este bloco desligou a medicao de quem
  # nunca pediu consentimento — que seria um estrago maior que o defeito que ele conserta.
  describe 'modo `disabled` — o comportamento de HOJE, preservado' do
    it 'o GA4 sai GRANTED, byte a byte como antes do bloco' do
      inbox = inbox_com(nil)
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      Tracking::Destinations::Ga4Mp.new(event: registro, settings: settings, http_client: client).deliver!

      expect(client.last_body[:consent]).to eq(ad_user_data: 'GRANTED', ad_personalization: 'GRANTED')
    end

    it 'a CAPI envia mesmo com `denied` gravado na conversa — sem modo, sem gate' do
      inbox = inbox_com(nil)
      registro = evento(inbox: inbox, conversation: conversa_com(inbox, tudo_negado))

      resultado = Tracking::Destinations::MetaCapi.new(event: registro, settings: settings, http_client: client).deliver!

      expect(resultado.status).to eq(:sent)
    end
  end
end
