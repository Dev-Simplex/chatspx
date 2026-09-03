# Onda 0 — reconciliação do estado real (17/08/2026)

**Coordenador:** Claude Opus 5 (1M) · terminal `term_464aa2dc` · Run Orca `run_d71297edb110`
**Antecessor:** Codex, Run `run_26dd5a774ba8`, relatório `onda-0.md` de 13/08/2026 14:23

Este documento existe porque o relatório da onda e o estado do disco **divergiam**, e
seguir em frente sem resolver isso teria destruído trabalho real. Ele registra o que foi
encontrado, o que foi decidido e por quê.

---

## 1. O relatório estava desatualizado, não errado

`onda-0.md` foi escrito em **13/08 às 14:23**. O trabalho continuou depois dele, por outra
sessão, e ninguém reescreveu o relatório. Todas as três divergências apontadas se explicam
por isso:

| O que o relatório diz | O que o disco mostra | Veredito |
|---|---|---|
| `0.1`/`0.11` **FAIL**, aceite visual `0/16`, alterações revertidas, worktree limpo, sem commit | commit `f26db6ee81` de **14/08 23:18** (amend 23:43) com harness completo, **16 PNG**, `baseline.json`, fixture anti-erro e config de sabotagem | O relatório descreve corretamente a tentativa do dia 13. O bloco foi **refeito e entregue no dia 14**. |
| `0.2` (merge da v4.16.2) "não começou porque depende do baseline `0.1`/`0.11`" | merge da `v4.16.2` **iniciado em 14/08 23:53 e trabalhado até 15/08 03:40**: 3.463 arquivos no index, **0 conflitos pendentes**, `package.json` já em 4.16.2 | O merge começou logo depois de o baseline existir — exatamente na ordem que o plano manda. Só nunca foi commitado. |
| worktrees "limpos" | `chatwoot-redesenho-base` com `MERGE_HEAD` presente e merge inacabado há 3 dias | Estado frágil: qualquer `git checkout`, `git reset` ou `worktree remove` teria apagado ~4h de resolução de conflito em 200+ arquivos. |

O bloco **0.6** (contrato de paridade, commit `1a45399b2a`) confere com o relatório e **não
foi tocado**.

---

## 2. Primeira ação: tornar o trabalho não-perdível

Antes de qualquer análise, o merge em disco virou objeto git permanente. Dois refs, porque
o index e a árvore de trabalho **não eram iguais** — havia 8 arquivos com edição não-staged
que um `git write-tree` sozinho teria descartado em silêncio:

| Ref | Commit | Conteúdo |
|---|---|---|
| `refs/spx/merge-v4162-snapshot` | `a31b6071` | só o index |
| `refs/spx/merge-v4162-full` | `93571c69db` | index **+** as 8 edições de working tree ← autoritativo |

Os 8 arquivos do delta: `config/llm.yml`, `enterprise/app/services/llm/base_ai_service.rb`,
`lib/llm/feature_router.rb`, `public/version.json` e 4 specs de Captain/LLM — alguém estava
reconciliando a configuração de LLM quando a sessão parou.

Ambos os commits têm os **dois pais corretos** (`f26db6ee81` e `v4.16.2` = `70e284a044`),
então são merges de verdade, não fotografias.

Só depois disso o merge inacabado foi encerrado com `git merge --abort`, liberando o
worktree base. Nada se perdeu: `git diff` entre o worktree e o ref deu vazio antes do abort.

---

## 3. A decisão irreversível: **aproveitar o merge, não recomeçar**

A pergunta era se aquele merge de origem desconhecida merecia confiança. A resposta não
podia ser de opinião, então foram medidas as três travas que a auditoria upstream de 03/08
tinha declarado bloqueantes (`plano/auditoria-upstream-4.12.1-4.16.2/`):

