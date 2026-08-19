---
titulo: Repasse por SLA, fila e gatilho sem IA — Motor de Distribuição
status: CONSTRUÍDO (desligado em todas as contas)
data: 2026-08-19
tags: [spx, distribuicao, rodizio, sla, fila]
---

# Repasse por SLA, fila e gatilho sem IA

Três peças novas do `Spx::Distribuicao`. **Todas nascem desligadas.** Subir esta versão não muda
o comportamento de nenhuma conta — inclusive a 6, que segue usando `sla_assumir_minutos` apenas
como medida na tela do gestor.

## 1. O que mudou

| Peça | Coluna | Default | O que faz |
|---|---|---|---|
| Repasse por SLA | `distribuicao_policies.repasse_automatico` | `false` | Designação parada além do prazo passa ao próximo do rodízio |
| Teto de repasses | `max_repasses` | `2` | Quantas vezes o lead pode andar antes de escalar. `0` = sem teto |
| Escalação | `pool_esgotado_destino_user_id` | `nil` | Para quem vai quando o teto estoura ou o pool acaba |
| Gatilho sem IA | `gatilho_sem_ia` | `false` | Distribui quando um flow/regra troca o time, sem passar pelo handoff do Captain |
| Modo fila | `modo = 'fila'` | — | Pull: ninguém é escolhido, mas a espera ganha relógio e escalação |

E `distribuicao_logs.repasse_n` conta a que altura do ciclo cada linha está.

## 2. Por que isto não existia

A `sla_assumir_minutos` sempre foi **medida, não ação** — está escrito na migration de 31/07. O
motivo era da conta 6: repassar exigiria reescrever o `CorretorNegocio` de um card já criado no
Vista, capacidade não testada, e o `DELETE` do Vista responde 401. Errar custaria um lead que o
corretor já trabalhava.

**Essa amarra é do Vista, não do produto.** Onde não há Vista no meio, o repasse é seguro — daí
ele existir agora como opção, e não como comportamento.

## 3. Como o relógio conta

Em **horário de expediente**, lido do `working_hours` da inbox da conversa (o mesmo que o app usa
para o out-of-office). Um lead designado 18h50 de sexta não estoura um SLA de 30 min às 19h20 com
o corretor em casa. Inbox sem expediente habilitado cai no relógio de parede — o comportamento
honesto para quem atende 24/7 e não configurou nada.

## 4. Quando a designação fecha (e o cronômetro para)

Depende do `modo_posse`:

- **`assignee` (push) com repasse ligado** — "designado" passa a significar *atribuído e ainda sem
  primeira resposta*. Fecha na **primeira resposta humana** ao cliente, ou quando **outra pessoa**
  toma a conversa. Atribuir não é atender: é exatamente essa diferença que o SLA mede.
- **`designacao`** — inalterado: fecha quando um humano assume no painel ou quando o corretor
  engaja no card do Vista.
- **`fila`** — fecha quando alguém puxa a conversa.

## 5. O que acontece ao vencer

1. **Próximo** — ainda há gente no pool que não recebeu este lead e o teto não estourou →
   repassa (`motivo: repasse_sla`). Preferência e continuidade **não** se aplicam no repasse:
   apontariam de volta para quem deixou vencer e o lead nunca andaria.
2. **Gestor** — teto estourado, pool esgotado, ou modo fila (que não tem "próximo") → vai para
   `pool_esgotado_destino_user_id` (`motivo: escalado_gestor`). O destino **precisa ser membro do
   time**, senão a atribuição seria descartada em silêncio pelo `ensure_assignee_is_from_team`.
3. **Nada** — sem destino configurado, a linha fecha como `expirado` e a conversa volta a ficar
   sem dono. Inventar um destino seria pior que devolver o lead à fila.

Quem recebe por repasse **gasta a vez** no rodízio. Quem deixou vencer já tinha gastado a dele:
é a punição aritmética da SPEC §7.2 — ao longo do dia, quem não responde recebe menos.

## 6. Como ligar

```bash
# 1) a política do time (se ainda não existe)
bundle exec rails "spx:distribuicao:policy[<conta>,<time>,rodizio,<uid>:<cap>,<uid>:<cap>]"

# 2) o repasse: on/off, prazo em minutos, teto, destino da escalação
bundle exec rails "spx:distribuicao:repasse[<conta>,<time>,on,30,2,<user_id_do_gestor>]"

# 3) o gatilho sem IA (só se o time recebe conversa por flow/regra, não pelo handoff)
bundle exec rails "spx:distribuicao:gatilho[<conta>,<time>,on]"

# conferir
bundle exec rails "spx:distribuicao:show[<conta>,<time>]"
```

Para o modo **fila** (pull), use `fila` no lugar de `rodizio` no passo 1. A fila não tem próximo:
ao vencer, ela escala direto para o destino configurado.

Desligar é o mesmo comando com `off` — e o `sla_assumir_minutos` volta a ser só medida.

## 7. O varredor

`Spx::Distribuicao::VarrerSlaJob`, a cada 5 min (`config/schedule.yml`). Filtro grosso no banco
pelo índice `(status, designado_em)` usando o **menor** SLA entre as políticas ligadas; o prazo
real é conferido no relógio comercial, política por política. Teto de 200 linhas por rodada, para
que uma mudança de configuração que vença mil designações de uma vez saia em lotes.

**Sem nenhuma política com `repasse_automatico`, o job sai na primeira linha.** É por isso que
ligar o cron não muda conta nenhuma.
