# Plano — Alinhamento TOTAL das máquinas (nada se descarta)

**Objetivo:** uma **fonte única da verdade** (`producao`) que contenha **TUDO** o que existe espalhado
(nada perdido), e **todas as VMs no mesmo commit**. Depois, um fluxo que impeça re-divergir.
**Status:** SÓ PLANEJAMENTO — nada aplicado.

> Por que divergiu: 3+ branches trabalhadas em paralelo (`producao`, `homologacao`, `paulao`, `nicolas`) +
> cherry-pick + deploy por bundle. Enquanto forem várias fontes, "alinhar" não gruda. A cura é **1 fonte**.

---

## Estado hoje (levantado read-only)
| Fonte | SHA | O que tem de ÚNICO (a preservar) |
|---|---|---|
| **producao** | `265fdb63c1` | a base mais completa — é o tronco |
| **homologacao** (.232) | `dc0ffa51d` | `ver_detalhes` no carrossel (`9b8a3eccb`) + 8 × `docs(state)` |
| **fabrica** (3.87.182.184) | `c8f3dc803` | commit próprio não integrado + 5 arq WIP não commitado |
| **paulao** (192.168.8.100) | branch `05cf6005c` (ancestral) | **WIP local na VM** — a inventariar |
| **nicolas** (192.168.8.98) | `b9185275` (VM) vs branch `adbb115e5` | possível WIP local — a inventariar |
| frota cliente (.229/catatau/sentinela/agn/tozi) | no topo | — (já deployadas) |

---

## FASE 0 — Inventário (read-only, não muda nada)
Descobrir e **congelar por escrito** o que cada fonte tem que não está na `producao`:
1. **homologacao:** já mapeado → `9b8a3eccb` (ver_detalhes) + docs(state). ✅
2. **fabrica:** SSH read-only (bundle `c8f3dc803 --not producao` + `git status` do WIP não commitado) → listar.
3. **paulao (.100):** técnica do Nicolas — `paramiko`/SSH → `git bundle` do que a VM tem além do GitHub + `git status`/`git stash list` do WIP não commitado → baixar por SFTP.
4. **nicolas (.98):** idem (bundle do delta `adbb115e5..b9185275` + WIP).
   **Saída:** lista fechada de "código órfão" por fonte. Nada é tocado nesta fase.

## FASE 1 — Consolidar TUDO na `producao` (superset, nada se perde)
Trazer, um a um, o código órfão de cada fonte pra `producao`, **resolvendo conflito COM O AUTOR** onde
houver (o Captain/`buscar_imovel` é do Paulo — ele desempata; eu não resolvo às cegas em tool de cliente):
1. `ver_detalhes` (homolog `9b8a3eccb`) → **conflita** com a evolução do `buscar_imovel_tool` na prod → Paulo reconcilia.
2. WIP do **paulao** → bundle → cherry-pick/merge na prod → resolver → testar.
3. WIP do **nicolas** → idem.
4. WIP + `c8f3dc803` da **fabrica** → idem (⚠️ é greenfield, mais divergido — cuidado extra).
5. docs(state) da homolog → vão junto (decisão: "tudo tem que ir").
   **Saída:** `producao` = superset de absolutamente tudo. Cada passo testado (build + rspec dos specs tocados).

## FASE 2 — Espelhar as branches (todas viram cópia da `producao`)
Depois que a prod é o superset:
- `homologacao` → fast-forward/reset pra `producao`
- `paulao` → reset pra `producao`
- `nicolas` → reset pra `producao`
  As VMs de dev passam a **partir** da producao (dev não mantém fork paralelo). As branches de dev viram
  espelho; qualquer trabalho novo sai da producao.

## FASE 3 — Deploy pra TODAS as VMs (mesmo commit em todas)
Levar a `producao` consolidada pra: **.229, CATATAU, SENTINELA, AGN, TOZI, FABRICA, PAULAO, NICOLAS,
HOMOLOGACAO(.232)**. Método atual = **bundle + rsync** (as VMs cliente não têm credencial GitHub). Por VM:
gate + rollback + `db:migrate` por status + restart + validação objetiva. FABRICA/dev entram nesta rodada
(diferente de antes, onde ficavam fora) porque a decisão é "todas".

## FASE 4 — Prevenção (pra não redivergir — a cura real)
Sem isto, em 3 dias volta a bagunça:
1. **Uma branch fonte** (`producao`) trabalhada linearmente. **Parar** cherry-pick paralelo e deploy por
   bundle fora do Almirante.
2. **Credencial GitHub nas VMs** (decisão de arquitetura/segurança) → destrava o **Almirante a deployar de
   verdade** (hoje ele enxerga mas não transporta — só bundle). Aí deploy vira `propor → aprovar → deploy`
   governado, com trilha. Fim do bundle-SHA.
3. Regra operacional: **homolog → prod linear via Almirante**; dev (paulao/nicolas) parte da producao.

---

## Dependências / riscos (o que trava e de quem depende)
- **Paulo (autor):** reconciliar os conflitos do Captain (`buscar_imovel`/`ver_detalhes`) + validar o WIP das VMs de dev + os 12 fixes das branches `fix-fotos-handoff*` (que também são código órfão a integrar, não descartar).
- **Inventário das VMs de dev** (Fase 0) tem que vir ANTES de qualquer reset — senão reset destrói WIP.
- **Credencial nas VMs** (Fase 4) = decisão de arquitetura (Walisson/Paulo).
- **Fabrica** é a mais divergida (greenfield) — maior risco de conflito.

## Ordem executável (quando der o OK)
`Fase 0 (inventário) → Fase 1 (consolidar na prod, com Paulo nos conflitos) → Fase 2 (espelhar branches) →
Fase 3 (deploy em TODAS) → Fase 4 (prevenção)`. Cada fase validada antes da próxima; nada se descarta.
