# Onda 0 — lista de correções a aplicar no merge (em construção pelo coordenador)

Consolidada a partir dos quatro relatórios de auditoria e da DoD. Esta lista é a autoridade
do executor de correção: o que não está aqui não se aplica.

| # | Gravidade | Onde | O que fazer | Fonte |
|---|---|---|---|---|
| 1 | **DADO** | `db/migrate/20260714123000_purge_pending_captain_assistant_responses.rb` | Neutralizar. No upstream `status 0` é lixo; no fork era FAQ pendente. Medido nesta VM: **0 linhas com `status = 0`** (87 responses, todas `status 1`), mas a frota não foi medida. Dado de cliente não se apaga: virar no-op comentado ou migração que preserva. | coordenador + A2 |
| 2 | **RISCO ALTO (frota)** | `.env` de cada VM / `lib/safe_fetch.rb:38` | `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` tem default `false`. Todo webhook para IP privado (WAHA interna, n8n interno, receptor local, `192.168.x`) passa a falhar **silenciosamente** em `handle_failure`. É item de pré-deploy, não de código do merge — mas se não entrar no relatório da onda, derruba integração de cliente sem ninguém entender por quê. | A1 §1.3 |
| 3 | **PERDA** | `vite.shared.ts:19` | `lord-icon` deixou de ser custom element — ícone animado quebra em runtime. Uma linha. | A3 §C1 |
| 4 | **PERDA** | `vite.config.ts` | `optimizeDeps` do canvas de Automações se perdeu (o arquivo caiu de 30 linhas nossas para 17 do upstream). Quebra `vite dev` — e é a causa provável do `504 Outdated Optimize Dep` que matou a primeira tentativa de baseline em 13/08. | A3 §C2 |
| 5 | **PERDA** | `vite.config.ts` | `resolve.dedupe: ['html2pdf.js']` se perdeu → exportação de PDF dos relatórios. | A3 §C3 |
| 6 | **PERDA** | `swagger/swagger.json` | Caiu de **353 paths para 90** (ficou o artefato do upstream; `set(paths_MERGE) == set(paths_DELES)`). A marca ChatSPX sobreviveu. Agravante: o pipeline que gerava os 353 nunca foi versionado e não existe mais na VM. | A3 §C4 |
| 7 | RISCO | `shared/components/emoji/EmojiInput.vue` | Componente apagado **pelo upstream**, substituído por `EmojiPicker.vue`; nenhum arquivo o importa mais. Nossa customização era a cor do foco. Verificar o emoji picker do widget na revisão dos 16 snapshots. | A3 §R1 |
| 8 | **DADO** | `db/migrate/20260515000000_enqueue_validate_openai_hooks_job.rb` | Enfileira job que **destrói** `Integrations::Hook` de `openai` (com a chave e as settings dentro) para toda conta cuja chave falhe um `GET /v1/models`. Sem `down`, assíncrono, fora da transação. Numa VM com `CAPTAIN_OPEN_AI_ENDPOINT` apontando para gateway que responde 401 nesse path, **apaga as integrações de IA da VM inteira**. Neutralizar e, se quiser o housekeeping, rodar o job em modo relatório antes. **Exposição medida nesta VM pelo coordenador: 1 hook `openai` habilitado, e `CAPTAIN_OPEN_AI_ENDPOINT` NÃO configurado** (bate em `api.openai.com`). O cenário catastrófico (gateway que responde 401 em `/v1/models`) não se aplica aqui, mas as demais VMs não foram medidas. | A2 §2.3 |
| 9 | **PERDA (produção, cliente real)** | `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | `fix_property_links` foi apagado (método e chamada). O **produtor do dado continua vivo** e o comentário dele descreve o consumidor apagado (`buscar_imovel_tool.rb:125-127`). Efeito: a IA da Tozi volta a mandar **URL de imóvel inventada** ao cliente final. Restaurar o método e a chamada, mais `property_code` no placeholder de anexo. | A2 §3.7 |
| 10 | **PERDA (comportamento de IA)** | `enterprise/lib/captain/tools/handoff_tool.rb` | A `description` do tool — o texto que o LLM lê para decidir transferir — voltou à do upstream, mais restritiva ("only when…"). O comentário nosso que **condena exatamente essa descrição** sobreviveu três linhas acima: o arquivo se autocontradiz. Efeito: lead qualificado deixa de chegar ao humano. Restaurar a descrição em pt-BR. | A2 §3.6 |
| 11 | **PERDA (comportamento de IA)** | `enterprise/lib/captain/prompts/assistant.liquid` | 7 das 13 regras de `# Conduta no atendimento (sempre)` viraram 3 bullets em inglês. **Atenção:** parte da "perda" é falso positivo — `current_datetime`/`business_status`/`business_hours_text` migraram de propósito para `runtime_context.liquid` (design de prompt caching, correto, **não corrigir**). Restaurar só as 7 regras de conduta. | A2 §3.1 |
| 12 | **PERDA** | `enterprise/lib/captain/prompts/scenario.liquid` | Perdeu `business_status` sem migrar para lugar nenhum no caminho default (≠ do caso acima). Os agentes de cenário são os que atendem no modo multi-agente. | A2 §3.8, §3.5 |
| 13 | **PERDA** | `enterprise/app/models/concerns/agentable.rb` | `agent_model` perdeu as duas salvaguardas (`presence ||` do modelo da conta e a tradução `Llm::Models.runtime_id_for`). Reconciliar com o `Llm::FeatureRouter` novo do upstream — casa com os 8 arquivos de LLM que estavam em edição inacabada. | A2 §3.2, §3.4 |
| 14 | **PERDA (i18n, regra permanente)** | `lib/integrations/openai/openai_prompts/summary.liquid` | O bloco que força o resumo de conversa em **pt-BR** voltou ao inglês do upstream (MERGE == DELES byte a byte): os 4 cabeçalhos traduzidos e a regra `IMPORTANT — LANGUAGE` sumiram (`:20-28`). pt-BR é prioridade desta casa, não idioma secundário. Reaplicar. | A1 patch 1 |
| 15 | **PERDA (produção)** | `app/controllers/swagger_controller.rb` | O merge repôs o gate `if Rails.env.development? \|\| Rails.env.test?` com `else head :not_found`, deixando nosso `authenticate_docs!` (`:20-37`) como **código morto**: a doc da API deixa de existir em produção. Remover o gate de ambiente **mantendo** o hardening de path traversal que o upstream trouxe junto. | A1 patch 3 |
| 16 | PERDA (decidida como NÃO-correção) | `app/views/layouts/portal.html.erb` | O `<title>SPX - CHAT</title>` fixo do portal voltou a `@portal.display_title(@locale)`. **Decisão do coordenador: manter o comportamento do upstream.** Num produto white-label, o título do Help Center do cliente deve ser o nome do portal do cliente, não a nossa marca cravada. O favicon com o nosso fallback já foi reaplicado no partial novo. Registrado para que ninguém "corrija" isso de volta achando que foi esquecimento. | A1 patch 2 — **recusado** |
| 17 | **RISCO ALTO (vazamento entre agentes)** | `components-next/Conversation/ConversationCard/ConversationCardExpanded.vue` via `components/ConversationList.vue:37` | O card expandido do upstream **não implementa o isolamento por agente**: em tela larga com layout expandido, o preview da última mensagem restrita a outro agente aparece **em texto cru**, sem o `🔒`. Também não tem o chip de IA, o destaque de não-atendida nem a cadeia de fallback de conteúdo. **DECISÃO DO COORDENADOR: Opção A** — neutralizar o caminho novo (`showExpandedCards = false`) com comentário explicando, restaurando exatamente o comportamento de hoje. A Opção B (portar as 4 customizações) fica como trabalho próprio, com id, depois da onda: adotar o card expandido é mudança de produto, e o merge não é hora de mudar produto. | A4 C-1 |
| 18 | RISCO | `dashboard/helper/actionCable.js:144` | Chama um `computed` ref como se fosse função. | A4 C-2 |
| 19 | **PERDA** | sidebar, Captain, preview de mensagem restrita, busca compacta, `ReplyTopPanel`, dropdowns de ação em massa | Seis perdas de customização ChatSPX no dashboard, cada uma com patch pronto no relatório: persistência do estado de subgrupo da sidebar (C-3), card de documento do Captain e visualizador (C-4), preview de mensagem restrita perdeu o texto (C-5), item compacto do resultado de busca (C-6), prop `isCopilotActive` do `ReplyTopPanel` (C-7), skin WhatsApp dos três dropdowns de ação em massa (C-10). | A4 C-3…C-7, C-10 |
| 20 | RISCO leve | modal de nova conversa · `MentionBox.vue` | Responsividade mobile (C-8) e `::v-deep` depreciado (C-9). Baratos; aplicar junto. | A4 C-8, C-9 |
| 21 | RISCO | `config/features.yml` | `quoted_email_reply` virou flag morto e **ainda ocupa um bit** da coluna cheia. | A4 A4-9 |
| 23 | **P0 — excluir conversa não exclui, e a API responde 200 OK** | `app/services/conversations/delete_service.rb` **+** migration nova de FK | O `Conversations::DeleteService` é **novo do upstream** e chama o **nosso** `DeleteObjectJob` com a assinatura antiga: `perform_later(conversation, user, ip)` — 3 objetos, quando o job espera `(object_type, object_id, user_id, ip)` com strings/ids. `ALLOWED_OBJECT_TYPES.include?(#<Conversation>)` compara `String == Conversation` → `false` → `return` na primeira linha. **O job termina com sucesso, sem exceção e sem log.** Os outros 7 chamadores estão certos. Correção (a): `perform_later(conversation.class.name, conversation.id, user&.id, ip)`. **Correção (b), obrigatória junto:** a FK sem cascade de `flow_runs`/`flow_step_logs` — sem ela, o `destroy!` volta a rodar e levanta `InvalidForeignKey` **num job com retry**, trocando "some em silêncio" por "falha em loop no GlitchTip". Aceite com mecanismo: `DeleteService#perform` + `perform_enqueued_jobs` + `expect(Conversation.exists?(c.id)).to be false` — hoje falha. | A6 §1.1 |
| 24 | **RISCO (armadilha de flag)** | `app/services/conversations/unread_counts/filtered_counter.rb:182` | O arquivo é **novo do upstream** e faz `.joins(:messages)`. Mas o nosso `Conversation` declara `has_many :messages` com scope **instance-dependent** (`conversation.rb:168`, para o `team_message_isolation`), e o Rails **proíbe** join em associação instance-dependent: `ArgumentError: association scope 'messages' is instance dependent`. **41 falhas de spec.** Não é risco em produção hoje — `conversation_unread_counts` e `unread_count_for_filters` estão `enabled: false` em `feature_flags_ext_1` (coluna nova, todas as contas em 0) e o caminho é gated por `feature_enabled?`. **É armadilha:** o dia em que alguém ligar a flag numa conta com isolamento por time, vira 500. Correção barata e que não toca o nosso modelo: trocar o `.joins(:messages)` por um JOIN explícito em `messages.conversation_id`. | T2 §5b padrão 2 |
| 25 | RISCO (documentado, **não corrigir**) | `lib/integrations/openai/key_validator.rb` (novo) + `app/models/integrations/hook.rb` (+70 linhas) | O upstream passou a validar a chave OpenAI **na gravação do hook**, batendo em `api.openai.com`. Nos specs isso vira **51 × `WebMock::NetConnectNotAllowedError`** — e o baseline, no mesmo ambiente e sem `.env`, teve **0**, o que prova que é do merge e não do ambiente. **Conferido pelo coordenador: a validação É guardada** — `hook.rb:111-113` só a dispara em `new_record? || openai_api_key_changed? || will_save_change_to_status?`. Não roda em todo save. Então **não se reverte**: é design razoável do upstream. O que fica registrado é que criar/trocar a chave de uma integração OpenAI passa a bloquear por até **5s** (timeout do Faraday) e a falhar se a rede estiver fora, e que isso é a mesma família do item 8 (o job que apaga o hook quando a chave devolve 401). | T2 §5b padrão 1 |
| 26 | **P0 — abrir "Editar" numa integração e salvar APAGA a credencial** | `app/views/api/v1/models/_hook.json.jbuilder` (upstream) × `EditHook.vue` (nosso) × `HooksController#update` | Defeito de **combinação**: o upstream passou a filtrar `settings` por `visible_properties` no jbuilder (correto isolado); o nosso `EditHook.vue` repopula o form daquele campo e reenvia tudo; o controller **sobrescreve** o jsonb. Nenhum lado está errado sozinho — e por isso passa por todo teste verde. **6 integrações / 14 chaves**: `openai.api_key`, `dialogflow.credentials`, `google_translate.credentials`, `meta_lead_ads.{app_secret,page_access_token,verify_token}`, `leadsquared.secret_key`, `dyte.api_token`. Correção recomendada: `update` faz **merge** do settings (protege também quem chama a API direto), e/ou o front não reenvia chave que não recebeu. **NÃO desfazer o filtro do jbuilder** — não devolver segredo no JSON é a parte certa. Exposição nesta VM: **1 hook openai habilitado**. | A7 P0 |
| 27 | P1 (i18n, chega no cliente do cliente) | `config/application.rb:62` + templates de e-mail EE × CE | O e-mail de confirmação/convite sai em **inglês** e com marca **"Chatwoot"**: o `unshift` de `enterprise/app/views` no view path faz o template EE (16 marcadores en, 0 pt) vencer o CE em pt-BR (37 pt, 1 en). **Não é regressão do merge** — mas o merge triplicou o texto no arquivo que não roda. pt-BR é prioridade desta casa. | A7 P1 |
| 22 | **RISCO (mudança de produto disfarçada de merge)** | `config/features.yml` + `db/migrate/20260409091202_enable_assignment_v2_for_new_accounts.rb` | O merge trocou `assignment_v2` de `enabled: false` (nosso, deliberado) para `enabled: true`, e a migration liga o flag no `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. Efeito: **toda conta nova nasce com o motor de atribuição v2**, e — por causa do auto-sync em `enterprise/app/models/enterprise/account.rb:119-123` — também com `advanced_assignment` (que só agora virou gravável). **DECISÃO DO COORDENADOR: voltar para `false` e neutralizar a migration.** Razão: o trabalho do merge é trazer o upstream **sem mudar o produto**. Adotar o motor v2 como padrão é uma decisão de produto legítima — mas ela se toma de propósito, com quem decide produto, e não como efeito colateral de um merge. Registrada como decisão disponível, não como pendência. | A2 §2.7 |
| 23 | **RISCO ALTO (latente, mas quebra na hora que ligarem)** | `app/services/conversations/unread_counts/filtered_counter.rb:182` | `.joins(:messages)` é **incompatível** com o nosso `has_many :messages` *instance-dependent* (`conversation.rb:168`, o lambda do `team_message_isolation`, que já existia no baseline). Rails levanta `ArgumentError: association scope 'messages' is instance dependent` — **41 falhas de spec**. Hoje é latente: `unread_count_for_filters` e `conversation_unread_counts` estão `enabled: false` e o counter só roda atrás do flag, então nenhuma conta da frota executa isso. Mas no dia em que alguém ligar para um cliente, levanta. **Correção: trocar o `joins(:messages)` por subconsulta em `Message`** (`where(id: Message.incoming.where(...).select(:conversation_id))` ou equivalente), preservando o nosso scope. NÃO remover o scope instance-dependent — ele é o isolamento por time. | T2 DoD §5b padrão 2 |
| 24 | **RISCO ALTO (frota, produção)** | `app/models/integrations/hook.rb:32,111` + `lib/integrations/openai/key_validator.rb` | Arquivos **novos do upstream** (`KeyValidator` não existe em `f26db6ee81`). O `Hook` passou a validar a chave por **HTTP síncrono dentro do `save`** (`validate :validate_openai_api_key`, disparando em `new_record?`, chave alterada ou mudança de status): um `GET {api_base}/v1/models` com timeout de 5s. O `rescue Faraday::Error → true` faz fail-open em erro de rede, **mas 401 devolve `false` e o save é REJEITADO**. Numa VM cujo `CAPTAIN_OPEN_AI_ENDPOINT` aponta para gateway que só libera `/chat/completions`, **o admin não consegue salvar uma chave válida**. É a mesma raiz do item 8, em outro lugar. **Correção: fail-open também no 401 quando houver endpoint customizado configurado** — não se pode assumir que gateway de terceiro implementa `/models`. | coordenador, a partir de T2 DoD §5b padrão 1 |
| 25 | RISCO (suíte) | specs que batem em `api.openai.com` | **51 falhas** de `WebMock::NetConnectNotAllowedError`, e o baseline tinha **0** — certificado rodando os mesmos specs em `f26db6ee81` com o mesmo ambiente. É consequência direta do item 24: o código novo faz chamada real. Stub do `KeyValidator` no `spec/` resolve a suíte; o item 24 resolve a causa. Fazer os dois, nesta ordem. | T2 DoD §5b |
| 24 | **RISCO de CUSTO na frota inteira** | `lib/llm/feature_router.rb` (`CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'`) | O merge passou a **forçar** `gpt-5.2` em toda conta com `captain_integration_v2` sem escolha explícita de modelo — e esse flag é ligado em `enable_default_features` para toda conta self-hosted enterprise (`enterprise/app/models/enterprise/account.rb:111`), isto é, **a frota**. Nosso fork nunca forçou modelo por flag: valia `account.captain_models['assistant']` ou o default do `llm.yml`. Efeito medido: `credit_multiplier` **3** contra **1** do `gpt-5-mini` — toda chamada do assistente ficou 3× mais caro sem ninguém decidir. **Neutralizar o forçamento** (restaurar escolha da conta → default do `llm.yml`). Autorizado a reescrever os asserts de `agentable_spec.rb:185`, `preferences_controller_spec.rb:128,144` e `super_admin/accounts_controller_spec.rb:77`, com comentário em cada um. | escalação do C1, decidida pelo coordenador |
| 26 | **DADO / integridade — o pior achado da onda** | `app/services/conversations/delete_service.rb` (novo do upstream) | **Excluir conversa não exclui, e a API responde `200 OK`.** O service novo do upstream chama um job NOSSO com a assinatura antiga. Não levanta exceção, não vai para o GlitchTip: o usuário clica em excluir, recebe sucesso, e a conversa continua lá. Correção de uma linha — **mas tem de ir junto com a FK de `flow_runs`**, senão troca-se "some em silêncio" por "falha em loop" (é o caso já conhecido de FK sem cascade travando `conversation.destroy!`). | A6 §1.1 |
| 27 | **RISCO ALTO (frota, silencioso)** | `.env` de cada VM | Sem `FB_APP_SECRET`/`INSTAGRAM_APP_SECRET`, **Instagram para de receber webhook**; e o WhatsApp Cloud **descarta mensagem** quando o canal não é resolvido pelo payload. Os dois respondem `401` — **nada no GlitchTip, nada no log de aplicação**. Mensagem de cliente sumindo sem rastro é o pior modo de falha possível num produto de atendimento. | A6 §1.2, §1.3 |
| 28 | **amplia o item 2** | `lib/safe_fetch.rb` | `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=false` não derruba só webhook interno: derruba também as **tools HTTP do Captain** — a porta pela qual os agentes de IA falam com os sistemas do cliente. O item 2 subestimava o alcance. | A6 §1.4 |
| 29 | RISCO (produto) | criação de conta | Criar conta **renomeia a conta sozinha** com o `<title>` scrapeado do domínio do e-mail do admin. É comportamento de SaaS público que não deveria existir em self-hosted white-label. | A6 §1.5 |
| — | — | — | *(fecha a lista; os RISCOs de deploy de A2 §2.4–§2.9 e o checklist de `.env` de A6 §2 viram checklist de pré-deploy no relatório da onda, não correção de código)* | |

