# HANDOFF — Chat SPX · frente `spx/rodizio`

> **Log APPEND-ONLY de entrega**, da sessão de build pra sessão orquestradora (e pro Paulo).
> Diferente do `STATE.md` (mutável, só o AGORA), aqui **nada se apaga** — cada sessão
> acrescenta um bloco no topo.
>
> Seções por bloco: **✅ O que fiz · 🔬 Verificado · 🧠 Decisões · ⚠️ Dúvidas/notas · ▶️ Próximo passo**

---

## [2026-07-31, madrugada] — 🎯 Rodízio: da spec ao ciclo fechado (6/6 itens)

### ✅ O que fiz

**Antes de tudo:** a worktree estava **45 commits atrás** da `origin/homologacao` — sincronizada
por `merge --ff-only` (`6ef8340e5` → `a75b08c54`). O `Spx::TemplateReplyRouterListener`, que o
`CLAUDE.local.md` dava como existente, só chegou aí.

**Design (grill-me → spec):** entrevista de 12 perguntas registrada em
`brainstorms/2026-07-30-rodizio-atribuicao-tozi.md` (registro bruto, com as respostas verbatim e
as recomendações minhas que foram **rejeitadas**), destilada em
**`docs/clientes/tozi/SPEC-RODIZIO.md`**.

**Implementação, 6 itens:**
1. **Catálogo de produtos** (`distribuicao_produtos` + `ResolverProdutoService`) filtra o pool
   antes do rodízio. Sem produto cadastrado = no-op total.
2. **Designação sem `assignee`** (`policy.modo_posse`) — o terceiro estado. O log virou
   livro-razão (`status`, `designado_em`, `encerrado_em`, `policy_snapshot`).
   `DesignacaoListener` fecha ao assumir.
3. **Carimbo** na conversa (`rodizio_designado_em`, `rodizio_produto`, `rodizio_corretor`),
   com o **nome do corretor removido do contexto do agente**.
4. **Espelho no Vista** (`VistaCardService`) atrás de `espelho_vista`, desligado por padrão.
5. **Tela de contabilização** — API `distribuicao_dashboard` + `RodizioPage.vue`
   (`/agents/rodizio`), com drill-down da regra que valeu.
6. **Consumo do `vista_engajado_em`** da `spx/eval` → fecha a designação e cala a IA.

**Depois do CI do Paulo:** pedido do cliente virou desvio que **consome a vez**; falsa órfã
tratada no `OrphanRetriageJob`; dívidas de lint quitadas.

**13 commits**, `c203edf06` → `bcd8b9bde`, todos em `origin/spx/rodizio`.

### 🔬 Verificado

**Honestamente: quase nada foi executado por mim.** Esta worktree **não tem Ruby nem
`node_modules`** — sem `rubocop`, `eslint`, `rspec`, `tsc` ou build.

| O que | Como | Resultado |
|---|---|---|
| JSON dos locales `en` + `pt_BR` | parser Python | ✅ válidos, conjuntos de chave idênticos |
| 28 chaves i18n usadas no template | cross-check contra os locales | ✅ nenhuma faltando, nenhuma órfã |
| `v-for` junto de `v-else`/`v-if` | varredura tag-a-tag | ✅ nenhum elemento |
| Linhas > 150 chars nos `.rb` tocados | scan | ✅ nenhuma |
| Provenance do `Metrics/PerceivedComplexity` | `git log -S` + diff da branch | ✅ **pré-existente** (`02bcbac0f`), não é dívida desta frente |

**Rodado pelo Paulo no box de CI (.232, worktree em /tmp):** RuboCop 27 offenses / 16 arquivos ·
ESLint 11 erros + 6 warnings. **Os 4 vermelhos apontados foram tratados** (BlockLength via disable
documentado, LineLength quebrado de verdade, `v-else`+`v-for` com wrapper, textos crus movidos pro
script). **Não re-rodei o lint depois dos consertos** — precisa de nova passada no box.

**Nunca executado:** `VistaCardService` contra o Vista real · a página renderizada · qualquer
migration · qualquer spec.

### 🧠 Decisões

- **Em vendas NÃO se seta `assignee`** (Paulo). Matou a proposta inicial de "dois campos vivos" e,
  com ela, a necessidade de mexer no `reset_agent_bot_when_assignee_present`. O trabalho pesado que
  a frente previa **evaporou**: o callback nunca dispara, o espelho sobrevive, a IA continua
  falando — zero linha do core alterada.
- **Handoff é evento de sistema, silencioso.** A IA nunca anuncia; o anúncio é decisão
  conversacional dela, desacoplada, e mora no prompt (conta 6), não aqui.
- **Preferência do cliente consome a vez; continuidade não.** Continuidade é retorno; preferência é
  lead novo, e se não contasse viraria porta dos fundos ("peça por mim").
- **Nome do corretor fora do contexto do agente** — o runner já tinha precedente
  (`aguardando_humano_desde` foi removido porque empurrava o LLM pro silêncio). Reverter é 1 linha.
- **SLA em vendas é medida, não ação** — reescrever `CorretorNegocio` de card existente é
  capacidade não testada e o `DELETE` do Vista é 401.
- **Fora de escopo de propósito:** `valor_max` (falta fonte do valor do lead, e o lugar de carimbar
  é arquivo de outra frente) · escala/turnos · `so_online` · punição automática · comissionamento.

### ⚠️ Dúvidas / notas

- 🔴 **`VistaCardService` nunca tocou o Vista.** Contrato de campos empírico, `DELETE` 401 = sem
  desfazer. `espelho_vista` nasce **desligado**; exige uma criação real antes de ligar.
- 🔴 **4 migrations**, todas com alvo (`db:migrate:up VERSION=…`, **nunca** `db:migrate` puro), e
  precisam subir **junto** com o código — o serviço grava `produto_slug`, `status`,
  `policy_snapshot`.
- 🟡 **Tela só alcançável por URL.** Quem precisa dela é o Guilherme, que não digita rota — ela
  entra no menu junto com a página de Avaliação da `spx/eval`. Não toquei a `Sidebar.vue` (arquivo
  quente, outras worktrees).
- 🟡 **Relógio da tela é wall-clock, não expediente** — o Chatwoot tem `working_hours` por *inbox*,
  não por time. De onde vem o expediente é decisão de produto (spec §9.1).
- 🟡 **Card trocado de corretor por fora** só vira log hoje; o que fazer com a contagem é decisão
  de produto (spec §13).
- 🟢 **`preferencia_cliente` depende de um escritor**: a conduta da IA precisa gravar
  `rodizio_preferencia`. Sem isso o desvio é inerte.
- **Handoff é versionado em caminho POR FRENTE** (`docs/handoffs/<frente>.md`), nunca na raiz. Raiz
  colidiria entre as seis frentes a cada merge; deixar local seria pior — handoff que vive só na
  worktree **some junto com ela** (foi o que aconteceu com o `TRIAGEM.md` da `spx/resgate`).

### ▶️ Próximo passo (proposto)

1. **Re-rodar lint no box** após os consertos (RuboCop + ESLint `--fix` pros 10 de prettier).
2. **Validar o `VistaCardService`** com uma criação real — é o que fecha o contrato de campos.
3. **Escrever a conduta de modo contido** no prompt da Sofia (conta 6): o carimbo já chega no
   contexto dela.
4. Configurar a primeira política de vendas (`spx:distribuicao:policy` + `posse` + `produto`) com o
   Guilherme — falta o `vista_corretor` de cada um e a composição do pool.
