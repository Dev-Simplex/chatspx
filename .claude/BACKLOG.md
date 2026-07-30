# Backlog técnico — ChatSPX

> Itens de melhoria não-bloqueantes. O que está **in-flight** vive no [`STATE.md`](STATE.md).
> Prioridade: 🔴 alta (dói no uso real) · 🟡 média · 🟢 nice-to-have.

---

## Knowledge / chunk-RAG (genérico do produto)

### 🔴 `format_chunk` descarta o `contextual_content` — chunk chega órfão pro agente
- **O quê:** `Captain::Tools::SearchKnowledgeTool#format_chunk` entrega `chunk.content` (texto cru fatiado) e ignora a coluna `contextual_content`, que é justamente onde o contextual retrieval grava a âncora ("O trecho descreve o empreendimento X…"). Resultado: o agente recebe fatos sem dono e os atribui ao assunto em discussão.
- **Medido na Tozi (28/07):** 93 de 114 chunks do catálogo não citavam empreendimento nenhum no `content`; **73 de 114 citavam no `contextual_content`**. Preço de um empreendimento podia responder pergunta de outro.
- **Fix:** entregar o `contextual_content` (ou content + âncora) no `format_chunk`. **1 linha**, beneficia todo cliente com `knowledge_mode` chunks/hybrid.
- **Mitigação já aplicada na Tozi:** 1 documento por empreendimento — o `name` do doc vira a fonte e ancora 100% dos chunks. Não resolve o caso de doc multi-assunto de outros clientes.
- **Relacionado:** não existe filtro de escopo no `hybrid_search` (busca todos os chunks do assistant). Um campo de escopo por documento resolveria multi-produto de forma estrutural.

---

## WhatsApp incoming / fichas duplicadas

### 🔴 Reconciliador de incoming — preferir conversa certa em ficha duplicada (9º dígito)
- **O quê:** quando um contato tem 2 fichas (12d/13d), o `Whatsapp::PhoneNumberNormalizationService` retorna a 1ª variante que casar (pode ser a errada). Proposta: quando 2+ fichas casam, rotear pra **ficha da conversa mais recente**.
- **⚠️ PROMOVIDO 🟢→🔴 em 22/07:** a premissa "fonte fechada" caiu — o caso 19765 (Leticia/Adrian) provou **fonte NOVA**: o envio de template 1:1 de dentro da conversa criou CI duplicado com 9º dígito no minuto do envio → resposta abriu conversa nova → triagem entregou pra IA (roubou prospecção humana). 333 pares duplicados na conta 6 (162 padrão 9º dígito). **Em execução via `MISSAO-9DIGITO-E-TRIAGEM.md`** (raiz do repo — fecha a fonte nova + este reconciliador + guarda de procedência na triagem).
- **Detalhe + código:** [`docs/backlog/reconciliador-incoming-9-digito.md`](../docs/backlog/reconciliador-incoming-9-digito.md)
- **Tamanho:** pequeno (1 método + 1 spec; OSS, sem override Enterprise; preserva caso comum com `matches.one?`).

---

## IA como extensão do atendimento humano (visão do Paulo, registrada 22/07)

### 🟡 Delegação com brief — IA dá sequência a template humano quando o remetente está offline
- **Ideia (Paulo, 22/07):** humano manda template 1:1 (ex.: Adrian → Leticia, 7h30, assunto de locação)
  **passando o contexto pra IA** (o que quer resolver). Cliente responde 12h com o Adrian offline →
  em vez de a conversa morrer no exato momento em que a CLIENTE está disponível, a **IA assume com o
  brief** e adianta/resolve, com a conversa em **"aguardando atendimento"** pro Adrian retomar assim
  que puder. IA como ponte da latência, não substituta.
