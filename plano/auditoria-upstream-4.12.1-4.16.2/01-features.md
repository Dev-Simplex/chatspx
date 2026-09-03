# W1 — Catálogo de features e melhorias de produto (upstream v4.13.0 → v4.16.2 + develop)

> Auditoria **read-only**. Base = `899fce1c9286b793d165c8ad6c0200ab676f185b` (v4.12.1).
> Fontes cruzadas: `gh api repos/chatwoot/chatwoot/releases` × `git log --oneline $BASE..v4.16.2`
> (555 commits) × `git log v4.16.2..upstream/develop` (47 commits).
> Fora de escopo (outros workers): Captain/IA e canais WhatsApp (W5), migrations/schema (W2),
> dependências/infra/segurança (W4), mapa de conflitos arquivo-a-arquivo (W3).

---

## Sumário executivo

1. **Achado que muda a prioridade de tudo:** o upstream resolveu o esgotamento do bitmask de
   `feature_flags` (`873d16f54c`, +197 linhas). **Nós já estamos 2 flags ALÉM do limite físico** —
   `config/features.yml` tem 65 entradas num `bigint` que só comporta 63, e as duas últimas
   (`conversation_required_attributes`, `advanced_assignment`) são features vivas referenciadas no
   front. Isso é bug latente hoje, não risco futuro. **Item #1 da lista, esforço P.**
   No caminho, apurei o que é **o maior risco isolado desta auditoria**: os slots de bit do nosso
   `features.yml` divergem dos do upstream em **10 posições**, então mergear esse arquivo por texto
   troca silenciosamente as features ligadas de toda a frota. Mapa completo em H1, risco #0.