| Trava da auditoria | Estado no merge | Leitura |
|---|---|---|
| **Bitmask de `feature_flags` estourado** (65 entradas em 63 bits) | Resolvido pelo mecanismo `feature_flags_ext_1` do upstream, **e** os nossos 2 flags excedentes (`conversation_required_attributes`, `advanced_assignment`) foram movidos para a coluna nova. Resultado: **63/63 default + 14 em ext_1** | Correta e **não óbvia**. Quem resolveu entendeu o problema. |
| **Colisão de timestamp de migration** | `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` → **vazio** | Limpa. |
| **2 migrations do upstream que destroem dado nosso** | `drop_channel_voice` **descartada** ✔ · `purge_pending_captain_assistant_responses` **entrou** ✘ | Defeito real, mas pontual: 1 arquivo. |

Somam-se a isso: **0 conflitos pendentes**, **0 marcadores `<<<<<<<`** no index e na árvore,
e um descarte deliberado e coerente de 872 linhas do front de voz do upstream
(`VoiceCall.vue` 371, `useCallSession.js` 317, `FloatingCallWidget.vue` 184) — coerente
porque ainda usamos `Channel::Voice` e a migration que o dropa foi descartada.

**Conclusão:** o merge foi resolvido com julgamento informado, não mecanicamente. Refazê-lo
custaria dias no bloco de maior esforço e maior risco de merge do plano (`0.2` é **G** e
🔴), e a segunda resolução não seria melhor que esta. **Aproveitar**, e submeter o
resultado a auditoria semântica arquivo a arquivo — que é trabalho de verificação, mais
barato e mais confiável que refazer.

O merge agora vive em worktree e branch próprios: `/home/chatwoot/chatwoot-redesenho-merge`,
branch `redesenho-merge`, `HEAD = 93571c69db`. Quando validado, ele entra em
`redesenho-base` por fast-forward — `93571c69db` já descende de `f26db6ee81`.

---

## 4. Triagem mecânica: 558 arquivos viraram uma lista priorizada

Os dois lados colidiram em **558 arquivos** (nós mudamos 4.760 desde a `v4.12.1`; eles,
3.605). Cada um foi classificado comparando o blob do merge com o blob de cada lado:

| Classe | Nº | O que significa |
|---|---:|---|
| `MERGE_REAL` | 490 | houve mesclagem de verdade — é onde mora o julgamento |
| `PEGOU_NOSSO` | 43 | ficou byte-idêntico ao nosso: mudança do upstream descartada |
| `PEGOU_DELES` | 15 | ficou byte-idêntico ao deles: **nossa customização pode ter sumido** |
| `APAGADO` | 9 | o arquivo **não existe mais**, e nós o tínhamos customizado |
| `IDENTICO` | 1 | os dois lados chegaram ao mesmo texto |

Dados brutos em `plano/redesenho/execucao/dados/` (`triagem.tsv`, `colisao.txt` e os
recortes por área). As 24 linhas de `APAGADO` + `PEGOU_DELES` são o topo da fila de risco e
são de cobertura **obrigatória** na auditoria.

### Três achados já confirmados pelo coordenador

1. **DADO — FAQ pendente do Captain é apagada.**
   `enterprise/app/models/captain/assistant_response.rb` passou de
   `enum status: { pending: 0, approved: 1 }` para `{ approved: 1 }`, e entrou a migration
   `20260714123000_purge_pending_captain_assistant_responses.rb`, que roda
   `DELETE FROM captain_assistant_responses WHERE status = 0`. No upstream, `status 0` é
   lixo; **no nosso fork é FAQ pendente viva**. Rodar isso na frota apaga FAQ pendente de
   todos os clientes.
2. **PERDA — a tela do fluxo casa com o achado 1.**
   `app/javascript/dashboard/routes/dashboard/captain/responses/Pending.vue` foi apagada
   pelo merge.
