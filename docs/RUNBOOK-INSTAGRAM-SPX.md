# RUNBOOK — Instagram no SPX (conectar conta e plugar IA)

> Passo a passo canônico, escrito depois do piloto Midwest (20/07/2026) com TODOS os erros
> enfrentados e seus fixes. Siga na ordem e nenhum deles volta.
> Credenciais do app atual: vault `Obsidian/credenciais/infraestrutura.md` § App Meta SPX Instagram.

## Arquitetura em 3 linhas

- O canal é **nativo do fork** (Chatwoot 4.12.1+, rota "Instagram API with Instagram Login" — **sem página do Facebook**). Não há código a escrever pra conectar contas.
- **1 app Meta serve a instância inteira** (todas as contas/tenants da VM). Configs vivem em `InstallationConfig` via **super_admin** — NÃO no `.env`.
- Modelo atual (sem App Review): cada conta IG conectada precisa ser **Instagram Tester** do app (teto 500). Com App Review (Advanced Access), cliente conecta sem convite — esse é o passo de escala.

## Parte A — Setup do app Meta (UMA vez por instância/VM)

1. Criar app em developers.facebook.com: caso de uso "Outro" → tipo **Business** → vincular ao BM.
2. Adicionar produto **Instagram** → **"API do Instagram com Login do Instagram"** (a rota direta).
3. ⚠️ **GOTCHA nº 1 — dois pares de credenciais:** o produto Instagram gera um **"ID do app do Instagram" + "Chave secreta"** PRÓPRIOS (dentro de *API setup with Instagram business login*). É ESSE par que o SPX usa. O App ID/Secret geral (Configurações → Básico) NO LOGIN dá **"Invalid platform app"**.
4. Business login settings → **OAuth Redirect URIs**: exatamente
   `https://<dominio-da-vm>/instagram/callback`
   (https, sem barra final, sem espaço — divergência dá **"Invalid redirect_uri"**).
5. Webhooks do produto Instagram:
   - Callback: `https://<dominio-da-vm>/webhooks/instagram`
   - Verify token: gerar aleatório (gravar ANTES no super_admin — passo 7 — pra validação passar de primeira)
   - Assinar campos: `messages`, `messaging_seen`, `message_reactions` (+ `comments`/`live_comments` quando usar automação de comentários)
6. Configurações → Básico: **URL de política de privacidade** + categoria. Ligar **modo Live** (sem Live não chega webhook, nem em teste).
7. No SPX: `https://<dominio>/super_admin/app_config?config=instagram` →
   `INSTAGRAM_APP_ID` (o do PRODUTO, gotcha nº 1) · `INSTAGRAM_APP_SECRET` · `INSTAGRAM_VERIFY_TOKEN` · `INSTAGRAM_API_VERSION` (v22.0).
8. Salvar o webhook na Meta → ela dispara o GET challenge → deve validar na hora (conferível no access.log do nginx: `GET /webhooks/instagram?hub.mode=subscribe... 200`).
9. Registrar app id/secrets/verify token no vault (`credenciais/infraestrutura.md`).

## Parte B — Conectar a conta de UM cliente (cada conta IG)

1. A conta IG precisa ser **profissional** (Business ou Creator). Conta pessoal quebra a troca de token.
2. **Adicionar como Instagram Tester**: painel do app → Funções do app → Funções → Adicionar pessoas → **Testador do Instagram** → @conta.
3. **⚠️ GOTCHA nº 2 — o passo que SEMPRE esquece: aceitar o convite DENTRO do Instagram.**
   Logado na @conta (app do IG): **Configurações e privacidade → Site e apps → Convites de tester → Aceitar**.
   Sem isso: `Failed to exchange token ("Unsupported request - method type: get", IGApiException 100)`.
4. No SPX, na CONTA do cliente: Configurações → Caixas de Entrada → **Nova → Instagram → "Continue with Instagram"**.
   No navegador, estar logado NA @conta certa na hora do OAuth. Autorizar.
5. Se falhar com autorização antiga pendurada ("você conectou anteriormente o app..."): no IG da conta →
   Site e apps → **apps conectados → remover o app** → refazer o passo 4 do zero.
6. Validar: inbox criada; token expira em ~60 dias (renova sozinho); `subscribed_apps` responde com os campos assinados.

## Parte C — Plugar IA na inbox (opcional, mas é o produto)

