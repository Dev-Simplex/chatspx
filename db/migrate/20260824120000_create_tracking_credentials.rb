class CreateTrackingCredentials < ActiveRecord::Migration[7.1]
  # Bloco 5.02 — o COFRE das credenciais de rastreio, uma linha por inbox.
  #
  # Por que tabela propria, e nao `inbox.additional_attributes` (onde mora a config publica do
  # 5.01): aquele jsonb e servido ao navegador em dois lugares (`widgets/show.html.erb` e
  # `widget/configs/create.json.jbuilder`). Segredo que mora junto do publico vaza no dia em que
  # alguem serializa o hash inteiro — que e exatamente o antipadrao ja presente nesta base em
  # `webhooks/_webhook.json.jbuilder:6`. Separar os dois torna o vazamento IMPOSSIVEL por
  # construcao, em vez de depender de cada serializador lembrar de filtrar.
  #
  # Todo campo de segredo e `text`, nunca `string`: o payload do Active Record Encryption e um
  # envelope JSON (ciphertext + iv + tag) codificado, varias vezes maior que o valor original — e
  # com `store_key_references = true` (ligado no bloco 0.10) ele cresce mais ainda. Um `string`
  # limitado truncaria o envelope e o registro voltaria ILEGIVEL, sem erro na gravacao.
  def change
    create_credentials_table
    add_credentials_foreign_keys
  end

  private

  def create_credentials_table
    create_table :tracking_credentials do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false

      # Segredos — cifrados pelo modelo, nunca serializados em claro.
      t.text :meta_access_token
      t.text :ga4_api_secret
      t.text :google_ads_refresh_token
      t.text :google_ads_developer_token

      # NAO e segredo, mas tambem NAO e publico: e o codigo que faz a Meta tratar o evento como
      # teste. A doc da Meta e explicita — tem de sair do payload de producao. Sem ele, `verify`
      # do provedor meta se recusa a rodar, porque testar sem ele gravaria evento REAL.
      t.string :meta_test_event_code

      # Metadados NAO sensiveis da conexao OAuth (escopo concedido, expiracao, id da conta de
      # anuncios conectada). Existe para o OAuth de um clique (T-C1.7, a outra metade deste bloco)
      # encaixar sem nova migration. O token que vier do OAuth vai nas colunas cifradas acima.
      t.jsonb :oauth_metadata, null: false, default: {}

      t.datetime :last_verified_at

      t.timestamps
    end

    # Uma credencial por inbox. UNIQUE nasce JUNTO da tabela porque indice unico adicionado depois
    # falha na frota se ja houver duplicata, e o banco de teste vazio nunca mostraria isso.
    add_index :tracking_credentials, :inbox_id, unique: true
    add_index :tracking_credentials, :account_id
  end

  def add_credentials_foreign_keys
    # Credencial nao existe sem o dono: apagar a conta ou a inbox tem de apagar o segredo junto.
    # Deixar orfao aqui seria manter access token da Meta de um cliente que ja saiu.
    add_foreign_key :tracking_credentials, :accounts, on_delete: :cascade
    add_foreign_key :tracking_credentials, :inboxes, on_delete: :cascade
  end
end
