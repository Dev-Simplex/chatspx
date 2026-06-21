# Prompt de implementação — Melhorias Galeria + Download em massa

| | |
|---|---|
| **Data** | 2026-06-15 |
| **Branch** | `nicolas` |
| **Origem** | Revisão por squad (backend + frontend + verificação) de 2026-06-15 |
| **Público** | Dev/agente que vai implementar |
| **Regra de ouro** | **Preservar 100% do funcionamento atual.** Toda mudança é aditiva/cirúrgica; nada de refatorar o que já passa. |

---

## 0. Contexto e guardrails (LER ANTES DE TOCAR EM QUALQUER ARQUIVO)

A feature "galeria de mídias + download em massa de attachments (.zip assíncrono)" **já está em produção no staging `nicolas` e funcional** (migration aplicada, rubyzip 2.4.1, rotas expostas, purge agendado, smoke test OK). Este prompt é de **endurecimento + UX**, não de reescrita.

**Guardrails obrigatórios:**

1. **Não regredir.** O fluxo atual de seleção→toolbar→ZIP funciona. Cada item abaixo é uma alteração pontual; rode mentalmente o caminho feliz antes/depois.
2. **Escopo e segurança intactos.** Não afrouxar `GalleryScopeBuilder` (visibilidade por inbox, `exclude_incoming_whatsapp`, dedup). Qualquer mudança de escopo precisa de spec cobrindo IDOR.
3. **Tudo com spec.** Há 7 specs em `spec/**/attachments*` + factory. Para cada correção de backend, estender o spec correspondente. Front: estender vitest onde já existir.
4. **i18n simétrico.** Toda string nova entra em `en/*.json` **e** `pt_BR/*.json`. Nunca deixar chave renderizando crua.
5. **Build/deploy é do usuário.** NÃO rode `git checkout/restore/reset` amplo (árvore tem muito trabalho não-commitado). NÃO deploye. Prepare tudo, rode lint + specs, e avise. Procedimento de build do staging: `assets:precompile` + `sudo /bin/systemctl restart chatwoot.target` (só o usuário executa).
6. **Lint limpo** (`eslint`/`rubocop`) antes de entregar.
7. **Commits pequenos e descritivos**, um por tarefa lógica, em pt_BR seguindo o padrão `fix(gallery): ...` / `feat(gallery): ...` do repo.

**Melhores práticas gerais:** prefira derivar estado (computed) a duplicá-lo; desabilite ações de forma **síncrona** no `@click` (não confie em estado assíncrono p/ guardar duplo-clique); no backend, falhas terminais usam `discard`/sem `raise`, falhas transitórias usam `retry_on`; valide caps **no momento da execução**, não só no enfileiramento.

---

## TAREFA 1 — [FEATURE/UX] Seleção da galeria por "dois cliques" + checkboxes ocultos por padrão

### Objetivo
Hoje o checkbox circular branco (canto superior esquerdo de cada imagem) fica **sempre visível** — polui a grade. Novo comportamento desejado:

- **Estado padrão (nada selecionado):** os botões de seleção (canto superior esquerdo) **não aparecem**. Um **clique simples** continua abrindo o lightbox (comportamento atual).
- **Selecionar a primeira imagem:** **duplo-clique** numa imagem a seleciona (entra em "modo seleção").
- **Com ≥1 selecionada:** os checkboxes passam a aparecer em **todos** os cards; a partir daí o usuário pode clicar nos checkboxes para adicionar/remover, e o duplo-clique continua alternando seleção.
- **Ao limpar a seleção (0 itens):** os checkboxes somem de novo e o clique simples volta a abrir o lightbox.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/gallery/components/MediaGrid.vue` (principal — imagens/vídeos)
- `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue` (já tem `selection`, `toggleSelect`, `clearSelection`)
- (opcional, p/ consistência) `DocumentList.vue` / `LinkList.vue` — ver nota no fim

### Abordagem recomendada (best practices)
1. **Visibilidade derivada, não novo estado redundante.** O "modo seleção" é simplesmente `selectedIds.size > 0`. Em `GalleryPage.vue`, passe uma prop calculada ao grid, ex.: `:selection-active="selection.size > 0"`. Não crie um `selectionMode` separado que possa dessincronizar.
2. **Checkbox em MediaGrid** (`MediaGrid.vue:144-160`): condicionar a exibição a `selectionActive || selectedIds.has(item.id)`. Mantenha o item **sempre** visível quando ele próprio está selecionado (senão o usuário "perde" o feedback). Use `v-if`/`v-show` com classe sólida — **não** use opacity com alpha dinâmico que o JIT do Tailwind pode pular (lição registrada no projeto).
3. **Conflito clique × duplo-clique (crítico).** `@dblclick` dispara *depois* de dois `click`. Hoje o `click` no `<article>` faz `$emit('open', item)` → o lightbox abriria no meio do duplo-clique. Resolva com **debounce do clique simples**: ao receber `click`, agende `open` com `setTimeout(~200ms)`; se um `dblclick` chegar antes, cancele o timer pendente e emita `toggleSelect`. Limpe o timer no `onBeforeUnmount`. (Alternativa pior: detectar `event.detail === 2` — menos confiável cross-browser.)
4. **Acessibilidade/mobile.** Duplo-clique não existe em touch. Mantenha o checkbox clicável assim que visível, e considere expor o gesto de entrada em modo seleção também via long-press OU manter o caminho atual de "clicar no checkbox" como fallback. No mínimo: garanta `aria-label` no botão e que ele seja alcançável por teclado. Não quebre o RTL (`ltr:left-2.5 rtl:right-2.5`).
5. **Reset coerente.** `clearSelection`/troca de aba já zeram `selection` (`GalleryPage.vue:48-52,86-89,123-129`) — confirme que isso some com os checkboxes automaticamente (sai de graça se a visibilidade é derivada).

### Critérios de aceite
- [ ] Grade limpa (sem checkboxes) quando nada está selecionado; clique simples abre lightbox.
- [ ] Duplo-clique numa imagem seleciona-a e revela os checkboxes em todos os cards.
- [ ] Duplo-clique não abre o lightbox junto.
- [ ] Clicar no checkbox alterna; zerar a seleção esconde os checkboxes de novo.
- [ ] Funciona em LTR e RTL; sem warning de lint; build serve o bundle novo.

> **Nota de consistência:** o usuário pediu explicitamente para **imagens**. `DocumentList`/`LinkList` usam checkbox quadrado sempre visível — avalie aplicar o mesmo padrão "oculto até 1 selecionado" para coerência, mas **só se** não conflitar com a Tarefa 8 (ocultar seleção na tab Links). Se em dúvida, mantenha documentos como estão e alinhe só a galeria de imagens.

---

## TAREFA 2 — [ALTO/Backend] Revalidar caps (500 arquivos / 2 GB) na execução do job

### Problema
Os caps são checados só no `create` (`attachment_bulk_downloads_controller.rb`, `validate_request`). No modo `filters`/`select_all`, o conjunto pode crescer entre o pedido e a execução do job; o `find_each` no service **não tem teto** → risco de RAM/disco/tempo.

### Arquivos
- `app/services/attachments/bulk_download_zip_service.rb`
- `app/jobs/attachments/bulk_download_job.rb`
- `app/models/attachment_bulk_download.rb` (constantes `MAX_FILES`, `MAX_TOTAL_BYTES`)

### Abordagem recomendada
- **Hard cap defensivo no scope de geração:** aplicar `.limit(AttachmentBulkDownload::MAX_FILES)` no `download_scope` do service.
- **Abortar por bytes acumulados:** durante o `find_each`, somar `blob.byte_size` processado; ao exceder `MAX_TOTAL_BYTES`, parar de adicionar, registrar no `_manifest.txt` (ex.: "limite de tamanho atingido, N itens omitidos") e finalizar o zip com o que já entrou — **não** explodir o job. Marcar contagem de omitidos em `skipped_count`.
- **Princípio:** validação no `create` é UX (resposta rápida 422); o teto no job é a **defesa real** de recurso. Os dois coexistem.
- Logar (auditoria) quando o teto do job for atingido, com `account_id`/`requester_user_id`/contagens.

### Critérios de aceite
- [ ] Job nunca processa > `MAX_FILES` nem ultrapassa materialmente `MAX_TOTAL_BYTES`, mesmo que o filtro tenha crescido.
- [ ] Itens omitidos por teto aparecem no manifest e em `skipped_count`; zip ainda abre.
- [ ] Spec de service cobrindo: scope com > MAX_FILES → zip tem no máx. MAX_FILES; soma de bytes além do teto interrompe sem raise.

---

## TAREFA 3 — [ALTO/Backend] TOCTOU de autorização no modo conversa

### Problema
`ConversationPolicy` (`authorize conversation, :show?`) é checada **só** no controller `create`. O job re-resolve a conversa sem revalidar. Se o agente perder acesso à inbox dentro da janela de retenção (7 dias), o zip ainda é gerado e fica baixável.

### Arquivos
- `app/services/attachments/bulk_download_scope_resolver.rb` (`conversation_scope`)
- `app/jobs/attachments/bulk_download_job.rb`
- `app/services/attachments/gallery_scope_builder.rb` (`visible_inbox_ids`)

### Abordagem recomendada (escolher 1)
- **Opção A (recomendada) — re-checar visibilidade no job:** no modo conversa, no início do `perform`, garantir `conversation.inbox_id ∈ GalleryScopeBuilder.new(user: requester_user, account:, params: {}).visible_inbox_ids`. Se não estiver, marcar `failed` com `error_message: 'acesso_revogado'` (falha terminal, sem retry).
- **Opção B — aceitar formalmente "autorização no momento do pedido"** e documentar no model/job (comentário + nota na memória) que a retenção de 7 dias pode conter mídia de acesso revogado. Só escolher B se houver razão de produto.

> Decisão default proposta: **A** (custo baixo, fecha a janela). Se o usuário preferir B, registrar a decisão explicitamente.

### Critérios de aceite
- [ ] Request/job spec: agente perde acesso à inbox entre create e job → zip **não** é entregue (status failed) na opção A.
- [ ] Nenhuma regressão no caminho feliz (agente com acesso baixa normalmente, incl. incoming WhatsApp da conversa, que é intencional).

---

## TAREFA 4 — [MÉDIO/Backend] `RecordNotFound` no job vira falha terminal

### Problema
Conversa (ou registro) deletada entre pedido e execução → `ActiveRecord::RecordNotFound` cai no `rescue StandardError` + `raise` → Sidekiq tenta **5 retries inúteis** num erro permanente.

### Arquivos
- `app/jobs/attachments/bulk_download_job.rb`
- `app/services/attachments/bulk_download_scope_resolver.rb` (onde há `find`/`find_by!`)

### Abordagem recomendada
- Tratar `ActiveRecord::RecordNotFound` como **terminal**: `discard_on ActiveRecord::RecordNotFound` (marcando o record `failed` antes, num bloco) ou capturar explicitamente, setar `status: :failed` + `error_message`, e **não** re-raise. Espelhar o tratamento que o job já dá a `DeserializationError`.

### Critérios de aceite
- [ ] Spec: conversa deletada → 1 tentativa, status `failed`, sem retries.

---

## TAREFA 5 — [MÉDIO/Backend] Filtro de data inválido não pode zerar a galeria silenciosamente

### Problema
`parse_time` retorna `nil` em erro; `apply_date_range` aplica `WHERE col >= NULL` → conjunto vazio. Um `after`/`before` malformado **zera a galeria sem erro** e também o download.

### Arquivos
- `app/services/attachments/gallery_scope_builder.rb` (`parse_time`, `apply_date_range`)

### Abordagem recomendada
- Se o valor está presente mas `parse_time` retorna `nil`, **ignorar o filtro** (não aplicar o `where`) — comportamento tolerante, padrão de listagem. Opcionalmente logar em debug.
- (Alternativa mais estrita: o controller do index retorna 422 em data inválida. Preferir a tolerante para não quebrar links/bookmarks existentes.)

### Critérios de aceite
- [ ] Spec de `GalleryScopeBuilder`: `after: 'lixo'` → filtro ignorado, scope volta ao conjunto normal (não vazio).

---

## TAREFA 6 — [MÉDIO/Backend] Modo "ids" usa `base_scope` (sem dedup/tipo) — decidir e alinhar

### Problema
No modo seleção manual (`attachment_ids`), o resolver usa `base_scope` (aplica visibilidade por inbox, mas **não** dedup nem filtro de tipo). Não cruza inbox (seguro), mas permite baixar duplicatas colapsadas ou tipos fora da aba — viola "só baixa o que vê".

### Arquivos
- `app/services/attachments/bulk_download_scope_resolver.rb`

### Abordagem recomendada
- **Se a regra é estrita** ("só o que vê"): intersectar os IDs com `deduped_scope` (ou ao menos aplicar `requested_types`). IDs fora viram `skipped` silencioso.
- **Se é intencional** (seleção pode cruzar abas/duplicatas de propósito): documentar no código com comentário claro e fechar como "won't fix".

> Esta é uma **decisão de produto** — perguntar ao usuário antes de mexer. Default sugerido: manter visibilidade por inbox (já segura) e **documentar** como intencional, já que o front só expõe IDs visíveis. Não gastar esforço sem confirmação.

### Critérios de aceite
- [ ] Decisão registrada (código + memória). Se alinhar ao deduped: spec cobrindo.

---

## TAREFA 7 — [ALTO/Frontend] Guarda síncrona contra duplo-clique nos botões de download

### Problema
"Baixar" / "Baixar .zip" não têm `:disabled` síncrono. Entre o clique e o tick em que `status` vira `preparing`, um duplo-clique rápido dispara **dois** `create`. O backend barra o 2º (`export_active` → toast de erro), mas é UX ruim.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/gallery/components/GallerySelectToolbar.vue` (`startZip`/`handleDownload`)
- `app/javascript/dashboard/composables/useBulkDownload.js`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue` (mesmos botões)

### Abordagem recomendada
- Flag local **síncrona** `isStarting` (ref), setada `true` no `@click` **antes** de chamar `start()`, e o botão `:disabled="isStarting || isPreparing"`. Resetar no `finally`/quando `status` sair de `preparing`. Não depender só do `v-if="isPreparing"` (que troca de forma assíncrona).
- Aplicar o mesmo padrão em ambos os consumidores do composable (galeria e conversa). Idealmente expor um `isStarting` do próprio `useBulkDownload` para centralizar.

### Critérios de aceite
- [ ] Duplo-clique rápido dispara **um** `create`. Botão desabilita no primeiro clique.
- [ ] Sem regressão no fluxo de preparo/progresso.

---

## TAREFA 8 — [MÉDIO/Frontend] "Baixar todas" não pode aparecer com 0 baixáveis

### Problema
Conversa só com links → `downloadableCount === 0`, mas o botão "Baixar todas (.zip)" aparece dizendo "Baixar todas (0)"; ao clicar, backend retorna `nothing_to_download` → toast de erro.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue`