> **Nota sobre os itens 3–5:** os três são do bloco **0.3** (reconciliação do build), não do 0.2.
> Ficam registrados aqui para não se perderem, e o despacho do 0.3 já aponta para o relatório A3.

## Já DESCARTADOS (investigados e improcedentes)

| Suspeita inicial | Veredito | Por quê |
|---|---|---|
| Realocação de `conversation_required_attributes` / `advanced_assignment` para `feature_flags_ext_1` perderia estado da frota | **improcedente** | Em `f26db6ee81` esses flags eram os bits 64 e 65 da coluna `feature_flags`, cujas máscaras (`1<<63` e `1<<64`) **excedem o `bigint`** da coluna. Nunca foram graváveis — não há estado a preservar. (A2 §1.3) |
| As 6 migrations `repurpose_*` do upstream apagariam features vivas do fork (bits 29 e 39 = `message_sequences` e `ai_assistant_v2`) | **já neutralizado pelo merge** | As 6 foram conferidas uma a uma: o loop `disable_features` em massa foi removido em todas; duas mantêm só a limpeza do `InstallationConfig`, que é correta e previne `NoMethodError` na criação de conta nova. (A2 §1.2) |

---

## Correções do HARNESS (bloco 0.1) — não são do merge, mas protegem a régua de tudo

