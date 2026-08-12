# Fechamento da frente `spx/followup` — 2026-08-11/12

> Documento de fechamento da sessão orquestrada. Serve pra abrir o PR da frente **sem depender
> do que ficou na tela de ninguém**. Escrito ao encerrar, sem rodar verificação nova.

---

## 1. O que os 6 commits entregam

A sessão fechou **quatro** das cinco tarefas planejadas e produziu seis commits. Duas são
**correções de código**: `30a6fd536e` conserta as duas guardas da fila de encerramento — o scan
deixou de varrer quem já espera atendente humano (antes essas conversas casavam com o escopo da
fila, pagavam classificação de LLM, podiam receber o aviso de "vou encerrar" e eram contadas em
duas filas ao mesmo tempo) e o marcador de encerramento passou a cair no `incoming` do cliente, e
não na transição de `waiting_since`; e `fd0a42dd1c` implementa a borda da janela no `FollowupJob`
(entrega 1) — **commit que esta sessão não verificou, ver §2**. Duas são **diagnósticos de
produção** que derrubaram a hipótese de partida: `2325bf7d9b` prova que a cutucada não morre
*depois* do handoff, ela **nunca chega a ser armada**, porque `ja_tem_destino?` enxerga o
`aguardando_humano_desde` que o próprio handoff acabou de escrever no mesmo turno; e `0349bf033a`
prova que a blindagem `campaign_without_reply?` não falhou nem foi neutralizada por resíduo — ela
**nunca foi exercida**, porque pergunta por `campaign_id` e o funil vivo da Tozi é Meta Lead Ads,
que jamais preenche esse campo. As duas restantes são **infraestrutura de confiança**:
`788ece5d89` fixa o baseline da suíte antes de qualquer mudança, e `d59802e91e` registra que a
`.232` é compartilhada por todas as frentes e que o `.env` symlinkado pelas receitas de CI é o de
**produção**.

| Commit | O quê |
|---|---|
| `2325bf7d9b` | diagnóstico: a cutucada não morre no handoff — nunca é armada |
| `788ece5d89` | baseline da suíte antes das tarefas B e C |
| `30a6fd536e` | **código** — as duas guardas da fila de encerramento |
| `0349bf033a` | diagnóstico: a blindagem de campanha não enxerga o disparo da Tozi |
| `d59802e91e` | a `.232` é compartilhada e o `.env` symlinkado é o de produção |
| `fd0a42dd1c` | **código** — a borda da janela no `FollowupJob` (entrega 1) |

---

## 2. O que foi verificado — e o que NÃO foi

### ✅ Verificado, com número e local

**Baseline** (`788ece5d89`) — rodado na **`.232`**, worktree `/tmp/ci-followup-a` + banco dedicado
`chatwoot_ci_fup_a`, ambos removidos ao final, `chatwoot_test` intocado:

