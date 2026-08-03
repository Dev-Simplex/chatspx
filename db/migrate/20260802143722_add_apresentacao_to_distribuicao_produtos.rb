# Inventário de peças de marketing por produto (contrato em docs/contratos/apresentacao-produto.md).
#
# A tabela `distribuicao_produtos` é da frente spx/rodizio; quem CONSOME esta coluna é a
# spx/followup. A migration mora aqui pra não repetir a colisão de 30/07 — duas frentes
# migrando a mesma tabela em paralelo.
#
# PRINCÍPIO DO FORMATO, e ele é a razão de a coluna ser jsonb livre: a config descreve
# **material e público**, NUNCA sequência. Quem escolhe qual peça e quando é a IA, no
# contexto. Config com ordem/prazo engessa e não deixa testar estratégia.
#
# Additiva e inerte: sem `apresentacao` preenchida, ninguém muda de comportamento.
# Aplicar com alvo específico (db:migrate:up VERSION=20260802143722).
#
# NOTA DE CONVENÇÃO: o timestamp tem segundos reais de propósito. A colisão de 30/07
# (DuplicateMigrationVersionError, que impede TODAS as migrations de rodar) aconteceu porque
# as frentes escolhem hora redonda — 120000, 130000, 120100. Segundo real não colide.
class AddApresentacaoToDistribuicaoProdutos < ActiveRecord::Migration[7.1]
  def change
    # `if_not_exists` NÃO é cargo cult: antes de a divisão de responsabilidade ficar clara, a
    # frente spx/followup chegou a aplicar esta MESMA coluna no banco de teste da .232 e depois
    # removeu. Se a remoção não pegou, `add_column` puro aborta com "column already exists" e
    # derruba o lote inteiro de migrations do deploy — custo alto pra um resíduo conhecido.
    #
    # ⚠️ Efeito colateral aceito: se a coluna tiver sobrado com definição DIFERENTE (sem
    # `null: false` ou sem default), esta migration a aceita em silêncio. É tolerável porque os
    # leitores do model tratam nil (`(apresentacao || {})`); mas se o resíduo aparecer, confira
    # a definição antes de popular.
    add_column :distribuicao_produtos, :apresentacao, :jsonb, null: false, default: {}, if_not_exists: true
  end
end