Descobertas durante a própria execução da Onda 0, as duas por falha real observada.

| # | Gravidade | O que | Evidência | Correção |
|---|---|---|---|---|
| H1 | **ALTA — falso verde** | O readiness check do harness **não verifica identidade** do servidor que respondeu. Com as portas ocupadas por outro worktree, o Playwright viu o `/__ready` **de outro checkout** responder e seguiu em frente, testando contra um build que não era o dele. | Run do executor da DoD: servidores morreram com `EADDRINUSE`, 2 testes falharam com 404 no `sdk.js`, 17 com `CONNECTION_REFUSED`, e **zero** imagens `-actual`/`-diff` foram geradas — nenhum snapshot chegou a ser comparado. | `/__ready` passa a devolver um token único da execução; o teste só prossegue se o token bater. Um servidor velho de outro checkout deixa de satisfazer o check. |
| H2 | MÉDIA — flaky | 3 dos 16 falham em **cache frio** (`TimeoutError: page.goto 15000ms`), não por diff de pixel. Um baseline que só passa quente não é régua para revisar um merge de 558 arquivos. | Rodada 1 do executor do baseline: 13/16 frio, 16/16 quente. | Aquecer o servidor do widget em `globalSetup` antes do primeiro teste. **Aquecer, não aumentar timeout** — aumentar esconde o custo, aquecer o paga uma vez. |
| H3 | BAIXA — operacional | Portas **hardcoded** (3038 sdk / 3999 widget / 8899 host / 3040 hmr) com `reuseExistingServer: false` impedem que dois worktrees rodem o harness na mesma máquina. Custou uma serialização nesta onda. | Colisão observada entre `redesenho-base` e `redesenho-merge`. | Portas configuráveis por env **com os valores atuais como default**, para que o teste de contrato (o 17, que valida as portas) continue valendo sem override. Depende de H1 para ser seguro. |

