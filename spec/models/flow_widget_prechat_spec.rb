# frozen_string_literal: true

require 'rails_helper'

# 4.02 — o gatilho `widget_prechat` no modelo: o valor do enum (BK-21), a forma do `trigger_config`
# conferida por json_schemer (§10.2 N3) e o teto de 8 campos coletados (BK-23).
RSpec.describe Flow do
  let(:account) { create(:account) }

  def prechat(trigger_config: {}, definition: { 'nodes' => [], 'edges' => [] })
    build(:flow, account: account, trigger_type: :widget_prechat,
                 trigger_config: trigger_config, definition: definition)
  end

  describe 'o valor do enum' do
    it 'ocupa o inteiro 5, logo depois de external_webhook (4), sem migration' do
      expect(described_class.trigger_types['widget_prechat']).to eq(5)
      expect(described_class.trigger_types).to eq(
        'manual' => 0, 'conversation_event' => 1, 'schedule' => 2,
        'keyword' => 3, 'external_webhook' => 4, 'widget_prechat' => 5
      )
    end

    it 'nao gera token de webhook (o token e exclusivo do external_webhook)' do
      flow = prechat
      flow.save!

      expect(flow.reload.webhook_token).to be_nil
    end
  end

  describe 'a forma do trigger_config' do
    it 'aceita o contrato completo' do
      flow = prechat(trigger_config: {
                       'inbox_ids' => [1, 2],
                       'url_conditions' => [{ 'operator' => 'contains', 'value' => '/precos' }],
                       'match' => 'any',
                       'utm' => { 'utm_source' => 'google' },
                       'devices' => %w[mobile tablet],
                       'business_hours_only' => true,
                       'priority' => 10
                     })

      expect(flow).to be_valid
    end

    it 'recusa um operador de URL que nao existe, dizendo ONDE esta o erro' do
      flow = prechat(trigger_config: { 'url_conditions' => [{ 'operator' => 'regex', 'value' => '.*' }] })

      expect(flow).not_to be_valid
      expect(flow.errors[:trigger_config].join).to include('url_conditions/0/operator')
    end

    it 'recusa condicao de URL com chave inventada e priority fora da faixa' do
      operador = prechat(trigger_config: { 'url_conditions' => [{ 'operator' => 'contains', 'value' => 'x', 'flags' => 'i' }] })
      expect(operador).not_to be_valid

      prioridade = prechat(trigger_config: { 'priority' => 99_999 })
      expect(prioridade).not_to be_valid
      expect(prioridade.errors[:trigger_config].join).to include('priority')
    end

    it 'nao reprova chave de OUTRO gatilho que ficou no objeto ao trocar de trigger_type' do
      # Um fluxo que era `keyword` e virou `widget_prechat` chega carregando `keywords`. Reprovar
      # transformaria a troca de gatilho num 422 sobre dado que o proprio produto gravou.
      flow = prechat(trigger_config: { 'keywords' => %w[oi ola], 'webhook_token' => 'abc',
                                       'url_conditions' => [{ 'operator' => 'contains', 'value' => '/x' }] })

      expect(flow).to be_valid
    end

    it 'nao aplica o schema aos outros gatilhos' do
      flow = build(:flow, account: account, trigger_type: :keyword,
                          trigger_config: { 'url_conditions' => 'qualquer coisa' })

      expect(flow).to be_valid
    end
  end

  describe 'o teto de 8 campos coletados (BK-23)' do
    def capture_definition(fields)
      {
        'nodes' => Array.new(fields) { |i| { 'id' => "w#{i}", 'type' => 'wait_for_reply', 'replies' => [] } },
        'edges' => []
      }
    end

    it 'salva um fluxo de captura com 8 campos' do
      flow = prechat(definition: capture_definition(8))

      expect(flow.collected_fields_count).to eq(8)
      expect(flow).to be_valid
    end

    it 'RECUSA 9 campos, e o erro diz o numero encontrado e o teto' do
      flow = prechat(definition: capture_definition(9))

      expect(flow).not_to be_valid
      expect(flow.errors[:definition].join).to eq('fluxo de captura coleta 9 campos; o teto e 8')
      expect(flow.save).to be(false)
    end

    it 'conta tambem os campos de um no send_form — um formulario de 12 campos e 12 campos' do
      definition = {
        'nodes' => [{ 'id' => 'f', 'type' => 'action', 'action_name' => 'send_form',
                      'action_params' => [{ 'content' => 'Seus dados',
                                            'items' => Array.new(12) { |i| { 'name' => "campo#{i}" } } }] }],
        'edges' => []
      }
      flow = prechat(definition: definition)

      expect(flow.collected_fields_count).to eq(12)
      expect(flow).not_to be_valid
    end

    it 'nao aplica o teto a fluxos de outros gatilhos (nao e regra do motor, e do fluxo de captura)' do
      flow = build(:flow, account: account, trigger_type: :conversation_event,
                          definition: capture_definition(20))

      expect(flow).to be_valid
    end
  end
end