- **É a v2 da guarda de procedência** (`MISSAO-9DIGITO-E-TRIAGEM.md` entrega a v1: resposta a template
  humano → vai pro humano, IA não assume). Condições de design pra v2 não sair pela culatra:
  1. **Brief é o contrato:** IA só avança o que o brief cobre; fora dele → segura e registra. Mandato
     limitado (adiantar, coletar, informar) — nunca negociar/prometer em nome do humano (mesma
     disciplina anti-cedência da Bruna).
  2. **Identidade honesta:** o template diz "Aqui é Adrian" — a IA não finge ser ele; assume como
     assistente do Adrian/da Tozi (padrão de disclosure já usado na Midwest/IG).
  3. **Só cobre ausência:** remetente online → resposta vai direto pra ele (v1). IA entra só
     offline/fora de horário, e cala quando o humano assumir (regras pós-handoff existentes).
- **UX:** opt-in POR ENVIO (toggle + campo de brief no modal "Enviar Template") + opt-in por conta.
  Nunca automático.
- **Tamanho:** médio-grande (UX do modal + persistência do brief + conduta da IA + gate de presença).
  Depende da v1 entregue.

---

## Módulo Disparo / Campanhas (construído 01-02/jun sob disparo ativo — tem arestas)

> Contexto: o motor de disparo (`Spx::Tozi::DisparoLeadJob` + rake `spx:tozi:disparo`) funciona,
> mas o **controle e a visualização** ficaram parciais porque foi tudo feito com o disparo rodando.

### 🔴 Controle do disparo é 100% console (pausar/retomar/redistribuir/dedup = scripts Ruby)
- **Dói:** pra pausar foi `Sidekiq::ScheduledSet ... j.delete`; pra retomar, re-enqueue com dedup; pra trocar corretor, script. Nada disso tem botão.
- **Fix:** na tela de detalhe da campanha (`WhatsAppCampaignDetail.vue`) — botões **Pausar** (cancela os `DisparoLeadJob` agendados) / **Retomar** (re-enfileira os não-enviados com dedup) / **Redistribuir** (reatribui restantes entre corretores selecionados). Backend: action no `campaigns_controller` que opera o `ScheduledSet` por `campaign_id`.
- **Tamanho:** médio (1 controller action + 3 botões + 1 service que encapsula os scripts de `Temp/`).

### 🔴 Iniciar um disparo só existe via rake/CSV no servidor
- **Dói:** subir CSV pra `/home/chatwoot/`, rodar `rake spx:tozi:disparo[...]` por SSH. Inviável pro time operar.
- **Fix:** UI "Novo disparo" — upload de CSV, multiselect de corretores, multiselect de templates (com rotação automática decorrelacionada), slider de pacing (s/envio), preview da audiência limpa (dedup + blacklist na hora). Reusa o motor existente.
- **Tamanho:** grande (é um módulo). Candidato a workflow de design antes de implementar.

### 🟡 Tela de detalhe é estática (números congelam até reload)
- **Fix:** auto-refresh do `getStats` a cada ~15s enquanto a campanha tem jobs pendentes (polling simples ou `setInterval` no `onMounted`/`onUnmounted`). Indicador "ao vivo".
- **Tamanho:** pequeno.

### 🟡 Falhas sem drill-down
- **Dói:** mostra "131026: 119" mas não dá pra ver QUAIS números falharam (pra reprocessar/limpar a base).
- **Fix:** clicar no código de falha → lista de conversas/contatos com aquele erro + ação "reprocessar" ou "marcar inválido".
- **Tamanho:** médio.

### 🟢 Rotação template×corretor invisível na UI
- **Dói:** o cruzamento (cada corretor manda os 3 templates, decorrelacionado) só foi verificável por script de console.
- **Fix:** card na tela de detalhe mostrando a matriz corretor×template (quantos de cada).
- **Tamanho:** pequeno.

---

## Respostas rápidas com anexo (deployado 02/jun)

### 🟡 Só validado com 1 anexo, fluxos secundários não exercitados
- **Já corrigido (02/06):** o `/` inline não anexava (só o modal anexava) — agora os 2 caminhos anexam. Ver STATE.md.
- **Ainda verificar:** múltiplos anexos numa resposta; preview do anexo no modal antes de enviar; remover anexo na edição; tipos não-imagem (PDF/áudio); comportamento quando o `file_url` expira (URL assinada do ActiveStorage tem TTL); indicador visual na lista de respostas rápidas de que uma resposta tem anexo.
- **Tamanho:** investigação + ajustes pontuais.

