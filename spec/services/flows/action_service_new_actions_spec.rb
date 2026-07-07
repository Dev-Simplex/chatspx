require 'rails_helper'

RSpec.describe Flows::ActionService do
  let(:account) { create(:account) }
  let(:flow) { create(:flow, account: account) }

  after { Current.reset }

  def action(name, params)
    { 'type' => 'action', 'action_name' => name, 'action_params' => params }
  end

  describe '#send_template (gap-BR P0)' do
    let(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:conversation) { create(:conversation, account: account, inbox: whatsapp_channel.inbox) }
    let(:template) { { 'name' => 'test_no_params_template', 'language' => 'en', 'content' => 'Olá!', 'processed_params' => {} } }

    it 'creates an outgoing message carrying template_params for an approved template' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('send_template', [template])) }.to change(Message, :count).by(1)
      expect(Message.last.additional_attributes['template_params']).to include('name' => 'test_no_params_template', 'language' => 'en')
    end

    it 'carries the flow_id anti-loop marker in automation mode' do
      described_class.new(flow: flow, conversation: conversation).execute(action('send_template', [template]))
      expect(Message.last.content_attributes['flow_id']).to eq(flow.id)
    end

    it 'is a silent no-op when the template is not approved (padrão add_sla)' do
      service = described_class.new(flow: flow, conversation: conversation)
      unknown = template.merge('name' => 'nonexistent_template')
      expect { service.execute(action('send_template', [unknown])) }.not_to change(Message, :count)
    end

    it 'is a silent no-op when the inbox is not whatsapp_cloud' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      service = described_class.new(flow: flow, conversation: other)
      expect { service.execute(action('send_template', [template])) }.not_to change(Message, :count)
    end

    it 'works when no display content is provided (template-only)' do
      service = described_class.new(flow: flow, conversation: conversation)
      expect { service.execute(action('send_template', [template.except('content')])) }.to change(Message, :count).by(1)
    end

    it 'does not send in manual mode either — pipeline stays the same, authored by the actor' do
      agent = create(:user, account: account)
      service = described_class.new(flow: flow, conversation: conversation, actor: agent)
      service.execute(action('send_template', [template]))
      expect(Message.last.sender).to eq(agent)
      expect(Message.last.content_attributes['flow_id']).to be_nil
    end
  end

  describe '#set_attribute' do
    let(:conversation) { create(:conversation, account: account) }

    it 'writes a custom attribute on the conversation' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'key' => 'lead_score', 'value' => 'quente' }]))
      expect(conversation.reload.custom_attributes['lead_score']).to eq('quente')
    end

    it 'writes an additional attribute when store is additional' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute',
                                     [{ 'target' => 'conversation', 'store' => 'additional', 'key' => 'origem', 'value' => 'anuncio' }]))
      expect(conversation.reload.additional_attributes['origem']).to eq('anuncio')
    end

    it 'writes on the contact when target is contact' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'contact', 'key' => 'vip', 'value' => 'true' }]))
      expect(conversation.contact.reload.custom_attributes['vip']).to eq('true')
    end

    it 'resolves Liquid in the value' do
      conversation.contact.update!(name: 'Maria')
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'key' => 'saudacao', 'value' => 'Oi {{contact.name}}' }]))
      expect(conversation.reload.custom_attributes['saudacao']).to eq('Oi Maria')
    end

    it 'is a no-op when key is blank' do
      described_class.new(flow: flow, conversation: conversation)
                     .execute(action('set_attribute', [{ 'target' => 'conversation', 'value' => 'x' }]))
      expect(conversation.reload.custom_attributes).to eq({})
    end
  end
end
