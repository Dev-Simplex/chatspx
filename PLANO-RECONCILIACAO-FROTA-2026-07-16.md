# Plano de Reconciliação — Frota + Branches ChatSPX (16/07/2026)

**Para:** Nicolas · **De:** sessão ORQUESTRADOR (Paulo)
**Por quê:** auditoria da noite revelou que branches e VMs **divergiram** em direções diferentes (efeito de `cherry-pick` + `deploy por bundle` + vários commitadores). O git não responde mais "o que está onde" de forma limpa. Este plano regulariza e volta o fluxo pra linear.

> ⚠️ **Retrato é de 16/07 e a frota estava se mexendo** (SHAs mudaram durante a própria auditoria). Reconferir os tips antes de executar.

---

## Retrato (patch-id, 16/07)

- **Tips:** `producao` `339b53a7e` · `homologacao` `10be3ebcb`
- **24** patches na **prod** sem equivalente na homolog · **9** na **homolog** sem equivalente na prod (desses 9, só **2 são código**).
- **Frota NÃO unificada:** trio geral (PRODUCAO/CATATAU/SENTINELA) `05cf6005c` (3 atrás da prod) · **TOZI `1ffd7c49e` — SHA de bundle, não existe no GitHub** · Fábrica `c8f3dc803` (bem atrás; greenfield).
- **`drift_check`: sem edição off-git pendente** (o hand-edit do `track_imoveis` foi superado pelo deploy; `0d9d08238` já está no git da prod).

## Pendente pra produção (código)

1. **Carrossel de fotos interativo** (`b74fdb576`) + **fix `selected_option`** (`7548b40e7`) — na homolog, **vivos na conta 3 (HML)**, fora da prod. São os 2 únicos códigos "homolog-only".
2. **F2.0 eval — filtro de representatividade** (`8d21fbcf2`, branch `worktree-tozi-eval`) — runbook pronto em `Downloads/RUNBOOK-F2.0-eval-conta6.md`.
3. Os outros 7 "homolog-only" são `docs(state)` — irrelevantes pra prod.

## Passos (na ordem)

1. **`freeze_deploys`** curto na frota enquanto reconcilia (evita o alvo se mexer no meio).
2. **Back-merge `producao → homologação`** (é `merge`, **não** `reset` — não reescrever histórico da homolog, que a `.232` auto-pull). Regulariza a homolog: depois disso, "homolog − prod" = só carrossel + selected_option + F2.0.
   - Conflitos esperados nos gêmeos de cherry-pick (mesmo conteúdo, SHA diferente) → resolver mantendo a versão da **prod**.
3. **Um deploy governado de `origin/producao`** pro grupo de prod via Almirante → **unifica trio + TOZI** no mesmo SHA do GitHub (acaba o bundle-SHA da Tozi). `migrate:status` **antes** de restart (regra do incidente).
4. **Promover** carrossel + selected_option (já testados na conta 3) + **F2.0** (pelo runbook).
5. **Apagar** as branches zumbis: `spx/fix-fotos-handoff`, `spx/fix-fotos-handoff-hml`, `worktree-tozi-eval` (violam a regra das 3 branches).
6. **`unfreeze_deploys`.**

## Processo daqui pra frente (a cura de verdade)

- **Homolog → prod LINEAR** via Almirante (`propose_merge` → aprova → `propose_deploy`). **Parar** cherry-pick solto e deploy por bundle fora do Almirante — foi o que gerou a divergência 24×9 e o bundle-SHA da Tozi.
- Aí "o que está na homolog e não na prod" volta a ter resposta limpa, e some a dúvida diária "será que subiu?".

## Fábrica (à parte)

Fábrica (`c8f3dc803`) está bem atrás e é greenfield — reconciliar num segundo momento, com o código off-git do box (`3.87.182.184`) trazido pro repo antes.
