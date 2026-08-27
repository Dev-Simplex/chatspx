# Orquestração no Orca — a prática que funciona

> Derivado do guia oficial (`orca skills get orchestration --full`) **e** dos erros medidos na sessão
> de 12/08/2026, que gastou meia dúzia de horas descobrindo na marra o que o guia já dizia.
> **Leia isto antes de despachar o primeiro worker.** Substitui a receita do
> `docs/handoffs/orquestracao-geral-2026-08-11.md`, que está errada em dois pontos (§7).

---

## 1. A regra que evita 90% da dor

**Use `worker-start`, não `terminal create` + `dispatch --inject`.**

```bash
orca orchestration run-create --objective "<objetivo>" --json
orca orchestration task-create --spec "<tarefa completa>" --json
orca orchestration worker-start --task <task_id> --worktree <seletor> --agent claude --json
```

O caminho de baixo nível **funciona e entrega**, mas o dispatch que ele cria é invisível para o
ciclo de vida: `worker-release`, `worker-show`, `worker-read` e `worker-abandon` respondem
`dispatch_not_found`. Consequência medida em 12/08: workers que já tinham entregue continuaram vivos
emitindo batimento, o Orca passou a rejeitar com *"capability is revoked"*, e cada rejeição virou
notificação para o usuário. **Não havia como liberá-los porque nunca houve como liberá-los.**

Baixo nível só quando `worker-start` não expressa a topologia (argv customizado, por exemplo).

## 2. Preste contas de todo worker que terminou — antes de esperar de novo

Do guia, literal: *"Coordinators must account for every settled worker terminal before waiting again
or ending the turn."* Depois de cada `worker_done` aceito, escolha **uma**:

| situação | comando |
|---|---|
| tem tarefa nova para o mesmo agente | `worker-start --task <nova> --terminal <handle>` |
| não tem | `worker-release --dispatch <id>` |
| o usuário pediu para manter vivo | `worker-retain --dispatch <id>` |

**Nunca** libere por timeout, TUI ocioso, batimento, pergunta ou escalação. Liberar é limpeza
pós-conclusão, não cancelamento — e worker liberado continua legível por `worker-read`.

## 3. O laço de supervisão é um comando só

```bash
orca orchestration check --ack <delivery_id> --wait \
  --types worker_done,escalation,question --timeout-ms 900000 --json
```

- `check` devolve a Delivery FIFO mais antiga e **repete o mesmo lote** até você dar `--ack`.
- Processe **todas** as mensagens do lote antes de confirmar.
- **Timeout e `count: 0` são checkpoint, não falha.** Tarefa de código roda de 15 a 60 minutos.
  Rearme a espera.
- Só **um waiter por Run**. Um segundo devolve `waiter_exists` — confira se já existe antes de armar.
- ⚠️ Não canalize o `--wait` por `head`: o pipe fecha e mata a espera.
- ⚠️ Não dispare com `nohup ... &`: ele segura a vaga de waiter e some do rastreamento do harness,
  então você não é avisado quando chega resultado.

## 4. Batimento: peça um recibo, depois silêncio

O guia diz que o worker manda batimento **só quando o preâmbulo pede**. A calibragem que funciona:

> *"Emita UM heartbeat ao começar, como recibo, e depois siga em silêncio até o `worker_done`."*

Sem recibo nenhum você não distingue **worker trabalhando** de **worker que nunca recebeu a tarefa** —
aconteceu em 12/08, com uma frente parada por meia hora enquanto o dispatch dizia `dispatched`.
Com batimento contínuo, o usuário vira caixa de entrada. Um recibo resolve os dois.

**`status: dispatched` significa "eu mandei", não "está rodando".** Confirme que pegou: o título do
terminal muda para o nome da tarefa, e `dispatch-show` passa a ter `last_heartbeat_at`.

⚠️ **Pedir silêncio na spec não segura.** Medido em 12/08 com cinco workers: a linha "emita um
heartbeat e depois silêncio" é obedecida no começo e esquecida no meio do trabalho. O que funciona é
`orchestration send` **durante** a execução, pedindo para parar — os cinco pararam depois da
mensagem. Então: peça o recibo na spec, e mande parar assim que ele chegar.

