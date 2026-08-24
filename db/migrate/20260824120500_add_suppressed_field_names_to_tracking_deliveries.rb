class AddSuppressedFieldNamesToTrackingDeliveries < ActiveRecord::Migration[7.1]
  # Bloco 5.12 — o aceite do modo sem PII e "verificado no LOG DE AUDITORIA, que registra NOMES de
  # campos". `field_names` ja diz o que SAIU; faltava o outro lado da mesma frase: o que a base
  # tinha e RETEVE.
  #
  # Sem esta coluna, o log passa no aceite pelo motivo errado — a ausencia de `em` em `field_names`
  # tambem seria verdade se o contato nao tivesse e-mail nenhum, ou se o job nunca tivesse rodado.
  # A afirmacao negativa so vale acompanhada da positiva.
  #
  # Guarda NOMES, nunca valores, exatamente como `field_names`: a mesma validacao no modelo recusa
  # qualquer coisa que nao seja lista rasa de strings. Tabela nova, sem linha legada — NOT NULL com
  # default e seguro aqui.
  def change
    add_column :tracking_deliveries, :suppressed_field_names, :jsonb, null: false, default: []
  end
end