> **Por que H1 é a mais grave dos três achados desta onda inteira, incluindo os do merge:** os
> outros defeitos produzem erro. Este produz **verde**. Uma suíte que mede o código errado e
> reporta sucesso é a única falha que não aparece em lugar nenhum — e é ela que estaria
> certificando os 16 snapshots que servem de régua para as seis ondas seguintes.

### H4 — o aceite do bloco 0.11 passa, mas a regra MUST do §10.3 é mais ampla que ele

Medido pelo coordenador, com o mecanismo que o próprio aceite nomeia:

```
$ grep -rn "from '@playwright/test'" spec/e2e/widget/     → vazio  ✅ (aceite do 0.11: PASS)
```

O único arquivo de `spec/e2e/widget/` que importa `@playwright/test` é
`sabotage.playwright.config.js` — e é um arquivo de **configuração**, que precisa de
`defineConfig`. Não é spec e não viola nada.

Só que a regra MUST do §10.3 não diz "widget", diz **"todo teste E2E usa o fixture anti-erro —
nunca `@playwright/test` direto"**. E as duas suítes que já existiam não a cumprem:

```
$ grep -rn "@playwright/test" spec/e2e/copilot/ spec/e2e/resolve-gate/
spec/e2e/copilot/*.spec.js   → 10+ arquivos importam direto
```

