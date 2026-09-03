require 'rails_helper'
require_relative '../../services/tracking/fake_http_client'

# A JUNTA, de ponta a ponta: credencial gravada no cofre -> resolver -> leque -> job -> fio.
#
# TODO o resto da suite desta trilha dubla o resolver (`allow(Tracking::CredentialResolver).to
# receive(:call)`), o que e legitimo para testar backoff e DLQ isoladamente — mas deixa um buraco
# exato: nenhum exemplo provava que uma credencial REAL produz uma entrega. Enquanto o resolver
# devolvia `nil` fixo, a fila inteira estava inerte e a suite ficava verde do mesmo jeito.
#
# Por isso aqui NADA e dublado alem do cliente HTTP: o `TrackingCredential` e gravado, o
# `widget_tracking` e gravado, e o que se mede e o POST que chega ao dublê.
RSpec.describe 'A fila de tracking ligada ao cofre de credenciais', type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # Contato COM e-mail e telefone de proposito: e o controle do modo sem PII la embaixo. Com um
  # contato vazio, "nao vazou e-mail" seria verdade por ausencia de e-mail.
  let(:contact) { create(:contact, account: account, email: 'visitante@exemplo.com', phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:meta_token) { 'EAAtoken-da-junta-que-nao-pode-vazar-4321' }
  let(:ga4_secret) { 'ga4-secret-da-junta-8765' }
  let(:client) { FakeHttpClient.new(status: 200) }

  def record_event(dedup_key)
    Tracking::EventRecorder.record!(name: 'chatspx_lead', account: account, inbox: inbox,
                                    conversation: conversation, contact: contact,
                                    dedup_key: dedup_key, deliver: false)
  end

  def configure_credential!
    inbox.update!(additional_attributes: inbox.additional_attributes.to_h.merge(
      'widget_tracking' => { 'meta_pixel_id' => '99887766', 'ga4_measurement_id' => 'G-JUNTA123' }
    ))
    create(:tracking_credential, account: account, inbox: inbox,
                                 meta_access_token: meta_token, ga4_api_secret: ga4_secret)
  end

  def call_to(url_fragment)
    client.calls.find { |call| call[:url].include?(url_fragment) }
  end

  before do
    # As fixtures nascem AQUI, fora de qualquer `perform_enqueued_jobs`: criar contato dentro do
    # bloco faria o job de avatar rodar inline e bater no WebMock.
    conversation
    allow(Tracking::HttpClient).to receive(:new).and_return(client)
  end

  describe 'com credencial gravada — a prova pelo POSITIVO' do
    before do
      configure_credential!
      clear_enqueued_jobs
    end

    it 'entrega a Meta com o pixel da inbox e o token do cofre' do
      evento = record_event('junta-meta')

      perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }

      chamada = call_to('graph.facebook.com')
      expect(chamada).to be_present
      expect(chamada[:url]).to include('/99887766/events')
      expect(chamada[:query][:access_token]).to eq(meta_token)
      expect(evento.tracking_deliveries.find_by(destination: :meta_capi))
        .to have_attributes(status: 'sent', http_status: 200, attempts: 1)
    end

    it 'entrega ao GA4 com o measurement id da inbox e o api secret do cofre' do
      evento = record_event('junta-ga4')

      perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }

      chamada = call_to('google-analytics.com')
      expect(chamada).to be_present
      expect(chamada[:query]).to include(measurement_id: 'G-JUNTA123', api_secret: ga4_secret)
      expect(evento.tracking_deliveries.find_by(destination: :ga4_mp)).to have_attributes(status: 'sent')
    end

    # A fronteira do Google Ads: o `customer_id`, o `conversion_action_id` e o `access_token` nao tem
    # fonte enquanto o OAuth do 5.02(b) nao existir. O destino fica FORA do leque em vez de montar um
    # payload que a API recusaria — e a ausencia e afirmada aqui, ao lado das duas presencas acima,
    # senao ela se confundiria com a fila inerte.
    it 'nao enfileira o Google Ads, cujo OAuth ainda nao existe' do
      evento = record_event('junta-leque')

      destinos = Tracking::DeliveryDispatcher.call(evento)

      expect(destinos).to contain_exactly(:meta_capi, :ga4_mp)
      expect(evento.tracking_deliveries.pluck(:destination)).to contain_exactly('meta_capi', 'ga4_mp')
    end
  end

  # O PAR do bloco acima. Sozinho, este exemplo passaria tambem com o resolver quebrado — e passava,
  # ate agora. Ele so mede alguma coisa porque os exemplos acima provam que o MESMO cenario com
  # credencial entrega.
  describe 'sem credencial gravada — o negativo, que so vale acompanhado do positivo' do
    it 'nao reserva, nao enfileira e nao toca o fio' do
      evento = record_event('junta-sem-cofre')
      clear_enqueued_jobs

      expect { perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) } }
        .not_to change(TrackingDelivery, :count)
      expect(client.called?).to be(false)
    end

    it 'e uma entrega ja reservada fica skipped, sem gastar tentativa' do
      evento = record_event('junta-sem-cofre-2')
      entrega = evento.claim_delivery(:meta_capi)

      Tracking::MetaCapiDeliveryJob.perform_now(entrega.id)

      expect(entrega.reload).to have_attributes(status: 'skipped', error_code: 'not_configured', attempts: 0)
      expect(client.called?).to be(false)
    end
  end

  describe 'o segredo nao aparece em log, em erro nem na DLQ' do
    let(:client) { FakeHttpClient.new(status: 400, body: { 'error' => { 'message' => 'Invalid parameter' } }) }

    before do
      configure_credential!
      clear_enqueued_jobs
    end

    it 'a entrega morta guarda destino, status e motivo — e nenhum valor de credencial' do
      evento = record_event('junta-dlq')

      perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }

      entrega = evento.tracking_deliveries.find_by(destination: :meta_capi).reload
      # OS CONTROLES: o segredo REALMENTE viajou nesta requisicao, e a linha REALMENTE guardou erro e
      # nomes de campo. Sem eles, os `not_to include` abaixo passariam sobre uma linha vazia.
      expect(call_to('graph.facebook.com')[:query][:access_token]).to eq(meta_token)
      expect(entrega).to have_attributes(status: 'dead', http_status: 400)
      expect(entrega.error_message).to be_present

      expect(entrega.attributes.to_json).not_to include(meta_token)
      expect(entrega.attributes.to_json).not_to include(ga4_secret)
    end

    it 'o log da fila carrega o id da entrega, nunca o segredo' do
      evento = record_event('junta-log')
      saida = StringIO.new
      logger = ActiveSupport::Logger.new(saida)

      # Os DOIS loggers, e nao so o do ActiveJob: um `Rails.logger.error` posto no meio do destino
      # para "melhorar o diagnostico" escaparia de uma captura que so olhasse um deles.
      begin
        anterior = ActiveJob::Base.logger
        ActiveJob::Base.logger = logger
        allow(Rails).to receive(:logger).and_return(logger)
        perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }
      ensure
        ActiveJob::Base.logger = anterior
      end

      entrega = evento.tracking_deliveries.find_by(destination: :meta_capi)
      # O CONTROLE: o log capturou o trabalho desta entrega. Sem ele, um logger que nao gravou nada
      # passaria no `not_to include` com folga.
      expect(saida.string).to include('Tracking::MetaCapiDeliveryJob', entrega.id.to_s)
      expect(saida.string).not_to include(meta_token)
      expect(saida.string).not_to include(ga4_secret)
    end
  end

  describe 'ligar o cofre NAO ligou a PII' do
    before do
      configure_credential!
      clear_enqueued_jobs
    end

    it 'a trava do 5.12 continua fechada por construcao' do
      expect(Tracking::PiiPolicy::DPA_SIGNED).to be(false)
    end

    it 'o corpo entregue nao leva e-mail nem telefone do contato que os tem' do
      evento = record_event('junta-sem-pii')

      perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }

      entrega = evento.tracking_deliveries.find_by(destination: :meta_capi).reload
      # O CONTROLE que o proprio modelo documenta: a base TINHA `em` e `ph` e os reteve. Sem esta
      # linha, "nao vazou e-mail" seria verdade tambem para um contato sem e-mail.
      expect(entrega.suppressed_field_names).to include('em', 'ph')
      expect(entrega.field_names).not_to include('em', 'ph', 'fn', 'ln')
      expect(call_to('graph.facebook.com')[:body].to_json).not_to include('visitante@exemplo.com', '+5511999990000')
    end

    # A entrega BEM SUCEDIDA e a unica que grava `field_names` — a morta guarda so status e motivo.
    # Entao e aqui que se prova que o log de auditoria carrega NOMES, e nenhum valor de credencial.
    it 'o log de auditoria da entrega guarda nomes de campo, nunca o token' do
      evento = record_event('junta-auditoria')

      perform_enqueued_jobs { Tracking::DeliveryDispatcher.call(evento) }

      entrega = evento.tracking_deliveries.find_by(destination: :meta_capi).reload
      # O CONTROLE: a lista existe e tem os nomes do payload real.
      expect(entrega.field_names).to include('event_id', 'user_data')
      expect(entrega.field_names.to_json).not_to include(meta_token)
      expect(entrega.attributes.to_json).not_to include(meta_token, ga4_secret)
    end
  end
end
