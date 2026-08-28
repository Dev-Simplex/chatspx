require 'rails_helper'

# O teto de TAMANHO do bloco 1.14 so enxergava String e Integer no TOPO do hash.
# Valor ANINHADO passava inteiro: pela rota real do widget, 10 PATCH de
# {"bag" => {...100 KB}} devolviam 200 e terminavam com 1.000.129 bytes no jsonb
# do contato — sem nenhuma validacao reclamar. O controle que ja funcionava
# (string de 1501 no topo -> 422) esta aqui junto, para separar "o teto existe"
# de "o teto enxerga o que cresce".
RSpec.describe 'teto de custom_attributes do contato, pela rota do widget', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  # ~101 KB num PATCH so, todos os valores abaixo do teto de 1500 por string:
  # nenhuma das regras antigas morde nisto.
  def nested_bag
    (1..100).to_h { |index| ["chave_#{index}", 'a' * 1000] }
  end

  def patch_custom_attributes(custom_attributes)
    patch '/api/v1/widget/contact',
          params: { website_token: web_widget.website_token, custom_attributes: custom_attributes },
          headers: { 'X-Auth-Token' => token },
          as: :json
  end

  describe 'PATCH /api/v1/widget/contact com valor aninhado' do
    it 'recusa o payload aninhado e o jsonb nao cresce', :aggregate_failures do
      statuses = (1..10).map do |round|
        patch_custom_attributes("bag_#{round}" => nested_bag)
        response.status
      end
      bytes_gravados = contact.reload.custom_attributes.to_json.bytesize

      expect(statuses).to eq([422] * 10)
      expect(bytes_gravados).to be <= 65_536
      expect(contact.custom_attributes.keys).to eq([])
    end

    it 'nomeia o motivo no corpo da resposta' do
      patch_custom_attributes('bag' => nested_bag)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('total size should be at most 65536 bytes')
    end

    it 'recusa aninhamento acima do teto de profundidade' do
      patch_custom_attributes('a' => { 'b' => { 'c' => { 'd' => 1 } } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('nesting should be at most 3 levels deep (got 4)')
      expect(contact.reload.custom_attributes).to eq({})
    end
  end

  describe 'os caminhos que nao podem ter quebrado' do
    it 'controle positivo: payload normal continua gravando com 200' do
      patch_custom_attributes('plano' => 'ouro', 'itens' => %w[a b])

      expect(response).to have_http_status(:success)
      expect(contact.reload.custom_attributes).to eq('plano' => 'ouro', 'itens' => %w[a b])
    end

    it 'controle: string de 1501 no topo ja era recusada antes e continua' do
      patch_custom_attributes('bio' => 'a' * 1501)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(contact.reload.custom_attributes).to eq({})
    end

    it 'acumula PATCH sucessivos enquanto cabe no teto' do
      patch_custom_attributes('primeira' => 'a' * 1000)
      patch_custom_attributes('segunda' => 'b' * 1000)

      expect(response).to have_http_status(:success)
      expect(contact.reload.custom_attributes.keys.sort).to eq(%w[primeira segunda])
    end
  end
end