**Isto NÃO reprova o bloco 0.11**, cujo aceite nomeia `spec/e2e/widget/` e só. Fica registrado
como decisão consciente, com o custo à vista: migrar `copilot/` e `resolve-gate/` para o fixture
provavelmente as deixa **vermelhas no primeiro dia**, porque foram escritas sem essa restrição e
o dashboard emite erro de console que ninguém tratou. Isso é trabalho de verdade, não uma linha
de import — e é escopo que o plano não pediu na Onda 0.

Recomendação: fazer quando alguém for mexer nessas suítes de qualquer jeito, e não antes. O que
não pode acontecer é a frase *"todo E2E usa o fixture"* seguir escrita no §10.3 como se fosse
verdade — hoje ela vale para 1 das 3 suítes.

### H5 — a causa raiz do item 9 do bloco 0.2, provada por medição direta

O aceite do 0.2 — *"os 16 snapshots revisados um a um"* — **não pôde ser medido**, e a razão não é
o baseline nem colisão entre executores. O executor da DoD mediu com portas exclusivamente suas,
depois que a colisão já tinha passado, e o resultado foi idêntico. Prova por `curl` contra o
próprio sdk-server dele:

```
GET /__ready                                  → 200
GET /app/javascript/entrypoints/sdk.js        → 404      ← a URL que o harness usa
GET /entrypoints/sdk.js                       → 200      ← o root foi reescrito
```

O merge tomou o `vite.config.ts` do upstream por inteiro e perdeu o branch de teste do fork:

```
f26db6ee81:vite.config.ts:27   const isTestMode = process.env.TEST === 'true';
f26db6ee81:vite.config.ts:41   } else if (isTestMode) {      // plugins só [vue()], sem ruby()
```

Sem ele, o `vite-plugin-ruby` entra também em modo de teste e reescreve o `root` para
`app/javascript`; a URL que `spec/e2e/widget/harness/host-server.mjs:72` traz cravada deixa de
existir. Resultado: **19 failed / 1 passed, zero imagens `-actual`/`-diff`, 0 dos 16 comparados**.

**Consequência de ordem, e ela contraria o plano:** o PLANO-MESTRE declara `0.3` como dependente de
`0.2`. Na prática, **verificar o aceite de `0.2` depende de `0.3`**. A dependência se inverteu
porque o merge quebrou o caminho de build de que a régua depende — algo que o plano não tinha como
prever. Decisão do coordenador: `0.3` foi despachado **antes** de `0.2` fechar, sozinho no worktree
do merge, com escopo restrito a `vite*.ts`.

**Distinção que o relatório precisa preservar:** existe regressão do merge, e ela é **no build**,
não nos snapshots. Nenhum dos 16 foi observado. Dizer "os snapshots falharam" seria inventar um
veredito que ninguém pôde medir.

### H6 — dívida de tradução herdada do merge (não bloqueia)

A auditoria do dashboard mediu o i18n inteiro: **0 chaves nossas destruídas**, 0 locales perdidos,
e as 11 chaves perdidas foram todas removidas de propósito pelo upstream. Mas o merge trouxe
**95 chaves novas sem `pt_BR`**. Não é perda e não bloqueia a onda; é dívida, e pt-BR é prioridade
desta casa. Vai para o relatório da onda como trabalho conhecido, com o número à vista.

---

## Bloco A6 — o quarto vetor cego: arquivos que **só o upstream** mudou

A triagem por colisão (558 arquivos) é, por construção, cega para o que o upstream mudou sem
conflitar conosco. A auditoria A6 cobriu esse vetor no backend — **645 arquivos**, 311 novos e 334
modificados — e achou três P0 que **passariam para produção sem gerar uma única exceção**. Nenhum
deles apareceria em teste, log ou GlitchTip.

| # | Gravidade | Onde | O que fazer | Fonte |
|---|---|---|---|---|
| 17 | **P0 · PERDA + DADO** | `app/services/conversations/delete_service.rb` (novo, upstream) | **Excluir conversa não exclui, e a API responde `200 OK`.** O service novo chama `DeleteObjectJob.perform_later(conversation, user, ip)` — 3 **objetos**. Nosso job (hardening `87095e111b`, que sobreviveu ao merge) tem assinatura `(object_type, object_id, user_id, ip)` — 4 args, **strings/ids** — e a primeira linha é `return unless ALLOWED_OBJECT_TYPES.include?(object_type)`. Comparar `String == Conversation` dá `false`, o job retorna `nil` e **nada acontece**: sem exceção, sem log. O front some com a conversa, o reload a traz de volta. Corrigir a chamada do service para a nossa assinatura. | A6 §1.1 |
| 18 | **P0 · PERDA** | Instagram / Messenger | Todo webhook passa a exigir assinatura HMAC → **401 em 100% dos webhooks**, silencioso. Exige `FB_APP_SECRET` e `INSTAGRAM_APP_SECRET` no `.env` de toda VM com canal IG/Messenger. | A6 §1.2, §2 |
| 19 | **P0 · PERDA** | WhatsApp Cloud (`source: embedded_signup`) | 401 nos webhooks quando o canal não é resolvido. Exige `WHATSAPP_APP_SECRET`. | A6 §1.3, §2 |
| 20 | **P0 · RISCO (alcance maior que o item 2)** | `lib/safe_fetch.rb:39` | O `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=false` não quebra só webhook: quebra também a **tool HTTP do Captain para IP privado** e **avatar em storage interno**. `=true` em toda VM. | A6 §1.4 |
| 21 | **DADO** | `app/jobs/account/branding_enrichment_job.rb` + `accounts_controller.rb:37-46` | **Criar conta renomeia a conta sozinha.** O job é enfileirado incondicionalmente no `create` (inclusive pelo "adicionar conta" do dashboard), faz `SafeFetch` no domínio do e-mail do admin, faz scrape do `<title>` e **sobrescreve o nome digitado** — sem guarda de "só se estiver em branco". Criar "Cliente Fulano" com admin `@gmail.com` dispara request a `https://gmail.com`. É fluxo de onboarding do Chatwoot Cloud que a frota não usa: **desligar o enfileiramento**. | A6 §1.5 |

