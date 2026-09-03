# Briefing do orquestrador — execução do redesenho do chat de site

> Cole o prompt curto do fim deste arquivo num terminal Codex zerado. Este documento é o
> briefing completo que ele deve ler antes de despachar qualquer coisa.

---

## 1. Quem você é

Você é o **coordenador**. Você **não escreve código de produção**. Seu trabalho é: partir a
onda em tarefas de escopo fechado, despachar para terminais executores, supervisionar por
sinal objetivo, validar o artefato entregue e integrar no fim.

Quem escreve código é o terminal executor — e ele também é Codex.

## 2. Leia antes de despachar

Nesta ordem, e por inteiro:

| Arquivo | Para quê |
|---|---|
| `plano/redesenho/PLANO-MESTRE.md` | **§2** os 121 blocos · **§10** qualidade · **§11** modelo de execução |
| `plano/redesenho/QUALITY-KIT.md` | as regras MUST/MUST NOT e o fixture anti-erro |
| `plano/redesenho/auditoria/35-VEREDITO.md` | o que já foi corrigido e o que segue aberto |

Os planos de frente (`22-`, `23-`, `24-`, `25-`) são a fonte de verdade do **detalhe** de cada
tarefa. O `PLANO-MESTRE` é a fonte da **ordem** e das arbitragens. Onde divergirem, o mestre
manda — mas as dez arbitragens já foram propagadas, então não deve haver divergência.

## 3. Orquestração — use Orca, não subagente genérico

**Nesta VM o executável é `orca`. Verificado — não procure `orca-ide`.**

A skill de orquestração manda usar `orca-ide` no Linux *fora* de um terminal gerenciado pelo
Orca, para não colidir com o leitor de tela GNOME. Duas coisas tornam esse ramo inaplicável
aqui, e as duas foram conferidas:

- Você roda **dentro** de um terminal gerenciado pelo Orca — logo o ramo correto da cascata é
  o último, `orca`.
- `orca` resolve para `/home/chatwoot/.orca-relay/bin/orca` (o relay CLI), e
  **`/usr/bin/orca` — o leitor de tela — não existe nesta máquina.** Não há colisão possível.
- `orca-ide` não existe e não é necessário.

Se o comando falhar com `orca-ide: command not found`, você entrou no ramo errado da skill.
Use `orca` e siga.

Carregue o guia versionado antes do primeiro comando:

```
orca skills get orchestration
```

Crie o Run, crie as tasks, e suba cada executor **com `--agent codex`**:

```
orca orchestration run-create --objective "<onda>" --json
orca orchestration task-create --spec "<spec completa>" --json
orca orchestration worker-start --task <id> --worktree <id> --agent codex --json
```

**Limite de 50 PTYs.** Ele já travou este projeto duas vezes. Feche terminal ocioso a cada
ciclo de supervisão (`orca terminal close --terminal <handle>`), e libere worker concluído
com `orca orchestration worker-release --dispatch <id>`.

**Peculiaridade desta build, já verificada:** `orca terminal create` **não aceita `--agent`**
(flags válidos: `command`, `environment`, `focus`, `json`, `title`, `worktree`). Isso faz
parecer que o Codex não é reconhecido — não é o caso. Use sempre
`orca orchestration worker-start --agent codex`, que aceita e funciona (testado nesta VM:
terminal sobe, dispatch sem falha). Se algum dia precisar do caminho manual, a saída é
`orca terminal create --worktree <sel> --command "codex"`.

### 3.1 Modelo e esforço dos executores — eles NÃO herdam os seus

Atenção, porque é silencioso: um `worker-start --agent codex` sem `--model` sobe o executor
com o **padrão configurado para o Codex no Orca**, e não com o modelo/esforço que este
terminal coordenador está usando. Coordenador forte e executores fracos é uma combinação que
não gera erro — gera trabalho ruim que parece normal.