1. **⚠️ GOTCHA nº 3:** desligar auto-atribuição humana da inbox — `enable_auto_assignment=false`.
   Com ela ligada, a conversa nasce atribuída a um humano e o callback
   `reset_agent_bot_when_assignee_present` **derruba o bot** — a IA nunca gruda e ninguém vê erro.
2. Criar/definir o assistant da conta (conduta NO BANCO da conta, nunca no molde compartilhado) com as regras do canal:
   - **disclosure**: dizer que é assistente virtual na primeira resposta (política Meta);
   - mensagens ≤ 1.000 caracteres (limite do IG; humanizer ~900);
   - **sem PDF/documento** (canal não suporta), imagem até 8 MB;
   - **follow-up automático SÓ dentro da janela de 24h** — IG não tem template/HSM; a tag HUMAN_AGENT (7 dias) é SÓ pra humano real (IA com a tag = violação de política).
3. `CaptainInbox` (inbox ↔ assistant) + AutomationRule de triagem:
   evento `conversation_created`, condição `inbox_id = <inbox>`, ação `assign_ai_agent` com **o ID DO ASSISTANT** (não do AgentBot espelho).
4. Smoke: DM de outra conta → conversa nasce sem humano → IA atribuída pela regra → responde sozinha.

## Tabela de erros conhecidos (todos já enfrentados)

| Erro | Causa | Fix |
|---|---|---|
| `Invalid platform app` no OAuth | App ID **geral** no lugar do Instagram App ID do produto | Trocar `INSTAGRAM_APP_ID` pelo par do produto (gotcha nº 1) |
| `Invalid redirect_uri` | URI não registrada ou diferente (barra final, http, outro host) | Registrar a URI exata em Business login settings (Parte A.4) |
| `Failed to exchange token` (`Unsupported request - method type: get`, code 100) | Conta sem role de tester **aceito**, ou conta pessoal | Convite de tester + **aceitar no IG** + conta profissional; se persistir, remover app conectado e refazer OAuth (Parte B.5) |
| Idem, mas "a conta JÁ é testadora" | Tester adicionado **no app errado** (cliente costuma ter app próprio de n8n/automação) — e/ou confundir "app autorizado" (clique no Permitir) com papel de tester | O tester tem que ser no app **que o SPX usa** (o do `INSTAGRAM_APP_ID` do super_admin — a instância usa UM app por VM, pra todos os clientes). Conferir em Apps e sites → aba **Convites do testador** (autorização "Ativos" NÃO é tester) |
| Webhook não valida ao salvar | Verify token divergente, app fora do Live, URL errada | Conferir token no super_admin (salvar limpa o cache), Live ON, URL exata |
| IA não responde na inbox IG (silêncio, sem erro visível) | (a) humano auto-atribuído (auto_assignment ON); (b) **key OpenAI morta**: `faq_lookup` → embedding 401 mata a resposta em silêncio | (a) Parte C.1 + limpar `assignee_id`; (b) `journalctl` do worker procurar `Embedding API Error`; atualizar `CAPTAIN_OPEN_AI_API_KEY` no InstallationConfig **daquela VM** — rotação de key precisa cobrir TODAS as VMs da frota |
| Erro 190 semanas depois; canal pede reconexão | Senha trocada / app removido na conta IG | Reconectar a inbox (fluxo Reauthorizable); monitorável via health-check |

## Cola de janelas e limites (IG ≠ WhatsApp)

- **DM / story reply / story mention**: janela de 24h renovável a cada mensagem do cliente. Fora dela, nada automático (sem HSM no IG).
- **Private reply de comentário**: janela PRÓPRIA de **7 dias** a partir do comentário, **1 mensagem**; funciona em post, reel, story, live (só durante a transmissão) e **anúncio**; se a pessoa responder, abre a janela normal de 24h.
- **Webhooks pra conta própria/tester: Standard Access basta** (inclusive `comments` — provado na prática; a tabela "Advanced Access required" da doc vale pra contas de terceiros sem role).
- Limites: private replies 750/h (posts/reels) e 100/s (live); Send API ~100/s texto, 10/s mídia. API gratuita (sem custo por conversa).

## Escala (quando virar produto de prateleira)

App Review com **Advanced Access** (`instagram_business_basic` + `instagram_business_manage_messages` + feature `human_agent`) + Business Verification, de preferência num **app da SimplexIA** (a tela de consentimento mostra o nome do app pro cliente — hoje aparece "Business MW-IG"). Aprovado, cliente conecta sem convite de tester. Guia oficial: developers.chatwoot.com/self-hosted/instagram-app-review.