---

## Editor / Respostas rápidas

### 🟡 Canned multi-parágrafo via `/` inline achata quebras duplas → simples
- **Sintoma:** resposta rápida com linhas em branco entre parágrafos (`\n\n`), inserida pelo `/` inline, chega no WhatsApp com quebra simples (`\n`). O **botão** (modal) preserva.
- **Causa-raiz (confirmada lendo a fonte):** `editorHelper.js::insertAtCursor` desembrulha só o caso de **1 parágrafo**; multi-parágrafo faz `tr.insert(from, docNode)` numa posição inline → ProseMirror achata os parágrafos em `hard_break` → `MessageMarkdownSerializer` emite `\n` em vez de `\n\n`. O modal escapa porque seta `this.message = content` cru (sem round-trip ProseMirror).
- **Fix candidato:** tratar o caso multi-parágrafo no `insertAtCursor` (inserir os blocos preservando estrutura, ou — pro canned — rotear como o modal). **Risco:** é o editor compartilhado que todo o time usa via `/`; **exige verificação em browser** (não dá pra validar server-side). NÃO é patch cego de madrugada em produção.
- **Workaround imediato (zero-risco):** usar o **botão** de resposta rápida (não o `/`) quando precisar do espaçamento com linha em branco.
- **Tamanho:** médio, mas com verificação obrigatória em browser.

## Produtização — vender o SPX pro 2º cliente (Auditoria 2026-06-04)

> Origem: [`docs/AUDITORIA-SPX-2026-06-04.md`](../docs/AUDITORIA-SPX-2026-06-04.md). Hoje o SPX é um **serviço gerenciado para 1 cliente** (Tozi). O que falta pro 2º cliente não é feature — é **desacoplamento, isolamento e operação self-service**.
> Os itens de controle de disparo via console (R3) já estão na seção "Módulo Disparo" acima — não repetidos aqui.

### Caminho crítico (ordem de ataque)
```
1. De-hardcode Tozi → config por conta       (P1.1) ─┐
2. Isolar chave/billing LLM por conta         (P3.1) ─┼─ sem isso, 2º cliente = fork do fork
3. Resolver landmine + schema drift           (C2)   ─┘
4. UI de disparo + ativação IA (R3, acima)         ── mata o console SSH
5. Specs dos 3 caminhos do dinheiro           (C1)   ── confiança pra cobrar
6. Runbook + onboarding reproduzível          (P4)   ── escala sem o Paulo no console
```

---

### Confiabilidade (bloqueadores de confiança)

#### 🔴 C1 — Cobertura de testes ZERO no código custom
- **Dói:** disparo de **milhares de HSM pagos**, funil, cadência, Meta Lead Ads, tools — nenhum spec. Os 705 specs do repo são todos upstream. O susto "Oi Adriana!" (fallback de `PREVIEWS`) é exatamente o que 1 spec pegaria.
- **Fix (ROI máximo, começar por aqui):** 3 specs dos **caminhos do dinheiro** —
  1. `Spx::Tozi::DisparoLeadJob` — normalização de telefone BR + montagem de `template_params` + idempotência por telefone.
  2. `Meta::LeadAds::{SignatureVerifier,FetchLeadService,CreateConversationService}` — segurança (HMAC) + parsing de campos custom + criação de conversa.
  3. `Spx::Tozi::ReactivationCadenceService` — idempotência (`cadence_already_scheduled?`) + no-op fora de Cloud API.
  Depois: behavior services (puros, fáceis) e `campaign_stats`.
- **Tamanho:** médio (3 specs de alto valor primeiro; o resto incremental).