2. Segundo item obrigatório: **SLA agora respeita horário comercial** (`49b0ab0e1f`, #13392). Hoje
   nosso SLA computa breach em wall-clock mesmo com "only during business hours" ligado — é
   **dado errado sendo mostrado ao cliente**, não falta de feature.
3. Ganho de produto mais denso: o módulo **Companies** foi de "só uma listagem" (o que temos) para
   CRM B2B completo em v4.14.0 — página de detalhe, notas, histórico, seletor no contato, atributos
   customizados, última atividade. Colide com **1 arquivo** nosso. É o melhor retorno por risco da auditoria.
4. Help Center recebeu o maior volume (layout "documentation", busca pública, per-locale, staged
   edits, editor rico). Valor real, mas **colide exatamente no `portals/base_controller.rb` da nossa
   Central de Ajuda embutida** — nada aqui entra sem adaptação.
5. Onde o upstream tentou fazer o que já fizemos, **nós ganhamos**: Flows > `time based automation`
   (develop); relatórios de atribuição, Kanban e chat interno o upstream simplesmente não tem;
   campanha WhatsApp nossa (CSV + dedup + normalização BR) é mais completa — mas o processador Liquid
   deles é complementar e vale P de esforço.
6. Perigo silencioso: a feature flag `api_and_webhooks` (`9c444315a6` + `522e3c4d3f`) **desliga token
   de API e webhooks de conta** se vier sem a flag ligada. Merge cego derruba integração de cliente.
7. A saga de **unread counts** foi revertida duas vezes por performance e hoje vive atrás de flags
   `chatwoot_internal`. Não é feature madura — não perseguir.

---

## Tabela de decisão

Legenda: valor `A`lto / `M`édio / `B`aixo / `N`enhum · risco `B`aixo / `M`édio / `A`lto ·
esforço `P` (<1d) / `M` (1-3d) / `G` (>3d).

### A. Conversas / Inbox

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| A1 | Merge de 3 `COUNT` em query única no `/meta` | `a901c87ab4` #13536 v4.15.0 | A | B | **TRAZER** | P |
| A2 | Elimina N+1 em `inboxes#index` | `dd7f5c27e5` #14451 v4.14.0 | A | B | **TRAZER** | P |
| A3 | Merge opt-in de `custom_attributes` da conversa + `destroy_custom_attributes` | `acae0a2acf` #15119 develop | A | B | **TRAZER** | P |
| A4 | Anexos na sidebar da conversa (+ endpoint) | `8f532f45ff` #14371 / `dc332dd93e` #14391 v4.14.0 | A | M | **TRAZER** | M |
| A5 | Busca de etiqueta no menu de contexto (botão direito) | `bae20ca83e` #15084 v4.16.2 | M | B | **TRAZER** | P |
| A6 | Remoção de etiquetas em lote | `b981ba766f` #14534 v4.14.1 | M | B | **TRAZER** | P |
| A7 | Filtro por contato na lista de conversas | `e919a2cef5` #14629 v4.14.2 | M | M | **TRAZER** | M |
| A8 | Nova UI de ações em lote | `2435d7503c` #14118 v4.14.0 | M | M | **TRAZER ADAPTADO** | M |
| A9 | Exibir ID da conversa na view | `815593eec9` #14381 v4.14.0 | M | B | **TRAZER** | P |
| A10 | Aba "Participating" | `b96bf41234` #11714 v4.13.0 | M | M | **TRAZER ADAPTADO** | P |
| A11 | Takeover de conversa pendente (bot → humano) | `226af4959e` #14876 develop | M | M | **TRAZER ADAPTADO** | P |
| A12 | Contadores de não-lidas (série completa + 2 reverts) | `3fae800936`/`27f2c2b392`/`f33e469e9a`/`66cfb26c77` | M | **A** | **AVALIAR DEPOIS** | G |
| A13 | Layout expandido da chatlist (v5) | `3a4738729d` #13652 v4.14.0 | B | **A** | **DESCARTAR** | G |
| A14 | Imagens inline em website/e-mail | `1beaa284c6` #14516 v4.14.2 | B | B | AVALIAR DEPOIS | P |
| A15 | Quoted reply sai de trás da flag (flag vira `deprecated`) | `ef27e571f7` #14469 v4.14.1 | B | B | **JÁ TEMOS (só ligar a flag)** | P |
| A16 | Anexos XML e PFX | `bef25781de` #14539 v4.14.1 | M | B | **TRAZER** | P |
| A17 | Emoji do Slack renderizado como unicode | `80fccbc526` #12928 v4.14.0 | B | B | TRAZER | P |
| A18 | `\` residual depois de hard-break antes de lista | `42cbf7d3b9` #15112 v4.16.1 | M | B | **TRAZER** | P |

### B. Contatos / CRM

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| B1 | **Companies completo** (detalhe, notas, histórico, criação, seletor, atributos, última atividade) | `fe44b07147` #14054 · `086aa36ffe` #14401 · `10597863d7` #14402 · `41a3ab6dfa` #14496 · `1d2f3e86dd` #14435 · `2b37fef0e0` #14759 · `16b8693e1b` #14099 — v4.14.0 a v4.16.0 | **A** | B | **TRAZER** | G |
| B2 | Media view do contato | `35bef21f83` #14393 v4.15.0 | A | M | **TRAZER** | M |
| B3 | BOM UTF-8 no export CSV + strip do BOM no import | `c5fb8d73cc` #14123 / `9a89e1f522` #14126 v4.14.0 | **A** | B | **TRAZER** | P |
| B4 | Edição inline dos dados do contato | `64f6bfc811` #13976 v4.13.0 | M | M | **TRAZER** | P |
| B5 | Etiquetas no import/export de contatos | `d43a87c9dc` #13313 v4.14.0 | M | B | **TRAZER** | P |
| B6 | País deixa de cair em "Zimbabwe" por default | `7820739f3a` #14078 / `5e79dd699e` #14098 v4.14.0 | M | B | **TRAZER** | P |
| B7 | Permissão de export de contato alinhada | `1afcd36dee` #14601 v4.14.2 | M | B | **TRAZER** *(segurança)* | P |
| B8 | Fallback por telefone pra atualizar lead | `e4c3f0ac2f` #13910 v4.13.0 | M | M | AVALIAR DEPOIS | P |
| B9 | Truncar nome de contato vindo de IMAP | `6d26e7930a` #14631 v4.15.0 | B | B | TRAZER | P |
| B10 | `first_name` de nome de palavra única (drops) | `9d808a18df` #13488 v4.14.2 | B | B | TRAZER | P |
| B11 | Encode de `+` em e-mail na busca de contato | `bc2cebd255` #15295 develop | M | B | **TRAZER** | P |

### C. Relatórios

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| C1 | Drawer de drilldown na barra do relatório (+ fix RTL) | `6a7ca9dd3b` #14626 v4.16.0 / `90b9dba9f9` #14919 | A | **A** | **TRAZER ADAPTADO** | G |
| C2 | Abstração rollup do report builder [2/3] | `6cbddbdb67` #13798 v4.14.0 | M | **A** | **AVALIAR DEPOIS** | G |
| C3 | Reaproveita `resolved_count` na taxa de reabertura | `ddb0535a93` #15122 v4.16.1 | M | B | **TRAZER** | P |
| C4 | Relatórios de atribuição por agente / matriz autor→destino | — (nosso: `4dd480a060`, `def522d5ba`) | — | — | **JÁ TEMOS (superior)** | — |
| C5 | Signals + heatmaps nos relatórios | — (nosso: `c669743e73`, `1c0da4275b`) | — | — | **JÁ TEMOS (não existe upstream)** | — |

### D. Campanhas

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| D1 | Variáveis Liquid em campanha WhatsApp (`{{contact.name}}` etc.) | `f8f0caf443` #13649 v4.14.0 | **A** | B | **TRAZER ADAPTADO** | P |
| D2 | Status `processing` + `with_lock` contra disparo duplicado de campanha one-off | `f27bbef73b` #14592 v4.14.2 | M | B | **JÁ TEMOS (WhatsApp) / TRAZER ADAPTADO (SMS)** | P |
| D3 | Automação não envia fora da janela de resposta | `166a41c31c` #15113 v4.16.2 | A | M | *(W5 — canal WhatsApp)* | — |

### E. Portal / Help Center

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| E1 | Página pública de resultados de busca do portal | `ecd9c26c8c` #11086 v4.14.2 | **A** | M | **TRAZER** | M |
| E2 | Edições em rascunho de artigo já publicado (staged edits) | `0fccb7dacd` #14842 v4.16.0 | **A** | M | **TRAZER** | M |
| E3 | Título/nome/header do portal por locale + conteúdo popular por locale | `64c5aeebee` #14642 v4.14.2 / `331875cdaa` #14939 v4.16.0 | **A** | M | **TRAZER** | M |
| E4 | Layout "documentation" + seletor de layout | `64585faff0` #14403 / `6560dbb68d` #14491 v4.14.1 (+ `f9cc702030`) | M | **A** | **TRAZER ADAPTADO** | G |
| E5 | Busca nas telas admin do Help Center | `32b63ad0c0` #14772 v4.16.0 | M | B | **TRAZER** | P |
| E6 | Reordenar artigos por drag entre páginas | `34d8741b9b` #14910 v4.16.0 | M | M | **TRAZER** | M |
| E7 | Pacote do editor de artigo: tabelas, slash menu, embeds de URL, GuideJar, resize de imagem, resize do editor | `edd0fc98db` #13974 · `5eee331da3` #14035 · `8cc36e1938` #14284 · `42441dbd28` #13944 · `bca95efb82` #14293 · `b5264a2560` #13916 — v4.13.0/v4.14.0 | M | M | **TRAZER** | M |
| E8 | Ações em lote de artigos + troca de categoria em lote | `2ada713f29` #14137 / `b33eecaff7` #14443 v4.14.1 | M | M | **TRAZER** | M |
| E9 | Emoji/ícone para categorias | `1713cabdf2` #14702 v4.15.0 | B | B | TRAZER | P |
| E10 | Tradução de artigo via LLM (EE) | `751c28d94d` #14136 v4.14.0 | M | M | AVALIAR DEPOIS | M |
| E11 | Provedores de analytics no Help Center | `6347ad1926` #15124 develop | M | B | AVALIAR DEPOIS | P |
| E12 | Hardening: autor cross-account, escape de markdown, href inseguro, cor do portal, `lang` BCP 47, 500 em `portals#create`, 500 com `blob_id` inteiro | `1b487f49d8` · `651db39765` · `2192af80f4` · `940428c10e` · `0d59fb4459` v4.14.2 · `dda25c0b51` v4.15.0 · `5f6bd951b9` · `b0aa844a32` | A | B | **TRAZER** *(segurança)* | P |
| E13 | Central de Ajuda embutida em iframe no dashboard | — (nosso: `74bce592fe`) | — | — | **JÁ TEMOS (não existe upstream)** | — |

### F. Widget de chat

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| F1 | Validação do `identifier_hash` no update de contato | `c8bfbadae2` #14884 v4.16.0 | **A** | B | **TRAZER (obrigatório)** | P |
| F2 | Rack-attack consolidado, kill switch por endpoint, defaults sãos | `039a311327` #14376 develop | **A** | M | **TRAZER** | M |
| F3 | Rate limit na API de transcript + guard de duplo clique | `71fffdd2b9` #15085 v4.16.1 / `5733b822e3` #15095 v4.16.1 / `b7a0ec62ba` #15135 develop | A | B | **TRAZER** | P |
| F4 | Atributos custom do pre-chat form perdidos em contato existente | `6b3800e25b` #14956 v4.16.0 | M | B | **TRAZER** | P |
| F5 | Atributos/labels do SDK enfileirados até a 1ª mensagem | `b3d0af84c4` #13912 v4.13.0 | M | B | **TRAZER** | P |
| F6 | Re-fetch do status ao reconectar | `ce93ddec78` #14683 v4.15.0 | M | M | **TRAZER ADAPTADO** | P |
| F7 | Payload público de contact_inbox retornado no update | `20227403ce` #14946 v4.16.0 | M | B | TRAZER | P |
| F8 | Dark mode do `<select>` do widget | `e09496078b` #14538 v4.14.1 | B | M | **DESCARTAR** | — |

### G. Automação (`automation_rules` / macros)

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| G1 | SSRF no webhook usado por macros e automações | `c8e551820b` #14155 CW-6940 v4.14.0 | **A** | B | **TRAZER (obrigatório)** | P |
| G2 | Macros: visibilidade pública bloqueada para agentes | `00ba468486` #14349 v4.14.0 | A | B | **TRAZER** *(segurança)* | P |
| G3 | Ação explícita de "remover atribuição" em macros/automações | `aee979ee0b` #12172 v4.13.0 | M | M | **TRAZER ADAPTADO** | P |
| G4 | Opção "último agente que respondeu" no assign | `135be52431` #12326 v4.13.0 | M | M | **TRAZER ADAPTADO** | P |
| G5 | Condição de automação filtrando notas privadas | `45b6ea6b3f` #12102 v4.13.0 | M | M | **TRAZER ADAPTADO** | P |
| G6 | Variáveis de agente renderizadas em mensagem de automação | `2a30e7b082` #14338 v4.14.0 | M | B | **TRAZER** | P |
| G7 | Remoção assíncrona de associações de label | `9c1d1c4070` #13531 v4.14.0 | M | B | **TRAZER** | P |
| G8 | `time based automation` (delay de execução em regra) | `0c606babea` #15022 develop | B | **A** | **JÁ TEMOS (superior)** | — |
| G9 | Auto-link de issue do Linear a partir de nota privada | `71cc5168be` #14405 v4.14.0 | B | B | DESCARTAR | — |

### H. Configurações / Admin

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| H1 | **Segunda coluna de feature flags (`feature_flags_ext_1`)** | `873d16f54c` #14947 CW-7238 v4.16.0 | **A** | B | **TRAZER (obrigatório)** | P |
| H2 | Gestão de sessões ativas no perfil + limite de sessões concorrentes com login picker | `92a1fb8ab7` #14556 / `396631ad7d` #14621 CW-7169 v4.15.0 | A | M | **TRAZER** | M |
| H3 | Política de atribuição ignora conversas paradas (age threshold) | `df79c0bbde` #14766 v4.16.0 | **A** | M | **TRAZER** | M |
| H4 | Banners de status da plataforma (aviso de incidente) | `5325e05143` #13943 v4.14.0 | A | M | **TRAZER ADAPTADO** | M |
| H5 | Layouts de e-mail com marca por inbox | `c420edce58` #14936 v4.16.0 | M | M | **TRAZER** | M |
| H6 | Desativar 2FA com backup code | `51eb626b88` #14102 v4.14.0 | M | B | **TRAZER** | P |
| H7 | Ícone/emoji para times | `e8edc9ebf5` #14767 v4.16.0 | M | B | TRAZER | P |
| H8 | Capacity policy com limite zero + fix de bypass no time | `5fd3d5e036` #13964 / `9efd554693` #13904 v4.13.0 | M | M | **TRAZER** | P |
| H9 | IMAP: tipo de autenticação configurável, timeout + skip de e-mail problemático, não re-sincronizar conversa apagada | `202403873d` #12306 / `52da165cb7` #11981 / `ee6382109a` #14612 | M | M | **TRAZER** | M |
| H10 | Ferramenta de diagnóstico de push no super admin | `6a9c44476e` #14105 v4.14.0 | M | B | AVALIAR DEPOIS | P |
| H11 | Detecção de provedor de e-mail por MX no onboarding | `9c17a6f302` #14571 v4.14.1 | M | B | AVALIAR DEPOIS | P |
| H12 | Ordenação de seções da sidebar (pastas, times, canais, labels) | `d8a16278b9` #14609 v4.15.0 | M | **A** | **TRAZER ADAPTADO** | M |
| H13 | Migração Dyte → Cloudflare RealtimeKit | `74db16158d` #14752 v4.16.0 | B | M | **DESCARTAR** | — |
| H14 | Onboarding: UI de inboxes, geração de HC, OAuth `return_to`, enrichment context.dev, firecrawl branding, verificação de signup | `62cbeae95f` · `3d20a7b049` · `95cb3a7ad8`/`4c6a345d60`/`1f6203d558` · `e5107604a0` · `7651c18b48` · `4f94ad4a75` | B/N | M | **DESCARTAR** | — |
| H15 | Suspensão de conta (metadata, acesso a billing, ação de suporte), PIX/BRL, planos cloud | `7c1711170b` · `afa6421809` · `35fcd56ba9` · `11deffdd5d` · `9d591b8f46` · `4381be5f3e` · `cf6ee13665` · `80b132e155` | N | B | **DESCARTAR** *(cloud-only)* | — |
| H16 | Script de migração de imagens entre storage providers | `64b0ebd8dc` #9117 v4.15.0 | B | B | AVALIAR DEPOIS | P |
| H17 | Setup do Playwright + teste de login | `6aeda0ddf6` #13578 v4.14.0 | M | B | AVALIAR DEPOIS | P |

### I. API pública

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| I1 | Webhooks assinados para API Channel e AgentBot (**breaking**) | `95463230cb` #13892 v4.13.0 | **A** | M | **TRAZER** | M |
| I2 | Feature flag `api_and_webhooks` + gate no token API e nos webhooks de conta | `9c444315a6` #14972 / `522e3c4d3f` #14973 v4.16.0 | B | **A** | **TRAZER ADAPTADO** *(ou descartar o gate)* | P |
| I3 | Evento `inbox_updated` quando a inbox é desconectada | `d0ecdc14d8` #14504 v4.14.1 | **A** | B | **TRAZER** | P |
| I4 | `destroy_custom_attributes` + merge opt-in na conversa | `acae0a2acf` #15119 develop | A | B | **TRAZER** *(= A3)* | P |
| I5 | Headers `X-Chatwoot-*` estruturados de sessão mobile | `e785620921` #14762 v4.16.0 | B | B | DESCARTAR | — |
| I6 | Docs OpenAPI de inbox/anexos + payloads de webhook mais ricos | vários, v4.14.2 | B | B | TRAZER *(junto)* | P |

### J. SLA

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| J1 | **Horário comercial no cálculo de breach de SLA** | `49b0ab0e1f` #13392 v4.16.0 | **A** | M | **TRAZER (obrigatório — correção de dado)** | M |
| J2 | SLA para contatos bloqueados | `7bf76057c2` #14861 v4.16.0 | M | M | **TRAZER** | P |
| J3 | Congelar SLA miss depois da resolução | `502c45f73b` #15024 develop | M | M | **TRAZER** | P |

### K. Times e Permissões

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| K1 | APIs de custom role gated na feature `custom_roles` | `94d7ccf5e9` #15208 develop | **A** | B | **TRAZER (obrigatório)** | P |
| K2 | Sanitiza caracteres de controle em nome de time | `ce8c8e9a11` #14865 v4.16.2 | M | B | **TRAZER** | P |
| K3 | Ações de agente visíveis no edit/add de time | `2324a344dc` #14304 v4.14.0 | B | B | TRAZER | P |
| K4 | Checkbox de ação em lote não reseta na view de time | `85ddc68834` #14432 v4.14.0 | B | B | TRAZER | P |
| K5 | Permissão de export de contato | `1afcd36dee` #14601 | — | — | *(= B7)* | — |

### L. Busca

| # | Item | Origem | Valor | Risco | Recomendação | Esf. |
|---|---|---|---|---|---|---|
| L1 | Página de resultados de busca do portal | `ecd9c26c8c` #11086 | — | — | *(= E1)* | — |
| L2 | Busca nas telas admin do Help Center | `32b63ad0c0` #14772 | — | — | *(= E5)* | — |
| L3 | Busca de etiqueta no menu de contexto | `bae20ca83e` #15084 | — | — | *(= A5)* | — |
| L4 | `advanced_search` exposto no super admin self-hosted | `a585853690` #14750 v4.16.0 | B | B | AVALIAR DEPOIS | P |
| L5 | Suporte a API key do Elastic Cloud | `8fcd32f442` #15231 develop | B | B | DESCARTAR *(não usamos ES)* | — |
| L6 | Broaden search scope na geração do HC | `8670f66155` #14880 v4.16.0 | B | B | DESCARTAR | — |

---

## Detalhamento — itens de valor Alto

### H1 · Segunda coluna de feature flags — **este é o item mais urgente da auditoria**

**O que é.** `873d16f54c` reescreve `app/models/concerns/featurable.rb` para suportar N colunas
bitset em vez de uma. Adiciona a coluna `accounts.feature_flags_ext_1` (bigint) e um campo
`column:` opcional em `config/features.yml`; flags novas passam a declarar
`column: feature_flags_ext_1`. `all_feature_flags` / `selected_feature_flags` viram agregadores
sobre `FEATURE_FLAG_COLUMNS`, então as APIs de enable/disable e o super admin continuam iguais.
Ele também adiciona `validate_feature_count!`, que **levanta `ArgumentError` no carregamento da
classe** se uma coluna passar de 63 flags.

> **Consequência prática na hora de aplicar:** trazer o `featurable.rb` novo **sem antes mover 2
> flags nossas para `feature_flags_ext_1` derruba o boot da aplicação** — o nosso YAML tem 65 na
> coluna default e a validação dispara na hora. A ordem correta é: migration da coluna → editar o
> nosso `features.yml` marcando `column: feature_flags_ext_1` nas duas últimas → só então o
> `featurable.rb`. Isso é bom, aliás: transforma um bug silencioso num erro alto e imediato.
> E não deve haver dado a migrar nessas duas: como o bit nunca coube, nenhuma conta deveria ter
> essas flags gravadas — mover para `ext_1` seria ganho puro, sem risco de perder estado.
> *Confirmar antes* (não executei nada; ver "o que eu NÃO consegui apurar", item 2).

**Por que é urgente pra nós — não é preventivo, é bug vivo.**
`config/features.yml:1..245` do nosso fork tem **65 entradas** num único `bigint` com sinal, que
comporta no máximo 63 flags (flag *n* → `2^(n-1)`; a de nº 64 já seria `2^63`, fora do range de
`bigint` com sinal). As duas que estouram são as duas últimas:

| Posição | Flag | Usada em |
|---|---|---|
| 64 | `conversation_required_attributes` | `app/javascript/dashboard/featureFlags.js:46`, `components-next/ConversationWorkflow/ConversationRequiredAttributes.vue:52`, `composables/useConversationRequiredAttributes.js:32` |
| 65 | `advanced_assignment` | `app/javascript/dashboard/featureFlags.js:5`, `routes/dashboard/settings/assignmentPolicy/Index.vue:42` |

Ou seja: são features de produto referenciadas no front cujo flag **não tem bit onde morar**.
O comentário que o upstream colocou em `config/features.yml` é explícito — *"The `feature_flags`
column is FULL (63/63 slots used). Do NOT add to it."*

O workaround que adotamos (`internal_attributes`, ver memória do projeto) resolveu o sintoma
mas não a causa; com H1 a gente volta a ter flag de conta de verdade, com super admin e API.

**"Então é só apagar duas flags do YAML" — não é.** A posição do bit é derivada da **ordem** das
entradas em `config/features.yml` e está persistida em cada linha de `accounts.feature_flags`.
Remover ou reordenar qualquer entrada re-mapeia todas as flags seguintes e **troca silenciosamente
as features ligadas de todas as contas da frota**. É por isso que o upstream, ao aposentar o
`quoted_email_reply` (`ef27e571f7`), **manteve a entrada no YAML e só marcou `deprecated: true`**
(`config/features.yml`, +1 linha) em vez de deletá-la. Adicionar a coluna é a única saída segura.

**Risco de merge do código: Baixo.** 9 arquivos (`app/models/account.rb`, `featurable.rb`,
`features.yml`, 1 migration, `db/schema.rb` + 4 specs). Nosso `featurable.rb` está intocado desde a
base (`has_flags FEATURES.merge(column: 'feature_flags')`, linha 17) — é substituição limpa.
Cuidado com **conflito de timestamp de migration** — a deles é `20260706215758` e nós temos 105
migrations no período (ver [reference_migration_timestamp_colisao] e o relatório do W2).

**Risco de merge do `features.yml`: ALTO — e vale para a auditoria inteira, não só pra este item.**
Os dois lados já reaproveitaram slots de forma independente (o upstream faz isso de propósito:
ver `b4ce59eea8` "reclaim response_bot flag for custom_tools"). Comparando slot a slot o nosso
`config/features.yml` com o de `v4.16.2`, **10 slots colidem dentro da mesma coluna `feature_flags`**:

| Slot | Nosso | Upstream v4.16.2 |
|---|---|---|
| 4 | `channel_twitter` | `conversation_unread_counts` |
| 29 | `message_sequences` | `custom_tools` |
| 30 | `internal_chat` | `message_reply_to` |
| 31 | `insert_article_in_reply` | `branded_email_templates` |
| 39 | `ai_assistant_v2` | `captain_v1_action_classifier` |
| 52 | `twilio_content_templates` | `captain_document_auto_sync` |
| 57 | `quoted_email_reply` | `unread_count_for_filters` |
| 61 | `kanban_cursor_loading` | `captain_tasks` |
| 62 | `kanban_ux_v2` | `conversation_required_attributes` |
| 63 | `captain_tasks` | `advanced_assignment` |
| 64-65 | `conversation_required_attributes`, `advanced_assignment` *(fora do bigint)* | `whatsapp_manual_transfer`, `data_import` *(em `feature_flags_ext_1`)* |
| 66-68 | — | `api_and_webhooks`, `whatsapp_reconfigure`, `whatsapp_embedded_signup_inbox_creation` *(em `ext_1`)* |

Os outros 53 slots batem exatamente. Ou seja: **um `git merge` textual do `config/features.yml`
reinterpreta o inteiro `accounts.feature_flags` de toda a frota** — a conta que tinha `internal_chat`
ligado passa a ter `message_reply_to`; quem tinha `kanban_ux_v2` passa a ter
`conversation_required_attributes`; e o `channel_twitter` de todo mundo vira
`conversation_unread_counts`. Nada disso gera conflito visível no git nem erro no boot.

**Este arquivo tem que ser reconciliado à mão, com migration de dados**, em qualquer onda de merge —
não é problema exclusivo do H1. Sugestão de procedimento: (1) fotografar `accounts.feature_flags`
de cada VM antes; (2) escrever o YAML final preservando os nossos 10 slots onde estão e movendo as
features novas do upstream para `feature_flags_ext_1`; (3) migration que traduz o bitmask antigo →
novo por conta. Isso é o único jeito de nunca precisar repetir o exercício.

**Pegadinha.** A migration se chama `AddFeatureFlagsExt2ToAccounts` mas adiciona a coluna
`feature_flags_ext_1`. É inconsistência cosmética do upstream, não bug — mas confunde quem revisa.

**Recomendação: TRAZER, esforço P.** É o primeiro item da fila e destrava tudo o que depende de
flag nova (Kanban v2, Flows, Captain).

---

### J1 · SLA respeitando horário comercial

**O que é.** `49b0ab0e1f` (#13392) move o cálculo de deadline de SLA para o backend e faz o
`Sla::EvaluateAppliedSlaService` somar o threshold **apenas dentro do horário comercial da inbox**
quando a policy tem `only_during_business_hours`. Novo `enterprise/app/services/sla/business_hours_service.rb`
(108 linhas), `applied_sla.rb` passa a expor deadlines pré-computados no jbuilder, e o front
(`helper/slaHelper.js`, 150 linhas novas) só formata.

Exemplo do próprio PR: conversa criada sexta 16:30, FRT de 1h, comercial seg-sex 9-17 →
**antes** o breach era sexta 17:30; **depois** é segunda 09:30.

**Por que importa pra nós.** Hoje o nosso `enterprise/app/models/applied_sla.rb:57` já envia
`sla_only_during_business_hours` para o front, mas o cálculo continua em wall-clock — ou seja,
**a gente mostra breach de SLA que não é breach** para todo cliente que configurou horário
comercial. Isso não é falta de feature, é número errado num relatório que o cliente usa pra cobrar
o time dele.

**Risco de merge: Médio.** 16 arquivos, +1211/-92. Só 4 arquivos de SLA estão na lista de colisão
(`overlap.txt`), e nosso único serviço próprio é `enterprise/app/services/sla/evaluate_applied_sla_service.rb`
— que é exatamente o que o PR reescreve (121 linhas trocadas). Precisa revisão manual desse arquivo,
não merge automático. Os 3 `SLACardLabel.vue` também são tocados (temos redesign WhatsApp-fiel neles).

**Recomendação: TRAZER (obrigatório), esforço M.**

---

### B1 · Módulo Companies completo

**O que é.** Em v4.12.1 (nosso ponto de corte) o Companies era só backend + listagem: temos
`enterprise/app/models/company.rb`, `components-next/Companies/{CompaniesCard,CompaniesHeader,CompaniesListLayout.vue}`
e a tabela `companies` com `name/domain/description/contacts_count` (`db/schema.rb`).
A v4.14.0/v4.15.0 completou o módulo:

| Peça | Commit |
|---|---|
| Fluxo de criação (`CompanyCreateDialog.vue`) | `10597863d7` #14402 |
| Página de detalhe (`CompanyDetailView.vue`, `CompanyProfileCard.vue`, sidebar de contatos) | `fe44b07147` #14054 |
| Notas e histórico (`CompanyNotesSidebar`, `CompanyHistorySidebar`, `companies/notes_controller.rb`) | `086aa36ffe` #14401 |
| Atributos customizados (`CompanyCustomAttributes.vue` + migration `20260422133000_add_additional_attributes_to_companies`) | `086aa36ffe` |
| Seletor de empresa no contato (`CompanySelector.vue`, `Contacts::CompanyAssociationService`) | `41a3ab6dfa` #14496 |
| Última atividade da empresa | `1d2f3e86dd` #14435 |
| Sincronizar nome do contato ↔ empresa (`Companies::SyncContactNamesJob`) | `2b37fef0e0` #14759 |
| Padronizar campo `company_name` (+ migration que renomeia a condition key em `automation_rules`) | `16b8693e1b` #14099 |
| Conversas da empresa (`companies/conversations_controller.rb`) | pacote v4.14.0 |
| Job de exclusão (`Companies::DeleteJob`), policy, jbuilders | pacote v4.14.0 |

**Valor: Alto.** Nosso negócio é multi-cliente B2B — praticamente todo cliente da frota tem contatos
que pertencem a uma empresa (e várias inboxes WhatsApp por empresa). "Ver todas as conversas desta
empresa" e "notas da conta" são pedidos recorrentes que hoje não têm resposta.

**Risco de merge: Baixo — e este é o ponto.** Dos 558 arquivos em colisão, **exatamente 1** casa com
`compan*`. É quase tudo arquivo novo. É o melhor retorno por risco de toda a auditoria.

**Caveats:**
- `9d591b8f46` (#14598) habilita Companies só para planos Business do cloud — precisa **TRAZER
  ADAPTADO** essa parte (liberar para self-hosted), ou a feature entra desligada.
- Requer H1 antes se for depender de flag nova.
- A migration `20260427094500_rename_company_condition_key_in_automation_rules` mexe em
  `automation_rules` — nossa área sensível (Flows). Se a conta usa Flows e não rules, é inócua;
  se usa "modo antigo", tem que rodar.

**Recomendação: TRAZER, esforço G** (o volume é grande, mas o risco é baixo — é trabalho de porte,
não de conciliação).

---

### F1/F2/F3 · Endurecimento do widget e do rack-attack

**O que é.**
- `c8bfbadae2` (#14884) — valida `identifier_hash` no update de contato pelo widget. Sem isso, um
  visitante pode sobrescrever atributos de um contato identificado. **Segurança, não conforto.**
- `039a311327` (#14376, develop) — consolida os throttles do widget num único ponto
  (`config/initializers/rack_attack.rb`, +58/-13), com kill switch por endpoint via env
  (`.env.example` ganha 16 linhas) e defaults mais razoáveis.
- `71fffdd2b9` (#15085) + `5733b822e3` (#15095) + `b7a0ec62ba` (#15135) — rate limit na API de
  transcript, guard contra clique repetido no botão de e-mail do transcript, e validação de
  checkbox obrigatório no pre-chat form.

**Por que importa pra nós.** A frota tem widget exposto na internet em várias VMs, e o GlitchTip
já mostrou volume de erro vindo de tráfego automatizado ([reference_glitchtip_observabilidade],
[project_remediacao_bugs_frota]). O F2 em particular dá um botão de emergência por endpoint sem
precisar de deploy.

**Risco.** F1 e F3 são cirúrgicos (P). F2 toca `rack_attack.rb` inteiro — se a gente customizou
throttle nessa VM, precisa conciliar. `widget` aparece 30× na lista de colisão, mas quase tudo é
componente Vue com nosso skin, não backend.

**Recomendação: TRAZER (F1 obrigatório), esforço P/M.**

---

### G1/G2/K1 · Segurança em automações, macros e custom roles

- **`c8e551820b` (#14155, CW-6940)** — SSRF no webhook disparado por macro/automação. Nós temos
  `Flows::SafeHttpClient` próprio para os Flows, mas as `automation_rules` legadas **continuam
  rodando** nas contas em "modo antigo" (ver [reference_chatspx_automacao_modo_antigo]) — o buraco
  é real no nosso código. **Obrigatório.**
- **`00ba468486` (#14349)** — impede agente de marcar macro como pública. Escalada de privilégio
  discreta: macro pública roda para todo mundo.
- **`94d7ccf5e9` (#15208, develop)** — as APIs de custom role não checavam a feature `custom_roles`.
  Em self-hosted isso significa endpoint de RBAC acessível sem a feature. **Obrigatório.**

Os três são P e nenhum toca área sensível nossa. Devem entrar juntos, cedo.

---

### I1/I2/I3 · API pública — um item obrigatório, um perigoso e um muito útil

**I1 — Webhooks assinados (`95463230cb`, #13892).** Chatwoot passa a gerar `secret` por AgentBot e
por `Channel::Api`, e a assinar os webhooks. 33 arquivos, 3 migrations (incl. backfill dos secrets
existentes). **É breaking change documentada na release note da v4.13.0**: quem consome nosso
webhook precisa passar a verificar a assinatura. Valor alto (hoje qualquer um que descubra a URL
posta evento falso), risco médio (mexe em `agent_bots_controller`, `inboxes_controller`,
`webhook_listener` — todos na lista de colisão). **TRAZER, M**, com aviso prévio a quem integra.

**I2 — `api_and_webhooks` (`9c444315a6` + `522e3c4d3f`). Cuidado.** O upstream criou uma feature
flag reconciliada a partir do plano de billing e **passou a exigir ela** para (a) usar token de
API pessoal e (b) criar/disparar webhooks de conta (`app/listeners/webhook_listener.rb`,
`spec/controllers/api/base_controller_spec.rb` ganha 61 linhas de teste de bloqueio). É lógica de
monetização do cloud. Se isso vier junto num merge sem a flag ligada por default no self-hosted,
**derruba integração de cliente sem aviso** — token de API para de funcionar. Recomendação:
**TRAZER ADAPTADO** (flag `enabled: true` no nosso `features.yml`) ou simplesmente não trazer o
gate; mas é preciso saber que ele existe, porque vem de carona em qualquer merge dessa faixa.

**I3 — `inbox_updated` quando a inbox desconecta (`d0ecdc14d8`, #14504).** Pequeno (P) e diretamente
útil: hoje a gente descobre que um WhatsApp caiu pelo `health_service` e por reclamação do cliente.
Um webhook nativo de "inbox desconectada" alimenta alerta no Almirante/GlitchTip sem polling.
**TRAZER, P.**

---

### A3/I4 · Merge opt-in de `custom_attributes` da conversa (`acae0a2acf`, develop)

Hoje `PATCH /conversations/:id/custom_attributes` **substitui** o hash inteiro. Quem escreve
atributo de conversa em paralelo (nossos Flows escrevem; o Captain escreve) sobrescreve o que o
outro acabou de gravar. O PR adiciona um `ConversationCustomAttributesConcern` com merge opt-in e
um endpoint `destroy_custom_attributes` para apagar chave específica. 10 arquivos, quase tudo
swagger e spec. **Valor Alto para os Flows, risco Baixo, esforço P.** Deveria entrar na primeira leva.

---

### H3 · Política de atribuição ignora conversas paradas (`df79c0bbde`, #14766)

Adiciona um limiar de idade na assignment policy: conversa parada há mais de X não volta para a
roda de auto-assign. **Muito relevante no WhatsApp**, onde conversa fica "aberta" por dias porque o
cliente sumiu, e a auto-atribuição fica reciclando lixo e queimando a capacidade dos agentes.
15 arquivos, +177. Colide com a área de assignment policy (`app/services/...assignment...`,
`agent_capacity_policy.rb`) — atenção porque também temos `advanced_assignment` (a flag que está
fora do bitmask, ver H1). **TRAZER, M.**

---

### H2 · Sessões ativas e limite de sessões concorrentes (CW-7169)

`92a1fb8ab7` (#14556, 25 arq, +754) adiciona "Sessões ativas" no perfil — lista dispositivos,
permite revogar. `396631ad7d` (#14621, 9 arq, +476) impõe limite de sessões simultâneas com um
"login picker" que faz o usuário escolher qual sessão derrubar.

**Valor Alto no nosso contexto multi-cliente**: é o tipo de controle que aparece em checklist de
segurança de cliente corporativo, e resolve o caso do agente que compartilha login. Temos MFA
(`profile/MfaSettings*.vue`) mas não temos gestão de sessão. Risco Médio (mexe em autenticação —
testar com nosso SAML/`account_saml_settings.rb`). **TRAZER, M.**

---

### E1/E2/E3 · Help Center — os três que valem a pena

**E1 — Busca pública no portal (`ecd9c26c8c`, #11086).** Cria a rota e as views de resultado de
busca do portal (`public/api/v1/portals/search_controller.rb`, `search/index.html.erb`,
`_search_handler.html.erb`). **Isso é diretamente relevante pra nós**: a Central de Ajuda embutida
(`74bce592fe`) coloca o portal dentro do dashboard via iframe — e hoje quem está no iframe não tem
página de busca, só o autocomplete. **TRAZER, M.**

**E2 — Staged edits (`0fccb7dacd`, #14842, 21 arq, +1280).** Permite editar um artigo já publicado
sem que a alteração vá ao ar até aprovar. Hoje qualquer salvamento num artigo publicado é
publicação imediata — risco operacional real para quem mantém base pública. **TRAZER, M.**

**E3 — Portal por locale (`64c5aeebee` #14642 + `331875cdaa` #14939).** Título, nome e header do
portal por idioma, e "conteúdo popular" por locale. Nosso i18n é pt-BR-first
([feedback_i18n_priority]) e hoje o portal carrega o nome em idioma único. **TRAZER, M.**

**E4 — Layout "documentation" (`64585faff0` #14403 + `6560dbb68d` #14491): TRAZER ADAPTADO, G.**
São 51 arquivos criando um segundo layout público inteiro (`documentation_layout/*`) mais
variantes `+documentation.erb` de todas as views, e um seletor no dashboard. O problema é onde ele
pousa: `app/controllers/public/api/v1/portals/base_controller.rb:53-56` é **exatamente** o arquivo
onde implementamos o `embed=true`, e a lógica que ele conflita com (`@is_plain_layout_enabled`) é a
mesma linha. Também colide `app/views/layouts/portal.html.erb`, `HelpCenterLayout.vue`,
`ArticleEditor.vue`, `PortalSwitcher.vue`. Não dá pra fazer merge — tem que reimplementar a
resolução de layout como uma cadeia de três (`plain` / `documentation` / `embed`).

---

### D1 · Variáveis Liquid em campanha WhatsApp (`f8f0caf443`, #13649)

`Whatsapp::LiquidTemplateProcessorService` (66 linhas) renderiza `{{contact.name}}`,
`{{agent.name}}`, `{{inbox.name}}`, `{{account.name}}` dentro dos `processed_params` do template,
com `json_escape` e fallback silencioso em erro de Liquid.

**Nota sobre D2 (mesma família).** O `f27bbef73b` não é só cosmético: ele adiciona
`campaign_status: processing` e um `mark_processing!` com `with_lock`, com o comentário
*"Multiple scheduler jobs can pick the same active campaign; lock before flipping status to avoid
duplicate sends."* — ou seja, **corrige disparo duplicado por corrida entre schedulers**.
No caminho WhatsApp nós estamos imunes: `app/models/campaign.rb:80-92` deixa `execute_campaign`
como no-op para WhatsApp (log `"WhatsApp one-off nativo desativado"`) e o disparo real passa pelo
nosso `Campaigns::Whatsapp::DispatchSchedulerJob` com `dispatch_status` (`running`/`paused`) —
guarda própria e com pacing, que o upstream não tem. **Mas o `trigger!` nativo continua com o
`return if completed?` desprotegido** (`app/models/campaign.rb:64-68`) para inbox `Sms` e
`Twilio SMS`. Se alguma conta da frota usa esses canais, a corrida existe. **TRAZER ADAPTADO** só
o `mark_processing!`, **P**.

**Comparação com o nosso (D1).** Nossa campanha WhatsApp (`app/services/campaigns/whatsapp/`) é mais
completa no que ela faz: `ListLoaderService` materializa a lista enviada em `campaign_recipients`
com normalização de telefone BR (`Contacts::BrazilPhoneNormalizer`), dedup idempotente por número,
`template_params` por destinatário e default esperto (`{"1" => nome}`); e o
`RecipientDispatchService` já monta `processed_params` (linhas 97-103). **Nós ganhamos no fluxo
CSV/lista.** Mas o nosso caminho exige que a variável venha na planilha — não dá pra dizer
"use o nome do contato que já está no CRM". O Liquid do upstream cobre exatamente esse buraco e são
4 arquivos. **TRAZER ADAPTADO** (plugar o processor no nosso `RecipientDispatchService`), **P**.

---

## Onde o upstream fez o que a Simplex já tinha feito — e quem ganha

### 1. Flows × `time based automation` — **nós, com folga**

Upstream (`0c606babea`, #15022, develop, 40 arquivos, +2429) adiciona `execution_delay` em
`automation_rules` + tabela `automation_rule_pending_executions` + dois jobs (`TriggerPendingExecutionsJob`,
`ProcessPendingExecutionJob`). É "espere N minutos antes de rodar a regra".

Nosso motor Flows já tem, em `app/services/flows/`:

| Capacidade | Arquivo |
|---|---|
| Nó `wait` com prazo | `runner_service.rb` (`wait_until`) |
| `wait` que pula para a próxima abertura comercial | `business_hours.rb` |
| Nó `wait_for_reply` — suspende esperando o contato responder, com timeout e ramificação | `reply_wait.rb`, `reply_resume_service.rb` |
| Retomada por mensagem e por timeout | `resume_service.rb` |
| Snooze | `snooze_action.rb` |
| Simulação/dry-run do fluxo | `simulation_service.rb`, `simulation_walk.rb` |

O upstream entrega um delay linear numa regra; nós entregamos um grafo com espera condicional,
ramificação por resposta e respeito a horário comercial. **JÁ TEMOS (superior) — DESCARTAR.**
Ressalva honesta: para conta em "modo antigo" (`automation_rules` ativas, Flows desligado —
[reference_chatspx_automacao_modo_antigo]), o delay do upstream seria a única opção. Se a estratégia
é migrar todo mundo pra Flows, não vale o custo.

### 2. Relatórios de atribuição — o upstream não tem

Nosso `AssignmentReports.vue` + backend (`4dd480a060` F2, `def522d5ba` filtro por time/inbox e
matriz autor→destino) não têm equivalente upstream. O que o upstream fez em relatórios no período
foi **outra coisa**: drilldown genérico por barra do gráfico (C1) e refactor do report builder (C2).
São **complementares** — o drilldown deles poderia servir os nossos relatórios de atribuição.
Nada aqui é "JÁ TEMOS" no sentido de descartar; é "temos algo que eles não têm, e o que eles fizeram
serve pra melhorar o nosso".

### 3. Kanban e chat interno — o upstream não tem

`git log --grep=kanban -i` no intervalo: **zero resultados**. Chat interno idem
(`internal_channel.rb`, `internal_message.rb` são só nossos). Nada a comparar; só registrar que
essas duas áreas **não recebem conflito nenhum** do upstream, o que é uma boa notícia pro W3.

### 4. Central de Ajuda embutida × layout "documentation" — features diferentes, mesmo arquivo

O nosso (`74bce592fe`) é **embed no dashboard**: `embed=true` libera framing mantendo o layout
completo com o widget de suporte, mais `HelpCenterEmbedPage.vue` e entrada na Sidebar. O deles é
**um layout público alternativo** (estilo docs, com sidebar de navegação e breadcrumb). Não são
concorrentes — são coisas diferentes que **brigam pela mesma linha de código**
(`portals/base_controller.rb:53-56`). Ver E4.

### 5. Takeover de conversa — complementares

Nosso (`ed60e4745f` Fase 3.7 + `a69bb9ab81`) é **aprovação agente→agente**: banner na conversa,
lista de "Pedidos", pluralização correta. O do upstream (`226af4959e`, develop) é **bot→humano**:
quando a conversa está `pending` e o assignee é `AgentBot`, mostra banner "assumir do
`{botAssigneeName}`" que reabre + auto-atribui. O deles é 6 arquivos e resolve um caso que o nosso
não cobre — e que **é o nosso caso de uso principal** (Captain atendendo, agente precisa assumir).
**TRAZER ADAPTADO, P.**

### 6. Campanha WhatsApp — nós ganhamos no fluxo, eles ganham na interpolação

Ver D1. Nosso `ListLoaderService`/`RecipientDispatchService` > o `oneoff_campaign_service` deles;
o `LiquidTemplateProcessorService` deles preenche um buraco nosso.

---

## Riscos e pegadinhas

0. **`config/features.yml` não pode ser mergeado por texto — vale para TODAS as ondas.**
   10 slots de bit colidem entre o nosso YAML e o de `v4.16.2` (tabela completa em H1). Um merge
   textual reinterpreta `accounts.feature_flags` de toda a frota: `internal_chat` vira
   `message_reply_to`, `kanban_ux_v2` vira `conversation_required_attributes`, `channel_twitter` vira
   `conversation_unread_counts` — **sem conflito no git e sem erro no boot**. Reconciliação manual +
   migration de dados, sempre. Este é o risco número um da auditoria inteira, acima de qualquer
   feature individual.

1. **`api_and_webhooks` derruba token de API.** Ver I2. É o item que pode causar
   incidente em cliente por merge distraído. Se qualquer coisa da faixa v4.16.0 entrar, conferir
   `app/models/account.rb` e `app/listeners/webhook_listener.rb`.

2. **Unread counts: 2 reverts, não é feature estável.** Cronologia real:
   `3fae800936`/`27f2c2b392`/`f33e469e9a` (20/05, base) → `88e2661ca6` remove a flag (02/06) →
   `87df43bdd0` **reverte e restaura a flag no mesmo dia** → `4d3196b02f` (11/06) →
   `fe6368b42e` sidebar por filtro (16/06) → `f66b551c7d` **reverte a sidebar em 17/06** (e a
   release note da v4.15.1 admite: *"due to performance related issues"*) → `66cfb26c77` (08/07)
   reintroduz atrás de `unread_count_for_filters`, marcada `chatwoot_internal: true`.
   Hoje são 4538 linhas atrás de duas flags que nem o Chatwoot liga em produção pública. Somando os
   commits dá >7000 linhas em ~130 arquivos de conversa que estão na nossa lista de colisão.
   **Não perseguir. AVALIAR DEPOIS** — e se um dia trouxer, trazer a versão final (`66cfb26c77`),
   nunca a série inteira.

3. **Rollup do report builder apaga arquivo que nós editamos.** `6cbddbdb67` **deleta**
   `timeseries/average_report_builder.rb` e `timeseries/count_report_builder.rb` e reescreve
   `base_summary_builder.rb` (+59/-...), criando `services/reports/{data_source,raw_data_source,report_metric_registry}.rb`.
   Todos esses estão em `overlap.txt` — nós mexemos neles em `c669743e73` (signals backend) e
   `1c0da4275b` (signals no summary v2). Merge automático aqui **apaga os signals silenciosamente**
   (deleção de arquivo não gera conflito visível se a nossa mudança estiver noutro arquivo do mesmo
   pacote). Se for trazer C1 (drilldown), decidir antes se C2 vem junto — o drilldown foi construído
   em cima da abstração nova.

4. **`portals/base_controller.rb` é ponto único de falha do Help Center.** Toda a família E depende
   dele. Trazer E4 antes de E1/E2/E3 é a ordem errada — E1/E2/E3 são independentes do layout e
   entregam valor sem tocar na resolução de layout.

5. **Migrations no meio de features de produto.** Vários itens aqui carregam migration:
   H1 (`20260706215758`), B1 (`20260422133000`, `20260427094500`), I1 (`20260324070820`,
   `20260324070828`, backfill), G8 (4 migrations). Com 105 migrations nossas no período, colisão de
   timestamp é provável — é o `DuplicateMigrationVersionError` que já travou a frota antes
   ([reference_migration_timestamp_colisao]). **Isso é escopo do W2**; aqui só sinalizo quais
   itens de produto trazem migration junto.

6. **`Sidebar.vue` é campo minado.** Aparece em `74bce592fe` (nosso, +117/-51 pro embed do HC), em
   `fe6368b42e` (unread por filtro), `4d3196b02f`, `11c65f3b9a` (Intercom), `d8a16278b9`
   (ordenação de seções) e `b96bf41234` (aba Participating). Qualquer um desses itens toca o mesmo
   arquivo. Sugestão pro W3: tratar `Sidebar.vue` como merge manual único, não por PR.

7. **Itens marcados "cloud-only" não são inofensivos.** H15 (suspensão de conta, PIX, gating por
   plano) vem embutido em commits que também mexem em `app/models/account.rb` e
   `enterprise/app/models/enterprise/account.rb`. Descartar a feature ≠ descartar o commit inteiro.

8. **Dyte → Cloudflare RealtimeKit (`74db16158d`) é breaking.** A release note da v4.16.0 é
   explícita: quem usa a integração de vídeo tem que **deletar e reconfigurar**. Se alguma conta da
   frota usa Dyte, isso quebra na hora do merge. Vale um `SELECT` nas `integrations_hooks` antes.

---

## O que eu NÃO consegui apurar

1. **Números de PR × commits de merge.** Cruzei release notes com `git log`, mas não abri os 555
   commits um a um. Para os itens de valor Alto eu li `git show`/`--stat`; para os de valor Baixo
   confiei na mensagem de commit. Se algum item Baixo/Descartar for promovido, reabrir o diff.

2. **Se `advanced_assignment` e `conversation_required_attributes` já estão quebrando em runtime.**
   A aritmética do bitmask é clara (posições 64 e 65 em `bigint` com sinal), e o próprio upstream
   documenta o teto de 63 — mas **não executei nada** (auditoria read-only, sem `rails runner`).
   Confirmar com `Account.first.enable_features('advanced_assignment')` num console de teste antes
   de tratar como incidente. O risco de estar errado é baixo; o de ignorar é alto.

3. **Quais contas da frota usam `automation_rules` "modo antigo" vs Flows.** Isso muda a
   recomendação de G3/G4/G5/G8 (se ninguém usa rules, portar as condições pro Flows vira trabalho
   perdido). Precisa de query no banco de cada VM — fora do escopo read-only deste worker.

4. **Se alguma conta usa a integração Dyte.** Ver risco 8.

5. **Reports: quanto exatamente dos nossos "signals" o rollup do upstream destruiria.** Precisaria
   de um diff semântico entre `c669743e73`/`1c0da4275b` e `6cbddbdb67` — é trabalho de W3, e eu
   parei na constatação de que os arquivos se cruzam.

6. **Volume de i18n.** Ignorei sync de i18n por instrução, mas registro que praticamente toda
   feature de UI listada traz ~70 arquivos de locale junto. Para o planejamento de esforço isso é
   ruído mecânico; para o mapa de conflitos do W3 pode não ser (nosso pt_BR é customizado —
   `app/javascript/dashboard/i18n/locale/pt_BR/report.json` já está em `overlap.txt`).

7. **Captain/IA e WhatsApp.** Deliberadamente fora (W5). Aparecem aqui só quando um commit de
   produto arrasta o outro — ex.: D3 (`166a41c31c`, janela de resposta) e `59eac9a7c5`
   (token de gestão de template WhatsApp Cloud) estão listados como ponteiro, não auditados.

---

## Ordem sugerida de execução (se o coordenador quiser uma fila)

**Onda 0 — obrigatórios, esforço P, risco baixo:** H1 (feature flags), G1 (SSRF), K1 (custom roles),
F1 (identifier_hash), G2 (macro pública), A3/I4 (merge de custom_attributes), B3 (BOM CSV),
E12 (hardening do portal).

**Onda 1 — correção de dado e perf:** J1 (SLA business hours), A1 + A2 (queries), C3 (reopen rate),
J2/J3.

**Onda 2 — produto de retorno alto e risco baixo:** B1 (Companies), I3 (`inbox_updated`),
D1 (Liquid), A4/A5/A6/A9/A16, H3 (assignment stale), A11 (takeover do bot).

**Onda 3 — produto com adaptação:** E1/E2/E3 (Help Center sem tocar layout), H2 (sessões),
I1 (webhooks assinados), H4 (banners), C1 (drilldown).

**Onda 4 — decidir depois:** E4 (layout documentation), C2 (rollup), A12 (unread counts).
