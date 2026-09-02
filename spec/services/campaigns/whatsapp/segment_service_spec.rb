require 'rails_helper'

# O segmento existe pra montar o público sem planilha. Ele NÃO decide quem entra no disparo:
# devolve as mesmas `rows` do upload e o AudienceBuilderService continua sendo o único lugar
# que aplica a higiene. É por isso que os testes olham quem SAI daqui, não quem é descartado.
RSpec.describe Campaigns::Whatsapp::SegmentService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }

  def contato(nome, telefone)
    create(:contact, account: account, name: nome, phone_number: telefone)
  end

  describe 'o formato de saída' do
    it 'delivers the same shape the spreadsheet upload produces' do
      contato('Maria', '+5566999990001')

      linha = described_class.new(account: account, filtros: { ultima_atividade_dias: nil }).perform.rows.first

      expect(linha.keys).to contain_exactly(:name, :phone)
    end

    # Contato sem telefone não é destinatário — e deixá-lo entrar só para ser descartado
    # depois inflaria o total que o operador usa para decidir se a lista está certa.
    it 'leaves out contacts with no phone at all' do
      contato('Com telefone', '+5566999990002')
      create(:contact, account: account, name: 'Sem telefone', phone_number: nil)

      resultado = described_class.new(account: account, filtros: {}).perform

      expect(resultado.rows.size).to eq(1)
      expect(resultado.total).to eq(1)
    end
  end

  describe 'critérios' do
    it 'narrows by label' do
      alvo = contato('Etiquetado', '+5566999990003')
      contato('Sem etiqueta', '+5566999990004')
      alvo.update!(label_list: ['pacaembu'])

      rows = described_class.new(account: account, filtros: { labels: ['pacaembu'] }).perform.rows

      expect(rows.map { |r| r[:phone] }).to eq([alvo.phone_number])
    end

    # Time e caixa são da CONVERSA, não do contato: quem tem alguma conversa que bate entra.
    it 'narrows by the team of the contact conversation' do
      alvo = contato('Do time', '+5566999990005')
      fora = contato('De outro time', '+5566999990006')
      create(:conversation, account: account, inbox: inbox, contact: alvo, team: team)
      create(:conversation, account: account, inbox: inbox, contact: fora)

      rows = described_class.new(account: account, filtros: { team_id: team.id }).perform.rows

      expect(rows.map { |r| r[:phone] }).to eq([alvo.phone_number])
    end

    # Os dois motores contam: o antigo carimbava `campaign_id` na conversa e não criava
    # campaign_recipients. Ler só a tabela nova foi o que deixou 294 pessoas receberem o
    # mesmo assunto duas vezes.
    it 'counts as reached whoever appears in either dispatch engine' do
      por_recipient = contato('Pelo motor novo', '+5566999990007')
      por_conversa = contato('Pelo motor antigo', '+5566999990008')
      contato('Nunca recebeu', '+5566999990009')
      campanha = create(:campaign, account: account, inbox: inbox)
      CampaignRecipient.create!(campaign: campanha, account: account,
                                contact: por_recipient, phone_number: por_recipient.phone_number)
      create(:conversation, account: account, inbox: inbox, contact: por_conversa, campaign: campanha)

      rows = described_class.new(account: account, filtros: { campaign_id: campanha.id }).perform.rows

      expect(rows.map { |r| r[:phone] })
        .to contain_exactly(por_recipient.phone_number, por_conversa.phone_number)
    end

    it 'inverts to whoever did NOT receive that campaign' do
      recebeu = contato('Recebeu', '+5566999990010')
      nao_recebeu = contato('Não recebeu', '+5566999990011')
      campanha = create(:campaign, account: account, inbox: inbox)
      CampaignRecipient.create!(campaign: campanha, account: account,
                                contact: recebeu, phone_number: recebeu.phone_number)

      rows = described_class.new(
        account: account, filtros: { campaign_id: campanha.id, excluir_campanha: true }
      ).perform.rows

      expect(rows.map { |r| r[:phone] }).to eq([nao_recebeu.phone_number])
    end

    it 'finds who never received any campaign at all' do
      recebeu = contato('Recebeu', '+5566999990012')
      virgem = contato('Nunca recebeu', '+5566999990013')
      campanha = create(:campaign, account: account, inbox: inbox)
      CampaignRecipient.create!(campaign: campanha, account: account,
                                contact: recebeu, phone_number: recebeu.phone_number)

      rows = described_class.new(account: account, filtros: { sem_campanha: true }).perform.rows

      expect(rows.map { |r| r[:phone] }).to eq([virgem.phone_number])
    end

    # Critérios se somam (E). Se alternassem, o público cresceria por engano — que é o jeito
    # mais rápido de mandar campanha para quem não devia.
    it 'combines criteria instead of widening the audience' do
      dois = contato('Bate nos dois', '+5566999990014')
      um = contato('Bate só na etiqueta', '+5566999990015')
      [dois, um].each { |c| c.update!(label_list: ['alvo']) }
      create(:conversation, account: account, inbox: inbox, contact: dois, team: team)

      rows = described_class.new(
        account: account, filtros: { labels: ['alvo'], team_id: team.id }
      ).perform.rows

      expect(rows.map { |r| r[:phone] }).to eq([dois.phone_number])
    end
  end
end
