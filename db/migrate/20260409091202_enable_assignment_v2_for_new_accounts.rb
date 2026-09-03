class EnableAssignmentV2ForNewAccounts < ActiveRecord::Migration[7.1]
  def up
    # ChatSPX (item 22): no-op de propósito. Esta migration liga `assignment_v2` no
    # `ACCOUNT_LEVEL_FEATURE_DEFAULTS` do InstallationConfig, o que faz TODA conta criada depois do
    # deploy nascer com o motor de atribuição v2 — e, por causa do auto-sync em
    # `enterprise/app/models/enterprise/account.rb:117-124`, também com `advanced_assignment`.
    # No ChatSPX o flag está `enabled: false` deliberadamente (config/features.yml): é a diferença
    # entre o round-robin clássico e o motor v2 com assignment policies.
    #
    # Contas existentes nunca foram tocadas por esta migration (ela só mexe no default), então
    # neutralizá-la não desfaz nada gravado — só evita que o merge mude o produto por tabela.
    # Para adotar o motor v2 de propósito: `enabled: true` em config/features.yml e rodar o corpo
    # original (que está no histórico, em 93571c69db).
    # Ver plano/redesenho/execucao/onda-0-auditoria-enterprise.md §2.7 e C-7.
  end

  def down; end
end