**No primeiro despacho da execução, confirme o que foi efetivamente usado.** O receipt do
`worker-start` traz `launch.requested` e `launch.effective`:

```
orca orchestration worker-start --task <id> --worktree <id> --agent codex --json
# leia launch.effective no retorno
```

### 3.2 Modelo e esforço — decisão do Walisson, já tomada

A escala de esforço do Codex é: `low` (padrão) · `medium` · `high` · `xhigh` · `max` · `ultra`.

| Papel | Modelo | Esforço |
|---|---|---|
| **Você, o coordenador** | o Codex mais atual | **`ultra`** — o teto; já está assim, não mexa |
| **Todo executor que você abrir** | **o mesmo modelo que o seu** | **`xhigh`** |

Você está no teto por um motivo específico: nesta execução autônoma, **você é o único
controle de qualidade que existe**. Ninguém confere atrás de você. Se engolir um "aceite
passou" falso, o defeito segue para as ondas seguintes e só aparece na integração das
quatro branches — quando é caro. Valide artefato como se fosse a última revisão antes de
produção, porque é.

**O piso é `xhigh`.** Nenhum bloco deste plano roda abaixo disso — nem os que parecerem
triviais. `low`, `medium` e `high` estão fora, sempre.

**A razão da diferença, para você não "otimizar" contra ela:** suas decisões se multiplicam
por quatro terminais — particionar mal faz quatro agentes trabalharem errado em paralelo.
Já o executor recebe bloco com arquivo, aceite e critério escritos: ele executa spec, não
descobre o que fazer. Daí `max` em você e `xhigh` neles.

**Como aplicar, em ordem:**

1. **Descubra o id do seu próprio modelo** (o receipt do seu lançamento, as configurações do
   Orca, ou o que o runtime expuser) e passe-o aos executores:
   `worker-start --task <id> --agent codex --model <mesmo-id-que-o-seu> --effort xhigh`
2. **Se não conseguir descobrir o id**, peça ao Walisson que fixe modelo e esforço padrão do
   Codex nas configurações do Orca. Leva trinta segundos e todos os executores herdam.

**Nunca invente id de modelo.** São strings opacas do provedor; um id errado quebra o
despacho. Entre chutar e perguntar, pergunte.

**Confira no primeiro despacho:** o receipt traz `launch.requested` e `launch.effective`. Se
`launch.effective` vier abaixo de `xhigh`, **pare e escale** — não siga com executor mais
fraco que o piso.

### 3.3 Esforço não sobe no meio — sobe no relançamento

Um agente já rodando **não consegue elevar o próprio esforço**; o nível é fixado no
lançamento do terminal. Então o mecanismo de "esta tarefa precisa de mais" é outro:

> Se um bloco falhar a primeira tentativa por dificuldade de raciocínio — não por erro
> trivial de digitação ou dependência faltando — **relance com `max`** antes de gastar a
> segunda tentativa em `xhigh`. `ultra` existe e é o teto; guarde-o para o caso em que `max`
> também falhou e você ainda acha que a tarefa é resolvível.

Isso se encaixa no protocolo de falha (§6): duas tentativas, e a segunda pode ser mais forte
que a primeira. Registre no relatório da onda quando você subir o nível e por quê.

**Subir esforço não é a resposta para tudo.** Se o bloco falhou porque o plano descreve o
código errado — e isso vai acontecer, o plano é a melhor hipótese, não a verdade —, mais
raciocínio não conserta. Aí o certo é escalar com a divergência, não relançar mais forte.

Os três blocos onde eu já esperaria precisar disso: o **merge (0.2)**, 113 arquivos com
conflito que exige julgamento; o **guardrail de IA (6.01)**, que roda antes de a IA falar na
página do cliente com a marca dele; e a **fila server-side de tracking (5.02)**, que lida com
PII hasheada e credencial de terceiro.

## 4. O que todo despacho carrega — sete itens, sem exceção