⚠️ **`terminal list` mente por alguns segundos depois de fechar.** Logo após `terminal close`, a
listagem ainda mostra os terminais fechados. Confira de novo antes de concluir que a limpeza falhou —
e nunca feche "de novo por garantia" sem reler os handles, porque eles mudam.

## 5. Worktree: só quando há conflito de verdade

O guia é explícito: *"Independent tasks, parallel execution, convenience, or a preference for
separate checkouts are not isolation requirements."* Crie worktree quando o usuário pedir **ou**
quando houver conflito concreto — o caso legítimo mais comum aqui é **duas frentes de código que
precisam de branches diferentes**, porque um checkout só não segura duas branches.

Para paralelismo **dentro** da mesma worktree, crie um terminal de agente por worker. É o padrão da
frente que virou coordenadora de si mesma em 11/08 e deu errado por outro motivo (escrita
concorrente): leitura pode paralelizar, **escrita no checkout é um agente por vez**.

Quando criar worktree, use **agent-first**:

```bash
orca worktree create --name <nome> --agent claude --setup run --json
# handle em result.agentTerminalHandle (fallback: startupTerminal.handle)
```

Criar em dois passos (`worktree create` e depois `terminal create --command claude`) **deixa um shell
órfão ao lado do agente** — em 12/08 sobrou um por worktree, e eles aparecem como lixo na lista.

## 6. Identidade e vínculo — o que engana

- **Omita `--from`.** O Orca resolve do terminal atual. Só use ao impersonar.
- O vínculo do Run se perde quando o painel é recriado **ou quando você faz `cd` para outra
  worktree** — o erro é `run_required` ou `no_active_sender_terminal`, mesmo com Run recém-criado.
  Passe caminho absoluto em vez de `cd`, e sobrescreva `ORCA_TERMINAL_HANDLE`/`ORCA_PANE_KEY` na
  chamada quando precisar.
- **Como saber qual terminal é o seu:** o `run-create` detecta o pane do ambiente de quem o executa,
  então o `coordinator_pane_key` do Run recém-criado **é o seu pane**. Guarde esse `tabId:leafId`; o
  handle troca quando o painel é recriado, o pane não.
  ⚠️ **Não** se identifique pelo `preview` do `terminal list`: um terminal flutuante onde o prompt foi
  colado exibe esse texto e parece você. Em 12/08 isso levou a vincular o Run ao terminal errado e a
  supervisão morreu junto com ele.

## 7. Correções ao handoff de 11/08

1. **"`worker-start` falha neste host com `selector_not_found`"** — a causa é conta de agente
   inexistente ou inativa, não o comando. O próprio handoff diz isso duas parágrafos abaixo e mesmo
   assim conclui pelo caminho de baixo nível. Teste `worker-start` antes de abandoná-lo.
2. **"o campo `preview` mostra o seu próprio último comando — é assim que você se identifica"** —
   não é confiável. Use o pane do `run-create` (§6).

## 8. Perguntas, respostas e recuperação

```bash
# worker bloqueado:
orca orchestration ask --question "<pergunta>" --options "a,b" --timeout-ms 600000 --json
# coordenador:
orca orchestration reply --id <msg_id> --body "<resposta>" --json
```

⚠️ Texto em português passando por `--body` no Bash do Windows **corrompe acento**. Mande um adendo
em ASCII com o que for crítico, ou escreva o valor decisivo sem acento.

Recuperação é condicional, nunca uma sequência destrutiva fixa:

| `worker-show` diz | faça |
|---|---|
| `ready` | continue esperando, ou leia saída limitada |
| `failed` / `stopped` | `worker-start --task <t> --retry-of <id>` com placement explícito |
| `outcome_unknown` | `worker-stop` e inspecione, ou `worker-abandon` aceitando recurso vivo |

## 9. Higiene ao fechar

Antes de encerrar a sessão: nenhum worker liberado pendente, nenhum shell órfão, `/tmp` das VMs
limpo, e o `.claude/STATE.md` atualizado. O estado que só existe na conversa **não existe**.
