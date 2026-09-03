# frozen_string_literal: true

require 'rails_helper'

# 6.05 — o A/B DENTRO da resolucao do 4.02. O que se prova aqui e a fronteira: o
# experimento redistribui trafego entre fluxos que o desempate ja considerava elegiveis, e
# nao mexe em NADA para quem nao declara experimento (que e toda a frota hoje).
RSpec.describe Flows::WidgetPrechatResolver do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }

  before do
    web_widget.update!(pre_chat_form_enabled: true,
                       pre_chat_form_options: web_widget.pre_chat_form_options.merge('mode' => 'flow'))
  end

  def prechat_flow(config = {})
    create(:flow, account: account, trigger_type: :widget_prechat, trigger_config: config)
  end

  def variante(key, extra = {})
    prechat_flow(extra.merge('experiment' => { 'key' => key }))
  end

  def resolve(visitor_key:, url: nil)
    described_class.new(account: account, inbox: inbox, url: url, visitor_key: visitor_key).perform
  end

  describe 'a flow that declares no experiment' do
    it 'is resolved exactly as before — the tie-break decides alone' do
      antigo = prechat_flow({ 'priority' => 5 })
      prechat_flow({ 'priority' => 1 })

      expect(resolve(visitor_key: 'visitante-1')).to eq(antigo)
      expect(resolve(visitor_key: 'visitante-2')).to eq(antigo)
    end
  end

  describe 'two variants of the same experiment' do
    let!(:a) { variante('checkout') }
    let!(:b) { variante('checkout') }

    it 'shows the same visitor the same variant across separate resolutions' do
      primeira = resolve(visitor_key: 'visitante-fixo')
      segunda = resolve(visitor_key: 'visitante-fixo')
      terceira = resolve(visitor_key: 'visitante-fixo')

      expect([segunda, terceira]).to eq([primeira, primeira])
    end

    it 'sends traffic to BOTH variants — which is what makes it a test' do
      escolhidos = (1..120).map { |n| resolve(visitor_key: "visitante-#{n}")&.id }

      expect(escolhidos.uniq.sort).to eq([a.id, b.id].sort)
    end

    it 'falls back to the 4.02 winner, and never to a coin toss, when the visitor has no key' do
      escolhas = Array.new(10) { resolve(visitor_key: nil) }

      # O desempate do 4.02 com tudo empatado elege o MAIS ANTIGO, e ele nao varia.
      expect(escolhas.uniq).to eq([a])
    end
  end

  describe 'the boundary with the 4.02 tie-break' do
    it 'never promotes a variant that the URL rules had already excluded' do
      de_precos = variante('checkout', 'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }])
      catch_all = variante('checkout')

      # Todo visitante numa URL que so casa o catch-all recebe o catch-all: a variante de
      # /precos nem entra no sorteio, porque ela nao era elegivel para esta pagina.
      escolhidos = (1..40).map { |n| resolve(visitor_key: "v-#{n}", url: 'https://site.com/blog') }

      expect(escolhidos.uniq).to eq([catch_all])
      expect(escolhidos).not_to include(de_precos)
    end

    it 'keeps a non-experiment flow with higher priority winning over the experiment entirely' do
      chefe = prechat_flow({ 'priority' => 10 })
      variante('checkout')
      variante('checkout')

      expect((1..30).map { |n| resolve(visitor_key: "v-#{n}") }.uniq).to eq([chefe])
    end
  end
end
