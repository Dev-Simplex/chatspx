module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # F1.4 (modo FILA): quando ligado, a action assign_ai_agent vira no-op. Usado pela
  # re-triagem de órfãs (OrphanRetriageJob) no modo fila pra NÃO reanexar a IA e quebrar
  # a fila — a triagem inicial NUNCA seta isto (a IA atende normalmente na 1ª passada).
  thread_mattr_accessor :skip_ai_agent_assignment

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.skip_ai_agent_assignment = nil
  end
end