#### 🔴 C2 — Resolver a migration-landmine `20260330120000` + schema drift
- **Dói:** `DELETE` em cascata de `conversations`→`messages`/`scheduled_messages`/`funnel_items`, **sem proteção em código** (`disable_ddl_transaction!` remove até o rollback). `db:migrate` puro a dispara. E o `db/schema.rb` versionado **já contém as FKs da landmine + `template_params`** (dumpado de dev onde ela rodou) → diverge do banco de produção; `schema:load` acidental reconstrói com cascade ativo.
- **Fix:** (a) extrair a limpeza de órfãos pra **script idempotente auditado** (com contagem prévia + backup), aplicar as FKs, **remover a migration do caminho de `db:migrate`**; OU (b) reescrever a migration pra **abortar se órfãos > teto** e exigir `ENV['CONFIRM_DESTRUCTIVE']`. Em qualquer caso, **regenerar `schema.rb` a partir do banco de produção real**.
- **Tamanho:** médio (delicado, exige janela e backup). Bloqueia qualquer automação de deploy/migrate.

#### 🟠 C3 — Observabilidade do disparo (rescue silencioso)
- **Dói:** `DisparoLeadJob` tem `rescue StandardError` que **engole falhas pro log** (`disparo_lead_job.rb:73`). Em escala de milhares, falha sistemática é invisível sem tail de log. Sem métrica, sem dead-letter, sem retry.
- **Fix:** contador de enviados/entregues/falhas em tempo real (não só log) + dead-letter pra falhas + **alerta de degradação de tier WABA** (YELLOW→RED, que o STATE mostra que acontece). Complementa o drill-down de falhas já listado na seção Disparo.
- **Tamanho:** médio.

#### 🟠 C4 — Gap Meta Lead Ads → Cloud API (1ª mensagem como HSM)
- **Dói:** `create_conversation_service.rb:129` manda **texto livre**; numa inbox Cloud API fora da janela 24h a Meta **bloqueia** → lead de formulário entra no funil mas **não recebe abertura** (morre). Funciona em WAHA, não em prod Cloud API.
- **Fix:** quando `inbox.whatsapp?` (Cloud API), enviar a 1ª msg como **HSM** (`tozi_lead_abertura` via `template_params`) em vez de texto livre. Pré-req Meta-side: template aprovado + switch do callback do app Meta pra prod.
- **Tamanho:** médio. Bloqueia ativar Meta Lead Ads em produção.

---

### Multi-tenant / de-hardcode (bloqueadores de produto)

#### 🔴 P1.1 — Tirar os hardcodes Tozi do código → config por conta
- **Dói:** `DisparoLeadJob::INBOX_ID=91`, `DISPARO_BROKERS=[128,126,127,131,125]`, funil "Pré-Venda Tozi", ENV `TOZI_VISTA_*`/`TOZI_EVAL_ACCOUNT_ID(default '1')`. Um 2º cliente **não roda sem editar código**.
- **Fix:** model/JSONB de settings por account (ex.: `SpxAccountConfig`) com inbox-alvo, brokers, templates, chaves de integração. `Spx::Tozi::*` → `Spx::*` recebendo `account`/`inbox`/`brokers` como parâmetro.
- **Tamanho:** grande (é o coração do de-hardcode). Candidato a workflow de design.

#### 🟡 P1.2 — Gate do `FunnelAutomationListener` por conta/feature-flag
- **Dói:** registrado no `AsyncDispatcher#listeners` **global** → roda `current_type` (query c/ joins) em **todo** `message_created`/`assignee_changed` de **toda conta**, mesmo sendo no-op fora da Tozi.
- **Fix:** checar feature-flag/conta **antes** de tocar o banco.
- **Tamanho:** pequeno.

#### 🟡 P1.3 — Tools de domínio plugáveis por conta
- **Dói:** `BuscarImovelTool`/`EnviarFotosImovelTool` são imobiliário-específicas (Vista API). 2º cliente de outro vertical precisa de outras tools.
- **Fix:** registro de tools **por conta** sem deploy (já existe `ToolRegistryService`; falta a config por conta).
- **Tamanho:** médio.

---

### Robustez do pipeline de IA

#### 🟠 P2.1 — Exceção em service de gating sobe pelo callback `message_created`
- **Dói:** `hook_execution_service#process_captain_behavior` **não tem rescue** envolvendo os gating services. Exceção em `RouterService`/`BusinessHoursChecker`/`DebounceService` (Redis down) **sobe pelo callback** e pode quebrar o **recebimento de mensagem** da inbox. Config behavior ruim num assistant = inbox para de receber.
- **Fix:** rescue defensivo no orquestrador (degradar pra "não responde" em vez de derrubar o callback). Espelhar a robustez que o `ResponseBuilderJob` já tem.
- **Tamanho:** pequeno-médio.