3. ~~**RISCO — mover flag de coluna move o bit.**~~ **REFUTADO — o coordenador estava errado.**
   A suspeita era que conta da frota com `conversation_required_attributes` ou
   `advanced_assignment` ligados passaria a ler o bit em outro lugar. **A2 e A3 investigaram
   de forma independente e chegaram à mesma conclusão: não havia estado a preservar.** Em
   `f26db6ee81` esses eram os bits 64 e 65 da coluna `feature_flags`, e o FlagShihTzu mapeia
   bit → máscara com `1 << (n-1)`: as máscaras seriam `1<<63` e `1<<64`, que **excedem o
   `bigint`** da coluna (`db/schema.rb:80`). Os dois flags eram fisicamente ingraváveis.
   Nenhuma migration de carregamento é necessária. A realocação para `ext_1` não só é certa
   como é o que torna esses dois flags graváveis pela primeira vez.

Nenhum dos dois achados válidos foi corrigido ainda — correção é de outra task, depois dos
relatórios, para que ela seja completa em vez de pontual.

> **Registro de método:** os três achados acima foram entregues aos auditores como
> *calibração*, com a instrução explícita de **confirmar por conta própria em vez de repetir
> a afirmação do coordenador**. Um dos três caiu. É exatamente para isso que a instrução
> existia — e é a razão de o coordenador não ser a última palavra sobre os próprios achados.

---

## 5. Os dois bloqueios que pararam o antecessor

**`0.1`/`0.11` — porta 3000 e o 504 do Vite.** O bloqueio **não existe mais**, e não por
autorização: o harness entregue em `f26db6ee81` sobe servidores `.mjs` próprios
(`host-server.mjs`, `sdk-server.mjs`, `widget-server.mjs`) em vez de depender do dev server
do Vite — que era a causa raiz do `504 Outdated Optimize Dep`. É exatamente a "nova
abordagem" autorizada, e ela já estava no disco. O que falta é **validar**, com a matriz
íntegra de 16 e sem `--update-snapshots`. O Puma da porta 3000 desta VM não será tocado.

**`0.4`/`0.10` — sudo.** Continuam **pendentes por falta de privilégio**, como instruído.
Nenhuma senha será pedida. O que exatamente falta está na §7.

---

## 6. Frota de execução

Um worktree por frente, seis executores Claude, todos com commit local e nenhum com
permissão de push, PR ou deploy.

| Task | Frente | Worktree | Natureza |
|---|---|---|---|
| **T1** | validar baseline `0.1`/`0.11` | `chatwoot-redesenho-base` @ `f26db6ee81` | mede e prova |
| **T2** | Definition of Done numérica do `0.2` | `chatwoot-redesenho-merge` | mede e prova |
| **A1** | auditoria: Ruby de aplicação (121 arq.) | `chatwoot-redesenho-merge` | somente leitura |
| **A2** | auditoria: Enterprise/Captain, specs, config, db (117 arq.) | `chatwoot-redesenho-merge` | somente leitura |
| **A3** | auditoria: widget, shared, SDK, build (53 arq.) | `chatwoot-redesenho-merge` | somente leitura |
| **A4** | auditoria: dashboard e i18n (267 arq.) | `chatwoot-redesenho-merge` | somente leitura |

As quatro auditorias dividem um worktree porque **nenhuma escreve no repositório** — a
regra de um worktree por frente existe para impedir conflito de escrita, e leitura paralela
não a viola. A correção do que elas encontrarem é de um único executor, depois, sozinho.

---

## 7. Pendências declaradas

- **`0.4` (compressão gzip/brotli no nginx)** e **`0.10` (chaves
  `ACTIVE_RECORD_ENCRYPTION_*`)** exigem `sudo` que esta sessão não tem. Documentados na
  §5, não executados, não pedidos.
- Os 8 arquivos de reconciliação de LLM em estado inacabado (§2) precisam de decisão: eram
  edições em curso, não resultado de merge. Vão para a auditoria A2.
</content>
</invoke>