### Abordagem recomendada
- Condicionar o botão "Baixar todas" a `downloadableCount > 0` (mesmo padrão já usado no botão "Selecionar").
- Revisar também a tab Links da galeria (ver Tarefa 9) pela mesma razão.

### Critérios de aceite
- [ ] Conversa só com links não mostra "Baixar todas (0)".

---

## TAREFA 9 — [MÉDIO/Frontend] "Preparando… (0/0)" no primeiro tick

### Problema
`PREPARING` renderiza sempre `({processed}/{total})`. No primeiro tick `total` pode ser legitimamente `0` (job ainda contando), exibindo "Preparando… (0/0)" — parece travado.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/gallery/components/GallerySelectToolbar.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationMedia.vue`
- i18n: `en/gallery.json`, `pt_BR/gallery.json` (+ `conversation.json` se a chave for compartilhada)

### Abordagem recomendada
- Quando `total === 0`, exibir um texto neutro **sem contador** (ex.: nova chave `GALLERY.BULK.PREPARING_INDEFINITE` = "Preparando arquivo…"). Quando `total > 0`, manter o `({processed}/{total})` atual.
- Lembrar: o backend já retorna `total_count` no `create` e o composable faz `total = data.total_count || total` (não zera de volta) — então o "0/0" é só o instante inicial. Fallback de UI resolve.

### Critérios de aceite
- [ ] Nunca exibe "(0/0)"; mostra texto indefinido até `total > 0`.
- [ ] Chave nova em EN e pt_BR.

---

## TAREFA 10 — [BAIXO/Frontend] Limpar comentário `[TESTE]` enganoso em GalleryPage.vue

### Problema
`GalleryPage.vue:135-138` e `:209-211` afirmam que a lógica do botão global "Baixar todas (.zip)" segue "dormente no `<script>` — basta restaurar o `<button>`". **Falso:** a lógica (imports `useBulkDownload`/`useAlert`, `downloadAll`, `canBulkDownload`, watch de toast) foi removida junto. O comentário induz a erro.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/gallery/GalleryPage.vue`