#### 🟠 P2.2 — `BusinessHoursChecker.parse_time` sem validação
- **Dói:** `schedule` JSONB malformado (`"25:00"`, `nil`, `"9h"`) levanta exceção; o call-site de gating não tem rescue (só o de prompt tem).
- **Fix:** validar/sanitizar `parse_time` + rescue no call-site de gating. Idealmente, **schema/validação do JSONB `behavior`** (ver P2.4).
- **Tamanho:** pequeno.

#### 🟠 P2.3 — `processed_params` sempre com 2 vars → `#132000`
- **Dói:** `DisparoLeadJob:107` manda `{'1','2'}` pra todo template; template de 1 variável pode dar `#132000 number of parameters` (gotcha já vivido).
- **Fix:** montar `processed_params` conforme o nº de variáveis do template (lookup no template sincronizado).
- **Tamanho:** pequeno.

#### 🟡 P2.4 — `store_accessor :behavior, :*_config` é dead code + sem validação do JSONB
- **Dói:** os accessors declaram `router_config`/`humanizer_config`/etc., mas os services leem `behavior['router']`/`['humanizer']` (sem sufixo) → accessors nunca usados; typo numa chave vira silenciosamente "feature off".
- **Fix:** remover os accessors mortos + adicionar validação/schema do JSONB `behavior` (resolve P2.2 de quebra).
- **Tamanho:** pequeno-médio.

#### 🟡 P2.5 — `MediaPipelineService` órfão (UI enganosa)
- **Dói:** sem call-site no backend; a config na UI sugere controle que não existe; transcrição de áudio roda **sempre** (via `OpenAiMessageBuilderService`), fora do toggle.
- **Fix:** ou ligar o service no pipeline (gatear transcrição pelo behavior), ou remover o service + esconder a config da UI. Decidir qual.
- **Tamanho:** pequeno (decisão + cirurgia).

#### 🟡 P2.6 — Handoff de cota estourada com string EN hardcoded
- **Dói:** `perform_handoff` usa "Transferring to another agent…" sem i18n; cliente PT vê EN. O handoff normal já é i18n-aware.
- **Fix:** trocar por `I18n.t` com locale da conta.
- **Tamanho:** trivial.

#### 🟢 P2.7 — `max_turns: 100` no runner
- **Dói:** loop de tool-calls pode consumir muitos tokens/tempo por request.
- **Fix:** baixar pra um teto razoável (ex.: 12–20) + log quando atingir.
- **Tamanho:** trivial.

---

### Billing / isolamento de custo

#### 🔴 P3.1 — Isolar a chave LLM (e o custo) por conta
- **Dói:** o runtime v2 (gem `agents`, boot `ai_agents.rb`) usa a chave Anthropic **global** de instalação → billing e rate-limit **não isolados** entre clientes. Custo de IA de todos cai no mesmo balde.
- **Fix:** chave LLM por conta (ou medição de uso por conta pra repassar). Pré-req pra precificar.
- **Tamanho:** médio.

#### 🟡 P3.2 — Medição de uso por conta (base de cobrança)
- **Fix:** medir mensagens IA, tokens LLM, HSM disparados (custo Meta), storage de knowledge — por conta. Sem isso não há como precificar nem cobrar. Checar se a quota `captain.responses` é por conta e se alimenta cobrança.
- **Tamanho:** médio-grande.

---

### Performance

#### 🟡 P5.1 — `campaign_stats` N+1 + full-scan JSONB
- **Dói:** `pluck(:id)` de todas as conversas em memória + `find_each` em cada falha + **15 N+1** no bloco `recent` (última msg por conversa) + filtro `template_params ->> 'name'` sem índice GIN. OK na escala Tozi, não escala pra 10k+/multi-cliente.
- **Fix:** materializar (rollup) ou cachear com TTL curto; índice parcial GIN no `template_params`; substituir o N+1 do `recent` por 1 query com `DISTINCT ON`.
- **Tamanho:** médio.

