# Plano — Alinhamento de branches (homologação ↔ produção + VMs dev)

**Data:** 2026-07-09
**Escopo:** `homologacao`, `producao`, máquina `.232`, VMs dev `paulao` e `nicolas`.
**FORA de escopo (decisão Walisson):** `develop` (tratada como morta) e `fabrica` (produção Atacadão com 159 commits off-git — sessão dedicada com o Paulo).
**Execução:** eu executo, **sempre com backup antes** e reportando cada passo. Nada roda sem greenlight por fase.
**Referência do modelo:** `docs/WORKFLOW-GIT-SPX.md` (fonte da verdade do fluxo `feat/* → VM dev → homologacao → producao`).

---

## 1. Estado atual (verificado 09/07)

| Ref / Máquina | HEAD | Situação |
|---|---|---|
| `origin/producao` | `985db1f9f` | Fonte de verdade. Frota (5 VMs) alinhada ✅ |
| `origin/homologacao` | `9798186e8` | **1 commit atrás da prod** (falta o `fix(migration)` `985db1f9f`) |
| `.232` local (branch `homologacao`) | `26d45df7a` | Atrás do origin + WIP redundante (`conversation_eval`, já commitado no origin) |
| `origin/paulao` | `29a32046f` | 361 atrás, **nada único** (branch velha) |
| `origin/nicolas` | `5170569e2` | 269 atrás, **nada único** (branch velha) |
| VM **paulao** (`192.168.8.100`, `paulo`/master123) | `a1ca9dd81` (br `paulao`) | Trabalho (funil+HSM) **já promovido em prod**; só WIP `hook_execution_service.rb` |
| VM **nicolas** (`192.168.8.98`, `nicolas`/master123) | `62ba7ebbc` (br `nicolas`) | até **144 commits** no cache local fora das remotes + 2 WIP — **AUDITAR quantos são únicos** |

**Fatos que guiam o método:**
- `origin/homologacao` (`9798186e8`) é **ancestral** de `origin/producao` (`985db1f9f`) → alinhar é **fast-forward** (seguro, sem merge/conflito).
- VMs dev **não têm credencial GitHub** → backup/deploy por **git bundle** (via `.232`, que tem credencial).
- Regra do doc: **push em homolog/prod = gate humano**; aqui o Walisson autorizou eu executar com backup.

---

## 2. FASE 0 — Backup do off-git (URGENTE, não-destrutivo)

**Objetivo:** garantir que nada que só vive nas VMs se perca (regra 4 do doc). Zero impacto em produção.

### 0.1 — Auditar o que a VM nicolas tem de único
Na VM nicolas, medir quantos commits realmente não estão em `producao`/`homologacao` (o "144" usa o cache velho da VM):
```bash
# na .232: levar refs atuais pra VM nicolas via bundle
git bundle create /tmp/refs.bundle origin/producao origin/homologacao
scp /tmp/refs.bundle nicolas@.98:/tmp/    # (askpass master123)
# na VM nicolas (como chatwoot):
git fetch /tmp/refs.bundle 'refs/heads/producao:refs/spx/producao' 'refs/heads/homologacao:refs/spx/homologacao'
git rev-list --count nicolas ^refs/spx/producao ^refs/spx/homologacao   # N = commits GENUINAMENTE únicos
```
- **N = 0** → trabalho do Nicolas já está em prod/homolog → reset da VM (Fase 3) é seguro.
- **N > 0** → há trabalho não promovido → segue 0.2 (backup) e **não reseta sem OK do Nicolas**.