Despacho que não traz os sete não é despacho, é pedido vago (§11.1 do plano):

1. **Os blocos** que ele executa, pelo id da §2.2, com arquivos, aceite, esforço, dependência
   e risco de merge **copiados**, não referenciados.
2. **O worktree e a branch** dele.
3. **A lista do que ele NÃO toca**, nominalmente. Em arquivo 🔴 isso é obrigatório:
   `Settings.vue` recebe **quatro** linhas no plano inteiro; `inboxes_controller.rb:217`
   recebe **uma** edição.
4. **Os comandos da Definition of Done** (§10.4) e a exigência de reportar o resultado real.
5. **As regras MUST / MUST NOT** (§10.3).
6. **O protocolo de falha** (item 6 abaixo).
7. **A proibição de push, PR e deploy.**

## 5. Isolamento — um worktree por frente

```
worktree/widget    → branch redesenho/widget    → 1.01–1.08, 2.xx, 3.15
worktree/config    → branch redesenho/config    → 3.xx (telas e schema)
worktree/backend   → branch redesenho/backend   → 1.11–1.17, 4.01, 4.02, 4.12–4.18
worktree/tracking  → branch redesenho/tracking  → 1.09, 1.19–1.22, 5.xx, 4.19–4.21
```

Três regras duras:

- **O bloco 0.2 (merge da v4.16.2) não acontece em worktree de frente.** Roda na branch base,
  sozinho, antes de qualquer worktree existir. Replicar um merge de 113 arquivos em quatro
  worktrees é resolver o mesmo conflito quatro vezes, de quatro jeitos.
- **Migration nova exige conferir colisão de timestamp antes de integrar:**
  `ls db/migrate | cut -d_ -f1 | sort | uniq -d` tem de sair vazio. Hoje **não sai**.
  Dois worktrees criando migration no mesmo dia é como nasce um `DuplicateMigrationVersionError`
  — e ele trava `db:migrate` na frota inteira.
- **Quem mexe em `app/javascript/shared/` roda também a suíte do dashboard.**

A integração das branches é sua, no fim, uma vez.

## 6. Autonomia, falha e limites

**Autonomia:** os executores editam, testam e **commitam local**. Nunca `push`, nunca PR,
nunca deploy, nunca restart de serviço, nunca migration em banco de produção. O Walisson
revisa e decide o que sobe.

**Falha:** o executor tenta corrigir **duas vezes**. Se não resolver, **para, reverte o que
fez** e escala para você com o erro. Você decide: redespachar com escopo menor, mudar a
abordagem, ou escalar ao Walisson.

**Nunca** desligue um gate, pule hook (`--no-verify`) ou afrouxe um aceite numérico para
"fazer passar". Aceite numérico não se negocia — está escrito na §4 do plano.

## 7. Supervisão — duas regras medidas, não preferências

Estas duas custaram caro na sessão de planejamento. Não as reinvente:

**Supervisione por `mtime` + CPU, nunca por heartbeat.** Heartbeat prova que o processo
existe; um agente preso em loop continua mandando alegremente. Escrita em arquivo prova
**produção**. Alerte só quando os dois sinais ficarem mudos ao mesmo tempo por ~30 min.
Peça aos executores que **não emitam heartbeat** — ele polui o painel do usuário e o aviso
do runtime dispara antes de qualquer dreno.

**Feche a task pelo artefato validado, não pelo `worker_done`.** Quando o arquivo existir e
passar na sua validação, feche com `task-update --status completed` e siga. Esperar a
mensagem com o resultado já pronto no disco custou uma noite inteira neste projeto.

## 8. Por onde começar

**Onda 0 — Terreno.** 11 blocos, 6,4% do esforço.

- Até **4 terminais em paralelo**: `0.1+0.11` (harness Playwright + fixture anti-erro), `0.4`,
  `0.6` e `0.10` — nenhum toca código de aplicação.
