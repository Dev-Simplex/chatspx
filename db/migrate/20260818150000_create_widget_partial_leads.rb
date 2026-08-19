# frozen_string_literal: true

# Bloco 4.18 (BE-5) — LEAD INCOMPLETO.
#
# A resposta parcial do pre-chat precisa existir ANTES de a conversa existir, que e a
# mudanca de momento que a decisao D3 aprovou. Por isso ela nao cabe em nenhuma tabela
# atual: `conversations` e `messages` pressupoem uma conversa, e e justamente ela que
# ainda nao nasceu.
#
# POR QUE TABELA E NAO jsonb EM CONTACT: o registro parcial e de quem NAO concluiu, tem
# retencao propria (LGPD) e precisa ser CONTADO por etapa para o relatorio responder
# "quantos leads perdemos e onde". Cardinalidade alta, expurgo por data e agregacao por
# coluna sao exatamente o que jsonb nao faz bem.
class CreateWidgetPartialLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :widget_partial_leads do |t|
      # CASCADE nas TRES pontas, e isso e deliberado — ja custou caro aqui uma FK sem
      # cascade: `flow_runs` travava `conversation.destroy!` com InvalidForeignKey, e o
      # agente descobria pelo 500 na tela. Um registro parcial NUNCA pode impedir apagar
      # uma conta, uma inbox ou um contato.
      #
      # No contato, `cascade` (e nao `nullify`) tambem e a leitura de LGPD certa: apagar a
      # pessoa apaga as respostas que ela deu pela metade. Orfao anonimo seria pior.
      #
      # As tres rotas de exclusao sao CONFERIDAS por spec
      # (`spec/models/widget_partial_lead_spec.rb`), porque cascade por multiplos caminhos
      # ate a mesma linha filha e exatamente o caso em que a suite fica verde e a frota
      # quebra — o teste apaga de verdade pelos tres lados.
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      # O contato so nasce quando o lead e MATERIALIZADO (abandono confirmado + canal de
      # contato preenchido). Ate la e nulo — o registro parcial nao vira cadastro sozinho.
      t.references :contact, foreign_key: { on_delete: :cascade }, index: true

      # A sessao do visitante (o `source_id` do contact_inbox). E a chave de idempotencia:
      # retomar na MESMA sessao atualiza a linha, nunca cria outra.
      t.string :session_id, null: false
      t.integer :step_reached, null: false, default: 0
      t.string :step_key
      t.jsonb :answers, null: false, default: {}

      t.datetime :last_answered_at, null: false
      # Concluiu o pre-chat (virou conversa de verdade): deixa de ser lead incompleto e o
      # varredor nunca mais o toca. Nao apagamos a linha — o relatorio precisa do
      # denominador para dizer QUANTOS se perderam.
      t.datetime :completed_at
      # Abandono CONFIRMADO pelo varredor (passou a janela sem nova resposta).
      t.datetime :abandoned_at

      t.timestamps
    end

    # Idempotencia da sessao — e o que faz "retomar na mesma sessao nao duplicar o
    # registro" ser garantia do BANCO, e nao boa intencao do servico.
    add_index :widget_partial_leads, [:inbox_id, :session_id], unique: true,
                                                               name: 'index_widget_partial_leads_on_inbox_and_session'
    # O varredor procura exatamente por isto: da conta, ainda nao concluido, parado desde.
    add_index :widget_partial_leads, [:account_id, :completed_at, :last_answered_at],
              name: 'index_widget_partial_leads_on_account_and_state'
  end
end
