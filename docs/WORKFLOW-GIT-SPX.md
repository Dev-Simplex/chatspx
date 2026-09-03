# Workflow de branches e worktrees — Chat SPX

> **Fonte da verdade** de como o trabalho flui no `chatspx`. Se uma sessão Claude (ou um dev)
> está em dúvida sobre "em que branch eu commito isto?", a resposta está aqui.
> Complementa: `AGENTS.md` (§Isolamento multi-cliente), `.claude/STATE.md` (in-flight),
> `scripts/ops/AMBIENTES.md` (mapa de deploy por cliente).

---

## TL;DR — a regra de uma linha

**A branch certa é escolhida pela PASTA que você abre, não por `git checkout` manual.**

- **Código compartilhado / plataforma** (vale pra todos os clientes) → repo principal `chatspx/`, numa **feature branch** (`feat/*`, `spx/*`). Nunca commite direto em `homologacao`/`producao`.
- **Operação de UM cliente** (conduta de IA, deploy, análise) → abra o Claude **na pasta-worktree do cliente** em `chatspx-clientes/<cliente>/` (cada uma tem `CLAUDE.local.md` fixando CLIENTE·CONTA·VM).

Abriu a pasta certa → está no lugar certo. Errar = abrir a pasta errada, não "estar na branch errada".

---

## Conceito rápido: worktree ≠ clone

Todas as worktrees do `chatspx` **compartilham o mesmo `.git`** (mesmo histórico, mesmos commits, mesmos remotes). O que muda entre pastas é só **qual branch está aberta em cada uma**. Por isso dá pra ter Tozi-produção e Tozi-homologação abertos ao mesmo tempo, em pastas separadas, sem ficar trocando de branch. Um `git fetch` numa pasta vale pra todas.

---

## Topologia de branches

| Branch | Papel | Quem commita | Onde roda |
|---|---|---|---|
| `feat/*`, `spx/*` | **Unidade de trabalho** — 1 branch por task/feature | qualquer dev | VM de teste do dev |
| `paulao` | **Branch de dev do Paulo** (VM pessoal de teste) | Paulo | VM Dev `paulao` |
| `nicolas` | **Branch de dev do Nicolas** | Nicolas | VM Dev `nicolas` |
| `homologacao` | **Staging** — integração antes de prod | via merge (não direto) | 1 VM `homologacao` (Proxmox) — contas 3/4/5 |
| `producao` | **Produção** — o único que **replica** pras VMs de cliente | via merge (não direto) | **5 VMs CRÍTICAS**: `producao` · `catatau` · `sentinela` · `tozi` (c6) · `fabrica` (c1/2) |
| `master` | Chatwoot upstream (open-source). **NÃO é o produto** — só a base do fork. Não tocar. | ninguém (só sync upstream) | — |

> ⚠️ **`paulao` precisa de reconciliação antes de reviver:** a branch `origin/paulao` está ancestral de `producao` (nada único), MAS a **VM `paulao` roda um commit à frente do `origin/paulao`** (trabalho off-git no box). Antes de resetar a branch, **fazer backup/push do que está na VM** — senão estranda. Ver "Reviver a branch de dev".

---

## O fluxo (dev VM → homologação → produção)

```
  feature branch (feat/*, spx/*)      ← onde o CÓDIGO é escrito, 1 por task
          │
          │  dev testa na SUA VM (branch de dev: paulao=Paulo, nicolas=Nicolas)
          ▼
     homologacao         staging (contas 3/4/5 — clientes reais leves)
          │
          │  valida em homologação
          ▼
     producao            → REPLICA pras 5 VMs de produção (catatau/sentinela/tozi/fabrica/producao)
```

**Promoção é sempre por merge + deploy gated** — nunca commit direto em `homologacao`/`producao`.

---

## O versionamento é git puro, pelo GitHub

Commit, push, PR, review e merge acontecem **no git e no GitHub** (`gh` ou a interface web).
Não há control plane, painel de aprovação nem canal paralelo — e não deve haver.

- Trabalho vive numa branch própria (`spx/*`, `feat/*`). **Nunca** commit direto em
  `homologacao` ou `producao`.
- `git push -u origin <branch>` no fim do dia. Branch local-only é trabalho que existe só neste
  notebook.
- Entrega = **PR contra `homologacao`**. Promoção `homologacao` → `producao` também por PR.
- **Merge é humano.** O Claude abre, descreve e revisa; quem aperta o botão é gente.

