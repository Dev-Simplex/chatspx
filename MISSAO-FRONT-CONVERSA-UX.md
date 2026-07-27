# MISSÃO: 7 ajustes de UX na tela de conversa (front compartilhado)

> Abrir sessão Claude no repo principal (`chatspx/`). Trabalhar sobre a branch **`homologacao`**
> (o checkout local pode estar em branch antiga — `git checkout homologacao && git pull` antes;
> stash do que estiver sujo, sem perder nada). Commit direto na `homologacao`, Conventional
> Commits em PT. ⚠️ Push desce AO VIVO pra `.232` (contas reais 3/4/5) — e a UI só aparece lá
> após precompile + restart do web na VM (coordenar; não é automático).
> Referência visual: screenshot do Paulo em 21/07 (conversa da Millenna, conta 6).

## Regras do projeto (não negociáveis)
- **Tailwind only** (sem CSS custom/scoped/inline). Dark mode obrigatório em tudo (tokens `bg-n-*`, `text-n-slate-*`, `border-n-weak`).
- **i18n** — zero strings hardcoded; editar as chaves existentes (`pt_BR/conversation.json` já tem as customs do fork; espelhar em `en/conversation.json` se a chave existir lá).
- Cirurgia, não reforma: tocar SÓ o que os 6 itens pedem.
- Verificação: `pnpm eslint` limpo + validar visualmente (dev local ou Playwright).

## Componentes já mapeados (recon de 21/07 na origin/homologacao)
- Banner "RESUMO DA IA" na conversa: `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` (chave `AI_SUMMARY_TITLE`).
- Card lateral Resumo IA/humano: `app/javascript/dashboard/routes/dashboard/conversation/ConversationSummary.vue` (chaves `SUMMARY.AI_TITLE/HUMAN_TITLE/EDIT/SAVE/CANCEL/SAVE_ERROR`).
- Checklist: chaves `CHECKLIST.*` no `pt_BR/conversation.json` (TITLE "Assuntos / Tarefas"); componente junto do Summary ou vizinho — confirmar.
- Tela janela 24h expirada: `app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/WhatsappWindowExpired.vue` (chave `WHATSAPP_WINDOW_EXPIRED.QUICK_TEMPLATES` = "Envio rápido").
- Ações da conversa: `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue` e `MoreActions.vue` (chave `RETRIAGE` = "Devolver para a IA").

## Os 7 itens

### 1. Resumo da IA colapsável (banner NA conversa)
Resumo longo come a janela. Colapsar por padrão (clamp de ~2-3 linhas, `line-clamp` do Tailwind)
com "ler mais"/"ler menos" no clique. **Estado expandido NÃO persiste**: ao atualizar a página ou
voltar pra conversa, nasce colapsado de novo (estado local do componente, sem store/localStorage).

### 2. Resumo lateral idem
Mesmo comportamento de colapso no card "Resumo da IA" da sidebar (`ConversationSummary.vue`).

### 3. Tirar os "templates rápidos" da tela de janela expirada
Em `WhatsappWindowExpired.vue`: remover a lista "Envio rápido" (os 3 templates clicáveis).
Fica só o aviso + botões "Enviar Template" (abre o modal de seleção, como já faz) e "Nota Privada".
Limpar o que órfão desta remoção (chave i18n `QUICK_TEMPLATES`, props/fetch de templates se só
serviam à lista).

### 4. Resumo do humano: BUG de escrita + Resumo da IA read-only
(a) **Bug:** o campo "Resumo do humano" não aceita escrita (clicar em "Adicione um resumo..." não
entra em edição, ou salva e falha). Investigar em `ConversationSummary.vue` + endpoint de save e
consertar — humano TEM que conseguir escrever/editar o resumo dele.
(b) **Regra:** o card "Resumo da IA" (lateral e banner) é **somente leitura pra humanos** — remover
qualquer affordance de edição (o EDIT/SAVE genérico do componente não pode se aplicar ao da IA).
Só a IA escreve nele.

### 5. Checklist: checkbox invisível + rename
(a) Checkbox desmarcado não tem contorno (invisível no dark) — dar borda visível nos dois temas
(ex.: `border border-n-strong` ou token equivalente; conferir light + dark).
(b) Renomear "Assuntos / Tarefas" → **"Assuntos e Tarefas"** (chave `CHECKLIST.TITLE` no pt_BR;
espelhar en se existir).

### 6. Ações da conversa: toggle Atribuir ↔ Devolver
Hoje: conversa atribuída a OUTRO agente mostra "Atribuir pra mim" E "Devolver para a IA" empilhados.
Regra nova (visibilidade por dono, em `ConversationAction.vue`; conferir se `MoreActions.vue` repete):
- Atribuída a MIM (`assignee.id === currentUser.id`) → mostra **"Devolver para a IA"** (no lugar do
  "Atribuir pra mim", que some — não faz sentido atribuir o que já é meu).
- Atribuída a outro ou SEM atribuição → mostra **"Atribuir pra mim"** (e o "Devolver para a IA" some).
- Nunca os dois ao mesmo tempo.
Escopo = SÓ visibilidade. NÃO mexer no comportamento do RetriageService (gotcha #29 da memória:
ele apaga assignee e re-espelha triagem — é conhecido, fora de escopo).

### 7. Resumo da IA só aparece em conta que TEM IA
Banner (item 1) e card lateral (item 2) do "Resumo da IA" só renderizam se a conta tem o módulo de
IA ativo. Detectar pelo sinal canônico que o resto do front já usa pra esconder o módulo Agentes IA
(feature flag da conta — provável `CAPTAIN_V2`/captain no `isFeatureEnabledonAccount`; descobrir o
getter usado nas rotas de agentes e REUSAR o mesmo, não inventar sinal novo). Conta sem IA: nada de
resumo da IA (o "Resumo do humano" e o checklist continuam aparecendo normalmente — decisão:
são genéricos). Multi-tenant: zero hardcode de conta.

## Critério de aceite
- Resumos nascem colapsados (banner + lateral), expandem no clique, voltam colapsados no refresh.
- Tela de janela expirada sem lista de templates; modal via botão continua funcionando.
- Humano escreve/salva o resumo dele; card da IA sem botão/afford de edição.
- Checkbox desmarcado visível nos 2 temas; título "Assuntos e Tarefas".
- Toggle Atribuir/Devolver certo nos 3 estados (minha / de outro / sem dono).
- Conta SEM módulo de IA não vê "Resumo da IA" (banner nem lateral); conta COM IA vê tudo.
- `pnpm eslint` limpo · sem strings hardcoded · dark mode ok · commit na `homologacao`.
- Pre-commit: se falhar por erro PRE-EXISTENTE em arquivo não tocado, `--no-verify` e anotar.

## Ao final
Atualizar `chatspx/.claude/STATE.md` (1 linha na seção de UI) + avisar que a `.232` precisa de
precompile + restart web pra exibir.
