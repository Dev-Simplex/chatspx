class BackfillEditedOnCaptainAssistantResponses < ActiveRecord::Migration[7.0]
  def up
    # ChatSPX: no-op de propósito. A heurística do upstream — ">15 dias entre created_at e
    # updated_at ⇒ um humano editou" — é falsa neste fork: Captain::AssistantResponse tem
    # `after_commit :update_response_embedding`, então toda reindexação de embedding toca
    # `updated_at` sem que ninguém tenha editado nada. O `update_all(edited: true)` em massa
    # gravaria um palpite sobre dado de cliente, sem `down` que o desfaça.
    # `edited` fica `false` para o legado — a única coisa que sabemos ser verdade.
    # Ver plano/redesenho/execucao/onda-0-auditoria-enterprise.md §2.4 e C-4.
  end

  def down
    # no-op: rolling back migration of edited column will drop the edited column entirely
  end
end
