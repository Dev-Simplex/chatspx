class Migration::ValidateOpenaiHooksJob < ApplicationJob
  queue_as :async_database_migration

  # `dry_run: true` só relata o que seria apagado. É o modo obrigatório na primeira passada por VM:
  # `KeyValidator` considera inválida QUALQUER resposta 401 de GET {api_base}/models, e um gateway
  # que só libere /chat/completions devolve 401 aí mesmo com chave boa — o que classificaria as
  # chaves válidas da VM como mortas e apagaria as integrações. Ver onda-0-auditoria-enterprise.md C-2.
  def perform(account: nil, dry_run: false)
    stats = { checked: 0, destroyed: 0 }

    hooks_scope(account).find_each do |hook|
      stats[:checked] += 1
      next if Integrations::Openai::KeyValidator.valid?(hook.settings&.dig('api_key'))

      dry_run ? report_would_destroy(hook) : destroy_hook(hook)
      stats[:destroyed] += 1
    end

    Rails.logger.info("[openai-backfill] completed #{stats.inspect}")
    stats
  end

  private

  def hooks_scope(account)
    scope = Integrations::Hook.where(app_id: 'openai', status: 'enabled')
    account ? scope.where(account_id: account.id) : scope
  end

  def report_would_destroy(hook)
    Rails.logger.warn("[openai-backfill][dry-run] WOULD destroy hook_id=#{hook.id} account_id=#{hook.account_id}")
  end

  def destroy_hook(hook)
    AdministratorNotifications::IntegrationsNotificationMailer.with(account: hook.account).openai_disconnect.deliver_later
    hook.destroy!
    Rails.logger.warn("[openai-backfill] destroyed hook_id=#{hook.id} account_id=#{hook.account_id}")
  end
end
