# Unidades físicas do cliente — contrato em docs/contratos/unidades.md.
#
# Hoje não existe lugar nenhum no SPX pra endereço, telefone e horário de loja: `WorkingHour`
# é por INBOX (quando o SPX atende, não quando a loja abre) e não tem conceito de exceção;
# `Captain::CustomTool` exige `endpoint_url` — consulta, não guarda; knowledge responde por
# similaridade e não faz conta de data.
#
# DUAS camadas de propósito, e é essa separação que resolve a dor real:
#   1. `unidade_horarios` — a regra padrão por dia da semana. Muda raramente.
#   2. `unidade_excecoes` — a exceção DATADA, que vence e some sozinha. Ninguém desmarca nada.
# No n8n a tabela só sabia expressar a regra, então "neste domingo as lojas de MT abrem" virava
# edição manual linha a linha — e quem esquecia de desfazer mentia pro cliente na semana seguinte.
#
# Additiva e INERTE: conta sem unidade cadastrada não muda de comportamento em nada — a tool
# `buscar_unidades` nem entra no toolset do agente (gate em `active?`).
#
# NOTA DE CONVENÇÃO: o timestamp tem segundos reais de propósito. A colisão de 30/07
# (DuplicateMigrationVersionError, que impede TODAS as migrations de rodar) aconteceu porque
# cada frente escolhe hora redonda — 120000, 130000, 120100. Segundo real não colide.
class CreateUnidades < ActiveRecord::Migration[7.1]
  def change
    criar_unidades
    criar_horarios
    criar_excecoes
  end

  private

  def criar_unidades
    create_table :unidades do |t|
      t.bigint  :account_id, null: false
      t.string  :slug,       null: false
      t.string  :nome,       null: false
      t.string  :cidade
      t.string  :uf
      # Unidade que fechou é `ativa: false`, nunca linha apagada — mesmo princípio do
      # `distribuicao_produtos`: o histórico continua legível e a IA para de oferecê-la.
      t.boolean :ativa,      null: false, default: true
      t.text    :endereco
      t.string  :telefone
      # O fuso é POR UNIDADE porque a resolução de "abre amanhã?" acontece em Ruby, no fuso de
      # quem abre a porta — não no fuso do servidor nem no da conta.
      t.string  :timezone,   null: false, default: 'America/Cuiaba'
      # Agrupamento pra exceção em lote. Campanha nunca é uma loja — é "as unidades de MT neste
      # domingo". Com etiqueta isso é UM registro; sem ela, trocar "editar 20 linhas" por "criar
      # 20 exceções" não ganha nada.
      t.jsonb   :etiquetas,  null: false, default: []
      # Campos livres POR CLIENTE, pra não nascer uma coluna nova a cada cliente novo. É texto
      # pra IA ler, não filtro programático — mesma disciplina do `apresentacao` em
      # docs/contratos/apresentacao-produto.md.
      t.jsonb   :atributos,  null: false, default: {}
      t.timestamps
    end
    add_index :unidades, %i[account_id slug], unique: true
    add_index :unidades, %i[account_id ativa]
  end

  def criar_horarios
    create_table :unidade_horarios do |t|
      t.bigint  :unidade_id, null: false
      # 0 = domingo ... 6 = sábado (convenção do Date#wday, pra não precisar traduzir na leitura).
      t.integer :dia_semana, null: false
      t.time    :abre
      t.time    :fecha
      t.boolean :fechada,    null: false, default: false
      t.timestamps
    end
    # Índice NÃO único de propósito: comércio de rua fecha no almoço, e duas linhas no mesmo dia
    # é como se expressa uma grade partida. Único aqui proibiria isso pra sempre.
    add_index :unidade_horarios, %i[unidade_id dia_semana]
  end

  def criar_excecoes
    create_table :unidade_excecoes do |t|
      t.bigint  :account_id,  null: false
      # unidade_id preenchido = exceção de UMA unidade; etiqueta preenchida = de um GRUPO;
      # os dois vazios = a conta inteira (feriado nacional).
      t.bigint  :unidade_id
      t.string  :etiqueta
      t.date    :data_inicio, null: false
      t.date    :data_fim,    null: false
      t.boolean :fechada,     null: false, default: false
      t.time    :abre
      t.time    :fecha
      t.string  :motivo
      t.timestamps
    end
    add_index :unidade_excecoes, %i[account_id data_fim]
    add_index :unidade_excecoes, :unidade_id
  end
end
