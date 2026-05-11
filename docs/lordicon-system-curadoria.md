# Curadoria Lordicon System — Sidebar ChatSPX

> **Status:** 🟡 Aguardando preenchimento do Walisson
> **Objetivo:** para cada conceito do sidebar, escolher o par `System Regular` (outline, idle) + `System Solid` (filled, active) no Lordicon PRO.
>
> **Como preencher:**
> 1. Entrar em https://lordicon.com/ logado na conta PRO
> 2. Filtrar: **Family = System**, **Style = Regular** → copiar URL CDN `.json` na coluna REGULAR
> 3. Voltar, filtrar: **Family = System**, **Style = Solid** → copiar URL CDN `.json` na coluna SOLID
> 4. Se não achar em System, marcar `WIRED-FALLBACK` (mantém ícone atual, só muda cor quando ativo)

---

## 🔍 Termos de busca recomendados (search hints)

Para cada conceito, testa esses termos no campo de busca do Lordicon (com filtro System ativo):

### 🎯 Rail principal — 11 conceitos

| # | Conceito | Uso | Search hints | System Regular (URL `.json`) | System Solid (URL `.json`) |
|---|---|---|---|---|---|
| 1 | **mailbox** | Inbox + Canais (reuse) | `mailbox`, `mail`, `inbox`, `envelope` | | |
| 2 | **chatMessage** | Conversas | `chat`, `message`, `comment`, `speech bubble` | | |
| 3 | **kanban** | Kanban | `kanban`, `grid`, `layout`, `columns`, `dashboard` | | |
| 4 | **captain** | Captain AI | `robot`, `bot`, `ai`, `brain`, `sparkles`, `chip` | | |
| 5 | **contacts** | Contatos | `contact`, `user card`, `address book`, `person` | | |
| 6 | **companies** | Empresas | `building`, `office`, `company`, `skyscraper` | | |
| 7 | **reports** | Relatórios | `chart`, `bar chart`, `analytics`, `graph`, `report` | | |
| 8 | **live** | Ao Vivo | `activity`, `pulse`, `radio`, `broadcast`, `live` | | |
| 9 | **megaphone** | Campanhas | `megaphone`, `announcement`, `speaker`, `bullhorn` | | |
| 10 | **helpCenter** | Central Ajuda + Docs (reuse) | `book`, `library`, `help book`, `guide`, `manual` | | |
| 11 | **settings** | Configurações + Agent Assignment (reuse) | `settings`, `gear`, `cog`, `sliders`, `preferences` | | |

### 🔸 Sub-menus — 6 conceitos

| # | Conceito | Uso | Search hints | System Regular | System Solid |
|---|---|---|---|---|---|
| 12 | **unattended** | Não atendidas | `clock`, `hourglass`, `timer`, `pending`, `waiting` | | |
| 13 | **filter** | Status | `filter`, `funnel` | | |
| 14 | **folder** | Pastas | `folder` | | |
| 15 | **team** | Times + Segmentos + Settings Teams (reuse) | `users`, `group`, `team`, `people`, `community` | | |
| 16 | **label** | Etiquetas + Tagged With + Settings Labels (reuse) | `tag`, `label`, `bookmark`, `price tag` | | |
| 17 | **search** | Botão Busca | `search`, `magnifier`, `find`, `magnifying glass` | | |

### ⚙️ Settings — 15 conceitos

| # | Conceito | Uso | Search hints | System Regular | System Solid |
|---|---|---|---|---|---|
| 18 | **account** | Conta/Geral | `briefcase`, `user circle`, `id card`, `badge` | | |
| 19 | **agent** | Agentes + Editar Perfil (reuse) | `user`, `user edit`, `user pen`, `avatar`, `profile` | | |
| 20 | **waha** | WAHA Connections | — mantém SVG custom WhatsApp (não é Lordicon) | — | — |
| 21 | **customAttrs** | Custom Attributes | `code`, `curly braces`, `variable`, `brackets` | | |
| 22 | **automation** | Automation | `refresh`, `repeat`, `rotate`, `automation`, `cycle` | | |
| 23 | **bots** | Agent Bots | `robot`, `bot`, `cpu`, `machine` | | |
| 24 | **macros** | Macros | `blocks`, `puzzle`, `cube`, `stack`, `extension` | | |
| 25 | **cannedResp** | Canned Responses | `quote`, `message quote`, `speech bubble`, `template` | | |
| 26 | **integration** | Integrations | `integration`, `plugin`, `puzzle`, `connect`, `link` | | |
| 27 | **audit** | Audit Logs | `file check`, `scroll`, `clipboard check`, `audit` | | |
| 28 | **customRoles** | Custom Roles + Security (reuse) | `shield`, `shield check`, `lock`, `key` | | |
| 29 | **sla** | SLA | `alarm clock`, `timer alert`, `clock alert`, `stopwatch` | | |
| 30 | **workflow** | Conversation Workflow | `workflow`, `flow chart`, `git branch`, `tree`, `route` | | |
| 31 | **billing** | Billing | `credit card`, `wallet`, `payment`, `invoice`, `dollar` | | |

