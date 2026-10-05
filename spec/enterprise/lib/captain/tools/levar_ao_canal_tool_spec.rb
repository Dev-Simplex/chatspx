require 'rails_helper'

# A IA leva o cliente ao canal certo: escolhe o destino pelo nome e o sistema manda a abertura pela
# caixa de destino. O destino segue o roteamento dele (sem herdar dono nem time) e nenhum retorno
# à IA traz número de telefone.
RSpec.describe Captain::Tools::LevarAoCanalTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:unidade) { create(:unit, account: account) }
  let(:template) do
    { 'name' => 'acionamento_canal', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá, {{1}}! Você pediu para continuar por aqui. {{2}} Responda para seguir.' }] }
  end

  let(:origem) { caixa_whatsapp('Campanhas', { 'papel' => 'Disparos de campanha' }) }
  let(:destino) do
    caixa_whatsapp('Geral', { 'papel' => 'Atendimento geral', 'destino' => true,
                              'template_name' => 'acionamento_canal', 'template_language' => 'pt_BR' })
  end
  let(:time) { create(:team, account: account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza', phone_number: '+5566999887766') }
  let(:conversa) do
    ficha = create(:contact_inbox, contact: contato, inbox: origem, source_id: '5566999887766')
    create(:conversation, account: account, inbox: origem, contact: contato, contact_inbox: ficha, team: time,
                          assignee: create(:user, account: account, role: :agent))
  end
  let(:contexto) { Struct.new(:state).new({ conversation: { id: conversa.id } }) }

  def caixa_whatsapp(nome, canal = {})
    whatsapp = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                         validate_provider_config: false, message_templates: [template])
    whatsapp.inbox.tap { |caixa| caixa.update!(name: nome, unit_id: unidade.id, canal: canal) }
  end

  def sem_numero!(texto)
    expect(texto).not_to match(/\d{4}/)
  end

  before { destino }

  it 'abre a conversa no destino, manda o acionamento e não herda dono nem time' do
    resposta = tool.perform(contexto, canal: 'Geral', motivo: 'Você quer falar sobre locação.')

    nova = Conversation.where(inbox: destino, contact: contato).sole
    abertura = nova.messages.outgoing.where(private: false).sole
    expect(abertura.content).to eq('Olá, Maria! Você pediu para continuar por aqui. Você quer falar sobre locação. Responda para seguir.')
    expect(abertura.additional_attributes['template_params']).to include('name' => 'acionamento_canal', 'language' => 'pt_BR')
    expect(nova.assignee_id).to be_nil
    expect(nova.team_id).to be_nil
    expect(nova.messages.where(private: true).last.content).to include("##{conversa.display_id}")
    expect(conversa.reload.custom_attributes).to have_key('convite_whatsapp_em')
    expect(resposta).to include('pelo canal Geral')
    sem_numero!(resposta)
  end

  it 'leva o resumo da origem: nota no topo e atributo para a IA do destino' do
    conversa.update!(custom_attributes: { 'resumo_atendimento_ia' => 'Cliente quer alugar um apartamento.',
                                          'acionamento_falhou' => 'falha anterior' })

    tool.perform(contexto, canal: 'Geral', motivo: 'Você quer falar sobre locação.')

    nova = Conversation.where(inbox: destino, contact: contato).sole
    primeira, abertura = nova.messages.order(:id).first(2)
    expect(primeira.private).to be(true)
    expect(primeira.content).to include('Resumo da origem:', 'Cliente quer alugar um apartamento.')
    expect(abertura.additional_attributes['troca_de_canal_origem_id']).to eq(conversa.id)
    expect(nova.custom_attributes['origem_canal']).to include('Motivo: Você quer falar sobre locação.')
    expect(conversa.reload.custom_attributes).not_to have_key('acionamento_falhou')
  end

  it 'segue na conversa que o cliente já tem aberta no destino, sem trocar o dono' do
    dono = create(:user, account: account, role: :agent)
    ficha = create(:contact_inbox, contact: contato, inbox: destino, source_id: '5566999887766')
    existente = create(:conversation, account: account, inbox: destino, contact: contato, contact_inbox: ficha, assignee: dono)

    tool.perform(contexto, canal: 'Geral', motivo: 'Você quer falar sobre locação.')

    expect(Conversation.where(inbox: destino, contact: contato).sole).to eq(existente)
    expect(existente.reload.assignee_id).to eq(dono.id)
    expect(existente.messages.outgoing.where(private: false).count).to eq(1)
  end

  context 'with origem fora do WhatsApp' do
    let(:origem) { create(:inbox, account: account).tap { |caixa| caixa.update!(unit_id: unidade.id) } }
    let(:contato) { create(:contact, account: account, name: 'Maria Souza') }
    let(:conversa) { create(:conversation, account: account, inbox: origem, contact: contato) }
    let(:destino) do
      caixa_whatsapp('Principal', { 'principal' => true, 'template_name' => 'acionamento_canal' })
    end

    it 'chama no número que o cliente informou pelo WhatsApp principal' do
      tool.perform(contexto, canal: 'Principal', motivo: 'Você pediu para seguir no WhatsApp.', telefone: '(66) 99988-7766')

      nova = Conversation.where(inbox: destino).sole
      expect(nova.contact_id).to eq(contato.id)
      expect(nova.contact_inbox.source_id).to eq('5566999887766')
    end

    it 'pede o número quando ele não veio e o contato não tem' do
      resposta = tool.perform(contexto, canal: 'Principal', motivo: 'Você pediu para seguir no WhatsApp.')

      expect(resposta).to eq(described_class::PEDIR_NUMERO)
      expect(Conversation.where(inbox: destino)).to be_empty
    end

    it 'devolve o motivo quando o número é inválido' do
      resposta = tool.perform(contexto, canal: 'Principal', motivo: 'Você pediu para seguir no WhatsApp.', telefone: '123')

      expect(resposta).to include('não parece válido')
      expect(Conversation.where(inbox: destino)).to be_empty
    end
  end

  it 'devolve os canais disponíveis quando o nome não é de um destino' do
    resposta = tool.perform(contexto, canal: 'Outro', motivo: 'Você quer falar sobre locação.')

    expect(resposta).to include('"Geral"')
    expect(resposta).not_to include('Campanhas')
    expect(Conversation.where(inbox: destino)).to be_empty
  end

  it 'não envia quando o template do destino não está aprovado' do
    destino.update!(canal: destino.canal_config.merge('template_name' => 'inexistente'))

    resposta = tool.perform(contexto, canal: 'Geral', motivo: 'Você quer falar sobre locação.')

    expect(resposta).to eq(described_class::INDISPONIVEL)
    expect(Conversation.where(inbox: destino)).to be_empty
  end

  describe '#active?' do
    it 'só entra no toolset com algum destino configurado na conta' do
      expect(tool.active?).to be(true)
      destino.update!(canal: {})
      expect(tool.active?).to be(false)
    end
  end
end