### Abordagem recomendada
- **Decidir com o usuário:** (a) limpar o comentário e deixar claro que o ZIP só existe via `GallerySelectToolbar`; **ou** (b) — recomendado — **reintroduzir de fato** o botão global "Baixar todas (.zip)" no header (ver melhoria de descobribilidade abaixo), restaurando a lógica. O design "pill sofisticado" anterior está descrito na memória do projeto.
- Não deixar o comentário mentindo sobre o estado do código.

### Critérios de aceite
- [ ] Comentário reflete a realidade, **ou** o botão global foi restaurado e funcional.

---

## TAREFA 11 — [BAIXO/Frontend] Tab Links: ocultar seleção/checkbox

### Problema
`LinkList.vue` mostra checkbox e a toolbar aparece ao selecionar, mas links **não são baixáveis** (`downloadable` filtra `type === 'attachment'`): o botão ZIP some e "Baixar" cai em erro. Confuso.

### Arquivos
- `app/javascript/dashboard/routes/dashboard/gallery/components/LinkList.vue`
- (eventualmente `GalleryPage.vue`/`GallerySelectToolbar.vue` se a toolbar precisar ser suprimida na tab links)

### Abordagem recomendada
- Na tab Links, **ocultar o checkbox e a seleção** (links se abrem, não se baixam em zip). Se houver caso de uso futuro (ex.: copiar lista de URLs), tratar como feature separada — fora deste escopo.

