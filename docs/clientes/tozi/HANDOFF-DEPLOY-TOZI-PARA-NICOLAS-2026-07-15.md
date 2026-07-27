# Hand-off — Deploy Tozi PROD (conta 6) · para o Nicolas

> ✅ **PARCIALMENTE SUPERADO (16/07):** a Tozi já saiu de `c97ce3b8e` — você deployou e ela alinhou com a frota. O que **continua valendo** deste doc é a **higiene de processo** (deploy via Almirante, não bundle). O quadro atual + o plano completo de reconciliação estão em **`PLANO-RECONCILIACAO-FROTA-2026-07-16.md`** (raiz do repo).

**Data:** 2026-07-15 (noite) · **Origem:** sessão ORQUESTRADOR (Paulo) · **VM:** Tozi PROD `3.82.215.109` (`tozi.chatspx.app`, conta 6)

---

## TL;DR

A Tozi prod está rodando **código velho** (`c97ce3b8e`, ~14/07) — **90 commits atrás** da `producao` do GitHub. Um bug crítico (busca por código 100% quebrada) foi **paliado ao vivo hoje** por hand-edit, mas a **cura** é um deploy limpo da `producao`. O problema: esse deploy **hoje não passa pelo Almirante**, porque a esteira Tozi dele está **desalinhada do GitHub**. Preciso de você em 3 passos: **(1)** reconciliar a esteira, **(2)** deployar `producao` na Tozi numa janela, **(3)** padronizar deploy via Almirante.

---

## Estado atual (verificado na unha, não é achismo)

| Item | Valor |
|---|---|
| VM Tozi roda | `c97ce3b8e` (confirmado por `version.json` **e** `git HEAD` na `.109`) |
| GitHub `origin/producao` | `0a09e8954` (**+90 commits**, com todos os fixes) |
| Frota geral (PRODUCAO/CATATAU/SENTINELA) | `30a6a7b693` — já recebeu o merge de hoje |
| Fábrica / Tozi | **ficaram de fora** do fan-out de hoje |

⚠️ O box da Tozi está em estado **"Frankenstein"**: o arquivo novo `buscar_empreendimento_tool.rb` (pra Sofia) foi colado por cima do código `c97ce3b8e`, mas o `buscar_imovel_tool.rb` ainda é o velho. Não é um checkout limpo da `producao`.

---

## O que JÁ foi feito hoje (paliativo — **não precisa refazer**)

- `enterprise/lib/captain/tools/buscar_imovel_tool.rb` **linha 36**: `track_imoveis` → `track_codigos`.
  - Era o `NoMethodError` que quebrava **100%** da busca por código (foto de placa / código do site → "sistema indisponível" → handoff). Descoberto via convs 19212 (cód 2331) e 19216 (cód 1491).
  - `ruby -c` OK · worker (`chatwoot-worker.1`) reiniciado limpo · `migrate:status` estava 🟢.
  - **Backup no box:** `/tmp/buscar_imovel_tool.rb.orig-c97ce3b8e.bak`.
- É **idêntico** ao que já está na `producao` (`0d9d08238`) → o deploy limpo sobrescreve igual, **sem conflito**.

---

## O que AINDA está quebrado/faltando na Tozi (só o deploy resolve)

- 🟠 **`track_urls` (links da IA sumindo):** `0` ocorrências no `buscar_imovel_tool.rb` do box → o fix "restaura track_urls" **não está** na Tozi. Não hand-editei (é re-adicionar lógica, não rename) — vem no deploy.
- 🟠 **90 commits parados:** família de erros Meta, roteamento do lead Meta → Sofia, follow-up esgotado → humano, `buscar_empreendimento` respeitando limite 50 do Vista, e as suas features (kanban / sino-notificações / chat interno).

---

## Passos (nesta ordem)

### 1. Reconciliar a esteira Tozi no Almirante com o GitHub
**Sintoma:** `dry_run tozi` e `git_diff tozi` retornam *"TOZI já está no último commit (c97ce3b8e)"*. Ou seja, o Almirante acha que `c97ce3b8e` é o topo da `producao` pra Tozi → **`propose_deploy_vm tozi` seria no-op** (não traria os 90 commits).
**Ação:** apontar/atualizar a referência da esteira Tozi pra `origin/producao` (`0a09e8954`) — sincronizar o mirror/ref que o Almirante usa pra Tozi. O desalinho veio dos **deploys por bundle** (feitos por fora do Almirante). Você sabe onde fica esse ref melhor que eu.

### 2. Deploy limpo da `producao` na Tozi (janela combinada)
- **Pré-flight OBRIGATÓRIO:** `rails db:migrate:status` na Tozi **antes** do restart. `0a09e8954` traz migrations novas → **migrate ANTES de restart** (regra do incidente: migration pendente + restart = 500 em cadeia).
- **Caminho governado:** `propose_deploy_vm tozi` → aprovação humana → aplica (precompile + migrate + restart). Depois do passo 1, isso passa a enxergar os 90 commits.
- **Validar pós-deploy (sem olhar número):** busca por código (2331 / 1491) + links voltando + Sofia chamando `buscar_empreendimento`.

### 3. Padronizar: deploy **sempre** via Almirante
Os deploys de hoje foram por bundle, por fora do Almirante → histórico de deploy cego, versões descasadas e o Frankenstein. Combinar: frota **sempre** por `propor → aprovar`, pra ter trilha e não desalinhar a esteira de novo.

---

## Por que urge

O sangramento pior (busca por código) está paliado, mas na Tozi (**cliente real, conta 6**) os **links da IA continuam sumindo** e **90 commits** de melhorias não estão vivos — inclusive o roteamento dos leads Meta pra Sofia, que foi ativada hoje apontando pra código que só está meio-presente no box.