### As quatro formas de perder trabalho — todas já aconteceram aqui

1. **Commit em branch de PR já mergeado não chega a lugar nenhum.** Em 31/08 o `schedule.yml`
   foi corrigido na branch do PR #77, que fora mergeado dois dias antes: o commit ficou órfão e
   o digest voltou às 11h no boot seguinte. **Confira na branch de integração**, não na sua
   worktree: `git show origin/homologacao:<arquivo>`.
2. **Branch-limbo.** A `conciliacao/higiene-11ago` guarda documentos que nunca entraram na
   `homologacao`. Branch sem PR aberto = conteúdo que não existe para o resto do time.
3. **🔴 Merge feito no disco da box.** Em 01/09 um merge de 295 commits foi executado dentro da
   `.232`: ficaram 13 migrations pendentes, assets de quatro dias antes, e a box com **315
   commits que o GitHub não tem** — qualquer `checkout` ali os destrói. **Merge é no GitHub,
   sempre.** A box só recebe código que já está numa branch remota.
4. **Cherry-pick como rotina.** Cada cherry-pick cria um gêmeo com SHA diferente; em 02/09 eram
   **cinco pares**, e a próxima promoção conflita em cima de todos. Cherry-pick serve para
   hotfix isolado — e vem com PR de volta para a outra branch **no mesmo dia**, senão vira
   dívida silenciosa (foi assim que o `fix(auth)` ficou em produção e fora da homologação).

### Auditar divergência entre branches

Comparação por SHA dá falso-negativo quando houve cherry-pick. Compare por **patch-id**:

```bash
git fetch origin
git cherry -v origin/producao origin/homologacao   # "+" = não existe do outro lado
```

⚠️ **Faça isso numa cópia com `fetch` recente, nunca dentro da VM.** O deploy busca por refspec
e não atualiza `refs/remotes/origin/*`, então o git da box reporta commits "só na VM" que já
estão no GitHub — medido em 02/09: **18 commits fantasma** na VM da Tozi. Quem auditar de
dentro "resgata" o que não está perdido.

---

## Deploy: não há auto-pull — e deploy direto na VM é EXCEÇÃO

**Nenhuma VM faz auto-pull** (confirmado 08/07, 29/07 e 02/09). Mergear em `homologacao` não
desce nada ao vivo. Isso **não** transforma "entrar na VM" em passo de rotina:

- **O padrão é o merge.** A entrega da sessão termina no PR mergeado. Se o código precisa chegar
  ao cliente hoje, isso é uma conversa com o Paulo — não uma decisão da sessão.
- **Deploy direto na VM só em caso extremo** (produção quebrada, cliente parado) e **sempre com
  autorização explícita do Paulo na hora**. Autorização de um deploy não vale para o próximo.
- Quando for: **medir na box antes** (`git log -1`, `git status`, `db:migrate:status`, quantos
  commits de diferença) → `git merge --ff-only` (nunca `reset --hard`) → `db:migrate` →
  precompile **se houve arquivo de front** → restart do worker antes do web.
- **Antes de qualquer restart:** `rails db:migrate:status`. Migration pendente + restart = 500
  em cadeia.
- **Nada de arquivo solto por `scp`.** Foi assim que nasceu o off-git de junho. Se precisar
  transportar sem credencial git na VM, use `git bundle` — mantém o git da box consistente.

### Arquivo de produto que só existe no disco da VM

Imagem de campanha, asset servido por URL: se não está no git, some no próximo deploy **sem
erro nenhum** — e a Meta busca a URL no instante do envio. O `inq-mapa.jpeg` está 404 desde
08/06 por isso. Todo arquivo que o produto serve entra no git, **nas duas branches**.

---

## Onde cada tipo de sessão trabalha

**A) Código compartilhado / plataforma** → pasta `chatspx/` (repo principal)
- Feature branch por task → merge em `homologacao` → merge em `producao`.
- Ex.: motor de rodízio, receptor de config IA, mudança em `enterprise/`, UI.

**B) Operação de um cliente** → pasta-worktree em `chatspx-clientes/`:

| Pasta | Cliente | Conta | Branch (detached) | VM |
|---|---|---|---|---|
| `chatspx-clientes/tozi-prod/` | Tozi 🔴 PROD | 6 | `producao` | `tozi` (`3.82.215.109`) |
| `chatspx-clientes/tozi-hml/` | Tozi HML | 3 | `homologacao` | `homologacao` |
| `chatspx-clientes/fabrica/` | Fábrica/Atacadão | 1/2 | base prod | `fabrica` (`3.87.182.184`) |

