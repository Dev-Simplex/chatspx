require 'rails_helper'

# As saídas do estado "designado" no modo PUSH. A distinção que este spec protege: no push quem
# grava o assignee é o próprio Motor, então o evento de atribuição NÃO pode fechar a designação —
# senão o cronômetro do SLA morreria no instante em que nasce e nada nunca seria repassado.
RSpec.describe Spx::Distribuicao::DesignacaoListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretor) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }

  before do
    [corretor, outro].each do |user|
      create(:team_member, team: team, user: user)
      create(:inbox_member, inbox: inbox, user: user)
    end
  end

  def designacao_push(chosen)
    create(:distribuicao_log, :aberta, conversation: conversation, chosen_user_id: chosen.id)
  end

  def designacao_pull
    create(:distribuicao_log, conversation: conversation, chosen_user_id: corretor.id,
                              status: 'designado', designado_em: 5.minutes.ago,
                              policy_snapshot: { 'modo_posse' => 'designacao' })
  end

  def evento(nome, data)
    Events::Base.new(nome, Time.zone.now, data)
  end

  describe '#assignee_changed' do
    it 'NÃO fecha quando o assignee é a própria pessoa que o Motor designou (push)' do
      log = designacao_push(corretor)
      conversation.update!(assignee_id: corretor.id)

      listener.assignee_changed(evento('assignee.changed', conversation: conversation))

      expect(log.reload.status).to eq('designado')
    end

    it 'fecha quando OUTRA pessoa toma a conversa' do
      log = designacao_push(corretor)
      conversation.update!(assignee_id: outro.id)

      listener.assignee_changed(evento('assignee.changed', conversation: conversation))

      expect(log.reload.status).to eq('assumido')
    end

    # Comportamento de sempre da conta 6: em designação a posse nunca foi do Motor, então
    # qualquer humano assumindo encerra.
    it 'segue fechando no modo designação' do
      log = designacao_pull
      conversation.update!(assignee_id: corretor.id)

      listener.assignee_changed(evento('assignee.changed', conversation: conversation))

      expect(log.reload.status).to eq('assumido')
    end
  end

  describe '#message_created' do
    it 'fecha a designação push na primeira resposta humana' do
      log = designacao_push(corretor)
      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :outgoing, sender: corretor, content: 'oi')

      listener.message_created(evento('message.created', message: message))

      expect(log.reload.status).to eq('assumido')
    end

    it 'ignora mensagem do cliente' do
      log = designacao_push(corretor)
      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :incoming, content: 'oi')

      listener.message_created(evento('message.created', message: message))

      expect(log.reload.status).to eq('designado')
    end

    it 'ignora nota privada — anotar não é atender' do
      log = designacao_push(corretor)
      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :outgoing, private: true, sender: corretor, content: 'nota')

      listener.message_created(evento('message.created', message: message))

      expect(log.reload.status).to eq('designado')
    end

    it 'ignora resposta da IA (sender não é User)' do
      log = designacao_push(corretor)
      message = create(:message, :bot_message, account: account, inbox: inbox,
                                               conversation: conversation, content: 'resposta automática')

      listener.message_created(evento('message.created', message: message))

      expect(log.reload.status).to eq('designado')
    end
  end

  describe '#team_changed (gatilho sem IA)' do
    let(:policy) do
      create(:distribuicao_policy, account: account, team: team,
                                   pool: [{ 'user_id' => corretor.id, 'ativo' => true }])
    end

    it 'distribui quando a conversa cai no time sem dono' do
      policy

      listener.team_changed(evento('team.changed', conversation: conversation))

      expect(conversation.reload.assignee_id).to eq(corretor.id)
    end

    # Sem política no time não há intenção de distribuir — o Motor segue inerte.
    it 'não faz nada em time sem política' do
      policy.update!(modo: 'off')

      listener.team_changed(evento('team.changed', conversation: conversation))

      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'não atropela a IA que está atendendo' do
      policy
      bot = create(:agent_bot, account: account)
      conversation.update!(assignee_agent_bot_id: bot.id)

      listener.team_changed(evento('team.changed', conversation: conversation))

      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'não redesigna quando já existe designação viva' do
      policy
      designacao_push(outro)

      listener.team_changed(evento('team.changed', conversation: conversation))

      expect(conversation.reload.assignee_id).to be_nil
    end
  end
end
