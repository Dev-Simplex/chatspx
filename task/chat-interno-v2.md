# Chat Interno v2 — Repaginada (dinâmica + visual + features)

> Evolução do Chat Interno entre agentes (Módulo B, B1+B2 já entregues). O usuário pediu melhoria em **todas as frentes**: básico de mensageria, integração com atendimento, notificações & presença, gestão de canais & acabamento — **+ dinâmica e visual**. Base técnica intacta: `InternalChannel`/`Member`/`Message`, real-time via `RoomChannel` + `ActionCableBroadcastJob` (eventos `internal.message.created` / `internal.mention.created`), store `internalChat`, `InternalChatIndex.vue`. Flag `internal_chat` (bit 30), ligada na conta #1.
>
> Princípios: reaproveitar a casa (presença/notificações/soft-delete do Chatwoot já existem), atrás da flag, commit + deploy + validação por fase no staging.

---

## Fase 1 — Visual & dinâmica (revamp da UI) — **FUNDAÇÃO** ✅ FEITA (2026-06-26)
> Reescrita do `InternalChatIndex.vue`: avatares reais (componente `Avatar`, iniciais coloridas quando sem foto) na lista/header/mensagens; agrupamento por dia (Hoje/Ontem/data) + por autor consecutivo (<5min); bolhas refinadas (própria à direita verde, colega à esquerda, nome só no 1º do bloco, horário no hover); preview inline de imagem nos anexos + chip de arquivo; links clicáveis (linkify seguro, sem v-html); composer com textarea auto-resize, foco ao abrir canal, botão enviar com ícone; scroll suave + botão "descer" quando rolado pra cima (auto-scroll só se perto do fim); estados vazios/carregando. i18n (TODAY/YESTERDAY/DIRECT/MEMBERS_COUNT/LOADING). Build+lint verdes. **Deferido p/ Fase 2:** last_message do canal não atualiza em tempo real (só no refetch).

### Itens originais da Fase 1
Redesenho do `InternalChatIndex.vue` para parecer um chat de verdade (referência: a própria tela de conversa do Chatwoot, polida).
- **Avatares reais** (Thumbnail/avatar do user) na lista e nas mensagens, em vez do ícone genérico.
- **Agrupamento de mensagens** por autor consecutivo + **divisor de dia** ("Hoje", "Ontem", data) + horário discreto.
- **Bolhas refinadas**: própria à direita (verde brand), colega à esquerda; nome só no 1º de um bloco; cantos/spacing consistentes.
- **Preview inline de imagem** nos anexos (thumbnail clicável) em vez de só link; ícone+nome para outros arquivos.
- **Links clicáveis** + markdown leve (negrito/itálico/código) e quebra de linha.
- **Estados** caprichados: vazio (sem canais / sem mensagens), carregando (skeleton), erro.
- **Header do canal** mais rico: avatar/ícone + nome + subtítulo (membros do grupo / "online" no DM).
- **Composer** mais polido: textarea auto-resize, dica de envio, botões alinhados, foco automático ao abrir canal.
- **Dinâmica**: auto-scroll suave ao chegar/enviar, "▼ novas mensagens" quando rolado pra cima, transição de entrada das bolhas.

## Fase 2 — Básico de mensageria
- **Digitando…** em tempo real (broadcast `internal.typing` por pubsub_token; debounce).
- **Editar / apagar** mensagem (soft-delete: badge "editada"/"apagada"); broadcast de update.
- **Reações** com emoji (👍❤️✅) — nova tabela `internal_message_reactions` ou jsonb; toggle + contagem.
- **Responder/citar** uma mensagem (quote inline + scroll-to-original).
- **Recibo de leitura** ("visto") — exibir a partir do `last_read_at` dos membros.
- **Paginação do histórico** (cursor por created_at; carregar antigas ao rolar pro topo).

## Fase 3 — Integração com o atendimento (o diferencial)
- **Compartilhar conversa de cliente** no chat: action "encaminhar conversa #N" → mensagem com card clicável que abre `/conversations/N`.
- **"Pedir ajuda"** a partir da conversa do cliente: botão que abre/cria DM (ou posta em canal) com o link da conversa anexado.
- **Menção `#123`** vira link para a conversa; (opcional) menção a contato.

## Fase 4 — Notificações & presença
- **Som + notificação desktop** para @menção e nova DM (reusar Notification API / AudioAlerts do dashboard) — sem tocar no sino global.
- **Presença online/offline** (bolinha) — reusar `OnlinePresenceTracker`/presença do Chatwoot.
- **Badges** refinados: por canal na lista + total na sidebar (total já existe).

## Fase 5 — Gestão de canais & permissões
- **Gerenciar grupo** após criado: renomear, adicionar/remover membros, sair, arquivar.
- **Permissões**: quem pode criar grupos / canais de equipe (admin vs agente).
- **Canal "Geral"/Anúncios** por conta (opcional).

---

## Ordem & DoD
Fase 1 primeiro (fundação visual em que tudo se encaixa), depois 2 → 3 → 4 → 5.
Cada fase: specs (back) / lint+build (front) verdes → commit atômico → deploy no staging (assets + restart) → validação visual do usuário.

## Riscos / notas
- Real-time já provado (RoomChannel). Novos eventos (`typing`, `reaction`, `message.updated`) seguem o mesmo padrão de broadcast aos pubsub_tokens dos membros.
- Avatares/presença: reusar componentes existentes (Avatar, presença) para consistência.
- Markdown: usar o renderer já existente no projeto se houver (evitar dep nova).
- Paginação: o index hoje carrega tudo; migrar para cursor sem quebrar o real-time (append continua funcionando).
