# W3 — Mapa de conflitos ChatSPX × upstream `v4.16.2`

> Auditoria **read-only**. Nada foi mergeado, rebaseado ou cherry-pickado. Todos os números vêm de
> `git merge-tree --write-tree` (simulação em memória, não toca working tree) e de `git diff --numstat`.

| Parâmetro | Valor |
|---|---|
| merge-base (`v4.12.1`) | `899fce1c9286b793d165c8ad6c0200ab676f185b` |
| nosso HEAD (`homologacao`) | `ee87f5e799` |
| alvo | `v4.16.2` |
| árvore-resultado da simulação | `431b0842ce73809979e9225e8c8772d37890555d` |

---

## 1. Sumário executivo

1. O merge **não é impossível, é ingerenciável em bloco**: `merge-tree` produz **249 arquivos em conflito**
   (dos 558 em colisão), **427 hunks** e **15.667 linhas** dentro de marcadores — 7.230 nossas contra 8.437 deles.
2. Tirando `swagger/swagger.json` (4.188 linhas, arquivo que nós reescrevemos inteiro em pt-BR), sobram
   **11.479 linhas** de conflito real espalhadas em 248 arquivos.
3. A distribuição é boa notícia: **205 dos 249 (82%) são leves ou triviais** (≤80 linhas em conflito, ou
   binário). O veneno está concentrado em **44 arquivos** (28 pesados + 16 críticos).
4. O que trava de verdade **não é textual**: são **8 colisões arquiteturais** (Chatlist v5, bulk actions,
   unread counts, Voice/call model, Captain v2/sessions/LLM routing, template-preview, sidebar, swagger) —
   em várias delas o upstream **apagou** ou **moveu** o arquivo que nós evoluímos (10 `modify/delete`, 3 `add/add`, 4 renames).
5. Há **2 colisões de timestamp de migration** (`20260616120000`, `20260630000000`) que quebram o boot
   com `DuplicateMigrationVersionError` antes de qualquer teste rodar.
6. Só **27% dos 537 commits upstream** (147) não encostam em nenhum dos 558 arquivos em colisão — ou seja,
   cherry-pick "limpo" cobre menos de um terço do delta.
7. Em compensação, **3.047 arquivos o upstream tocou e nós não** — 924 deles são arquivos **novos**.
   Esse é o caminho barato, mas 1.432 são i18n de idiomas que não usamos.
8. **Recomendação: NÃO fazer merge de tag nem rebase.** Estratégia em 3 trilhos (§7): *pull por caminho* no
   que é só-deles, *merge assistido arquivo-a-arquivo* nos 205 leves, *port manual/decisão de produto* nos 44 quentes.
9. Áreas onde devemos **ignorar o upstream de vez**: swagger, branding/favicons, SCSS, i18n `pt_BR`/`en`.
10. Alerta operacional: alguém está editando **agora, sem commit**, `app/services/whatsapp/health_service.rb` e
    `AccountHealth.vue` — exatamente os arquivos que o upstream reescreveu no PR #15100 (§6.9).

---

## 2. Como os números foram medidos

```bash
BASE=899fce1c9286b793d165c8ad6c0200ab676f185b   # v4.12.1
git merge-tree --write-tree --name-only --messages HEAD v4.16.2   # exit 1 = há conflito
# → linha 1: OID da árvore-resultado; bloco 1: 249 nomes de arquivo em conflito; bloco 2: mensagens
git cat-file -p 431b0842ce73809979e9225e8c8772d37890555d:<arquivo> | grep -c '^<<<<<<<'   # hunks reais
git diff --numstat $BASE..HEAD -- <arquivo>  vs  $BASE..v4.16.2 -- <arquivo>              # volume
```

Contar `<<<<<<<` mede **quantos pontos** precisam de decisão humana. Contar as **linhas dentro** dos
marcadores mede **quanto código** precisa ser lido para tomar cada decisão. As duas métricas divergem
bastante (ex.: `ChatList.vue` tem 10 hunks mas só 183 linhas; `response_builder_job.rb` tem 3 hunks
e 485 linhas) — o ranking do §4 usa **linhas em conflito** porque é o que prevê custo de revisão.

**Limite conhecido da métrica:** `merge-tree` só enxerga colisão **textual**. Quando os dois lados
reescreveram o mesmo comportamento em regiões diferentes do arquivo, ele auto-merge "limpo" e produz
código que compila e está errado. Isso está tratado à parte no §6.

---

## 3. Faixas de severidade (os 558 arquivos em colisão)

| Faixa | Critério | Arquivos | O que significa na prática |
|---|---|---:|---|
| **F0 — auto-merge limpo** | sem conflito | **309** | Git resolve sozinho. **Mas 14 deles têm ≥40 LOC alteradas dos dois lados** → risco semântico, ver §6.10 |
| **F1 — trivial** | conflito sem marcador (binário / `modify/delete`) | **38** | 28 são favicons/ícones PNG do nosso branding → fica o nosso, decisão de 1 minuto. 10 são `modify/delete` (§6.11) |
| **F2 — leve** | ≤20 linhas em conflito | **107** | Resolve olhando o hunk. ~1–3 min/arquivo |
| **F3 — médio** | 21–80 linhas | **60** | Precisa entender o contexto dos dois lados. ~10–20 min/arquivo |
| **F4 — pesado** | 81–200 linhas | **28** | Precisa de quem escreveu o nosso lado. ~1h/arquivo |
| **F5 — crítico** | >200 linhas | **16** | Não é "resolver conflito", é **decidir arquitetura**. Ver §4 e §6 |

