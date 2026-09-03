# Como retomar esta execução

**Pausado em:** 17/08/2026, por troca de host/conta do Claude.
**Nada foi perdido.** Tudo que importa está em git ou em arquivo no disco desta VM
(`192.168.8.232`). Este documento é o único que o próximo coordenador precisa ler primeiro.

---

## 1. O estado, em cinco linhas

A **Onda 0 está materialmente concluída**. Todos os aceites numéricos fecharam, incluindo o
último e mais caro — os 16 snapshots. O que resta é **terminar duas correções P0**, fechar o
bloco 0.5, e **integrar as branches**. Nenhuma dessas três coisas é investigação; são execução
com o caminho já escrito.

---

## 2. Onde está cada coisa (branches locais, nada pushado)

| Branch | HEAD | Contém |
|---|---|---|
| `redesenho-base` | `d21794862b` | baseline dos 16 snapshots + fix do harness |
| `redesenho-merge` | `8684f07304` | **o merge da v4.16.2** + fix do harness + bloco 0.3 |
| `redesenho-correcoes` | `a9eeef3105` | 6 commits de correção **+ 1 commit `WIP(0.2 item 23)`** |
| `redesenho-config` | `6d4c8b608b` | blocos 0.7, 0.8 e 0.9 (fechados) |
| `redesenho-build` | `cd911c7682` | bloco 0.3 (origem; já cherry-picked no merge) **+ 1 commit `WIP(0.5)`** |

### Refs de recuperação — leia antes de mexer em qualquer coisa

```
refs/spx/merge-v4162-full       93571c69db   o merge recuperado (index + árvore de trabalho)
refs/spx/merge-v4162-snapshot   a31b607174   idem, só o index (histórico)
refs/spx/wip-correcoes          0461a03fba   trabalho NÃO commitado do item 23 (4 arquivos)
refs/spx/wip-build              9117cf17b9   trabalho NÃO commitado do bloco 0.5 (6 arquivos)
```

**As quatro worktrees estão LIMPAS** — nada solto. O trabalho em voo virou dois commits
explicitamente rotulados `WIP(...)`, cuja mensagem diz o que está feito, o que falta e por quê.
Os refs `wip-*` continuam como rede de segurança redundante. Se precisar deles:

```bash
git -C <worktree> diff HEAD refs/spx/wip-<nome>          # ver o que havia
git -C <worktree> checkout refs/spx/wip-<nome> -- .      # trazer de volta
```

---

## 3. O que falta, em ordem

### 3.1 Dois P0 de correção — **o mais importante**

Ambos estão especificados em `onda-0-correcoes-pendentes.md` (itens 23 e 26) e o executor já
tinha começado o 23. **Nenhum dos dois estava aplicado quando conferi o código**, apesar de uma
mensagem de commit citar o 23 — foi assim que apareceram.

| Item | Defeito | Estado |
|---|---|---|
| **23** | Excluir conversa **não exclui** e a API responde `200 OK` (assinatura errada no `DeleteObjectJob`) + a FK sem cascade que precisa ir junto | **código escrito, NÃO validado** — commit `a9eeef3105`. Falta rodar o spec e provar vermelho-antes/verde-depois |
| **26** | Abrir "Editar" numa integração e salvar **apaga a credencial** — 6 integrações, 14 chaves | **não iniciado** |

O item 26 é o defeito mais grave da onda. Detalhe completo em `onda-0-auditoria-views.md`
(achado P0), **com um request spec pronto lá** para fechá-lo com número.

### 3.2 Bloco 0.5 — gate de peso

WIP no commit `cd911c7682`. As duas decisões que ele esperava **já foram dadas**:

1. **O gate nasce vermelho e commita vermelho.** Medido: **422.599 B gzip** de JS *eager* contra
   teto de 300 kB (~41% acima) — e o executor da DoD, medindo first-paint, chegou a **416,28 kB**
   (~38%). São recortes diferentes do mesmo problema; quem fechar o bloco reconcilia e diz qual
   número o gate passa a reportar. O teto **não se afrouxa** — quem o baixa é o bloco 1.08. Mas a mensagem de falha
   tem de carregar a **linha de base do dia**, senão um gate permanentemente vermelho vira cego e
   ninguém percebe quando piorar de 41% para 60%.
2. **A sabotagem se prova com `bin/vite build` real**, não com manifest-fixture — um gate provado
   contra artefato montado não está provado.