#### 🟡 P5.2 — Humanizer `sleep` dentro do worker Sidekiq
- **Dói:** `sleep(1.5–7s)` por chunk **bloqueia o worker** (resposta de 5 partes segura ~35s). Sob carga multi-cliente, prende workers e derruba throughput.
- **Fix:** reagendar cada chunk como job separado (`perform_in`) em vez de bloquear.
- **Tamanho:** médio.

---

### Onboarding / Docs / Branding

#### 🟠 P4 — Onboarding de novo cliente reproduzível
- **Dói:** hoje é tribal/console (criar conta, inbox, assistant, knowledge, funil, brokers — tudo manual).
- **Fix:** rake `spx:onboard[account]` ou wizard que provisiona o cliente ponta-a-ponta. Incluir provisionamento WABA/Cloud API (o `TemplateManagementService` já cria templates via API — falta o fluxo).
- **Tamanho:** grande.

#### 🟡 P6.1 — Branding por tenant
- **Dói:** o manual de marca SPX existe (`/brand/manual-marca-spx.md`) e o fork usa `replaceInstallationName`/`useBranding`, mas o branding parece **por instância** (SPX), não por account. Cliente white-label precisa de logo/cores **por conta**.
- **Fix:** verificar e, se for o caso, mover branding pra config por account.
- **Tamanho:** médio.

#### 🟡 P6.2 — Runbook de operação + doc de arquitetura SPX
- **Dói:** conhecimento de operação (disparo, pausa, ativação IA, incidentes) vive no STATE.md/vault — ótimo pro Paulo, intransferível pra operador novo.
- **Fix:** runbook operacional + `docs/adr/` formalizando as decisões (code-first, behavior JSONB, disparo próprio vs nativo, landmine). A auditoria de 04/06 é ponto de partida.
- **Tamanho:** médio (escrita).

---

## Handoff / robustez do captain (resíduo da frente `spx/resgate`, 30/07)

> Origem: triagem da `spx/fix-fotos-handoff-hml` — 10 commits de 09–14/07 que nunca chegaram em
> `homologacao` nem em `producao`. 5 recuperados + 4 portados na `spx/resgate`; o que sobra é isto.

### 🔴 `ensure_handoff_if_promised` promete humano e não entrega
- **O quê:** `enterprise/app/jobs/captain/conversation/response_builder_job.rb`. A rede de segurança
  dispara quando a IA *escreve* que vai passar pro humano sem acionar o handoff. A **detecção** foi
  alargada (commit `25486bb49`, na `spx/resgate`), mas a **ação** continua furada em dois pontos:
  1. O grupo `HUMANO` da regex **não tem `corretor`** — que é a palavra natural no vertical da Tozi
     ("vou passar pro corretor"). `vendedor` idem, pra outros clientes.
  2. Chama `@conversation.bot_handoff!` puro, **não** o `Captain::Conversation::HumanHandoffService`.
     Perde-se: `aguardando_humano_desde` (a conversa não entra em "Aguardando atendimento"),
     roteamento de time, a nota-dossiê, o **motor de distribuição**
     (`Spx::Distribuicao::DistribuirService`) e o out-of-office.
- **Efeito:** a IA promete que um humano retorna, o safety-net dispara — e a conversa não chega em
  ninguém. Comparar com `escalate_after_unknown_marker`, no mesmo arquivo, que faz certo.
- **Dono:** frente `spx/followup`. **Tamanho:** pequeno (trocar a chamada + 2 palavras na regex).

### 🟡 Retry do Vista cobre só metade das chamadas
- `vista_get` (com retry, commit `9ceb1dde2`) protege só o `/imoveis/listar`. Continuam com
  `HTTParty.get` cru contra `/imoveis/detalhes`: `detalhes_info` (`buscar_imovel_tool`) e
  `fetch_detalhes` (`enviar_fotos_imovel_tool`). Mesmo transitório, mesmo sintoma — a IA diz que
  "o sistema caiu" por causa de uma falha momentânea.

