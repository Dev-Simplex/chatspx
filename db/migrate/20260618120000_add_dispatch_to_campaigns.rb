class AddDispatchToCampaigns < ActiveRecord::Migration[7.1]
  # Estende a entidade Campaign para suportar disparo em massa de WhatsApp (HSM)
  # dirigido por config, replicavel entre contas. O blaster nativo do Chatwoot
  # segue desativado (Campaign#execute_campaign e no-op p/ WhatsApp); o disparo
  # passa a ser conduzido pela engine Campaigns::Whatsapp::* via dispatch_status.
  def change
    # Template HSM aprovado (sincronizado no canal) usado no disparo.
    add_column :campaigns, :template_name, :string
    add_column :campaigns, :template_language, :string, default: 'pt_BR'
    # Time que a conversa recebe no disparo. A conversa fica FECHADA e SEM agente;
    # o reply reabre e a atribuicao (IA do time / regras normais) ocorre na
    # camada de orquestracao.
    add_column :campaigns, :target_team_id, :bigint
    # Ritmo do disparo (segundos entre envios) e estado da engine.
    add_column :campaigns, :pacing_seconds, :integer, default: 5, null: false
    add_column :campaigns, :dispatch_status, :integer, default: 0, null: false
    # Config livre do disparo: quiet_hours, health_gate, header de midia, default_params.
    add_column :campaigns, :dispatch_config, :jsonb, default: {}, null: false

    add_index :campaigns, :dispatch_status
    add_index :campaigns, :target_team_id
  end
end
