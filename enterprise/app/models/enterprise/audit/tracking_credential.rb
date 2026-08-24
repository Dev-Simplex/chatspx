module Enterprise::Audit::TrackingCredential
  extend ActiveSupport::Concern

  included do
    # `except:` com a lista canonica do modelo, e nao uma copia escrita a mao: campo de segredo novo
    # entra em SECRET_ATTRIBUTES e ja sai da auditoria junto, sem depender de alguem lembrar.
    #
    # Sem isto, `audits.audited_changes` guardaria o valor DECIFRADO em jsonb — a coluna estaria
    # cifrada e o log de auditoria, ao lado, teria o access token da Meta em texto puro. E o mesmo
    # cuidado que `Enterprise::Audit::Webhook` ja toma com `:secret`.
    audited associated_with: :account, except: ::TrackingCredential::SECRET_ATTRIBUTES.map(&:to_s)
  end
end