> **Comportamento de IA (prompt/persona/tom/conduta) NÃO é código.** Vive no **banco de cada conta**, não replica entre VMs, e se mexe pelo helper daquele cliente (`scripts/ops/<cliente>.sh`), com **backup antes e comando de reversão anotado**. Só `producao` (código) replica. Ver `AGENTS.md` §Isolamento.

> **Ler conversas / diagnosticar comportamento** = SSH no banco da VM. Independente da branch do worktree local — dá pra analisar a conta 6 por SSH mesmo com o worktree local desatualizado.

### Worktrees de task (efêmeras) — não confundir
`.claude/worktrees/*` (ex.: `tozi-eval`, `tozi-handoff`, `tozi-rodizio`) são worktrees **por task**, estilo Codex, isoladas pra uma feature. Descartáveis. Diferente das `chatspx-clientes/*`, que são **fixas por cliente**.

---

## Frentes de trabalho em paralelo — `chatspx-frentes/*` (criadas 29/07)

**Por que existem:** o git não permite duas worktrees na mesma branch. Enquanto todas as sessões
compartilhavam a pasta `chatspx/` (única com a `homologacao` aberta), trabalho paralelo virava
colisão — em 29/07 duas sessões commitaram na mesma worktree em 9 segundos e uma quase regrediu
o fix da outra. Uma frente = uma pasta = uma branch resolve isso na raiz.

| Pasta | Branch | Frente |
|---|---|---|
| `chatspx-frentes/rodizio/` | `spx/rodizio` | rodízio, handoff reservado, SLA, espelho do card no Vista |
| `chatspx-frentes/followup/` | `spx/followup` | follow-up, encerramento, agendamento, notificações |
| `chatspx-frentes/eval/` | `spx/eval` | Eval 2.0 (F3 outcomes, F5 golden set), sentimento, abordagem |
| `chatspx-frentes/campanhas/` | `spx/campanhas` | Meta Leads, analítico de campanha, módulo de disparo |
| `chatspx-frentes/fricoes/` | `spx/fricoes` | fricções de uso (erro de envio, lida/não-lida, chaves, link do site) |

Cada pasta tem um `CLAUDE.local.md` com o escopo da frente, as peças que já existem (pra não
reinventar) e os guard-rails. Nova frente: `git worktree add ../chatspx-frentes/<nome> -b spx/<nome> origin/homologacao`.

### Onde rodar teste e lint (as worktrees não têm Ruby)

Nenhuma worktree de frente tem Ruby, então `rubocop` e `rspec` **não rodam localmente** — o hook de
pre-commit quebra por ambiente e as frentes acabam entregando "verificado por leitura". Em 31/07
isso cobrou o preço: a `spx/followup` entregou três commits de lógica de fila; na primeira execução
real, **4 de 55 exemplos falharam**, incluindo o próprio fix central e uma regressão que ela mesma
tinha introduzido.

**A VM de homologação (`192.168.8.232`) é o box de CI** — tem ruby 3.4.4, rspec 7 e os bancos
`chatwoot_test` até `chatwoot_test_7`. A receita usa um **git worktree em `/tmp`**, então **não
toca o checkout que serve as contas 3/4/5**:

```bash
H=scripts/ops/tozi-hml.sh
# 1. cria o worktree isolado a partir da branch da frente
bash $H chatwoot "cd /home/chatwoot/chatwoot; git fetch origin --quiet; \
  git worktree add --detach /tmp/ci-<frente> origin/spx/<frente>"
# 2. o .env fica por symlink (não copia segredo pro /tmp)
bash $H chatwoot "ln -sf /home/chatwoot/chatwoot/.env /tmp/ci-<frente>/.env"
# 3. specs e lint
bash $H chatwoot "cd /tmp/ci-<frente>; RAILS_ENV=test bundle exec rspec <arquivos>"
bash $H chatwoot "cd /tmp/ci-<frente>; bundle exec rubocop <arquivos>"
# 4. limpeza
bash $H chatwoot "cd /home/chatwoot/chatwoot; git worktree remove --force /tmp/ci-<frente>"
```

Sem o symlink do `.env` o rspec morre em `PG::ConnectionBad: no password supplied` — o worktree não
herda a configuração do banco.