### Verificação de uma linha no primeiro deploy (não é código)

`config/initializers/sidekiq.rb` passou a usar `load_from_hash!(source: 'schedule')`, que **remove
do Redis** cron com esse source que não esteja mais no YAML. A6 investigou e **descartou** o risco
(o ChatSPX não registra cron fora do `schedule.yml`, e os três nossos sobreviveram ao diff:
`conversations_orphan_watch_job`, refresh de grupos WAHA e purge de bulk media). Mesmo assim:
depois do primeiro deploy, conferir em `/sidekiq/cron` que os três seguem listados. É o tipo de
coisa que só se vê uma vez.

---

## Da DoD (T2 §5b) — duas regressões que a suíte Ruby expôs, com delta certificado

O executor da DoD rodou os specs de maior concentração de falha **também no `f26db6ee81`**, em
worktree descartável e banco próprio, para não classificar por palpite: **+60 falhas em 169
exemplos** são atribuíveis ao merge. Duas causas raiz, e as duas mordem fora do teste.

| # | Gravidade | Onde | O que fazer | Fonte |
|---|---|---|---|---|
| 22 | **P0 · RISCO em produção** | `app/services/conversations/unread_counts/filtered_counter.rb:182` (novo, upstream) × `app/models/conversation.rb:168` (nosso) | **41 falhas com `ArgumentError: association scope 'messages' is instance dependent`.** O upstream faz `.joins(:messages)`; o fork declara `has_many :messages` com **scope dependente da instância** (o lambda recebe a conversa) para o `team_message_isolation`. O Rails não monta JOIN de associação assim → exceção **em runtime**, não só em teste. Nenhum dos dois lados está errado sozinho: **o defeito nasceu do merge**, que juntou a feature nova com a customização antiga sem reconciliá-las. Reconciliar — sem abrir mão do isolamento por time, que é requisito de privacidade nosso. | T2 §5b padrão 2 |
| 23 | **RISCO em produção** | `app/models/integrations/hook.rb` (+70 linhas do upstream) + `lib/integrations/openai/key_validator.rb` (novo) | **51 falhas de `WebMock::NetConnectNotAllowedError` para `api.openai.com`** — e o baseline teve **0**, então não é ambiente. A causa é `validate :validate_openai_api_key`, que faz **requisição HTTP síncrona de até 5s dentro de uma validação de ActiveRecord**. Fora do teste: salvar um hook do OpenAI passa a bloquear por até 5s. Pior, o `rescue` devolve `true` — erro de rede faz a chave ser considerada **válida**. Tirar a chamada de rede do ciclo de validação. | T2 §5b padrão 1 |

> **Sobre os 219 totais:** 110 estão medidos contra o baseline (delta +60); as outras 109 **não
> foram medidas** e o executor se recusou, corretamente, a extrapolar. Entre elas há 33 de
> `Status cannot be Pending — feature disabled for this inbox`, que são validação do fork contra
> specs do upstream, e 3 de `InvalidForeignKey` que casam com o defeito de FK sem cascade que já
> conhecíamos. Fechar a atribuição das 109 é trabalho de quem for aplicar as correções, não
> pré-requisito do 0.2.

### Verificações declaradas em aberto no bloco 0.3 (não são defeitos — são aceites não executados em navegador)

O executor do 0.3 restaurou as três customizações perdidas e **provou presença** das três por grep e
por build. Duas delas, porém, têm aceite que só fecha de verdade em navegador logado, e ele declarou
isso em vez de afirmar que estava OK:

| Customização restaurada | Aceite que fecharia | Estado |
|---|---|---|
| §C2 `optimizeDeps` do canvas de Automações | abrir o canvas com `vite dev` e ver o grafo carregar | **não executado** — exigiria o Puma de homologação da :3000 |
| §C3 `resolve.dedupe: ['html2pdf.js']` | exportar um PDF de relatório em navegador logado | **não executado** — idem |
| §C1 `lord-icon` custom element | ícone animado renderiza | coberto indiretamente: o `resolveComponent` saiu do `dashboard.js`, o que é a assinatura da correção |

Por que ficou assim, e por que está certo: validar os dois exigiria subir um segundo Puma servindo a
branch do merge (a :3000 serve o código de homologação, não o nosso). É trabalho de verdade, não é
escopo do 0.3, e o risco é baixo — são **restaurações** de código que já existia e cuja presença foi
provada. Fica registrado para quem for validar a branch em navegador antes de qualquer promoção.

---

## Débitos herdados do merge que NÃO entram nesta lista, e por quê

Registrados para não voltarem como surpresa. Nenhum é regressão de bloco nenhum desta onda —
todos vieram no merge e ficam declarados em vez de silenciados.

