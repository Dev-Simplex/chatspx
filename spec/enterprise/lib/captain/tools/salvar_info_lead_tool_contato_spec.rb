require 'rails_helper'

# Coleta do contato alternativo: no Instagram, fechada a janela de 24h nao existe template nem
# tag aprovada pra reabrir (medido em 08/09/2026 contra a Graph), entao quem some so volta se
# ELE escrever. O numero que a pessoa da enquanto a janela esta viva e a unica ponte — perder
# esse dado e perder o lead.
RSpec.describe Captain::Tools::SalvarInfoLeadTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  describe 'contato alternativo' do
    it 'guarda so os digitos e etiqueta a conversa pro time achar' do
      tool.perform(tool_context, contato_alternativo: '(66) 99999-1234')

      expect(contact.reload.custom_attributes['contato_alternativo']).to eq('66999991234')
      expect(conversation.reload.label_list).to include('contato-alternativo')
    end

    # O campo `phone_number` tem unicidade por conta: gravar ali faria o contato do Instagram
    # colidir com o cadastro que a mesma pessoa ja tem no WhatsApp, e o merge/erro aconteceria
    # no meio do atendimento. A ponte nao pode custar o cadastro.
    it 'NAO toca o phone_number do contato' do
      tool.perform(tool_context, contato_alternativo: '66999991234')

      expect(contact.reload.phone_number).to be_blank
    end

    # O campo `name` e area de trabalho do time humano nessa base ("Fulano / Casa do Beltrano").
    it 'NAO toca o name do contato' do
      original = contact.name
      tool.perform(tool_context, contato_alternativo: '66999991234')

      expect(contact.reload.name).to eq(original)
    end

    it 'preserva os outros custom_attributes do contato' do
      contact.update!(custom_attributes: { 'nome_confirmado' => 'Ana' })

      tool.perform(tool_context, contato_alternativo: '66999991234')

      expect(contact.reload.custom_attributes).to include('nome_confirmado' => 'Ana',
                                                          'contato_alternativo' => '66999991234')
    end

    # O modelo as vezes devolve a frase inteira em vez do numero. Frase virando contato gera
    # lista suja que ninguem consegue usar — campo vazio e melhor que numero que nao existe.
    it 'recusa texto que nao tem digitos de telefone' do
      tool.perform(tool_context, contato_alternativo: 'ela disse que depois manda')

      expect(contact.reload.custom_attributes).not_to have_key('contato_alternativo')
      expect(conversation.reload.label_list).not_to include('contato-alternativo')
    end

    it 'recusa numero curto demais pra ser telefone' do
      tool.perform(tool_context, contato_alternativo: '99123')

      expect(contact.reload.custom_attributes).not_to have_key('contato_alternativo')
    end

    it 'recusa sequencia longa demais pra ser telefone' do
      tool.perform(tool_context, contato_alternativo: '12345678901234567')

      expect(contact.reload.custom_attributes).not_to have_key('contato_alternativo')
    end

    it 'nao grava nada quando o parametro nem veio' do
      tool.perform(tool_context, status: 'em_contato')

      expect(contact.reload.custom_attributes).not_to have_key('contato_alternativo')
    end

    it 'aceita o numero com DDI colado' do
      tool.perform(tool_context, contato_alternativo: '+55 66 99999-1234')

      expect(contact.reload.custom_attributes['contato_alternativo']).to eq('5566999991234')
    end
  end
end