### 0.2 — Backup das VMs para o origin (branches de segurança)
Via bundle (VMs sem credencial):
```bash
# VM nicolas → .232 → origin
#   na VM: git bundle create /tmp/nicolas.bundle nicolas --not refs/spx/producao
#   (+ WIP: git stash create → incluir o SHA no bundle, ou git diff > nicolas-wip.patch)
scp nicolas@.98:/tmp/nicolas.bundle .232:/tmp/
#   na .232:
git fetch /tmp/nicolas.bundle 'refs/heads/nicolas:refs/heads/nicolas-backup-20260709'
git push origin nicolas-backup-20260709        # backup imutável no GitHub
# idem paulao (só a WIP hook_execution, já que os commits estão promovidos):
#   git diff hook_execution_service.rb > paulao-wip-20260709.patch  → guardar no origin/scratchpad
```
**Validação:** `git ls-remote origin | grep backup-20260709` mostra os refs. A partir daqui, nada da nicolas vive só na VM.
**Risco:** nenhum (só cria refs novas). **Rollback:** deletar a branch de backup.

---

## 3. FASE 1 — Alinhar `homologacao` = `producao`

**Objetivo:** levar o `fix(migration)` (`985db1f9f`) pra homologação, para `homologacao == producao`.

**Por que é seguro:** `9798186e8` é ancestral de `985db1f9f` → é **fast-forward** (não reescreve nada, não conflita).

```bash
# na .232 (com credencial):
git fetch origin
git merge-base --is-ancestor origin/homologacao origin/producao   # confirma FF (exit 0)
git push origin origin/producao:homologacao                        # FF: origin/homologacao 9798186e8 → 985db1f9f
git ls-remote origin homologacao                                   # deve == 985db1f9f
```
**Nota de processo:** idealmente o fix teria sido uma feature branch mergeada nas duas; como já está em prod (hotfix sob deploy), este back-merge é a reconciliação. Registrado no doc.
**Rollback:** `git push origin 9798186e8:homologacao` (a ref antiga é conhecida).
**Impacto ao vivo:** nenhum — não há auto-pull; a `.232` só muda na Fase 2.

---

## 4. FASE 2 — Sincronizar a `.232` SEM PERDER trabalho ⚠️ (corrigido)

**⚠️ A branch local NÃO pode receber `reset --hard` cego** — ela **divergiu**: tem **2 commits ÚNICOS** que não existem em NENHUMA branch do origin:
- `fb5430fef feat(automacoes): remediação da auditoria do canvas — blockers, paridade, a11y, testes`
- `26d45df7a fix(automacoes): corrige cor e layout dos inputs do canvas`
- **+2.040 linhas** (novos nós de config + ~1.400 de testes/specs). Quase **zero conflito** com o origin (arquivos tocados 0× lá; só `ConfigPanel.vue` 1×).

Já os **5 arquivos rastreados modificados** na working tree (`notification_builder`, `resolve_lid_job`, `waha/api_service`, `sentry` + `db/schema.rb`) NÃO têm conteúdo único: os 4 de código são **idênticos ao origin** (0 linhas exclusivas — fixes já commitados; a branch local é que está atrás) e o `schema.rb` é **auto-gerado** (regenera no `db:migrate`). Untracked (`conversation_eval`, `plano/`, `mockups/`, `.bak`) o reset nem tocaria — mas não vamos arriscar.

**Sequência segura (backup primeiro, nada de reset cego):**
```bash
cd /home/chatwoot/chatwoot
# 1) SALVAR os 2 commits numa feature branch + push (nunca mais vivem só na .232)
git branch feat/automacoes-canvas-remediacao 26d45df7a
git push origin feat/automacoes-canvas-remediacao
# 2) SALVAR a working tree inteira num stash (reversível, inclui untracked)
git stash push -u -m "wip-232-align-20260709"
git fetch origin
# 3) Realinhar a branch homologacao à base atual — ESCOLHER:
#    (a) rebase — mantém os 2 commits em cima da base (linear, resolve ConfigPanel.vue se conflitar):
git rebase origin/homologacao
#    (b) OU reset p/ base limpa (só AGORA é seguro: os 2 commits estão na feat branch + stash):
#        git reset --hard origin/homologacao   # e promover a feat branch por PR depois
```
**Destino dos 2 commits (decisão pendente):** são melhorias reais com testes e quase sem conflito → **promover via PR** `feat/automacoes-canvas-remediacao → homologacao` (gate humano). Ou manter na feature branch pra você revisar. **Não descartar sem OK.**
**Validação:** `feat/automacoes-canvas-remediacao` visível no `git ls-remote origin`; branch local realinhada; `git stash list` com a rede de segurança.
**Rollback:** `git stash pop` + `git reset --hard 26d45df7a` (ou a feature branch no origin).
**Risco:** eliminado — nada é tocado antes de estar salvo em 2 lugares (feature branch no GitHub + stash).