| O que | Onde aparece | Por que fica fora da lista |
|---|---|---|
| `[css-syntax-error] Unexpected "button"` em `.conversations-list [role=button]button` | aviso do `bin/vite build` | veio do upstream; o build **passa**, gera as 8 entradas e o CSS sai. É dívida de seletor inválido, não defeito funcional. Corrigir aqui misturaria escopo com o `0.2` |
| `AudioRecorder.vue` importado **dinâmica e estaticamente** | aviso do `bin/vite build` | mesmo caso; o efeito é chunk maior, e o gate que mediria isso é o **0.5**, que ainda não rodou |
| `swagger/swagger.json`: 353 → 90 paths | `git diff` do merge | agravante real: o pipeline que gerava os 353 (`assemble.rb` + `specs.json`) **nunca foi versionado**, então `rake swagger:build` não os reproduz. Reconstruir a doc da API é trabalho próprio, com dono e prazo — não cabe como correção de merge |
| `optimizeDeps` do canvas de Automações **não provado na tela** | `onda-0-bloco-0.3.md` §12.2 | o patch está provado na camada onde o bug vivia (pré-bundle do dev server), mas ninguém abriu o canvas num browser logado. Exigiria Rails + login, e o Puma da :3000 é homologação em uso |
| `resolve.dedupe: ['html2pdf.js']` **não provado ponta a ponta** | `onda-0-bloco-0.3.md` §12.3 | hoje o store pnpm tem **uma única** cópia de `html2pdf.js` (0.10.3), então a diretiva não tem duplicata para colapsar e não muda o bundle. É trava preventiva correta; a exportação real de PDF não foi testada |
| 109 das 219 falhas de `rspec` **sem atribuição** | `onda-0-dod-merge.md` §5b | 110 estão medidas contra o baseline (delta +60). As outras 109 não foram medidas, e o executor se recusou a extrapolar — corretamente. Fechar a atribuição é trabalho de quem aplica as correções, não pré-requisito do `0.2` |

## Decisões abertas para o dono do produto (nenhuma bloqueia a onda)

Todas seguem a mesma regra: **a direção escolhida foi a reversível e a mais barata.** Se o dono do
produto preferir a outra, cada uma custa uma linha.

| Decisão | O que foi feito por ora | O que a outra opção custa |
|---|---|---|
| Adotar `gpt-5.2` como default do assistente do Captain v2 na frota | **Não.** Forçamento neutralizado; vale a escolha da conta e, na falta dela, o default do `llm.yml` (`gpt-5-mini`) | `credit_multiplier` **3** contra **1** — 3× por chamada, em toda a frota |
| Default de `conversation_faq_generation` e `help_center_article_generation` | **Mantido o do upstream** (`gpt-5.2`) — são features **novas**, não há default nosso a restaurar | as duas nascem 3× mais caras por chamada |
| Adotar a política de handoff do upstream | **Não.** Restaurada a nossa descrição em pt-BR | a do upstream é mais restritiva ("only when…") e faz lead qualificado não chegar ao humano — foi o motivo de termos mudado |
| Temperatura default 0.5 (upstream) | **Não.** Restaurado 0.0 | menos determinismo nas respostas do Captain |
| Adotar o fluxo novo de FAQ (`captain_faq_suggestions`) | **Sim** — o front já migrou inteiro e coerentemente (rota antiga redireciona) | manter o fluxo velho exigiria reverter tela, enum e modelo |
| Título do portal: `display_title` (upstream) vs `SPX - CHAT` fixo | **Mantido `display_title`** | cravar a nossa marca no Help Center do cliente, num produto white-label |
| Migrar `copilot/` e `resolve-gate/` para o fixture anti-erro | **Não** — escopo que o plano não pediu na Onda 0 | provavelmente as deixa vermelhas no dia 1; é trabalho real, não um import |

---

## Dívida de i18n que o merge criou — medida pelo coordenador, fora do escopo da onda

Conferindo o aceite do bloco 0.8 pelo mecanismo que ele nomeia (§11.6: o coordenador roda o
comando, não lê o relatório), medi a paridade de chaves de `inboxMgmt.json` nos três estados:

| estado | `en` | `pt_BR` | só em `en` | só em `pt_BR` |
|---|---:|---:|---:|---:|
| pré-merge (`f26db6ee81`) | 764 | 801 | **0** | **37** ← o defeito que o 0.8 existe para corrigir |
| pós-merge, antes do 0.8 (`6ad7a9ec6e`) | 876 | 869 | **46** | 39 |
| depois do 0.8 (`c172432f34`) | 913 | 867 | **46** | **0** ✅ |

**O bloco 0.8 fechou o que lhe cabia**, e fechou inteiro: as 37 chaves `NPS.*` que faltavam em `en`
(o painel em inglês mostrando chave crua) viraram **zero**. A queda de 869 → 867 em `pt_BR` são as
2 chaves órfãs que o bloco **0.7** removeu de propósito.

