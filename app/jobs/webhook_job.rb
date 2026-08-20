class WebhookJob < ApplicationJob
  queue_as :medium
  # B3: enquanto Webhooks::Trigger engolia a excecao, este retry_on nunca via
  # nada — o job terminava com sucesso e o webhook dizia que entregou. Agora a
  # excecao sobe, as 5 tentativas acontecem de verdade, e o efeito colateral
  # roda UMA vez, no esgotamento (molde: AgentBots::WebhookJob).
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.handle_exhaustion(error)
  end
  discard_on ActiveJob::DeserializationError

  #  There are 3 types of webhooks, account, inbox and agent_bot
  #
  # `webhook_id` (bloco 4.14) entra como SEXTO parametro de proposito, contra o
  # Metrics/ParameterLists. A alternativa — agrupar secret/delivery_id/webhook_id num
  # objeto so — mudaria a assinatura de um job que tem instancias JA ENFILEIRADAS: no
  # deploy, todo webhook em fila falharia na desserializacao. Parametro novo com default
  # nil e compativel com o que ja esta na fila; job antigo simplesmente chega sem ele.
  # Um aviso de estilo nao vale uma entrega perdida de cliente.
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil, webhook_id: nil) # rubocop:disable Metrics/ParameterLists
    # job_id e estavel entre as tentativas (retry_job reenfileira a MESMA
    # instancia), entao quem chamou sem delivery_id ainda recebe um
    # X-Chatwoot-Delivery que nao muda de uma tentativa para a outra.
    delivery = Webhooks::Trigger::Delivery.new(id: delivery_id.presence || job_id, webhook_id: webhook_id)
    @trigger_context = { url: url, payload: payload, webhook_type: webhook_type || :account_webhook,
                         secret: secret, delivery: delivery }
    Webhooks::Trigger.execute(url, payload, webhook_type, secret: secret, delivery: delivery)
  end

  # Chamado so quando as tentativas acabam. Se rodasse a cada tentativa, a
  # mensagem nasceria "failed" no primeiro erro com 4 reentregas ainda por vir.
  def handle_exhaustion(error)
    context = @trigger_context || context_from_arguments
    Webhooks::Trigger.new(context[:url], context[:payload], context[:webhook_type],
                          secret: context[:secret], delivery: context[:delivery]).handle_failure(error)
  end

  private

  # Rede de seguranca: se a excecao vier antes de #perform atribuir o contexto,
  # reconstroi a partir dos argumentos serializados do job.
  def context_from_arguments
    url, payload, webhook_type = arguments
    kwargs = arguments.length > 3 && arguments.last.is_a?(Hash) ? arguments.last : {}
    { url: url, payload: payload, webhook_type: webhook_type || :account_webhook,
      secret: kwargs[:secret],
      delivery: Webhooks::Trigger::Delivery.new(id: kwargs[:delivery_id].presence || job_id,
                                                webhook_id: kwargs[:webhook_id]) }
  end
end