---

## 5. FASE 3 — Reviver as VMs dev (`paulao`, `nicolas`)

**Pré-requisito:** Fase 0 concluída (backup no origin) + Fase 1 (homologação atualizada).
**Objetivo:** cada VM dev volta a uma base limpa (`origin/homologacao`), trackeando sua branch; daí em diante o dev promove por PR (fluxo do doc).

### 5.1 — Atualizar as branches `paulao`/`nicolas` no origin para a base atual
```bash
# na .232 (só depois do backup!):
git push origin origin/homologacao:paulao --force-with-lease     # paulao passa a apontar p/ base atual
git push origin origin/homologacao:nicolas --force-with-lease
```

### 5.2 — Resetar cada VM sobre a base (via bundle, sem credencial)
```bash
# bundle da base p/ a VM (ex. paulao), fetch + reset
git bundle create /tmp/base.bundle origin/homologacao
scp /tmp/base.bundle paulo@.100:/tmp/        # askpass master123
# na VM (como chatwoot):
git fetch /tmp/base.bundle 'refs/heads/homologacao:refs/heads/paulao'   # ou reset --hard após fetch
git checkout paulao && git reset --hard <sha_985db1f9f>
```
- **paulao:** seguro já (trabalho promovido; WIP `hook_execution` backupeada na Fase 0).
- **nicolas:** só se a auditoria 0.1 der **N=0** (ou o Nicolas confirmar). Se N>0, o trabalho fica na `nicolas-backup-*` e a VM só reseta com o aval dele.

**Validação por VM:** `git rev-parse HEAD == 985db1f9f`, branch correta, `git status` limpo, app sobe (HTTP 200 se a VM roda o serviço).
**Rollback:** `git reset --hard nicolas-backup-20260709` (o backup está no origin).
**⚠️ Destrutivo** — por isso depende 100% da Fase 0.

---

## 6. Ordem de execução e dependências

```
Fase 0 (backup + auditoria)  ──►  Fase 1 (homolog=prod)  ──►  Fase 2 (.232 limpa)
                                                              │
                             Fase 0 obrigatória ─────────────►  Fase 3 (VMs dev)
```
- Fases 0, 1, 2 podem ir **hoje** (baixo/zero risco).
- Fase 3 exige Fase 0 confirmada; a parte da `nicolas` depende do resultado da auditoria 0.1.

## 7. Fora de escopo (e por quê)
- **`develop`** (881 atrás): morta no fluxo atual; alinhar não agrega e pode confundir. Deixar como está.
- **`fabrica`** (159 commits off-git + é produção Atacadão): risco alto, precisa auditoria dedicada com o Paulo (o que é único vs já-em-prod) antes de qualquer toque. **Só backup, e mesmo esse, em sessão própria.** Ver `reference_fabrica_vm_divergida`.

## 8. Resultado esperado ao fim
- `origin/homologacao == origin/producao == 985db1f9f`.
- `.232` na `homologacao` limpa e no ponto certo.
- `origin/paulao` e `origin/nicolas` = base atual; VMs dev resetadas (nicolas condicionada à auditoria); todo trabalho antigo preservado em branches `*-backup-20260709` no GitHub.
- Frota de produção intocada (segue `985db1f9f`).
