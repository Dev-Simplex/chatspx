# frozen_string_literal: true

require 'rails_helper'

# Bloco 1.20, asserção (5): `referer_raw` é dado CRU de visitante — a URL que nem escapando
# validou. Ele existe para diagnóstico, não para consumo. Não pode entrar no prompt da IA.
#
# O caminho é único e está mapeado: `RunnerStateHelper#build_conversation_state` copia
# `additional_attributes` inteiro para o state, e `enterprise/lib/captain/prompts/snippets/
# conversation.liquid` itera o hash inteiro dentro do system prompt. Sem filtro, o valor cru
# entraria literalmente no prompt.
#
# O `referer_raw` aqui não é escrito à mão: ele é produzido pelo caminho real de 1.20 (gravar uma
# conversa com URL que não valida), para o teste não espelhar a implementação.
RSpec.describe Captain::Assistant::RunnerStateHelper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:valor_cru) { 'javascript:alert(document.cookie)' }

  def state_para(conversation)
    Captain::Assistant::AgentRunnerService
      .new(assistant: assistant, conversation: conversation.reload)
      .send(:build_state)
  end

  context 'when the conversation carries a URL that did not validate (referer_raw set)' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact).tap do |conv|
        conv.update!(additional_attributes: { 'referer' => valor_cru })
      end
    end

    it 'o banco realmente guardou o valor cru (senão o resto do teste é vazio)' do
      atributos = Conversation.where(id: conversation.id).pick(:additional_attributes)

      expect(atributos['referer']).to be_nil
      expect(atributos['referer_raw']).to eq(valor_cru)
    end

    it 'remove referer_raw do state da conversa' do
      expect(state_para(conversation)[:conversation][:additional_attributes]).not_to have_key('referer_raw')
    end

    it 'não deixa o valor cru chegar ao texto renderizado do prompt' do
      state = state_para(conversation)
      prompt = Captain::PromptRenderer.render('snippets/conversation', conversation: state[:conversation])

      expect(prompt).to include("Conversation ID: #{conversation.display_id}")
      expect(prompt).not_to include('referer_raw')
      expect(prompt).not_to include(valor_cru)
    end
  end

  context 'when the conversation carries a recoverable URL' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact).tap do |conv|
        conv.update!(additional_attributes: { 'referer' => 'https://loja.exemplo.com.br/[promo]?utm_source=google' })
      end
    end

    it 'mantém o referer saneado no state e no prompt' do
      state = state_para(conversation)
      esperado = 'https://loja.exemplo.com.br/%5Bpromo%5D?utm_source=google'

      expect(state[:conversation][:additional_attributes]['referer']).to eq(esperado)
      expect(Captain::PromptRenderer.render('snippets/conversation', conversation: state[:conversation])).to include(esperado)
    end
  end

  context 'when the contact carries referer_raw' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'remove do state do contato e preserva o resto' do
      contact.update!(additional_attributes: { 'referer_raw' => valor_cru, 'city' => 'Curitiba' })

      atributos = state_para(conversation)[:contact][:additional_attributes]

      expect(atributos).not_to have_key('referer_raw')
      expect(atributos['city']).to eq('Curitiba')
    end
  end
end
