# Handoff — sessão orquestradora geral · 11/08/2026

> Para quem assume o papel de **geral** depois desta sessão. Não é doc de frente: é o mapa de
> como despachar, o que está no ar, e o que o Paulo quer abrir a seguir.

---

## 1. O papel, e a regra que o define

A geral é a **única sessão com quem o Paulo conversa**. Ela traduz intenção em frentes, cria/usa
worktrees, despacha, recolhe, verifica, junta e **abre o PR**. O trabalho dela termina em *PR
aberto* — quem aprova PR e faz deploy é o **Walisson** (conta `Dev-Simplex` no GitHub). O Paulo
**não** aprova merge nem deploy; não o coloque nessa fila.

**Uma geral por vez.** O `chatspx` é um repositório só servindo vários clientes — duas gerais ao
mesmo tempo sobre as mesmas branches é o acidente de 29/07 num nível acima. Quando o tema mudar e
o contexto ficar pesado, **aposente a anterior e abra uma nova**; não faça as duas conviverem.

**Frente não precisa de orquestrador próprio.** Em 11/08 a `spx/followup` virou coordenadora de si
mesma e abriu 3 agentes **na mesma pasta**. Sub-worker com `--worktree current` compartilha
filesystem — não há isolamento. A regra que funcionou:

> Dentro da frente, paralelize **leitura** (medir, investigar, rodar suíte na `.232`, que escreve
> em `/tmp` da VM). **Escrita no checkout: um agente por vez.** Precisa de dois escritores? Worktree
> nova, nunca `current`.

---

## 2. Estado em 11/08

**Branches:** `origin/homologacao` em `ebadc3f978`; `origin/producao` em `19ad487573`, **7 commits
atrás**. As VMs de produção rodam `19ad48757`.

**Esperando o Walisson:**

| | |
|---|---|
| **PR #32** | `spx/fricoes` — prioridade de crédito no handoff + guarda do link do imóvel |
| **PR #33** | `spx/eval` — adendo dos `custom_attributes` (complemento do #30, já mergeado) |
| **PR #34** | `spx/campanhas` — disparo passa a respeitar quem respondeu PARAR |
| **`mrg_901`** | promoção `homologacao` → `producao`, enfileirada no Almirante |

Os 7 commits parados incluem **a imagem do header do disparo Pacaembu** (`public/pacaembu-ago26.jpg`),
que vivia só no disco da VM. Enquanto não descer, o asset segue sem rede — e o precedente já
aconteceu: o `inq-mapa.jpeg`, ainda hardcoded em `disparo_lead_job.rb`, está 404 desde junho.

**Frentes:** `eval`, `fricoes`, `campanhas` e `rodizio` fecharam e pusharam. A `followup` entregou 5
commits (o principal: as duas guardas da fila de encerramento) e ainda tinha sessão viva ao fim do
dia — **conferir se fechou e abrir o PR dela**, do mesmo jeito que os outros três.

**PRs #1–#7**, de maio, seguem abertos e sem decisão: fechar ou reviver.

---

## 3. Como despachar (receita testada em 11/08)

O atalho oficial `orca orchestration worker-start` **falha neste host** com `selector_not_found`
para todos os agentes conhecidos, em qualquer worktree. Causa não identificada. O caminho de baixo
nível, que o próprio guia sanciona, funciona:

```bash
orca orchestration run-create --objective "<objetivo>" --json
orca orchestration task-create --spec "<tarefa completa>" --json
orca terminal create --worktree "id:<repoId>::<path>" --title "<nome>" --command claude --json
orca terminal wait --terminal <novo-handle> --for tui-idle --timeout-ms 90000 --json
orca orchestration dispatch --task <task_id> --to <novo-handle> --from <seu-handle> --inject --json
```

O `--inject` entrega o spec mais o preâmbulo de ciclo de vida; o worker passa a reportar
`heartbeat` e, no fim, `worker_done` com `--outcome` e `--files-modified`.

**Três armadilhas que custaram quase uma hora:**

1. **Conta de agente precisa existir E estar ativa.** Sem isso, tudo falha como `selector_not_found`,
   que não sugere conta nenhuma. `orca account add` cria (login interativo, só humano roda); ativar
   é no app — não há comando de CLI.
