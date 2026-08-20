class PurgePendingCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  # ChatSPX: `status = 0` NÃO é lixo aqui — é FAQ pendente de revisão humana, gravada pelo
  # Captain::Llm::ConversationFaqService antes de o upstream substituir o fluxo por
  # captain_faq_suggestions. O purge do upstream (`DELETE ... WHERE status = 0`, sem `down`)
  # apagaria dado de cliente sem substituto. Aqui a linha é TRANSFERIDA para o fluxo novo
  # (question/answer/embedding + o vínculo com a conversa de origem) e só então removida.
  # Ver plano/redesenho/execucao/onda-0-auditoria-enterprise.md §2.2 e C-1.
  #
  # SQL puro de propósito: usar os modelos dispararia `after_commit :update_embedding` do
  # Captain::FaqSuggestion, enfileirando um job de embedding por linha e gastando crédito para
  # recalcular um vetor que já temos gravado.
  def up
    execute(transfer_suggestions_sql)
    execute(transfer_observations_sql)
    execute('DELETE FROM captain_assistant_responses WHERE status = 0')
  end

  def down; end

  private

  # `language` fixado em 'pt': `accounts.locale` é enum INTEIRO, e resolver o nome em SQL puro
  # exigiria replicar o mapa do enum. `ConversationFaqService.normalize_language` reduz `pt_BR` a
  # `pt`, e pt_BR é o default da frota — então 'pt' é a resposta certa para todas as contas.
  # `status 0` = `open` no enum de Captain::FaqSuggestion, que é a semântica de `pending`.
  #
  # `DISTINCT ON (assistant_id, question, answer)`: o fluxo velho podia gravar a MESMA FAQ pendente
  # mais de uma vez (nada impedia), e o fluxo novo é deduplicado por construção — `source_count` é
  # justamente quantas conversas geraram aquela FAQ. Sem o DISTINCT ON, cada duplicata viraria uma
  # sugestão, e as extras ficariam SEM observation (o índice unique de
  # (conversation_id, faq_suggestion_id) colapsa as repetidas) — sugestão órfã. Medido rodando a
  # migration no banco de teste, não deduzido.
  def transfer_suggestions_sql
    <<~SQL.squish
      INSERT INTO captain_faq_suggestions
        (question, answer, embedding, assistant_id, account_id, language, source_count, status, created_at, updated_at)
      SELECT DISTINCT ON (r.assistant_id, r.question, r.answer)
             r.question, r.answer, r.embedding, r.assistant_id, r.account_id, 'pt',
             COUNT(*) OVER (PARTITION BY r.assistant_id, r.question, r.answer),
             0, r.created_at, r.updated_at
      FROM captain_assistant_responses r
      WHERE r.status = 0
      ORDER BY r.assistant_id, r.question, r.answer, r.id
    SQL
  end

  # `JOIN LATERAL ... LIMIT 1` e não JOIN simples: duas pendentes com o mesmo question/answer no
  # mesmo assistant produziriam produto cartesiano de observations. Assim é UMA observation por
  # pendente, deterministicamente. O `EXISTS` sobre conversations é necessário porque
  # captain_faq_observations não tem FK para conversations — sem ele, pendente cuja conversa já foi
  # apagada geraria observation apontando para id inexistente. `status 0` = `attached`.
  def transfer_observations_sql
    <<~SQL.squish
      INSERT INTO captain_faq_observations
        (account_id, conversation_id, faq_suggestion_id, generated_question, generated_answer,
         language, status, created_at, updated_at)
      SELECT r.account_id, r.documentable_id, s.id, r.question, r.answer, s.language, 0, r.created_at, r.updated_at
      FROM captain_assistant_responses r
      JOIN LATERAL (
        SELECT fs.id, fs.language
        FROM captain_faq_suggestions fs
        WHERE fs.assistant_id = r.assistant_id AND fs.question = r.question AND fs.answer = r.answer
        ORDER BY fs.id
        LIMIT 1
      ) s ON TRUE
      WHERE r.status = 0
        AND r.documentable_type = 'Conversation'
        AND r.documentable_id IS NOT NULL
        AND EXISTS (SELECT 1 FROM conversations c WHERE c.id = r.documentable_id)
      ON CONFLICT DO NOTHING
    SQL
  end
end
