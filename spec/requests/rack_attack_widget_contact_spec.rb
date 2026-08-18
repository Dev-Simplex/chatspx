require 'rails_helper'

# BLOCO 1.12 — o throttle de escrita de contato do widget nunca casava.
#
# A regra comparava o path com '/api/v1/widget/contacts' (plural), mas a rota e
# `resource :contact` (singular, config/routes.rb:643) — logo o path real e
# '/api/v1/widget/contact'. A comparacao era sempre falsa e o limite de 60/hora
# nunca chegou a existir na pratica.
#
# ARMADILHA DESTE ARQUIVO: o Rack::Attack tem safelist para 127.0.0.1
# (rack_attack.rb:28-31,49). Request spec roda como 127.0.0.1 por padrao, ou
# seja, um teste ingenuo passa verde sem NUNCA exercitar o throttle. Por isso
# todo request daqui carrega um REMOTE_ADDR fora da safelist.
RSpec.describe 'Rack::Attack — throttle de escrita de contato do widget', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end
  # IP de cliente real, fora da safelist. Com 127.0.0.1 o request nem chega no throttle.
  let(:client_ip) { '203.0.113.77' }
  let(:headers) { { 'X-Auth-Token' => token, 'REMOTE_ADDR' => client_ip } }

  around do |example|
    previous_store = Rack::Attack.cache.store
    previous_enabled = Rack::Attack.enabled
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    example.run
  ensure
    Rack::Attack.enabled = previous_enabled
    Rack::Attack.cache.store = previous_store
  end

  def patch_contact(path, ip: client_ip)
    patch path,
          params: { website_token: web_widget.website_token, custom_attributes: { visitas: 1 } },
          headers: headers.merge('REMOTE_ADDR' => ip),
          as: :json
    response.status
  end

  describe 'PATCH /api/v1/widget/contact' do
    it 'deixa passar as 60 primeiras e bloqueia a 61a chamada do mesmo IP' do
      statuses = Array.new(60) { patch_contact('/api/v1/widget/contact') }

      expect(statuses.count(429)).to eq(0)
      expect(patch_contact('/api/v1/widget/contact')).to eq(429)
    end

    it 'nao bloqueia um IP diferente que ainda nao gastou a cota' do
      60.times { patch_contact('/api/v1/widget/contact') }
      expect(patch_contact('/api/v1/widget/contact')).to eq(429)

      expect(patch_contact('/api/v1/widget/contact', ip: '198.51.100.9')).not_to eq(429)
    end
  end

  describe 'PATCH /api/v1/widget/contact/set_user' do
    it 'conta no mesmo balde: 60 updates gastam a cota e o set_user seguinte e bloqueado' do
      60.times { patch_contact('/api/v1/widget/contact') }

      expect(patch_contact('/api/v1/widget/contact/set_user')).to eq(429)
    end

    it 'sozinho, bloqueia na 61a chamada' do
      statuses = Array.new(60) { patch_contact('/api/v1/widget/contact/set_user') }

      expect(statuses.count(429)).to eq(0)
      expect(patch_contact('/api/v1/widget/contact/set_user')).to eq(429)
    end
  end

  describe 'safelist de localhost' do
    it 'confirma que 127.0.0.1 NAO exercita o throttle (por isso o teste usa IP real)' do
      statuses = Array.new(61) { patch_contact('/api/v1/widget/contact', ip: '127.0.0.1') }

      expect(statuses.count(429)).to eq(0)
    end
  end
end
