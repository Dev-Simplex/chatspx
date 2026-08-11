# frozen_string_literal: true

require 'rails_helper'

# Kanban tempo real (Fase 1.2) — trava DOIS contratos que, se separarem, geram
# bug silencioso:
#
#   1. `FunnelItem#push_event_data` (card vindo do websocket) tem que ser um
#      SUPERCONJUNTO de `api/v1/models/_funnel_item.json.jbuilder` (card vindo do
#      GET), menos `last_message` — que fica de fora de propósito para não meter
#      query no caminho síncrono do arraste. Campo que exista só num dos dois vira
#      card "meio desenhado" dependendo de como ele chegou na tela.
#
#   2. O payload é 100% tipo JSON nativo. Ele vira argumento de Sidekiq
#      (ActionCableBroadcastJob) e, sob `strict_args`, BigDecimal / Time /
#      ActiveRecord / Symbol fora de chave são rejeitados em runtime — longe
#      daqui, dentro da fila `:critical`.
RSpec.describe FunnelItem do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }
  let(:contact) { create(:contact, account: account, name: 'Fulano', phone_number: '+5566999998888') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent, priority: :high)
  end
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:stage) { FunnelStage.create!(funnel: funnel, name: 'Aberto', position: 0) }
  let(:label) { create(:label, account: account, title: 'urgente', color: '#ff0000') }

  let(:funnel_item) do
    described_class.create!(funnel: funnel, funnel_stage: stage, conversation: conversation, moved_at: Time.current, position: 3)
  end

  before do
    conversation.update_labels([label.title])
    conversation.update!(custom_attributes: { "funnel_#{funnel.id}_valor" => '1000', 'outro_integrador' => 'nao vaza' })
  end

  def rendered_partial(item)
    JSON.parse(
      ApplicationController.render(
        partial: 'api/v1/models/funnel_item',
        formats: [:json],
        locals: { resource: item }
      )
    )
  end

  def payload(item)
    item.push_event_data(label_colors: { label.title.downcase => label.color }).deep_stringify_keys
  end

  describe 'sincronia com o partial jbuilder' do
    it 'cobre todas as chaves de topo do partial' do
      expect(rendered_partial(funnel_item).keys - payload(funnel_item).keys).to be_empty
    end

    # `last_message` só sai do partial quando o controller populou
    # @last_messages_by_conversation_id, então aqui a lista pode vir vazia; o que
    # importa é que NADA além dele fique de fora.
    it 'cobre as chaves da conversa, exceto last_message (fora do broadcast de propósito)' do
      missing = rendered_partial(funnel_item)['conversation'].keys - payload(funnel_item)['conversation'].keys
      expect(missing - ['last_message']).to be_empty
    end

    it 'não carrega last_message (evita query extra no caminho síncrono do arraste)' do
      expect(funnel_item.push_event_data[:conversation]).not_to have_key(:last_message)
    end

    it 'cobre as chaves do contato' do
      partial_contact = rendered_partial(funnel_item)['conversation']['contact']
      expect(partial_contact.keys - payload(funnel_item)['conversation']['contact'].keys).to be_empty
    end

    it 'cobre as chaves do responsável do cartão de tarefa' do
      task = described_class.create!(funnel: funnel, funnel_stage: stage, title: 'Ligar para o cliente', assignee: agent)
      expect(rendered_partial(task).keys - payload(task).keys).to be_empty
      expect(rendered_partial(task)['assignee'].keys - payload(task)['assignee'].keys).to be_empty
    end
  end

  describe 'conteúdo' do
    it 'traz a etiqueta com a cor resolvida' do
      expect(payload(funnel_item)['conversation']['labels']).to eq([{ 'title' => 'urgente', 'color' => '#ff0000' }])
    end

    it 'cai na cor default quando o título não está no mapa' do
      expect(funnel_item.push_event_data[:conversation][:labels]).to eq([{ title: 'urgente', color: '#94a3b8' }])
    end

    it 'só expõe os custom attributes deste funil' do
      expect(payload(funnel_item)['conversation']['custom_attributes']).to eq("funnel_#{funnel.id}_valor" => '1000')
    end

    it 'marca o cartão de tarefa e dispensa a conversa' do
      task = described_class.create!(funnel: funnel, funnel_stage: stage, title: 'Tarefa avulsa')
      expect(task.push_event_data).to include(is_task: true, title: 'Tarefa avulsa', conversation: nil)
    end
  end

  describe 'tipos aceitos pelo Sidekiq (strict_args)' do
    # Mesma lista que o ActiveJob aceita sem serializador customizado.
    def assert_json_native(value, path)
      case value
      when Hash
        value.each { |k, v| assert_json_native(v, "#{path}.#{k}") }
      when Array
        value.each_with_index { |v, i| assert_json_native(v, "#{path}[#{i}]") }
      when NilClass, String, Integer, Float, TrueClass, FalseClass
        nil
      else
        raise "#{path} é #{value.class} — tipo não-JSON no payload do broadcast"
      end
    end

    it 'não deixa passar BigDecimal, Time nem objeto ActiveRecord' do
      expect { assert_json_native(payload(funnel_item), 'payload') }.not_to raise_error
    end

    it 'manda position como Float e os tempos como ISO 8601' do
      data = funnel_item.push_event_data
      expect(data[:position]).to be_a(Float)
      expect(data[:moved_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
      expect(data[:conversation][:last_activity_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it 'sobrevive a JSON.generate' do
      expect { JSON.generate(funnel_item.push_event_data) }.not_to raise_error
    end
  end
end
