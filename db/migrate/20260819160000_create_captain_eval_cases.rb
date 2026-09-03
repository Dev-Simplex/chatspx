# 6.02 — eval como produto. O que hoje é infraestrutura interna (o juiz roda sozinho
# sobre conversas reais) ganha a unidade que o CLIENTE controla: um conjunto de casos
# por assistente, versionado por execução.
class CreateCaptainEvalCases < ActiveRecord::Migration[7.1]
  def change
    criar_casos
    criar_execucoes
    criar_resultados
  end

  def criar_casos
    create_table :captain_eval_cases do |t|
      t.bigint :account_id, null: false
      t.bigint :captain_assistant_id, null: false
      t.string :titulo, null: false
      # Os turnos do visitante: [{ 'role' => 'user', 'content' => '...' }, ...]
      t.jsonb :mensagens, null: false, default: []
      # O que se espera da resposta, no vocabulário declarado de Captain::Eval::Expectations.
      t.jsonb :expectativas, null: false, default: {}
      t.boolean :ativo, null: false, default: true
      t.integer :posicao, null: false, default: 0
      t.timestamps
    end

    add_index :captain_eval_cases, [:captain_assistant_id, :posicao], name: 'idx_cap_eval_cases_assistant_pos'
    add_index :captain_eval_cases, :account_id
  end

  def criar_execucoes
    create_table :captain_eval_runs do |t|
      t.bigint :account_id, null: false
      t.bigint :captain_assistant_id, null: false
      t.string :status, null: false, default: 'pendente'
      # dry_run NUNCA nasce false: rodar contra a IA de produção é decisão explícita.
      t.boolean :dry_run, null: false, default: true
      # Identidade da versão do prompt que estava valendo NESTA execução — é o que
      # permite pôr dois vereditos do mesmo caso lado a lado.
      t.string :prompt_fingerprint
      t.jsonb :prompt_snapshot, null: false, default: {}
      t.string :modelo
      t.integer :casos_total, null: false, default: 0
      t.integer :casos_ok, null: false, default: 0
      t.integer :casos_falha, null: false, default: 0
      # O custo que foi EXIBIDO antes de rodar, guardado para poder ser conferido depois.
      t.jsonb :custo_estimado, null: false, default: {}
      t.datetime :iniciado_em
      t.datetime :concluido_em
      t.timestamps
    end

    add_index :captain_eval_runs, [:captain_assistant_id, :created_at], name: 'idx_cap_eval_runs_assistant_created'
    add_index :captain_eval_runs, :account_id
  end

  def criar_resultados
    create_table :captain_eval_case_results do |t|
      t.bigint :account_id, null: false
      t.bigint :eval_run_id, null: false
      t.bigint :eval_case_id, null: false
      t.boolean :passou, null: false, default: false
      t.text :resposta
      t.jsonb :findings, null: false, default: []
      t.jsonb :ferramentas, null: false, default: []
      t.integer :duracao_ms
      t.timestamps
    end

    add_index :captain_eval_case_results, [:eval_run_id, :eval_case_id], unique: true, name: 'idx_cap_eval_results_run_case'
    add_index :captain_eval_case_results, :eval_case_id
    add_index :captain_eval_case_results, :account_id
  end
end
