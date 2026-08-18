# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Instagram do
  let(:channel) { create(:channel_instagram) }

  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:instagram_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  it 'has a valid name' do
    expect(channel.name).to eq('Instagram')
  end

  describe '#subscribe' do
    let(:base_fields) { described_class::BASE_WEBHOOK_FIELDS }
    let(:extra_fields) { described_class::BASE_WEBHOOK_FIELDS + ['messaging_postbacks'] }

    # Cria o canal (e consome a assinatura do after_create_commit) antes de qualquer
    # stub/config do exemplo, pra medir só a chamada explícita.
    before { channel }

    def stub_subscription(fields, status:)
      stub_request(:post, "https://graph.instagram.com/v22.0/#{channel.instagram_id}/subscribed_apps")
        .with(query: { access_token: channel.access_token, subscribed_fields: fields })
        .to_return(status: status, body: '', headers: {})
    end

    it 'subscribes only the mandatory fields when no extra field is configured' do
      request = stub_subscription(base_fields, status: 200)

      expect(channel.subscribe).to be(true)
      expect(request).to have_been_requested.at_least_once
    end

    it 'reports failure instead of swallowing it when the mandatory fields are refused' do
      stub_subscription(base_fields, status: 400)
      allow(Rails.logger).to receive(:error)

      expect(channel.subscribe).to be(false)
      expect(Rails.logger).to have_received(:error).with(/assinatura recusada/)
    end

    context 'when an extra field is configured for the installation' do
      # `update!`, e não `first_or_create(value:)`: o ConfigLoader já semeia a chave sem
      # valor no boot, e o create não roda numa linha que existe. O clear_cache é explícito
      # porque a criação do canal, acima, já consultou a chave e deixou o "vazio" cacheado —
      # em produção quem invalida é o commit do super_admin.
      before do
        InstallationConfig.where(name: 'INSTAGRAM_WEBHOOK_EXTRA_FIELDS').first_or_create!.update!(value: 'messaging_postbacks')
        GlobalConfig.clear_cache
      end

      after { GlobalConfig.clear_cache }

      it 'subscribes the mandatory fields plus the extra one' do
        request = stub_subscription(extra_fields, status: 200)

        expect(channel.subscribe).to be(true)
        expect(request).to have_been_requested.at_least_once
      end

      # A chamada leva a lista inteira: um campo que o app daquela box não tem derruba tudo e o
      # canal ficaria SEM assinatura nenhuma — o DM morre em silêncio. O extra tem que ser
      # descartável, e a recusa tem que aparecer no log.
      it 'falls back to the mandatory fields when the extra one is refused' do
        stub_subscription(extra_fields, status: 400)
        fallback = stub_subscription(base_fields, status: 200)
        allow(Rails.logger).to receive(:error)

        expect(channel.subscribe).to be(true)
        expect(fallback).to have_been_requested.at_least_once
        expect(Rails.logger).to have_received(:error).with(/assinatura recusada/)
      end
    end
  end

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for instagram' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:instagram_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end
end