**202 exemplos / 12 falhas.** Por arquivo: `followup_job_spec` 12/0 · `response_builder_job_spec`
43/0 · `inbox_pending_conversations_resolution_job_spec` 27/**3** · `enterprise/message_spec` 15/0
· `conversation_spec` 105/**9**. As 12 são preexistentes **por construção** (árvore idêntica à
`origin/homologacao`, sem uma linha da frente) e reduzem a duas causas-raiz de spec parada no
upstream: a validação *"Status cannot be Pending — feature disabled for this inbox"* (commit
`da2ea07ed1`, 17/04) responde pelas 9 do `conversation_spec`; o `ActivityMessageJob` recebendo ID
em vez do registro, mais `ai_actor` e locale pt_BR, pelas 3 do `pending_resolution`. **RuboCop:
16 offenses, todas no `response_builder_job.rb`**; os outros três arquivos zerados.

**Guardas da fila de encerramento** (`30a6fd536e`) — rodado na **`.232`**, `/tmp/ci-followup-c` +
banco `chatwoot_ci_fup_c`, ambos removidos, `chatwoot_test` intocado:

**211 exemplos / 12 falhas** = exatamente as mesmas 12 do baseline **+ 9 exemplos novos verdes**.
**RuboCop 0 offenses** nos arquivos tocados. **Teste de mutação nas duas guardas**: revertendo a
guarda A, 3 de 4 exemplos ficam vermelhos (o 4º é controle positivo); revertendo a guarda B, 2 de
5. Ou seja, os testes detectam de verdade.

**Diagnóstico do handoff** (`2325bf7d9b`) — scripts **read-only** em produção Tozi (conta 6), via
`rails runner`: 335 handoffs em 30 dias, mediana 0,78 h, **22,5% atravessando 12 h**, 42 sem
humano nenhum (pior caso 243,6 h), 74 (22,1%) sem uma palavra humana, 19 com o cliente sumindo sem
ninguém retomar. Nas duas conversas do apontamento o espelho sobreviveu **18h42** (22804) e
**20h02** (22798). **Zero Policy de rodízio e zero `distribuicao_logs` na conta 6.** A série de
handoff passou a existir: 374 eventos desde 04/08, 80 `handoff_auto_fired` desde 31/07.

**Diagnóstico do encerramento** (`0349bf033a`) — 5 scripts **read-only** em produção Tozi (conta
6): portões hoje são `captain_auto_resolve_mode=disabled`, `auto_closure={enabled:false,
max_dias:0}`, `captain_tasks=true`. **355 marcadores** (não 536 como dizia o handoff de 31/07),
datados de 01/08 (351), 02/08 (3) e 03/08 (1) — cada um com nota do classificador, logo
**comportamento reprodutível, não sujeira histórica**. Das 355, **nenhuma** tem campanha+sem-resposta;
as 248 sem nenhuma mensagem do cliente são **100% `meta_lead_ads`**. Custo medido: **634 chamadas
de LLM para produzir zero ação ao cliente** (0 avisos enviados, 0 fechamentos). Apenas **1**
conversa está presa de fato; 253 das 355 (71%) estavam armadas pra nunca serem soltas quando o
cliente voltasse. O gêmeo `awaiting_human_clearable?` foi verificado e **não** tem o mesmo vício.

### 🔴 NÃO verificado — dito com todas as letras

**O commit `fd0a42dd1c` (a borda da janela, entrega 1) não foi verificado por esta sessão.**

O worker responsável **nunca enviou `worker_done`**. A coordenação soube da existência desse
commit pela sessão integradora, não pelo worker. Concretamente, sobre `fd0a42dd1c`:

- **não foi rodada suíte** — não existe número de examples/failures para ele;
- **não foi rodado RuboCop** — não se sabe se introduziu offense no `followup_job.rb`, que estava
  em **zero** no baseline;
- **não foi feito probe nem teste de mutação**;
- **o diff não foi lido** por esta coordenação.

Não há lastro nenhum sobre essa entrega. **Trate-a como não verificada.** Qualquer número verde
atribuído a ela seria invenção.

---

## 3. O que ficou faltando

1. **Validar o `fd0a42dd1c`** — suíte na `.232` (com path e banco próprios, ver §4), RuboCop no
   `followup_job.rb` contra o baseline de **zero** offenses, e teste de mutação. É o primeiro item
   de quem pegar a frente.
2. **O teto do "esperando humano"** (regra 6 do contrato). Diagnóstico e proposta estão prontos em
   `docs/clientes/tozi/analise-conversas/2026-08-11-cutucada-morre-no-handoff.md`; a implementação
   foi **deliberadamente não feita**, por decisão do Paulo, porque o limiar precisa ser combinado
   com a frente `spx/rodizio`.
3. **A limpeza dos 355 marcadores residuais.** O `scripts/spx/tozi/limpa_marcadores_encerramento.rb`
   está escrito em **dry-run** e **não foi executado** — tocaria 355 conversas, todas paradas há
   mais de 3 dias. É decisão do Paulo.
4. **Duas correções em documento canônico**, ambas provadas erradas nesta sessão e ainda não
   aplicadas: a frase do contrato §4 *"a IA emudece exatamente quando o rodízio funciona"* (falsa
   na conta 6, que não tem Policy de rodízio nenhuma) e a **"aresta aceita"** do
   `docs/handoffs/spx-followup.md` — com o marcador presente o compromisso **não** é auto-curável
   pela tool, porque a `ProgramarFollowupTool` arma e o `followup_pointless?` descarta em silêncio
   no disparo.

---

## 4. Achados que valem para OUTRAS frentes

### 🔒 A `.232` é compartilhada — e o `.env` symlinkado é o de produção

Vale pra **qualquer sessão** que rode suíte ali, não só pra esta frente. Detalhe completo na §5 de
`docs/handoffs/spx-followup-baseline.md`.

- **Path de worktree é recurso global.** Havia worktrees de pelo menos quatro frentes convivendo
  (`/tmp/ci-camp-e1`, `/tmp/ci-eval`, `/tmp/ci-fri`, `/tmp/ci-base`). As receitas começam com
  `git worktree remove --force <path>; rm -rf <path>` — quem chega depois **apaga a árvore de quem
  está rodando**. Aconteceu de verdade nesta sessão: o path que a spec mandava usar já estava
  ocupado por outra frente, e obedecer à letra teria destruído os dois runs.
- **O banco de teste default é o MESMO para todos.** `config/database.yml` resolve
  `ENV.fetch('POSTGRES_DATABASE', 'chatwoot_test')` e o `.env` da VM **não define** a variável.
  Duas suítes simultâneas compartilham fixtures e limpeza de banco: uma trunca a tabela que a
  outra usa e as duas colhem falha **espúria**, que parece bug de código. **Path próprio sozinho
  não protege — precisa de banco próprio também.**
- **⚠️ O alerta mais sério:** o `.env` que as receitas mandam symlinkar é o de **produção** da
  `.232`, que atende clientes reais (contas 1, 3, 4 e 5) e traz `RAILS_ENV=production`. Hoje
  `RAILS_ENV=test` é seguro **só porque** `POSTGRES_DATABASE` está ausente. **No dia em que alguém
  definir essa variável nesse `.env`, a mesma receita aponta a suíte para o banco vivo — e `rspec`
  limpa o banco entre exemplos.** Confira a variável antes de rodar suíte com o `.env` de produção
  symlinkado.

### Para a frente `spx/rodizio`

Não existe **nenhuma** Policy de rodízio na conta 6 (0 policies, 0 `distribuicao_logs`) — a
premissa de que "o rodízio funciona e por isso a IA emudece" é falsa lá. A proposta de teto desta
frente pede que os dois limiares morem na Policy da `spx/rodizio`, com a invariante
`sla_retomada >= sla_assumir`, e que o `modo_posse` decida qual frente é dona do relógio
(designação = followup; assignee = rodízio, porque ali o espelho cai e o teto fica inerte por
construção). São 5 decisões listadas na seção de coordenação do relatório do handoff.

### Para quem mexer em encerramento, campanhas ou disparo

`campaign_without_reply?` pergunta por `campaign_id`, e o **Meta Lead Ads nunca preenche esse
campo**. Qualquer regra que dependa dele **não enxerga o funil vivo da Tozi**. As 5.950 conversas
de campanha sem resposta já estão resolvidas e fora da varredura, enquanto as 248 que realmente
importam são 100% `meta_lead_ads`. A recomendação registrada é fechar por **regra determinística
sem LLM** (um `NOT EXISTS` responde de graça o que custou 634 chamadas de LLM), opt-in por conta e
default off.

### Para quem orquestrar com Orca nesta casa

A entrega de prompt falhou **silenciosamente duas vezes** nesta sessão: o Orca reporta
`stage: input_accepted` (sucesso) mas o texto fica **parado na caixa de entrada do agente, sem
Enter**, e o agente nunca começa. Custou ~70 minutos. O sinal óbvio engana — `worker-read` cai em
`transcript_missing`, raspa o TUI e mostra só o preâmbulo, que é indistinguível de "trabalhando".
O diagnóstico confiável é cruzar três sinais: `last_heartbeat_at` nulo + `tui-idle` atingido de
imediato + nenhum arquivo escrito. O campo `terminal.preview` do `worker-show` mostra o texto
preso na caixa e é a prova definitiva. Conserto: `orca terminal send --text <nudge> --enter`, que
preserva o dispatch e não exige retry.

### Sobre escrever em worktree compartilhada

Workers lançados com `--worktree current` **compartilham filesystem e índice git** — não há
isolamento. Com dois escritores simultâneos, um deles commitou com `add` abrangente e engoliu o
arquivo do outro (`49a6bf15ea`); foi detectado e corrigido, e o histórico final está limpo, mas a
regra que ficou é: **paralelize leitura, serialize escrita**, e rode `git status` antes de cada
commit adicionando só os próprios arquivos por nome.