**Para lint isolado** (sem precisar da branch pushada) dá pra empacotar só os arquivos alterados e
comparar contra o baseline do mesmo arquivo — foi assim que as frentes `resgate` e `fricoes` foram
conferidas. ⚠️ Rodando a partir de `/tmp`, os `Exclude:` do `.rubocop.yml` que são por caminho
(ex.: `spec/**/*`) **não casam** e geram falso positivo; para specs, rode de dentro do worktree.

### Contrato das frentes
1. **Executora commita só na própria `spx/<frente>`.** Nunca em `homologacao`/`producao`.
2. **Só a sessão da pasta `chatspx/` integra** — ela é a única que abre os PRs de promoção e
   conduz deploy. As frentes não pusham `homologacao`/`producao`.
3. **Fim de sessão: `git push -u origin spx/<frente>`.** Branch local-only = trabalho que vive só
   no notebook.
4. **Fecha na sessão: merge ou delete.** Branch órfã é lixo — em 29/07 havia 6 delas
   (`spx/fix-fotos-handoff*`, `tmp/f*-eval`, `worktree-tozi-eval`) cujo conteúdo já estava em
   `producao` por cherry-pick, só confundindo quem auditava.
5. **Bug de outra frente: anote e avise, não corrija.** Duas frentes no mesmo arquivo é como
   nasce o conflito de linhagem tripla.

### Se uma sessão de CLIENTE precisar mexer em código compartilhado
Não vá pra pasta `chatspx/` commitar. Use (ou crie) a worktree da frente correspondente — foi
por essa lacuna que a sessão da Fábrica commitou na worktree primária em 29/07.

---

## Regras não-negociáveis

1. **Nunca commitar direto em `producao` nem `homologacao`.** Sempre via feature branch → PR → merge.
2. **Merge de PR e deploy são gates humanos.** O Claude abre e revisa; humano aprova (anti-self-review).
3. **`master` não se toca** — é o upstream do Chatwoot, não o produto.
4. **Toda branch de trabalho deve estar no `origin` no fim do dia.** Branch local-only = trabalho que vive só no notebook (risco de perda total). Idem: commit no box de dev que nunca sobe pro GitHub.
5. **Nunca mergear dentro de uma VM.** Merge é no GitHub; a box só recebe o que já está numa branch remota.
6. **Antes de `restart` em prod:** `rails db:migrate:status` (migration pendente + restart = 500 em cadeia).

---

## Higiene de branches

- **Fim do dia:** `git push` de toda feature branch com trabalho novo (mesmo WIP). O `origin` é o backup.
- **Feature branch mergeada:** pode deletar local + remota depois de confirmar que entrou em `homologacao`.
- **Detectar o que ficou de fora** (commits fora de prod/homolog):
  ```bash
  git rev-list --count <branch> ^origin/producao ^origin/homologacao   # >0 = tem trabalho não promovido
  git branch -r --contains <sha>                                       # vazio = commit só local
  ```

---

## Reviver a branch de dev (`paulao`) no modelo "cada dev sua VM"

A VM `paulao` existe e está viva, mas roda commit à frente do `origin/paulao` (off-git). Sequência **segura**:

1. **Backup do box primeiro:** SSH na VM `paulao`, `git push origin paulao` (ou salvar o patch de `a1ca9dd81`). Só depois de garantir que nada da VM vive só lá.
2. Resetar `paulao` sobre a base atual: `git checkout paulao && git reset --hard origin/homologacao` **(destrutivo — só com OK explícito e após o passo 1)**.
3. VM do Paulo trackeia `paulao`; dev testa lá; promove pra `homologacao` por merge/PR.
4. Espelhar o mesmo pra `nicolas`.

---

## Pendências de reconciliação (auditoria 2026-07-08)

- 🟢 **`feat/aguardando-atendimento`** — 3 commits de handoff (Paulo, 24/jun) — **pushados pro origin em 08/07** (não vive mais só no notebook).
- 🟡 **VM `paulao` à frente do `origin/paulao`** (`a1ca9dd81`) — reconciliar/pushar antes de reviver a branch.
- 🟡 **VM `homologacao` à frente do `origin/homologacao`** (commits do Nicolas no box) — reconciliar com o GitHub.
- 🟢 `origin/paulao`, `origin/nicolas`, hotfix FK CASCADE, migration do eval: já reconciliados/salvos.
