# Dispara o digest diário do Eval para as contas que pediram (ver Spx::EvalDigestJob).
#
# Filtra no banco e não em Ruby: numa instância multi-conta, iterar Account.all para ler um
# custom_attribute é varredura inteira por um punhado de contas configuradas.
class Spx::EvalDigestSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    contas.find_each do |account|
      Spx::EvalDigestJob.perform_later(account)
    end
  end

  private

  def contas
    Account.where("custom_attributes -> 'eval_digest' ->> 'enabled' = 'true'")
  end
end
