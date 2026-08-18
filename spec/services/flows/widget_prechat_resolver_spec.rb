# frozen_string_literal: true

require 'rails_helper'

# 4.02 (BK-21) — o CONTRATO de resolucao, chave a chave. O aceite do bloco (dois fluxos, duas URLs,
# dois resultados) e medido de ponta a ponta em
# spec/controllers/api/v1/widget/prechat_flow_delivery_spec.rb; aqui ficam as regras finas: o que
# cada chave faz, o que acontece na AUSENCIA dela, e a ordem de desempate.
RSpec.describe Flows::WidgetPrechatResolver do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  def prechat_flow(config = {}, name: nil, active: true)
    create(:flow, account: account, active: active, trigger_type: :widget_prechat,
                  trigger_config: config, name: name || "Fluxo #{config.hash}")
  end

  def resolve(url: nil, browser: nil, on_inbox: inbox)
    described_class.new(account: account, inbox: on_inbox, url: url, browser: browser).perform
  end

  describe 'url_conditions' do
    it 'matches `contains` case-insensitively over the whole URL, querystring included' do
      flow = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/PRECOS' }] })

      expect(resolve(url: 'https://site.com.br/precos?x=1')).to eq(flow)
    end

    it 'supports equals, starts_with, ends_with and not_contains' do
      starts = prechat_flow({ 'url_conditions' => [{ 'operator' => 'starts_with', 'value' => 'https://loja.' }] })
      expect(resolve(url: 'https://loja.com.br/carrinho')).to eq(starts)

      starts.update!(active: false)
      ends = prechat_flow({ 'url_conditions' => [{ 'operator' => 'ends_with', 'value' => '/checkout' }] })
      expect(resolve(url: 'https://loja.com.br/checkout')).to eq(ends)

      ends.update!(active: false)
      exact = prechat_flow({ 'url_conditions' => [{ 'operator' => 'equals', 'value' => 'https://loja.com.br/' }] })
      expect(resolve(url: 'https://loja.com.br/')).to eq(exact)

      exact.update!(active: false)
      excluding = prechat_flow({ 'url_conditions' => [{ 'operator' => 'not_contains', 'value' => '/admin' }] })
      expect(resolve(url: 'https://loja.com.br/produtos')).to eq(excluding)
      expect(resolve(url: 'https://loja.com.br/admin/pedidos')).to be_nil
    end

    it 'requires ALL conditions by default and ANY when match is `any`' do
      todas = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => 'loja' },
                                                  { 'operator' => 'contains', 'value' => 'checkout' }] })
      expect(resolve(url: 'https://loja.com.br/checkout')).to eq(todas)
      expect(resolve(url: 'https://loja.com.br/carrinho')).to be_nil

      todas.update!(trigger_config: todas.trigger_config.merge('match' => 'any'))
      expect(resolve(url: 'https://loja.com.br/carrinho')).to eq(todas)
    end

    it 'treats a flow without url_conditions as catch-all — it matches even a conversation with no referer' do
      flow = prechat_flow({})

      expect(resolve(url: 'https://qualquer.com/pagina')).to eq(flow)
      expect(resolve(url: nil)).to eq(flow)
    end

    it 'does not match a URL-scoped flow when the conversation has no referer (except not_contains)' do
      prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })

      expect(resolve(url: nil)).to be_nil
    end
  end

  describe 'utm' do
    it 'requires every declared utm key to match, case-insensitively' do
      flow = prechat_flow({ 'utm' => { 'utm_source' => 'Google', 'utm_campaign' => 'black-friday' } })

      expect(resolve(url: 'https://site.com?utm_source=google&utm_campaign=BLACK-FRIDAY')).to eq(flow)
      expect(resolve(url: 'https://site.com?utm_source=google')).to be_nil
      expect(resolve(url: 'https://site.com')).to be_nil
    end
  end

  describe 'devices' do
    it 'classifies the visitor from the browser attributes the widget already records' do
      mobile = prechat_flow({ 'devices' => ['mobile'] })

      expect(resolve(url: 'https://site.com', browser: { 'device_name' => 'iPhone', 'platform_name' => 'iOS' })).to eq(mobile)
      expect(resolve(url: 'https://site.com', browser: { 'device_name' => 'Unknown', 'platform_name' => 'Windows' })).to be_nil
      # iPad casa tablet e mobile: a categoria mais especifica vence, entao NAO entrega o de mobile.
      expect(resolve(url: 'https://site.com', browser: { 'device_name' => 'iPad', 'platform_name' => 'iOS' })).to be_nil
    end

    it 'never matches a device-scoped flow when the browser was not recorded' do
      prechat_flow({ 'devices' => %w[mobile desktop tablet] })

      expect(resolve(url: 'https://site.com', browser: nil)).to be_nil
    end
  end

  describe 'inbox_ids' do
    it 'limits the flow to the declared inboxes and, when absent, serves any website inbox' do
      other_widget = create(:channel_widget, account: account)
      escopado = prechat_flow({ 'inbox_ids' => [other_widget.inbox.id] })

      expect(resolve(url: 'https://site.com')).to be_nil
      expect(resolve(url: 'https://site.com', on_inbox: other_widget.inbox)).to eq(escopado)

      escopado.update!(trigger_config: {})
      expect(resolve(url: 'https://site.com')).to eq(escopado)
    end
  end

  describe 'tie-break (a ordem publicada no contrato)' do
    it '1. priority declarada pelo admin vence a especificidade' do
      especifico = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })
      catch_all = prechat_flow({ 'priority' => 10 })

      expect(resolve(url: 'https://site.com/precos')).to eq(catch_all)
      expect(especifico.reload).to be_active # segue ativo, so perdeu o desempate
    end

    it '2. com a mesma priority, o mais ESPECIFICO vence o catch-all' do
      catch_all = prechat_flow({})
      especifico = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }] })

      expect(resolve(url: 'https://site.com/precos')).to eq(especifico)
      expect(resolve(url: 'https://site.com/blog')).to eq(catch_all)
    end

    it '3. empate total: o MAIS ANTIGO vence — criar um fluxo novo nao rouba o trafego do que ja estava no ar' do
      antigo = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => 'site.com' }] }, name: 'antigo')
      novo = prechat_flow({ 'url_conditions' => [{ 'operator' => 'contains', 'value' => 'site.com' }] }, name: 'novo')

      expect(novo.id).to be > antigo.id
      expect(resolve(url: 'https://site.com/x')).to eq(antigo)
    end
  end

  describe 'guardas' do
    it 'ignores inactive flows and flows of another trigger_type' do
      prechat_flow({}, active: false)
      create(:flow, account: account, trigger_type: :keyword, trigger_config: { 'keywords' => ['oi'] })

      expect(resolve(url: 'https://site.com')).to be_nil
    end

    it 'returns nil instead of raising when a trigger_config is malformed' do
      flow = prechat_flow({})
      flow.update_column(:trigger_config, { 'url_conditions' => 'nao-e-array' }) # rubocop:disable Rails/SkipsModelValidations

      expect(resolve(url: 'https://site.com')).to be_nil
    end
  end
end
