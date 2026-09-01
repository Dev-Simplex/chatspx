class Captain::TasksPolicy < ApplicationPolicy
  def rewrite?
    true
  end

  def summarize?
    true
  end

  def reply_suggestion?
    true
  end

  # Gate REAL do interruptor "Sugestao de rotulos" da tela de Agentes IA. Antes daqui o
  # metodo devolvia `true` fixo: o recurso ficava sempre ligado e o interruptor nao fazia
  # nada. Conta sem a chave gravada continua LIGADA (ver DEFAULT_ON_FEATURES em
  # CaptainFeaturable): quem nunca abriu a tela nao pode perder o recurso.
  def label_suggestion?
    return true if account.blank?

    account.captain_label_suggestion_enabled?
  end

  def follow_up?
    true
  end
end