### Critérios de aceite
- [ ] Tab Links sem checkbox/seleção; sem toolbar de download inútil.

---

## Ordem sugerida e entrega

1. **Lote A (UX, baixo risco):** Tarefas 1, 7, 8, 9, 10, 11. Buildar e validar visualmente no staging.
2. **Lote B (backend, lógica central):** Tarefas 2, 3, 4, 5 — cada uma com spec. Tarefa 6 depende de decisão do usuário.
3. Rodar **rubocop + eslint** e os **specs** (`spec/**/attachments*` + os novos). Se o DB de teste não tiver a tabela: `RAILS_ENV=test bundle exec rails db:migrate` antes.
4. **Não deployar.** Preparar `assets:precompile`, avisar o usuário para o restart (`sudo /bin/systemctl restart chatwoot.target`), e lembrar hard-refresh (Ctrl+Shift+R).
5. Atualizar a memória do projeto (`bulk-media-download-feature`) com o que foi corrigido.

**Checklist final antes de entregar:**
- [ ] Caminho feliz galeria (selecionar → zip) e conversa ("baixar todas") continuam funcionando.
- [ ] Nenhuma chave i18n crua; EN e pt_BR simétricos.
- [ ] Lint limpo; specs verdes (ou justificado o que não rodou e por quê).
- [ ] Decisões de produto (Tarefas 3-opção, 6) registradas explicitamente.
