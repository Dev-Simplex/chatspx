class EnqueueValidateOpenaiHooksJob < ActiveRecord::Migration[7.1]
  def up
    # ChatSPX: NÃO enfileirar automaticamente. O job faz `hook.destroy!` em Integrations::Hook de
    # `openai` cuja chave devolva 401 em GET {CAPTAIN_OPEN_AI_ENDPOINT}/models — apagando a
    # integração de IA da conta com a api_key e as settings dentro, sem `down`, assíncrono e fora
    # da transação da migration. Numa VM cujo CAPTAIN_OPEN_AI_ENDPOINT aponte para um gateway que
    # responda 401 nesse path (comum em gateways que só liberam /chat/completions), isso apaga as
    # integrações de IA da VM inteira, com chave boa.
    #
    # O housekeeping continua disponível, mas manual e auditável por VM:
    #   Migration::ValidateOpenaiHooksJob.new.perform(dry_run: true)   # só relata o que apagaria
    #   Migration::ValidateOpenaiHooksJob.new.perform                  # apaga, depois de conferir
    #
    # Ver plano/redesenho/execucao/onda-0-auditoria-enterprise.md §2.3 e C-2.
  end

  def down; end
end
