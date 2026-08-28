require 'rails_helper'

RSpec.describe Spx::EvalDigestJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def avaliar(conversation, nota:, findings:)
    Captain::ConversationEval.create!(
      account: account, conversation: conversation, captain_assistant_id: assistant.id,
      nota: nota, resumo: 'resumo do atendimento', response_findings: findings
    )
  end

  def finding(categoria, severidade: 'alta', quem: 'ia')
    { 'categoria' => categoria, 'severidade' => severidade, 'quem' => quem,
      'trecho' => 'trecho verbatim', 'porque' => 'motivo em uma frase' }
  end

  def habilitar(**extra)
    account.update!(custom_attributes: { 'eval_digest' => { 'enabled' => true,
                                                            'destinatarios' => ['gestor@tozi.com.br'] }.merge(extra) })
  end

  # Opt-in de verdade: conta sem a chave não pode receber e-mail nenhum. A instância é
  # multi-cliente e um digest que chega sem ninguém pedir é spam com dado de atendimento.
  describe 'quando a conta não pediu o digest' do
    it 'does not send anything' do
      avaliar(create(:conversation, account: account, inbox: inbox), nota: 2, findings: [finding('alucinacao')])

      expect { described_class.perform_now(account) }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it 'does not send when enabled but with no valid recipient' do
      account.update!(custom_attributes: { 'eval_digest' => { 'enabled' => true, 'destinatarios' => ['sem-arroba'] } })
      avaliar(create(:conversation, account: account, inbox: inbox), nota: 2, findings: [finding('alucinacao')])

      expect { described_class.perform_now(account) }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe 'com o digest habilitado' do
    before { habilitar }

    it 'sends the conversations with a severe AI finding' do
      conv = create(:conversation, account: account, inbox: inbox)
      avaliar(conv, nota: 2, findings: [finding('contradisse_tool')])

      expect { described_class.perform_now(account) }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq(['gestor@tozi.com.br'])
      expect(ActionMailer::Base.deliveries.last.body.encoded).to include(conv.display_id.to_s)
    end

    # Silêncio quando o dia foi bom: digest que chega todo dia mesmo vazio vira filtro de
    # caixa de entrada, e aí o problema de "ninguém lê" volta com outro nome.
    it 'stays silent on a clean day' do
      avaliar(create(:conversation, account: account, inbox: inbox), nota: 9, findings: [])

      expect { described_class.perform_now(account) }.not_to change { ActionMailer::Base.deliveries.size }
    end

    # ...mas o próprio eval ter parado É notícia, e o silêncio esconderia isso.
    it 'alerts when nothing was evaluated at all' do
      expect { described_class.perform_now(account) }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include('não avaliou nada')
    end

    it 'ignores findings that are not severe' do
      avaliar(create(:conversation, account: account, inbox: inbox), nota: 6,
                                                                    findings: [finding('repeticao', severidade: 'baixa')])

      expect { described_class.perform_now(account) }.not_to change { ActionMailer::Base.deliveries.size }
    end

    # O digest é sobre a IA. Falha de atendente humano é outro assunto e outro destinatário.
    it 'ignores findings attributed to a human agent' do
      avaliar(create(:conversation, account: account, inbox: inbox), nota: 4,
                                                                    findings: [finding('quebrou_regra', quem: 'humano')])

      expect { described_class.perform_now(account) }.not_to change { ActionMailer::Base.deliveries.size }
    end

    it 'does not look at another account' do
      outra = create(:account)
      outro_inbox = create(:inbox, account: outra)
      Captain::ConversationEval.create!(account: outra, conversation: create(:conversation, account: outra, inbox: outro_inbox),
                                        captain_assistant_id: create(:captain_assistant, account: outra).id,
                                        nota: 1, resumo: 'x', response_findings: [finding('alucinacao')])

      expect { described_class.perform_now(account) }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(ActionMailer::Base.deliveries.last.subject).to include('não avaliou nada')
    end

    it 'caps the list and says how many were left out' do
      habilitar('limite' => 2)
      3.times { |i| avaliar(create(:conversation, account: account, inbox: inbox), nota: i, findings: [finding('alucinacao')]) }

      described_class.perform_now(account)

      expect(ActionMailer::Base.deliveries.last.body.encoded).to include('Mostrando 2 de 3')
    end

    # Pior nota primeiro: quem abre o e-mail de manhã tem tempo para as duas ou três piores.
    it 'orders by worst grade first' do
      ruim = create(:conversation, account: account, inbox: inbox)
      menos_ruim = create(:conversation, account: account, inbox: inbox)
      avaliar(menos_ruim, nota: 6, findings: [finding('alucinacao')])
      avaliar(ruim, nota: 1, findings: [finding('alucinacao')])

      described_class.perform_now(account)

      corpo = ActionMailer::Base.deliveries.last.body.encoded
      expect(corpo.index(ruim.display_id.to_s)).to be < corpo.index(menos_ruim.display_id.to_s)
    end
  end
end