### 👤 Profile Menu — 6 conceitos novos

| # | Conceito | Uso | Search hints | System Regular | System Solid |
|---|---|---|---|---|---|
| 32 | **support** | Contact Support | `life buoy`, `support`, `help circle`, `headset`, `headphones` | | |
| 33 | **keyboard** | Keyboard Shortcuts | `keyboard` | | |
| 34 | **theme** | Appearance (palette) | `palette`, `brush`, `paint`, `color`, `swatches` | | |
| 35 | **changelog** | Changelog | `scroll`, `newspaper`, `document text`, `news`, `article` | | |
| 36 | **superAdmin** | Super Admin Console | `crown`, `castle`, `shield check`, `admin`, `key master` | | |
| 37 | **logout** | Logout | `power`, `log out`, `exit`, `sign out`, `door` | | |

### ➡️ Chevron — 1 conceito

| # | Conceito | Uso | Search hints | System Regular | System Solid |
|---|---|---|---|---|---|
| 38 | **chevronDown** | Seta expansão | `chevron down`, `arrow down`, `caret down` | (não precisa solid — roda 180°) | — |

---

## 📋 Tabela de reusos (economia)

Vários slots reutilizam o mesmo ícone. Se você curar estes 28 conceitos principais, cobre os 50 slots da UI:

| Principal | Reutilizado em |
|---|---|
| `mailbox` (1) | Inbox, Canais sub-conv, Settings Inboxes |
| `team` (15) | Times conv, Segmentos contatos, Settings Teams |
| `label` (16) | Etiquetas conv, Tagged With contatos, Settings Labels |
| `settings` (11) | Configurações rail, Agent Assignment |
| `customRoles` (28) | Custom Roles, Settings Security |
| `agent` (19) | Settings Agents, Edit Profile |
| `helpCenter` (10) | Central de Ajuda rail, Docs profile |

---

## ✏️ Formato esperado no preenchimento

Para cada linha, cola as URLs **completas** no formato:

```
System Regular: https://cdn.lordicon.com/abcdefgh.json
System Solid:   https://cdn.lordicon.com/ijklmnop.json
```

Ou, se não encontrar em System:

```
WIRED-FALLBACK (mantém ícone atual: https://cdn.lordicon.com/xxxxxxx.json)
```

---

## 🚫 Não precisa curar

- **WAHA** (#20) — é SVG custom (logo WhatsApp), não Lordicon
- **devices** — era pro "Auto Mode" que removemos
- **chevronUp** — usamos só chevronDown com `rotate-180` por CSS

---

## ⚙️ O que acontece depois que você entregar

1. O @dev atualiza `app/javascript/dashboard/constants/lordicons.js` para o novo formato:
   ```js
   export const LORDICON = {
     mailbox: { idle: 'cdn...', active: 'cdn-solid...' },
     chatMessage: { idle: '...', active: '...' },
     // Wired fallback (só idle, active=null):
     captain: { idle: 'cdn...wired...', active: null },
     waha: { idle: 'cdn...wired...', active: null },
     // ...
   }
   ```
2. `LordIconIcon.vue` ganha prop `srcActive` e troca o `src` quando `active=true`
3. Helper `lordIcon(key)` no `Sidebar.vue` passa `{idle, active}` automaticamente
4. Rebuild + restart + QA Playwright confirma:
   - Idle: outline System em `#aebac1` (dark) / `#54656f` (light)
   - Active: solid System em `#2dc46f` (novo verde — Decisão 1A)
   - Hover anima 1x (outline)
   - Wired-fallback: não muda forma no active, só muda cor

---

## ⏱️ Tempo estimado

- **Sua curadoria:** 1h30-2h (38 conceitos × ~2-3min no Lordicon PRO)
- **Dev implementação:** ~1h
- **QA final:** ~15min

**Total:** ~3h distribuídas (tua parte dá pra fazer em lotes enquanto toma um café ☕)

---

**Quando terminar, me devolve este arquivo preenchido ou cola as URLs aqui no chat que eu organizo.**