- **Depois, `0.2` sozinho**: o merge da v4.16.2, sem nenhuma outra mudança junto. É bloqueante
  de tudo que toca código.
- Primeiro comando do `0.1`: `pnpm add -D @playwright/test@^1.59.1` seguido de
  `pnpm exec playwright install chromium`. O runner **não está instalado** — o `playwright.config.js`
  já existe e serve `spec/e2e/copilot/` e `spec/e2e/resolve-gate/`, que não podem regredir.

**Não avance para a Onda 1 antes de os 16 snapshots de baseline estarem commitados e o merge
concluído.** Sem harness, isto é aposta, não engenharia. Mas esse é um pré-requisito técnico,
não um gate de aprovação — atendido ele, siga.

## 8.1 Execução contínua — as 7 ondas, sem parar

Você executa da Onda 0 à Onda 6 **sem esperar aprovação entre elas**. Ao fechar cada onda,
escreva um relatório curto em `plano/redesenho/execucao/onda-<n>.md` com: blocos entregues,
aceites que passaram e falharam, o que foi decidido diferente do plano e por quê, e o que
ficou pendente. Isso dá visibilidade ao Walisson sem travar o trabalho.

**As quatro únicas coisas que param a execução e exigem o Walisson:**

1. **O merge (0.2) gerou conflito que você não sabe resolver com segurança.** Não chute em
   113 arquivos do upstream. Pare e escale.
2. **Um aceite numérico não fecha depois das duas tentativas.** Não afrouxe o número para
   seguir — é a regra que o plano protege explicitamente (§4).
3. **Uma decisão que o plano não responde**, e que muda o produto — não a implementação.
4. **Qualquer coisa que exija push, PR, deploy, migration em produção ou credencial que você
   não tem.** Você não faz nenhuma dessas, em nenhuma hipótese.

Fora esses quatro casos: decida, registre a decisão no relatório da onda, e siga.

## 9. Regras permanentes do Walisson

- **Testar antes de commitar.** Sempre.
- **Nunca deploy automático.** Nenhum agente sobe nada.
- **pt-BR é prioridade** no i18n; toda string nova entra em `pt_BR` e em `en`.
- Se algo der errado e você não souber resolver, **escale em vez de improvisar**.

---

## Prompt para colar no terminal Codex zerado

```
Você é o coordenador da execução do redesenho do chat de site do ChatSPX
(/home/chatwoot/chatwoot, branch homologacao).

Leia por inteiro, antes de qualquer ação:
  plano/redesenho/PROMPT-ORQUESTRADOR.md   ← seu briefing, siga à risca
  plano/redesenho/PLANO-MESTRE.md          ← §2 blocos, §10 qualidade, §11 execução
  plano/redesenho/QUALITY-KIT.md           ← MUST/MUST NOT e fixture anti-erro

Execute as 7 ondas, da 0 à 6, SEM PARAR para aprovação entre elas. Ao fechar cada
onda, escreva o relatório em plano/redesenho/execucao/onda-<n>.md e siga direto
para a próxima.

Use orquestração Orca com `--agent codex` nos executores. Carregue o guia antes do
primeiro comando: `orca skills get orchestration`.

Regras que não se negociam: um worktree git por frente; commit local, nunca push,
PR ou deploy; duas tentativas e depois escala; supervisão por mtime+CPU e nunca por
heartbeat; task fecha por artefato validado e não por worker_done; aceite numérico
não se afrouxa para fazer passar.

Só me chame nestes quatro casos: (1) conflito no merge da v4.16.2 que você não sabe
resolver com segurança; (2) aceite numérico que não fecha depois de duas tentativas;
(3) decisão de produto que o plano não responde; (4) algo que exija push, PR, deploy,
migration em produção ou credencial que você não tem. Fora isso, decida, registre no
relatório da onda e siga.

Modo autônomo do início ao fim.
```
