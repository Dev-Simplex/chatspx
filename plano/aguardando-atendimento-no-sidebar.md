# Plano — "Aguardando atendimento": da aba para o sidebar

> **Status: PLANEJADO** (2026-06-20). Aterrado no código (2 estudos). Working tree only.
> Vale **só no modo IA ligado** (`reply_assignment_gate` ON); modo Clássico intacto.

## Objetivo
Tirar a aba "Aguardando atendimento" do tab-bar de conversas (que fica apertado com Minhas/Aguardando/IA/Todas) e colocá-la como **item no sidebar**, logo **abaixo do ícone de notificações**, com **badge destacado igual ao de notificação** e ícone animado (hover). As outras abas (Minhas/IA/Todas) ficam onde estão.

## Como o terreno ajuda (estudos)
- O sidebar é **1 array** (`menuItems` em `components-next/sidebar/Sidebar.vue`); inserir item é trivial e condicional por flag (padrão já usado no arquivo).
- O **badge vermelho é genérico** (`SidebarGroup` renderiza a partir de `getterKeys.count`) — mesmo do item de notificações (`Inbox`).
- O contador "aguardando" (`conversationStats.unAssignedCount`) **já é carregado no sidebar** no `onMounted`.
- O ícone que você colou (`kphwxuxr.json`) **já está mapeado no projeto** como a key `team` em `constants/lordicons.js` (e o projeto já usa Lordicon no sidebar inteiro).

## Decisões a confirmar (2)
1. **Ícone.** O `kphwxuxr` que você colou já é o ícone do item **"Times"** do sidebar — usar o mesmo pode confundir. Opções:
   - (a) usar `kphwxuxr` mesmo (consistente com o sidebar atual, via CDN já presente);
   - (b) escolher um ícone de "espera" (relógio/ampulheta) pra distinguir de Times;
   - (c) self-hosted via `LottieIcon` (baixa o `.json`, sem CDN) — mas seria o único self-hosted num sidebar todo em CDN (inconsistente).
   **Recomendo (b)** — ícone próprio de espera, via o helper `lordIcon()` existente.
2. **Contador no badge.** Mostrar o nº de "aguardando" do(s) **time(s) do usuário** (igual ao que ele vê ao clicar) ou **da conta inteira**? *Recomendo: por time* (consistente com a F2; o badge bate com o que ele acessa). Exige garantir o escopo por time também no endpoint `/meta` (pequeno ajuste no finder, se ainda não estiver).

## Arquivos a tocar
| # | Arquivo | Mudança |
|---|---|---|
| 1 | `components-next/sidebar/Sidebar.vue` | importar `useReplyAssignmentGate`; inserir item condicional logo após `Inbox` (linha ~184): `icon` (lordIcon), `to: accountScopedRoute('conversation_unattended', {}, { assignee_type:'unassigned' })`, `activeOn`, `getterKeys: { count: 'conversationStats/getUnAssignedCount' }`. Adicionar `useEmitter('fetch_conversation_stats', () => store.dispatch('conversationStats/get', {}))` pra manter o badge atualizado por websocket mesmo fora da lista. |
| 2 | `store/modules/conversationStats.js` | novo getter numérico `getUnAssignedCount` → `$state.unAssignedCount` (o `getStats` devolve objeto e vira `NaN` no badge). |
| 3 | `components/ChatList.vue` (~linha 326) | no modo gate, **remover a aba** unassigned do tab-bar: `return (stats.unAssignedCount ?? 0) > 0;` → `return false;`. O `return true` final preserva o modo Clássico. Limpar o bloco `isAwaitingTab` (vira morto). |
| 4 | i18n `pt_BR`/`en` (sidebar) | label "Aguardando atendimento" / "Awaiting assignment" (key `SIDEBAR.*`). |
| 5 | *(se decisão 1c)* `assets/lottie/` + LottieIcon | baixar `kphwxuxr.json` e usar `<LottieIcon mode="hover">`. |
| 6 | *(se decisão 2 = por time)* `finders/conversation_finder.rb` | garantir escopo por time no count do `/meta` p/ não-admin. |

## Testes
- **Vitest:** getter `getUnAssignedCount`; `assigneeTabItems` não inclui unassigned no gate ON e inclui "Não atribuídas" no Clássico.
- **Playwright (conta 3, light+dark):** item aparece no sidebar abaixo da notificação **só no modo IA**; badge com contador (destaque vermelho) quando há fila; some no modo Clássico; clicar navega pra lista filtrada "aguardando"; ícone anima no hover; aba "Aguardando atendimento" não está mais no tab-bar.

## Riscos
- Badge global vs por time (decisão 2) — alinhar count do `/meta` ao escopo.
- Ícone igual ao de Times (decisão 1) — confusão visual; resolver escolhendo ícone próprio.
- `to` precisa cair na visão certa — usar a rota que o item "Não atribuídas" já usa como precedente.