### 🟢 Verificado ao vivo (30/07) — não repetir a dúvida
- O `/imoveis/listar` do Vista **devolve** o campo `Condominio`, como **string** (`"Sim"`/`"Nao"`),
  não booleano. O `format_condominio` trata com `case`+`downcase`, então está correto — mas quem
  mexer nisso: `"Nao"` é *truthy* em Ruby, testar presença inverte o significado.
- `f9647e1c9` (recursão em `track_imoveis`) foi **descartado**: o método não existe mais; `perform`
  chama `track_codigos` e `track_urls` direto. Reaplicar criaria método morto.

### ⚠️ Dívida de lint pré-existente nesses arquivos
Baseline da `homologacao` nesses 10 arquivos: **60 offenses** (RuboCop). Quase tudo é
`Metrics/*` estrutural — `buscar_imovel_tool#perform` sozinho está em 22/7 de complexidade
ciclomática. Não confundir com regressão de quem mexer neles.

---

## Como usar este arquivo
- Resíduo arquitetural / bloqueio reutilizável → vault Obsidian (não aqui).
- Item fechado → remover (o git guarda histórico).
- Item que virou in-flight → mover pro `STATE.md`.

---

## Triado do INBOX 24/07 (sessão noturna) — revisar prioridades

> Origem: `cockpit/INBOX.md`, seções "Brain-dump de caderno" (24/07) e "Visão dos próximos 9 dias" (24/07 tarde). Triagem 25/07 — Paulo revisa prioridade.

### 🔴 Fechar o ciclo de follow-up, encerramento e evaluation
- [ ] 🔴 Aplicar cadência de follow-up (IA + disparo de leads) e as regras de fechamento/encerramento na operação real da Tozi — item batido de novo no "Teatro 1" de 24/07; boa parte da engenharia já existe (aguardando-encerramento, `motivo_encerramento`, cadência — ver `STATE.md`), falta ligar/validar ponta a ponta em produção.
- [ ] 🔴 Evaluation — fechar o ciclo de auto-avaliação das IAs. Eval 2.0 já tem F1 (episódios) + F2 (tool-trace) + F4 (painel) LIVE na conta 6 (ver `STATE.md`); falta F3 (outcomes/autoria) e F5 (golden set + simulador pass^k).
- [ ] 🟡 Rodízio de atribuições — regras finas por perfil: consultores de locação × corretores × administrativo. O piloto de locação (Gelson/Adrian/Camila, online-only) já foi aprovado (ver `STATE.md` "Motor de Rodízio"); falta desenhar as regras para os outros perfis.

### 🟡 Cards Loft/Vista + app nativo SPX (Walisson)
- [ ] Cadastrar leads no Vista e evoluir os cards Loft/Vista até os corretores conseguirem atender tudo dentro do SPX — em conjunto com o app nativo SPX que o Walisson está construindo (alinhar escopo/integração entre os dois).

### 🟡 Meta-leads/campanhas expandido + analítico de leads
- [ ] Meta-leads/campanhas: templates com imagem, remarketing de catálogo, áudios, follow-up e repescagem — o módulo Disparo hoje cobre o disparo básico (ver seção "Módulo Disparo" acima), falta a parte de campanha rica.
- [ ] Analítico de leads: onde travam, onde fluíram, onde perderam — painel/relatório do funil comercial (diferente do Eval 2.0, que mede qualidade de atendimento; este é sobre conversão).

### 🟡 Instagram — direct, comentários, curtidas (orgânico + pago)
- [ ] Ampliar o canal Instagram da Tozi além do DM (que já está live na conta 3, piloto Midwest — ver `STATE.md` "INSTAGRAM DM NO SPX"): cobrir comentários e curtidas, orgânico e pago.

> Nota: o caderno (pág. 4) lista soltos "front" e "imagens" entre as frentes da Tozi — provavelmente já cobertos pelos itens acima (carrossel de fotos já está LIVE, ver `STATE.md`) ou pelo item de UI; confirmar com o Paulo se sobra algo específico.

> Itens do caderno marcados **→ em tratamento (Plano Decolagem SPX)** e não migrados para este backlog: Fábrica dos Óculos, BigStore, CD Solar, Casarin, SimplexIA vitrine.