**O que sobrou é dívida do merge, não do bloco:** **46 chaves que o upstream trouxe só em `en`**.
O efeito não é chave crua na tela — o `vue-i18n` cai para `en` —, é **o painel do cliente brasileiro
mostrando 46 textos em inglês**. Isso encosta na regra permanente da casa (*"toda string nova entra
em `pt_BR` e em `en`"*, e pt-BR é prioridade), mas as strings não são nossas: são do upstream.

**Não despachei tradução, e a razão é escopo, não tamanho.** A Onda 0 não tem bloco de i18n de
chave do upstream, e criar um por conta própria é a forma mais educada de crescer escopo. Fica como
**decisão para o dono do produto**, com o custo à vista: são 46 strings, um executor, e não bloqueia
nada. A lista exata sai com o comando acima trocando o `print` pelo conjunto `en - pt_BR`.

---

## Decisão do coordenador sobre o gate do 0.5 — e por que "apertar demais" também é errado

O executor do 0.5 mediu **422.599 B gzip de JS eager** no grafo do widget e perguntou se commitava
o gate **vermelho**, com o CI vermelho junto, "sem afrouxar". A resposta foi **não**, e a razão não
é conforto:

O aceite do 0.5 na §2.2 nomeia **duas** condições de falha — `leaflet-*.js` voltando aos imports
estáticos, e o `sdk.js` passando de 15 KB gzip / 40 KB crus — e trata o grafo como **`Reporta`**,
não como falha. A §4, item 4 da Onda 0, diz o mesmo: *"reporta o grafo (~575 KiB hoje), não o chunk
de entrada"*. O teto de 300 kB do `size-limit` sempre mediu o **chunk de entrada** (76,53 kB);
aplicá-lo ao grafo é comparar coisas diferentes.

**Inventar uma condição de falha que o aceite não pede é tão ruim quanto remover uma que existe.**
Nos dois casos o gate deixa de dizer o que foi combinado que ele diria.

O que ficou decidido:

| item | decisão |
|---|---|
| o grafo | **reportado em destaque**, com o número medido — é o retrato honesto que o plano quis produzir |
| `leaflet-*.js` estático | **falha**, como o aceite manda |
| `sdk.js` acima de 15 KB gzip / 40 KB crus | **falha**, com delta em bytes contra `29.014 / 9.595` |
| teto do grafo | teto de **regressão** no valor **medido hoje** — nasce verde e fica vermelho no instante em que crescer |
| o alvo real | comentado no próprio script: é o bloco **1.08** (CSS ≤ 80 KB crus, hoje 1.692.256 B) |

**Por que teto de regressão e não teto de alvo:** um gate que nasce vermelho é vermelho para sempre
até alguém fazer o trabalho do 1.08 — e vermelho permanente vira ruído, e ruído faz gate ser
ignorado. O teto de regressão morde **hoje**, contra o crescimento que os blocos das ondas 1 a 6 vão
tentar introduzir, que é exatamente para isso que o gate existe agora.

E as três sabotagens continuam obrigatórias: leaflet estático → vermelho; `sdk.js` inflado →
vermelho com delta; grafo crescido → vermelho. Depois desfaz as três e mostra verde.

---

## Débito estrutural que o 0.3 levantou, e que vale mais que o próprio bloco

> **Nada protege o `isTestMode` contra o próximo merge do upstream.**

Quando o branch `isTestMode` desaparece do `vite.config.ts` — que foi exatamente o que este merge
fez —, o **build continua VERDE**, porque `ruby()` é o plugin correto em produção. O defeito só
aparece no harness, como 404 no SDK, e só se alguém rodar o harness. Esta onda pagou esse preço:
duas rodadas de medição inteiras foram perdidas antes de a causa aparecer, e o bloco 0.3 teve de ser
promovido a pré-requisito do 0.2 no meio do caminho.

O próximo merge do upstream vai reintroduzir isso, porque o upstream não tem esse branch e não vai
passar a ter. **A proteção que falta é um teste que falhe quando o caminho de teste quebrar** — e
ele é barato: subir o `sdk-server.mjs` e exigir `200` em `/app/javascript/entrypoints/sdk.js` é uma
asserção, não uma suíte. Registrado aqui como trabalho com dono a definir, não como parte do 0.3.

---

## Conferência do coordenador na correção de maior risco (§11.6)

A regra da §11.6 diz que quem fecha a tarefa é o coordenador, rodando **o mecanismo que o aceite
nomeia** — não lendo o relatório do executor. A correção do item 1 (a migration que ia apagar FAQ
pendente) é a de maior consequência da onda: se o `INSERT` não casar com o schema, ela **explode no
`db:migrate` da frota inteira**, e aí o remédio vira pior que a doença.

Conferido diretamente contra `db/schema.rb`:

| tabela | colunas no `INSERT` | colunas no schema | bate? |
|---|---|---|---|
| `captain_faq_suggestions` | question, answer, embedding, assistant_id, account_id, language, source_count, status, created_at, updated_at | as mesmas 10 | **sim** |
| `captain_faq_observations` | account_id, conversation_id, faq_suggestion_id, generated_question, generated_answer, language, status, created_at, updated_at | as mesmas 9 | **sim** |

E o executor acrescentou algo que ninguém pediu e que é a diferença entre funcionar e falhar no meio:
`SELECT DISTINCT ON (r.assistant_id, r.question, r.answer)`. Sem isso, duas respostas pendentes
idênticas gerariam duas linhas em `captain_faq_suggestions`, e o `JOIN LATERAL` do segundo `INSERT`
— que casa exatamente por esses três campos — ficaria ambíguo.

Continua **não executada** contra banco: rodar a migration exige banco de teste preparado, e é parte
da DoD que o próprio executor roda ao fechar. O que esta conferência estabelece é que ela **não vai
falhar por schema** — que era o risco de fazer o remédio virar o problema.

### H5 — o `isTestMode` ESTÁ protegido contra o próximo merge, mas a falha não se explica

O handover da coordenação anterior registrou como débito aberto que *"nada protege o `isTestMode`
contra o próximo merge"*. **Conferi, e a premissa não se sustenta — está protegido.** O teste de
contrato do harness (`spec/e2e/widget/widget.spec.js:222`, *"carrega SDK, entrypoint e host reais
nas portas contratadas"*) faz `expect.poll` em `window.$chatwoot?.hasLoaded === true` com timeout
de 30s. Se o `isTestMode` sumir de novo, o SDK volta a dar 404, `hasLoaded` nunca vira `true` e
**este teste falha**. A regressão é pega.

O que o handover acertou é outra coisa, e ela continua de pé: **a falha não se explica sozinha.**
Ela aparece como um `poll` estourando em 30s, não como *"o SDK respondeu 404"*. Quem pegar esse
vermelho daqui a seis meses vai gastar o mesmo tempo que esta onda gastou para achar a causa —
duas medições inteiras.

**Correção proposta (barata, e é uma asserção, não uma suíte):** antes do poll, uma verificação
direta do status HTTP do entrypoint do SDK, nomeando-o na mensagem de falha. A linha seguinte
(`expect(resources).toContain(…/sdk.js)`) **não** serve para isso: um 404 também gera entrada em
`performance.getEntriesByType('resource')`, então ela prova que o recurso foi pedido, não que veio.

Fica como débito de **diagnosticabilidade**, não de cobertura — e é a diferença entre um gate que
morde e um gate que morde explicando.