2. **O handle do terminal fica obsoleto e a variável de ambiente mente.** Quando o painel é
   recriado, o `ORCA_TERMINAL_HANDLE` do processo aponta pra um terminal morto. Sintomas em cascata:
   `no_active_sender_terminal` → `consumer_fenced` → `stable_pane_required`. Ache o handle vivo em
   `orca terminal list --json` (o campo `preview` mostra o **seu próprio último comando** — é assim
   que você se identifica) e re-vincule com `run-use --id <run> --from <handle>`.
3. **`orchestration check` não aceita `--from`.** Ele lê o ambiente, que está obsoleto, e fenceia
   pra sempre. Sobrescreva na chamada, com o pane que o Run guardou:

```bash
PK=$(orca orchestration run-show --id <run> --json | ... coordinator_pane_key)
ORCA_TERMINAL_HANDLE=<handle-vivo> ORCA_PANE_KEY="$PK" \
  orca orchestration check --run <run> --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

**Não canalize o `--wait` por `head`** — o pipe fecha e mata a espera. E timeout **não é falha**:
tarefa de código roda de 15 a 60 minutos, batimento significa vivo, não pronto. Reinicie a espera.

Terminal **flutuante** é coordenador frágil: o pane muda sozinho e cerca o vínculo. Coordenador
numa aba de worktree tende a ser mais estável — vale testar.

---

## 4. Os dois baldes — a regra que mantém o SPX universal

O SPX é uma plataforma só, hoje bastante moldada pela Tozi porque é o caso de maior volume. Toda
necessidade de outro cliente cai num de dois baldes, e saber em qual é o que impede a plataforma de
virar um Frankenstein de um cliente:

**Balde 1 — comportamento.** Persona, conduta, tom, FAQ, quais tools o agente usa, prompt. Vive no
**banco daquela conta**, via helper do cliente ou Almirante (`ai_update_prompt`, `ai_set_tool`,
`ai_update_behavior`, com `ai_history` e `ai_rollback`). **Sem código, sem PR, sem deploy.** Muda no ar.

**Balde 2 — capacidade.** Tool que não existe, canal incompleto, motor novo. É **código
compartilhado**, precisa nascer **agnóstico** e gateado por conta. PR e deploy.

> **Teste de uma linha: se a mudança nomeia o cliente, ela está no balde errado.**

Foi por violar isso que a conduta de óticas da Fábrica vazou pra Tozi (revertida em `645b58ceb`). O
molde `enterprise/lib/captain/prompts/assistant.liquid` é de **todos** os clientes.

---

## 5. O que o Paulo quer abrir a seguir

**Fábrica dos Óculos** (contas 1/2, box `3.87.182.184`) — "tools e IAs com seus comportamentos" é
quase todo **balde 1**: configuração no banco das contas. Ciclo rápido, reversível, sem depender do
Walisson. Só vira balde 2 se aparecer capacidade que o SPX não tem.
⚠️ Do levantamento de 10/08: o box da Fábrica está **225 commits atrás**, sem os fixes de áudio, e
tem `session_store.rb` **modificado e não commitado** no disco — deployar por cima destrói alteração
local. Isso precisa de sessão própria **antes** de qualquer deploy lá.

**BigStore / Instagram** — é **balde 2**, e é justamente onde o SPX deixa de ser moldado só pela
Tozi. Lacunas já conhecidas: não existe HSM no Instagram (nada fora da janela de 24h); a conduta não
é consciente da janela; falta disclosure de IA; teto de 1.000 caracteres por mensagem;
`private_replies` nunca investigado; e a frente `bigstore-ig` não tem canal nem credencial de app.
⚠️ A flag `HUMAN_AGENT` (janela de 7 dias) é **proibida para bot** e o chatspx a aplica em **toda**
mensagem, globalmente na instância — cadência fora da janela exige ramo por canal.

As duas frentes são de **naturezas opostas** de propósito: uma mostra o ciclo curto sem dev, a outra
o ciclo completo com PR e deploy.

---

## 6. Armadilhas de verificação — foram elas que estragaram o dia 10/08

O padrão que se repetiu em 7 de 9 sessões não foi "teste não rodado": foi **verificação feita em
ambiente errado, ou por leitura, e reportada como fato**. A melhor formulação veio da própria frente
de follow-up:

> *"Verde em banco sujo e verde vazio são mais perigosos que vermelho, porque viram relatório."*

Concreto, e vale para você:

- **Baseline NÃO é `origin/homologacao`.** É o **próprio ramo sem o próprio commit**. Comparar branch
  atrasada contra a homologação produz acusação falsa — aconteceu em 10/08, com 18 "falhas" que eram
  defasagem.
- **O banco de teste da `.232` é compartilhado.** Em 11/08 a mesma suíte deu **0, 9 e 15 falhas** em
  três medições, porque três frentes rodaram junto. Use banco dedicado — e note que
  **`TEST_ENV_NUMBER` é inerte neste repo** (não há a gem `parallel_tests`): o `database.yml` resolve
  por **`POSTGRES_DATABASE`**. Existem `chatwoot_test` até `_7`; só o primeiro estava em dia.
- ⚠️ **O `.env` symlinkado na receita de CI é o de PRODUÇÃO.** O ambiente de teste só é seguro porque
  `POSTGRES_DATABASE` não está nele. É frágil: se um dia estiver, `RAILS_ENV=test` bate no banco de
  produção. Sempre exporte `POSTGRES_DATABASE` explicitamente.
- **Almirante mente às vezes.** Já reportou VM defasada que estava em dia (compara SHA de 10 contra 9
  caracteres) e "0 puma / 0 sidekiq" numa VM com 4 e 3 rodando. Quando a resposta importar, bata na VM.

E o erro que **eu** cometi hoje, duas vezes: **matei minha própria supervisão** — primeiro com um
`--from` que aquele comando não aceita, depois com um `head` que fechou o pipe — e nas duas afirmei
que estava supervisionando sem conferir a saída. Confira o retorno do comando antes de declarar que
algo está rodando.

---

## 7. Decisões abertas

1. **Bug do enum no segmentador de episódios** — `pluck` de coluna enum devolve rótulo, `type == 2`
   nunca casa, e a fronteira resolve→reopen nunca dispara. **33% dos episódios splitariam** se
   corrigido. Corrigir re-segmenta ~15.700 episódios e órfã os evals. Decisão do Paulo.
2. **Ligar `captain_episode_window` na conta 6** — o código desceu com o PR #30 mas nasce desligado.
   Antes de ligar: a `HumanHistoryNote` e a nota de episódio **discordam da data por construção**
   (uma ancora em `conversation_resolved`, a outra fecha por silêncio em 81,5% dos casos). Raro
   (2 em 400) mas certo. Definir qual nota é dona da data — muda comportamento que vale para todos
   os clientes.
3. **A frente de visualização não existe.** 13 categorias de dado que só se leem por SQL. A primeira
   entrega sugerida é a tela de `campaign_recipients` — 3.908 pessoas invisíveis, dado já pronto com
   oito status e erro por linha.
4. **Opt-out está refém do motor de Flows** (achado do PR #34): a tabela está vazia na instância
   inteira, o gravador só roda dentro do `run_flows` (desligado na conta 6), e o matcher compara
   contra 4 palavras exatas — das 23 recusas explícitas da inbox 99, **zero** foram capturadas. O
   PR fecha o vazamento; quem alimenta o opt-out ainda não funciona.
5. **Motor de distribuição com zero spec** (achado da `rodizio`), incluindo o `vista_card_service`,
   que escreve no CRM do cliente. Inócuo hoje porque sem política é no-op — mas ligar a política,
   que é a decisão travada no time, seria ligar sem rede.

---

## 8. Onde buscar o resto

| Preciso de... | Onde |
|---|---|
| O que está in-flight | `.claude/STATE.md` |
| Regras da plataforma, multi-cliente, Almirante | `AGENTS.md` |
| Fluxo de branches e frentes | `docs/WORKFLOW-GIT-SPX.md` |
| Ambientes por cliente (qual VM é de quem) | `scripts/ops/AMBIENTES.md` |
| Panorama de 10/08 e o levantamento das 9 sessões | `docs/APANHADO-2026-08-10.md` |
| Preferências do Paulo e gotchas acumulados | `MEMORY.md` do projeto |