Distribuição de tipos de conflito emitidos pelo `merge-tree`:
`content` 236 · `modify/delete` 10 · `add/add` 3.

---

## 4. Ranking — os 40 arquivos mais conflitantes

`CL` = linhas dentro de marcadores de conflito · `h` = hunks (`<<<<<<<`) · LOC = linhas alteradas desde a base.

| # | CL | h | nosso LOC | up LOC | Arquivo | Nosso lado × lado deles |
|--:|--:|--:|--:|--:|---|---|
| 1 | 4188 | 8 | 69140 | 1566 | `swagger/swagger.json` | **Nós reescrevemos a spec inteira** (354 paths, 100% pt-BR, exemplos, UI Scalar — `0d5294c85a`, `1dd723b362`, `29e4fb4e3b`); eles só acrescentaram paths novos (branded email, anexos, webhook URL). **Não é merge, é substituição.** |
| 2 | 594 | 10 | 904 | 308 | `…/conversation/ConversationCard.vue` | Nós: skin WhatsApp-fiel + migração Lucide + isolamento por agente (`3ece56e04a`, `4284a31898`, `d845be8d33`). Eles: **layout v5 expandido do chatlist** (#13652), ícones de prioridade novos, SLA de contato bloqueado (#14861). Reescrita × reescrita. |
| 3 | 485 | 3 | 392 | 155 | `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | Nós: handoff prometido, trava de link de imóvel, `[IGNORAR]`, follow-up automático, NPS (`334f0409e9`, `c8281e82b2`, `85af22a3c3`). Eles: **captain sessions** (#14971), classificador de handoff v1 (#14337), harness de falsa promessa (#14672). Mesmo job, duas evoluções incompatíveis. |
| 4 | 417 | 6 | 794 | 259 | `components-next/sidebar/Sidebar.vue` | Nós: skin WhatsApp + itens novos (Pedidos, chat interno, Automações) (`ed60e4745f`, `74bce592fe`). Eles: FAQ suggestions (#15017), voice call dashboard (#14954), Intercom import (#14922), unread count flag (#14885). |
| 5 | 364 | 5 | 312 | 235 | `routes/dashboard/conversation/contact/ContactInfo.vue` | Nós: grupos WhatsApp com integrantes (`44b77d19c0`), export PDF, skin. Eles: avatares quadrados (#14656), WhatsApp Cloud Calling UI (#14346), edição inline de contato (#13976). |
| 6 | 324 | 10 | 2311 | 151 | `…/conversation/ReplyBox.vue` | Nós **+2.139 linhas**: interativos WAHA (botões/lista), upload em 2º plano, reconexão realtime, UX de resumos (`8644a144bd`, `3391e1dd99`, `91c016c4fa`). Eles: voice messages (#14606), emoji picker do Help Center (#14702), restrição Instagram (#15005/#15020). |
| 7 | 300 | 8 | 416 | 121 | `…/conversation/MessagesView.vue` | Nós: sliding window de scroll infinito, banner de aprovação, foco de upload (`6d26c7043b`, `ed60e4745f`). Eles: editor redimensionável (#13916), banners de restrição Meta (#14974/#15136). |
| 8 | 299 | 5 | 148 | 174 | `components-next/captain/assistant/DocumentCard.vue` | Nós: redesign glass/aurora do kit Ai* (`5665cd66c0`). Eles: detalhes de documento crawleado + contagem de FAQ (#14863), auto-sync (#14258), bulk select (#13907). |
| 9 | 270 | 1 | 176 | 524 | `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb` | Espelho do #3. Eles reescreveram 524 linhas do spec (sessions, generation path, LLM routing); nós 176 (IA atribuível, NPS). |
| 10 | 250 | 6 | 437 | 30 | `…/conversation/ConversationHeader.vue` | Nós: **grupos WhatsApp com autor por mensagem** (`44b77d19c0`), skin, sidebar por clique no nome. Eles: só toques (avatar quadrado, ID da conversa, aba Participating, SLA). **Nosso lado domina 230 das 250 linhas.** |
| 11 | 225 | 9 | 1018 | 247 | `db/schema.rb` | Artefato gerado. Nós: 105 migrations (kanban, flows, labels/canned com visibilidade, isolamento por agente). Eles: 45 (captain sessions, FAQ suggestions, email layouts, whatsapp health). Resolve rodando `db:migrate`, **não à mão**. |
| 12 | 225 | 2 | 5 | 292 | `…/components/ConversationItem.vue` | Nós praticamente não tocamos (5 LOC); eles reescreveram no **layout v5** (#13652). Aqui **o lado deles vence** — é o exemplo mais barato do ranking. |
| 13 | 220 | 2 | 20 | 463 | `…/conversationBulkActions/Index.vue` | Eles reescreveram a UI de bulk action (#14118) e **deletaram os 4 sub-componentes** que nós tocamos. Ver §6.2. |
| 14 | 214 | 1 | 168 | 88 | `spec/listeners/action_cable_listener_spec.rb` | Nós: pin de mensagem, reactions, `user_settings` (PRs G1/B1/B4). Eles: unread count (adicionado, revertido, re-adicionado 3×). |
| 15 | 212 | 6 | 257 | 112 | `components-next/NewConversation/ComposeConversation.vue` | Nós: fluxo "Solicitar atendimento", modal redesenhado, dialpad (`fb78cc1f1e`, `3f92b58d9c`). Eles: popover de geração de mensagem (#15114), template picker (#14129). |
| 16 | 202 | 1 | 88 | 120 | `spec/enterprise/models/inbox_spec.rb` | Nós: IA como agente atribuível (`2bee0f7244`). Eles: limite de inbox no model (#14949), bypass de capacidade V2 (#13904). |
| 17 | 200 | 1 | 247 | 121 | `store/modules/conversations/specs/mutations.spec.js` | Nós: painel de bloqueio, falha WAHA, ordem cronológica. Eles: unified call model (#14091). |
| 18 | 192 | 2 | 175 | 36 | `spec/controllers/api/v1/accounts/labels_controller_spec.rb` | Nós: **visibilidade de labels** (pública/privada/time — `819bf3a84e`). Eles: remoção assíncrona de associação (#13531). |
| 19 | 183 | 10 | 683 | 154 | `…/components/ChatList.vue` | Nós: abas dinâmicas em 2 linhas, fila "Aguardando atendimento", fila de encerramento da IA, gate de atribuição (`ba0f124929`, `33eececf10`). Eles: sort by unread (#14512), filtro por contato (#14629), bulk UI (#14118), layout v5 (#13652), aba Participating (#11714). **10 hunks, quase todos "nosso bloco novo × bloco deles novo".** |
| 20 | 175 | 1 | 121 | 60 | `…/conversation/specs/ConversationCard.spec.js` | `add/add` — os dois lados criaram o mesmo spec do zero. |
| 21 | 166 | 2 | 95 | 153 | `app/views/layouts/mailer/base.liquid` | Nós: branding ChatSPX. Eles: redesign do e-mail de convite (#14090) + branded email layouts (#14936). |
| 22 | 165 | 4 | 749 | 83 | `i18n/locale/en/conversation.json` | Nós: +714 chaves (atendimento, grupos, checklist). Eles: label search no menu, generation path do Captain, banners Meta. **JSON — conflito é ruído de chave adjacente, não semântico.** |
| 23 | 155 | 1 | 243 | 120 | `spec/models/attachment_spec.rb` | Nós: teto de 100MB, falha WAHA, waveform, áudio sem arquivo. Eles: `external_url` do Instagram, `extension`/`content_type` no webhook. |
| 24 | 149 | 3 | 745 | 69 | `i18n/locale/pt_BR/conversation.json` | Idem #22. Nosso pt-BR é **a fonte de verdade**; o deles é saída de máquina de tradução (`e70bbfaaa5`). |
| 25 | 144 | 3 | 621 | 22 | `components-next/message/Message.vue` | Nós: grupos WhatsApp, delete-for-everyone, vCard, isolamento por agente, animações de envio. Eles: Calls page (#15129), report de mensagem do Captain (#14799), fallback de link do Facebook (#14554). |
| 26 | 140 | 2 | 134 | 22 | `store/…/helpers/specs/actionHelpers.spec.js` | Nós: 4 bugs de produção (`1e9ff5f196`). Eles: aba Participating. |
| 27 | 140 | 1 | 142 | 22 | `enterprise/app/models/concerns/agentable.rb` | Nós: prompt caching Anthropic por conta, injeção de horário de funcionamento (`e785949cea`, `1f59794f7a`). Eles: **captain v2 por padrão** (#14917), roteamento de LLM Enterprise (#14841), temperatura fixa 0.5 (#14879). Colisão de arquitetura de prompt. |
| 28 | 133 | 4 | 513 | 41 | `routes/dashboard/conversation/ConversationAction.vue` | Nós: "Devolver para a IA", Solicitar atendimento, ações por dono. Eles: dropdown de agent bot otimizado (#14866), ícone/emoji de time (#14767). |
| 29 | 130 | 1 | 30 | 116 | `vite.config.ts` | Eles: **upgrade para Vite 6** (#14363) + fim de warnings sass/vue. Nós: entradas do Flow/canvas e i18n. **Item obrigatório de build** — ver §8. |
| 30 | 117 | 3 | 178 | 209 | `spec/services/whatsapp/incoming_message_whatsapp_cloud_service_spec.rb` | Nós: CTWA em `content_attributes`, WhatsApp interativo no canvas. Eles: CTWA referral (#14681), BSUID (#14436), filename original (#14168). **Os dois implementaram CTWA** — ver §6.7. |
| 31 | 116 | 3 | 749 | 22 | `…/WootWriter/CopilotMenuBar.vue` | Nós: redesign 2026 do painel/dropdown da IA (`494d35593f`). Eles: um fix de exibição (#14160). Nosso lado domina. |
| 32 | 115 | 3 | 61 | 69 | `enterprise/…/captain/assistants_controller.rb` | Nós: tools/integrações multi-tenant, geocoding, chaves fora da URL (`cde672ddb1`). Eles: assistant overview + stats (#14889/#15105), FAQ suggestions (#15017). |
| 33 | 113 | 4 | 62 | 207 | `components-next/sidebar/SidebarSubGroup.vue` | Eles: ordenação e colapso das seções (#14609/#14509). Nós: skin + tamanho de submenu. **Lado deles é maior e mais útil.** |
| 34 | 110 | 3 | 36 | 93 | `app/controllers/super_admin/accounts_controller.rb` | Eles: metadados de suspensão de conta (#15158), hardening de override de modelo (#14846). Nós: auditoria de best practices. |
| 35 | 110 | 3 | 36 | 93 | `components-next/sidebar/SidebarGroupSeparator.vue` | Idem #33. |
| 36 | 103 | 1 | 92 | 147 | `spec/models/account_spec.rb` | Eles: `api_and_webhooks` feature flag (#14972/#14973), embedded signup gate (#15046), Intercom. Nós: config de API key do Copilot. |
| 37 | 97 | 1 | 67 | 42 | `spec/enterprise/models/captain/assistant_spec.rb` | `add/add`. Nós: IA atribuível. Eles: custom tools no Captain V2 (#15015). |
| 38 | 96 | 3 | 84 | 64 | `shared/components/ui/MultiselectDropdownItems.vue` | Eles: guard de nome nulo (#15125), dropdown de agent bot (#14866), ícone de time (#14767). Nós: consolidação de WIP. |
| 39 | 94 | 3 | 93 | 62 | `app/controllers/api/v1/accounts/inboxes_controller.rb` | Nós: isolamento por agente, NPS, assinatura do agente, seleção de HSM. Eles: branded email (#14936), embedded signup → manual (#14975), limite de inbox (#14949), N+1 (#14451). |
| 40 | 93 | 2 | 193 | 15 | `store/modules/conversations/getters.js` | Nós: getters das abas novas (`getAwaitingChats`, `getAIChats`, `getPendingClosureChats`). Eles: `getParticipatingChats` + seção de anexos. **Conflito direto de contrato do store.** |

---

## 5. Veredito por subsistema

Métrica por subsistema, restrita aos 558 em colisão:

| Subsistema | Arqs | Conflit. | Hunks | LOC nosso | LOC deles | **Veredito** |
|---|--:|--:|--:|--:|--:|---|
| dashboard front (legado) | 113 | 58 | 132 | 12.095 | 6.581 | **Merge caro → port manual seletivo.** É onde mora nossa identidade (skin WhatsApp, abas, atendimento). Trazer só correções pontuais deles, arquivo a arquivo. |
| dashboard front (components-next) | 51 | 28 | 64 | 4.225 | 2.833 | **Misto.** Sidebar (`SidebarSubGroup`, `SidebarGroupSeparator`, `SidebarGroupLeaf`): **pegar o deles** (ordenação/colapso são melhores que o nosso). Captain/`ai-assistant`: **manter o nosso**. Message/bubbles: **port manual**. |
| specs/testes | 82 | 25 | 44 | 5.962 | 5.402 | **Merge viável, mas por último.** Spec conflitado não bloqueia decisão — resolve depois que o código estabilizar. Não gaste hora de sênior aqui. |
| enterprise/ | 41 | 18 | 25 | 1.483 | 1.586 | **Merge caro / decisão de produto.** É o Captain. Ver §6.5 — precisa decidir se adotamos o Captain V2 + LLM routing deles ou seguimos com o nosso. |
| i18n | 84 | 15 | 24 | 6.688 | 7.369 | **Manter o nosso e ignorar o upstream** em `pt_BR` e `en` (nosso pt-BR é fonte de verdade; o deles é máquina). **Trazer inteiro** os outros 1.432 arquivos de idioma que não tocamos, se quisermos os idiomas. |
| models | 23 | 12 | 23 | 798 | 651 | **Merge viável com revisão.** Volume baixo dos dois lados. `account.rb` e `conversation.rb` merecem par a par. |
| API controllers | 25 | 9 | 17 | 1.166 | 523 | **Merge viável.** Nosso lado é maior, mas os hunks são localizados. Atenção a `inboxes_controller` e `conversations_controller` (isolamento por agente é segurança). |
| jobs/listeners | 15 | 10 | 13 | 409 | 501 | **Merge viável.** Volume pequeno. `whatsapp_events_job` precisa de olho (§6.7). |
| dependências/build | 4 | 3 | 12 | 650 | 1.134 | **Reescrever do lado deles.** `pnpm-lock.yaml`/`Gemfile.lock` **não se resolvem à mão** — regenera. `package.json`/`Gemfile` merge manual (11 e 5 linhas). |
| javascript shared | 9 | 7 | 10 | 472 | 517 | **Merge viável.** |
| views/mailers | 12 | 8 | 10 | 300 | 497 | **Reescrever do lado deles + reaplicar branding.** Eles fizeram branded email layouts (#14936); nosso lado é só cor/logo. |
| config/ | 11 | 5 | 10 | 634 | 830 | **Merge viável, com 2 exceções críticas.** `config/routes.rb` (4 hunks) e `config/features.yml` (§6.8). |
| db/migrations+schema | 1 | 1 | 9 | 1.018 | 247 | **Reescrever do lado deles.** `schema.rb` é gerado — resolve com `db:migrate`. **Antes disso, corrigir as 2 colisões de timestamp (§6.12).** |
| lib/ | 13 | 6 | 8 | 181 | 227 | **Merge viável.** |
| swagger | 1 | 1 | 8 | 69.140 | 1.566 | **Manter o nosso e ignorar o upstream.** Nossa spec é produto (API pública em pt-BR). Reintroduzir manualmente os endpoints novos deles. |
| raiz/outros | 34 | 32 | 5 | 598 | 190 | **Manter o nosso.** 28 dos 32 são favicons/ícones do branding ChatSPX. Exceções: `vite.config.ts` (trazer o deles, §8) e `AGENTS.md`. |
| services | 12 | 3 | 5 | 223 | 308 | **Merge viável.** |
| builders | 11 | 5 | 4 | 200 | 222 | **Merge viável**, menos os 2 timeseries builders deletados (§6.11). |
| app/ (outros) | 7 | 1 | 2 | 419 | 70 | **Merge viável.** |
| **SCSS/estilos** | 3 | 1 | 1 | 683 | 50 | **Manter o nosso, risco ~zero.** Os 3 em colisão são `_base.scss`, `_next-colors.scss` e `widget/assets/scss/woot.scss` — e **só o último conflita, em 5 linhas**. Nosso `_wa-skin.scss` não aparece na colisão. Todo o redesign WhatsApp-fiel passa incólume |
| widget/portal/survey | 6 | 1 | 1 | 60 | 189 | **Reescrever do lado deles.** Quase não tocamos. |

---

## 6. Colisões arquiteturais — o que o `merge-tree` não mostra

Estes são os itens que **travam de verdade**: os dois lados reescreveram o mesmo comportamento.
Alguns aparecem como conflito pequeno (ou nenhum) e mesmo assim exigem decisão de produto.

### 6.1 Chatlist v5 (upstream #13652 `feat(v5): New expanded layout for chatlist`)
Upstream reescreveu `ChatList.vue` + `ConversationCard.vue` + `ConversationItem.vue` + ícones de prioridade
(deletou os 5 SVGs em `public/assets/images/dashboard/priority/`). Nós reescrevemos os mesmos arquivos com
skin WhatsApp-fiel, migração Lucide e **abas dinâmicas próprias** (Aguardando atendimento / IA / fila de
encerramento). Não existe merge: é escolher um layout. **Nossa recomendação: manter o nosso; portar dele só
`sort by unread` (#14512) e `filtro por contato` (#14629), que são funcionalidades, não layout.**

### 6.2 Bulk actions reescritas (upstream #14118 + #14534)
Upstream **deletou** `conversationBulkActions/{AgentSelector,LabelActions,TeamActions,UpdateActions}.vue`
(4 `modify/delete`) e concentrou tudo em `Index.vue` (+463 LOC). Nós tocamos os 4 deletados e temos, por
cima, o fluxo de transferência de time e o diálogo de bulk assign+resolve. **Port manual obrigatório** —
se aceitar o delete, perdemos nossas features silenciosamente.

### 6.3 Unread counts (CW-6851 / CW-7262 / CW-7237) — feature adicionada, revertida e re-adicionada 3×
Toca `helper/actionCable.js` (+220 LOC deles), `Sidebar*`, `conversation.rb`, `conversations_controller.rb`,
`action_cable_listener_spec.rb`. Nós reescrevemos `actionCable.js` na F0 "sempre conectado"
(`3391e1dd99`/`004a5d8a19`) — reconexão no `visibilitychange`, aviso offline escalonado. **Os dois lados
mexeram no coração do mesmo arquivo.** Como o próprio upstream reverteu duas vezes, o histórico deles está
instável: **recomendo esperar `develop` estabilizar e portar manualmente depois.**

### 6.4 Voice / unified call model (114 arquivos deles)
Upstream criou um modelo de chamada unificado (`enterprise/app/models/call.rb`), **deletou**
`enterprise/app/models/channel/voice.rb` e `FloatingCallWidget.vue` (que nós tocamos), e espalhou UI em
`ConversationHeader`, `ContactInfo`, `Message.vue`, `store/conversations`. Nós temos
`VoiceCall.vue`/`VoiceCallStatus.vue` próprios. **Valor para o ChatSPX é baixo hoje** (não vendemos voz) e o
custo de merge é alto → **descartar por ora e não arrastar os 114 arquivos**.

### 6.5 Captain V2 + sessions + LLM routing + FAQ suggestions
O maior choque do delta. Upstream criou **128 arquivos novos** de Captain (assistant overview, agent
sessions #14970/#14971, FAQ suggestions #14977/#14979/#15017, roteamento de LLM Enterprise #14841, captain v2
por padrão #14917) e **deletou** `routes/dashboard/captain/responses/Pending.vue` (substituído por
`FaqSuggestions.vue`). Nós criamos **164 arquivos** próprios (kit `Ai*` glass/aurora, `copilot/*`, tools
multi-tenant, eval, auto-closure, prompt caching, `spx/ai_config`). Os pontos de fricção textual são
`agentable.rb` (140 CL), `response_builder_job.rb` (485 CL) e `assistants_controller.rb` (115 CL) — mas o
problema é que **são dois produtos diferentes ocupando o mesmo namespace**. Decisão de produto, não de merge.

### 6.6 Message templates movidos + deletados
Upstream renomeou `components-next/message/bubbles/Template/{CSAT,Card,Text}.vue` →
`components-next/template-preview/*` e **deletou** `CallToAction`, `ListPicker`, `Media`, `QuickReply`
(+ 6 stories). Nós evoluímos `Message.vue`/`Base.vue` para grupos WhatsApp e delete-for-everyone.
Rename + delete no mesmo diretório que nós evoluímos = **o `merge-tree` resolve o rename e depois nossa
importação aponta para arquivo que não existe mais**. Falha só aparece em build.

### 6.7 CTWA referral — os dois implementaram a mesma coisa
Nós: `58c98bf1f2 feat(whatsapp): persistir referral CTWA em content_attributes`. Eles: `de137e8297
feat: Capture CTWA referral metadata for WhatsApp conversations (#14681)`. Mesmo dado, campos possivelmente
diferentes. `incoming_message_whatsapp_cloud_service_spec.rb` conflita em 117 linhas. **Verificar
compatibilidade de schema antes de escolher um dos dois** — se divergir, quebra dado já gravado em produção.

### 6.8 `feature_flags` — upstream resolveu o nosso problema de outro jeito
Upstream #14947 `feat: Extend account feature flag storage` adiciona `feature_flags_ext_2` em
`accounts` (migration `20260706215758`) + reescreve `app/models/concerns/featurable.rb`. **Isso é exatamente
o bitmask cheio que nós contornamos com `internal_attributes`.** `config/features.yml` conflita (2 hunks,
28 CL) e `account.rb` (5 hunks). **Alto valor**: adotar a solução deles nos tira de uma dívida conhecida —
mas exige migrar o que já pusemos em `internal_attributes`.

### 6.9 WhatsApp phone number health — colisão **em andamento, não commitada**
Upstream #15100 (`d644c207f0`) criou `app/services/whatsapp/health_service.rb`, `AccountHealth.vue`,
`health_sync_job`, `health_sync_scheduler_job` e a migration `20260718000000`. Esses arquivos **não estão
no overlap** (nós nunca os commitamos) — **mas o `git status` mostra `health_service.rb`, `AccountHealth.vue`
e `inboxes_controller_spec.rb` modificados no working tree agora**. Ou seja: alguém está editando à mão,
sem commit, exatamente o que o upstream reescreveu. Se esse WIP for commitado, +3 arquivos entram na
colisão. **Alinhar com quem está mexendo antes de qualquer integração.**

### 6.10 Auto-merge "limpo" com risco semântico (14 arquivos)
Passam sem conflito, mas os dois lados alteraram ≥40 LOC. Os piores:
`spec/controllers/api/v1/accounts/conversations_controller_spec.rb` (nosso 205 × deles 256),
`spec/controllers/…/captain/preferences_controller_spec.rb` (124 × 136),
`store/modules/specs/conversations/getters.spec.js` (334 × 92),
`spec/services/whatsapp/providers/whatsapp_cloud_service_spec.rb` (164 × 92),
`spec/finders/conversation_finder_spec.rb` (252 × 61),
`config/integration/apps.yml` (103 × 66),
`spec/listeners/webhook_listener_spec.rb` (113 × 76).
**Nenhum marcador de conflito → passa despercebido no review.** Precisam de leitura dirigida.

### 6.11 Os 10 `modify/delete` (upstream apagou, nós evoluímos)
| Arquivo | Contexto |
|---|---|
| `app/builders/v2/reports/timeseries/average_report_builder.rb` | Upstream removeu os builders de timeseries |
| `…/widgets/FloatingCallWidget.vue` | Substituído pelo call model unificado |
| `…/conversationBulkActions/{AgentSelector,LabelActions,TeamActions,UpdateActions}.vue` | §6.2 |
| `routes/dashboard/captain/responses/Pending.vue` | Virou `FaqSuggestions.vue` |
| `app/javascript/shared/components/emoji/EmojiInput.vue` | Substituído no #14702 (emoji/icon picker) |
| `app/jobs/inboxes/bulk_auto_assignment_job.rb` + spec | Removido pelo upstream |

Em todos, o `merge-tree` **mantém a nossa versão** — o que é o comportamento certo, mas deixa código órfão
apontando para APIs que sumiram.

### 6.12 Colisão de timestamp de migration (bloqueante de boot)
| Timestamp | Upstream | Nosso |
|---|---|---|
| `20260616120000` | `add_icon_to_teams.rb` | `add_agent_id_to_messages.rb` |
| `20260630000000` | `add_sender_created_index_to_messages.rb` | `extend_ai_config_changes.rb` |

`DuplicateMigrationVersionError` derruba `db:migrate` e o boot **antes de qualquer teste**. Fix conhecido:
`git mv` da nossa migration para um timestamp livre (não da deles — os deles já rodaram em outras bases).

---

## 7. Caminho de menor resistência — os 3.047 arquivos que só o upstream tocou

`theirs.txt − ours.txt` = **3.047 arquivos** (924 deles **novos**), **263.300 linhas**. Onde caem:

| Categoria | Arqs | Novos | LOC | Barato mesmo? |
|---|--:|--:|--:|---|
| i18n outros idiomas (`locale/*`, `config/locales/*`) | 1.432 | 162 | 90.532 | **Sim, e é a metade do volume.** 47 arquivos `uz`, 43 `zh_TW`, 25 `tl/ne/ms/it`… Só traz valor se vendermos fora do Brasil. Custo de merge ≈ 0 |
| specs | 430 | 178 | 36.185 | **Só junto com o código que testam.** Trazer spec sem a feature dá suite vermelha |
| front dashboard legado | 232 | 89 | 15.912 | **Parcial.** Os 89 novos são baratos; os 143 modificados costumam importar de arquivos em colisão |
| enterprise/ | 219 | **134** | 9.402 | **Os 134 novos são o Captain V2 deles** — barato de copiar, caro de decidir (§6.5) |
| front components-next | 169 | 80 | 14.677 | Idem front legado |
| views/mailers | 89 | 59 | 2.088 | **Sim.** Branded email layouts, quase tudo novo |
| services | 79 | 50 | 6.374 | **Sim, na maioria** |
| API controllers | 61 | 14 | 1.423 | **Sim** |
| raiz/infra (CI, docker, bin) | 51 | 29 | 2.942 | **Sim** |
| lib/ | 49 | 23 | 2.416 | **Sim** |
| db/migrate | 45 | 45 | 741 | **Sim — mas checar timestamp (§6.12)** |
| models | 40 | 10 | 913 | **Sim** |
| swagger (arquivos `.yml` fonte) | 37 | 17 | 6.169 | Irrelevante: nossa spec é o `swagger.json` |
| front shared / widget / app-outros / jobs / builders / config | 114 | 34 | 73.526 | **Sim, na maioria.** 61.512 dessas linhas são só `config/llm_models.json` (catálogo gerado de modelos LLM) — arquivo grande, custo de merge zero |

**Porém — o número que corrige o otimismo:** dos **537 commits upstream** (sem merges), só **147 (27%)**
não encostam em nenhum dos 558 arquivos em colisão, e **220 (40%)** não encostam em nenhum dos 249
efetivamente conflitados. Os 147 commits totalmente limpos entregam **404 arquivos**. Ou seja: o "caminho
barato" existe, mas **não é cherry-pickável commit a commit** — a maior parte dos 3.047 arquivos chega
dentro de commits que também mexem em arquivo quente. Traga **por caminho** (`git checkout v4.16.2 -- <path>`
sob revisão), não por commit.

---

## 8. Estratégia de integração recomendada

### Descartadas, com o número que as mata

| Opção | Por que não |
|---|---|
| **Merge direto da tag `v4.16.2`** | Entrega um working tree com **249 arquivos quebrados, 427 pontos de decisão e 15.667 linhas** de conflito ao mesmo tempo. Não roda um único teste até o último conflito ser fechado, e as 2 colisões de migration (§6.12) impedem até o boot. Além disso, **8 colisões arquiteturais** (§6) não têm resposta textual — o revisor trava. |
| **Rebase de `homologacao` sobre `v4.16.2`** | **940 commits nossos** replicados sobre 555 deles. Os mesmos conflitos de `ChatList.vue`, `ReplyBox.vue` e `response_builder_job.rb` reaparecem **em cada commit que os tocou** — dezenas de vezes. Custo multiplicativo, zero benefício sobre o merge. |
| **Cherry-pick seletivo por feature, como estratégia única** | Só **27% dos commits** (147/537) são limpos. Os PRs vêm em séries (`1/6`, `2/3`, `3/4`) que dependem umas das outras e atravessam os arquivos quentes. Serve como *tática*, não como *estratégia*. |

### Recomendada: **3 trilhos paralelos, `develop`-first, sem nunca mergear a tag**

**Trilho A — "pull por caminho" (barato, sem conflito, alta cobertura)**
Alvo: os 3.047 arquivos só-deles, ordenados por relação custo/valor.
Mecânica: `git checkout v4.16.2 -- <caminho>` em branch dedicado, um subsistema por PR, suite verde antes do próximo.
Ordem sugerida: `db/migrate` novos (45, corrigindo timestamp) → `lib/` (49) → `services` novos (50) →
`views/mailers` (89) → `API controllers` novos (14) → `models` novos (10) → `raiz/infra` (51).
**Deixar por último:** i18n de outros idiomas (1.432 — decisão comercial) e `enterprise/` (219 — §6.5).
Custo estimado: **M a G**, mas paralelizável e de baixo risco.

**Trilho B — merge assistido arquivo-a-arquivo (205 arquivos)**
Alvo: as faixas F1+F2+F3 do §3 (38 triviais + 107 leves + 60 médios) ≈ **4.500 linhas de conflito**.
Mecânica: usar a árvore `431b0842ce` já calculada como fonte dos hunks; resolver fora do working tree e
aplicar por arquivo. Os 28 favicons resolvem em bloco ("fica o nosso"). Adicionar à revisão os **14 arquivos
de auto-merge silencioso** do §6.10, que não têm marcador e por isso não entram na lista automática.
Custo estimado: **G** (≈ 3–5 dias de um sênior), mas mecânico e revisável em PRs pequenos.

**Trilho C — port manual + decisão de produto (44 arquivos + 8 temas)**
Alvo: faixas F4+F5 e as colisões do §6. Aqui **não se resolve conflito, se decide o produto**:
Chatlist v5, bulk actions, unread counts, Voice, Captain V2, template-preview, sidebar, swagger.
Cada tema vira um card com dono. Recomendação inicial por tema:
`swagger` → manter o nosso · `favicons/SCSS/i18n pt_BR+en` → manter o nosso ·
`sidebar (SubGroup/Separator/GroupLeaf)` → **pegar o deles** (ordenação/colapso) ·
`ConversationItem.vue` → **pegar o deles** · `Voice` → **descartar** ·
`feature_flags_ext_2` (#14947) → **trazer, alto valor** (§6.8) · `Vite 6` (#14363) → **trazer, obrigatório**
(destrava upgrades de dependência) · `Captain V2` → **avaliar depois, decisão de produto**.
Custo estimado: **G+**, com dependência de decisão de negócio.

**Trilho 0 (pré-requisito, faz antes de tudo):** corrigir as 2 colisões de timestamp de migration (§6.12).
Sem isso nenhum dos trilhos consegue rodar `db:migrate`. Custo: **P** (< 1h).

**Base de comparação:** apontar para `upstream/develop` (03/08/2026, +47 commits sobre `v4.16.2`) **só depois
que os trilhos A e B fecharem**. Antes disso, `v4.16.2` é o alvo estável — `develop` inclui as idas e vindas
do unread count (§6.3), que ainda estão instáveis.

---

## 9. Pegadinhas para quem for executar

1. **`db/schema.rb` e os lockfiles não se resolvem à mão.** `schema.rb` (225 CL), `pnpm-lock.yaml` (87 CL, 8
   hunks) e `Gemfile.lock` (5 CL) são gerados. Resolver o conflito textual neles produz artefato corrompido.
2. **`git status` mostra WIP de várias pessoas não commitado**, incluindo os arquivos exatos do WhatsApp
   health que o upstream reescreveu (§6.9), `config/routes.rb`, `copilot_*` do enterprise e i18n de
   conversation. **Esse WIP não está nos 558 e pode virar colisão nova a qualquer commit.**
3. **`ConversationHeader.vue` engana:** 250 linhas em conflito, mas **230 são nossas e só 20 deles**. Não é
   uma reescrita deles — é o nosso volume batendo em mudanças pequenas. Resolve rápido mantendo o nosso.
4. **`swagger/swagger.json` infla toda estatística.** Sozinho responde por 27% de todas as linhas em conflito.
   Qualquer métrica agregada que o inclua está distorcida.
5. **Os 3 `add/add`** (`ConversationCard.spec.js`, `captain/assistant_spec.rb`, `lib/llm/models_spec.rb`)
   são arquivos que os dois lados criaram do zero com o mesmo nome — não há ancestral comum, o diff é 100%.
6. **`enterprise/app/models/concerns/agentable.rb`**: 140 linhas de conflito em 1 hunk só. É um bloco único
   e denso — não dá para resolver por partes.
7. **Ordem importa nos specs**: 82 specs em colisão. Resolver spec antes do código correspondente gera
   retrabalho garantido.

---

## 10. O que eu NÃO consegui apurar

- **Se o CTWA deles é compatível com o nosso** (§6.7). Exigiria ler os dois `content_attributes` gravados em
  banco de produção — fora do escopo read-only de código.
- **Custo real em horas.** As estimativas P/M/G do §8 são derivadas de linhas de conflito e número de hunks,
  não de medição de time. Um arquivo de 20 linhas de conflito em `agentable.rb` custa mais que 200 linhas
  em `pt_BR/conversation.json`.
- **Se as features do Trilho A rodam isoladas.** Medi que 3.047 arquivos são só-deles e que 27% dos commits
  são limpos, mas não validei em runtime que, por exemplo, os 50 services novos bootam sem os controllers
  em colisão. Isso só um `rails runner` no ambiente diria — e eu não executei nada.
- **`upstream/develop` (+47 commits)** não foi analisado. Todo o mapa é contra `v4.16.2`.
- **Impacto em dados já gravados** por qualquer das migrations deles (as 45) — não inspecionei conteúdo de
  migration, só nomes e timestamps.
- **Conflitos que só aparecem em build/runtime** (imports quebrados pelos renames do §6.6). `merge-tree` não
  compila; só um `vite build` sobre a árvore mesclada mostraria, e isso exigiria escrever no working tree.

---

### Anexo — artefatos brutos desta auditoria

Gerados em `/tmp/claude-1001/-home-chatwoot-chatwoot/e955afb1-ebf1-43a0-a5ae-9e10a5dad60c/scratchpad/w3/`:
`conflicted_files.txt` (249) · `messages.txt` (log do merge-tree) · `hunks_sorted.tsv` (hunks/arquivo) ·
`conflines.tsv` (linhas em conflito, nossas × deles) · `rows2.json` (dataset completo dos 558) ·
`only_theirs.txt` (3.047) · `top40.txt` · `top45_log.txt` (commits por arquivo).
A árvore mesclada simulada permanece acessível em `431b0842ce73809979e9225e8c8772d37890555d`
(`git cat-file -p <tree>:<arquivo>` mostra o arquivo já com os marcadores, sem tocar no working tree).