### 3.3 Integração

Script pronto e testado em `/tmp/claude-1001/integrar.sh` (rode com `DRY=1` primeiro). Ele
**recusa** integrar se algum worktree estiver sujo. Ordem: `correcoes` → `build` → `config`,
tudo em `redesenho-merge`; depois `redesenho-base` recebe por `--ff-only`.

Conferências obrigatórias **depois** de integrar e **antes** de promover:

```bash
ls db/migrate | cut -d_ -f1 | sort | uniq -d      # VAZIO — colisão trava a frota inteira
git grep -n '<<<<<<<' -- .                        # VAZIO
pnpm exec vitest --no-watch --no-cache            # 4586 passed
pnpm exec playwright test --project=widget        # 20 passed / 0 failed
```

> ⚠️ **O harness usa portas fixas (3038/3999/8899).** Dois worktrees não rodam Playwright ao
> mesmo tempo. Isso já invalidou uma medição nesta onda — serialize.

---

## 4. O que sobrevive à troca de conta/host, e o que não

| Coisa | Sobrevive? |
|---|---|
| Branches, commits, `refs/spx/*` | **Sim** — git local nesta VM |
| Relatórios em `plano/redesenho/execucao/` | **Sim** — arquivos em disco |
| `PLANO-MESTRE.md` com as §12.1–§12.4 corrigidas | **Sim** |
| Run/tasks do Orca (`run_d71297edb110`) | **Sim, se o Orca continuar nesta máquina** |
| Terminais executores | **Encerrados de propósito** antes da pausa, com o WIP commitado antes |

**Nada depende da conta do Claude.** O trabalho está em git e em disco.

---

## 5. Como o próximo coordenador começa

```
Retomo a Onda 0 do redesenho do chat de site (/home/chatwoot/chatwoot).
Leia, nesta ordem:
  plano/redesenho/execucao/RETOMAR.md          ← este arquivo, primeiro
  plano/redesenho/execucao/onda-0-RELATORIO.md ← o que foi feito e por quê
  plano/redesenho/execucao/onda-0-correcoes-pendentes.md ← itens 23 e 26
  plano/redesenho/PROMPT-ORQUESTRADOR.md       ← as regras de execução
Falta: terminar os itens 23 e 26, fechar o bloco 0.5, e integrar as branches.
```

Para reaproveitar o Run do Orca em vez de criar outro:

```bash
orca orchestration run-use --id run_d71297edb110 --json
```

> **Peculiaridade medida nesta sessão:** o binding do Run se perde entre invocações quando o
> handle do terminal muda. Faça `run-use` **na mesma chamada de shell** que o `task-create` /
> `worker-start`, senão dá `run_required`.

---

## 6. Três coisas que o próximo coordenador precisa saber, e que custaram caro aqui

1. **Feche a task por artefato validado, nunca por `worker_done`.** Um commit citava o item 23 na
   mensagem sem ter o código. Se eu tivesse aceitado o relato, a onda fecharia com "excluir
   conversa responde 200 OK sem excluir" marcado como resolvido.
2. **Auditoria de colisão é cega para o que só o upstream mudou.** Os três P0 silenciosos
   (webhook de Instagram/WhatsApp em 401, e o de perda de credencial) estavam fora dos 558
   arquivos de conflito.
3. **Dois executores no mesmo worktree = medição inválida.** Aconteceu duas vezes. Um worktree
   por frente, e quem mede tem a porta fechada.


---

## 7. Estado no momento exato da pausa

Todos os executores foram **encerrados pelo coordenador**, não morreram sozinhos. As quatro
worktrees estão limpas, sem nada solto:

```
redesenho-merge      8684f07304   merge v4.16.2 + harness + bloco 0.3   ← os 16 snapshots passam aqui
redesenho-correcoes  a9eeef3105   6 commits de correção + WIP do item 23
redesenho-config     6d4c8b608b   blocos 0.7, 0.8 e 0.9 fechados
redesenho-build      cd911c7682   bloco 0.3 + WIP do 0.5
redesenho-base       d21794862b   baseline dos 16 + fix do harness
```

**Um detalhe que economiza confusão:** `playwright.strict.config.js` no `redesenho-build` é
instrumento de medição descartável (endurece a tolerância para zero pixel). Ele **não** faz parte
da suíte e deve sair antes da integração.
