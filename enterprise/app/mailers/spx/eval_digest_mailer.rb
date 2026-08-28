# Entrega o digest diário do Eval (ver Spx::EvalDigestJob).
#
# Herda o ApplicationMailer pelo rescue de SMTP que ele já traz: falha de e-mail vira log,
# não derruba o job do cron. O destinatário chega pronto do job — este mailer nunca resolve
# "todos os admins" sozinho, de propósito.
class Spx::EvalDigestMailer < ApplicationMailer
  def diario(account, dados, destinatarios)
    return unless smtp_config_set_or_development?

    @account = account
    @dados = dados
    @frontend_url = ENV.fetch('FRONTEND_URL', nil)
    @parou = dados[:conversas].empty? && dados[:avaliados].zero?
    # ivar e não método privado: a view do mailer não enxerga métodos privados da classe.
    @janela = ((Time.current - dados[:desde]) / 1.hour).round

    mail(to: destinatarios, subject: assunto)
  end

  private

  def assunto
    return "[#{@account.name}] Eval não avaliou nada nas últimas #{@janela}h" if @parou

    n = @dados[:total_conversas]
    "[#{@account.name}] #{n} conversa#{'s' if n != 1} da IA com falha grave nas últimas #{@janela}h"
  end
end
