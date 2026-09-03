# W4 — Dependências, Infraestrutura, Performance e Segurança

**Escopo:** upstream Chatwoot `v4.12.1` (`899fce1c92`) → `v4.16.2` (+ `upstream/develop`, 03/08/2026).
**Fork:** ChatSPX, branch `homologacao`, HEAD `ee87f5e799`.
**Auditoria read-only** — nenhum arquivo fora desta pasta foi tocado.

---

## Sumário executivo

1. **Runtime não muda.** Ruby continua `3.4.4`, Node `24.13.0`, pnpm 10, Rails `7.1.5.2`, bundler `2.5.16`. Nenhum upgrade de runtime na frota é exigido pelo upstream.
2. **Estamos com 8 gems vulneráveis** que o upstream já corrigiu: `puma 6.4.3→7.2.1`, `loofah 2.23.1→2.25.2`, `rails-html-sanitizer 1.6.1→1.7.1`, `crass 1.0.6→1.0.7`, `msgpack 1.8.0→1.8.3` (CVE-2026-54522), `nokogiri 1.19.1→1.19.4`, `jwt 2.10.1→2.10.3`, `rack 3.2.5→3.2.6`. Bump de lockfile isolado, sem merge de código.
3. **3 buracos de SSRF abertos hoje no ChatSPX** (`upload_controller`, `avatar_from_url_job`, `webhooks/trigger`) — o upstream fechou os três com a lib `SafeFetch` + gem `ssrf_filter`. Nós **não temos nem a lib nem a gem**. O de upload é explorável por qualquer agente autenticado.
4. **4 falhas de autorização/vazamento confirmadas no nosso código**: custom attributes sem policy (agente escala privilégio), `access_token` de agent bot exposto a agentes, API keys de integração em texto puro na resposta da API, HMAC do widget comparado sem tempo constante.
5. **BOMBA-RELÓGIO — `config/features.yml`:** temos **65 features numa coluna bigint de 63 bits**, e reciclamos slots deprecated **diferentes** dos que o upstream reciclou. Um merge cru de `features.yml` **remapeia silenciosamente flags já persistidas** em todas as contas da frota. O upstream resolveu isso com `feature_flags_ext_1` + validação que **derruba o boot** se passar de 63.
6. **2 colisões exatas de timestamp de migration** (`20260616120000`, `20260630000000`) → `DuplicateMigrationVersionError` trava `db:migrate` na frota inteira.
7. **Performance:** 4 patches pequenos e isoláveis valem muito para contas grandes — deadlock de labels, N+1 em `inboxes#index`, plano ruim no sort "Pending Response" e índice novo em `messages`.
8. **Quebras operacionais se subirmos sem ajuste:** `api_and_webhooks` derruba toda API por token; `SafeFetch` bloqueia webhook para IP privado; `sidekiq-cron` 2.x muda a API do initializer; `rails-i18n` vira dependência obrigatória.
9. **Build:** `vite 5.4.21 → 6.4.2` (major) e o SDK deixa de usar `BUILD_MODE=library` e passa a `vite build --config vite.lib.config.ts`. Nosso `deploy.sh`/`setup_spx_24.04.sh` não quebram, mas o `NODE_OPTIONS=4096` continua abaixo do que já provou ser necessário aqui.
10. **Recomendação:** um "pacote mínimo obrigatório" (segurança + gems + travas de merge) cabe em ~2-3 dias sem merge de feature. O merge grande pode esperar; esse pacote não.

---

## Tabela de decisão

Legenda de esforço: **P** < 1 dia · **M** 1-3 dias · **G** > 3 dias.

### 🔴 OBRIGATÓRIO — Segurança

| # | Item | Origem | Exposto hoje? | Valor | Risco merge | Rec. | Esf. |
|---|---|---|---|---|---|---|---|
| S1 | SSRF no endpoint de upload (`external_url`) | `871f2f4d56` (#14012) | **SIM** | Alto | Baixo | TRAZER | P |
| S2 | SSRF no download de avatar por URL | `661608c0b1` (#14153, CW-6931) | **SIM** | Alto | Baixo | TRAZER | P |
| S3 | SSRF no webhook de automações/macros/agent bot | `c8e551820b` (#14155, CW-6940) | **SIM** | Alto | **Alto** | TRAZER ADAPTADO | M |
| S4 | Bypass de autorização em custom attribute definitions | `5c6ea78ce6` (#14392, CW-7038) | **SIM** | Alto | Baixo | TRAZER | P |
| S5 | `access_token` do agent bot exposto a agentes | `13db36609d` (#14830) | **SIM** | Alto | Baixo | TRAZER | P |
| S6 | Segredos de integração (OpenAI/Dialogflow/Linear) em texto puro na API | `27404b4a27` (#14147) | **SIM** | Alto | Médio | TRAZER | P |
| S7 | Comparação de HMAC do widget não é constant-time | `1e7218d439` (#14945) | **SIM** | Médio | Baixo | TRAZER | P |
| S8 | XSS/HTML injection nos embeds markdown do Help Center | `2192af80f4` (#14140, CW-6934) | **SIM** | Médio | Baixo | TRAZER | P |
| S9 | Bump de gems por advisory (8 gems) | `a61a8bfbc6` `9caceea858` `e4ef2de8c8` `7718f2a62c` | **SIM** | Alto | Baixo | TRAZER | P |
| S10 | Bump front: `dompurify 3.3.2→3.4.11`, `video.js 7.18.1→7.21.1` | `8d7e926e06` (#13973, Snyk) | **SIM** | Alto | Baixo | TRAZER | P |
| S11 | Cookie de sessão sem `secure`/`httponly` | `95d6aecb51` (#14248) | **SIM** | Médio | Baixo | TRAZER | P |
| S12 | Rack::Attack: bypass de throttle por barra final + rotas sem limite | `2663a8495d` `b02e732dd1` `160732c07d` `71fffdd2b9` | **SIM** | Médio | Médio | TRAZER ADAPTADO | P |
| S13 | Vazamento de internals do Postgres em erro de API | `eab859cd04` (#14933, CW-7538) | **SIM** | Baixo | Baixo | TRAZER | P |
| S14 | `ActiveStorage`: DoS por múltiplos byte-ranges + metadata forjada | `config/initializers/active_storage.rb` | **SIM** | Médio | Baixo | TRAZER | P |
| S15 | libvips restrito a loaders confiáveis (`VIPS_BLOCK_UNTRUSTED=1`) | `f5eb7a954d` (develop) | **SIM** | Médio | Nenhum | TRAZER | P |
| S16 | Impersonation cria `UserSession` visível + token de ~2 meses | `ba0ba46c9c` (#14622, CW-7169) | Parcial | Baixo | Alto | AVALIAR DEPOIS | M |
| S17 | Help Center: autor cross-account em artigos | `1b487f49d8` `651db39765` (develop) | **SIM** | Médio | Baixo | TRAZER | P |
| S18 | Custom roles API sem gate de feature | `94d7ccf5e9` (develop) | Provável | Baixo | Baixo | AVALIAR DEPOIS | P |
| S19 | Nome de time com caracteres de controle | `ce8c8e9a11` (#14865) | **SIM** | Baixo | Baixo | TRAZER | P |

### 🔴 OBRIGATÓRIO — Quebra operacional

| # | Item | Origem | O que quebra | Rec. | Esf. |
|---|---|---|---|---|---|
| B1 | `feature_flags` — 65 features em coluna de 63 bits + remapeamento de slots | `config/features.yml`, `20260706215758`, `Featurable` | Boot do app + flags erradas em toda a frota | TRAZER ADAPTADO (com migração de dados) | M |
| B2 | Colisão de timestamp de migration (2 pares) | `20260616120000`, `20260630000000` | `db:migrate` trava na frota | TRAZER ADAPTADO | P |
| B3 | `api_and_webhooks` obriga flag para toda API por token | `522e3c4d3f` (#14973) | **Toda integração por `api_access_token` retorna 403** | TRAZER ADAPTADO | P |
| B4 | `SafeFetch` bloqueia webhook para IP privado | `7c16071fc7` (#14548) | Agent bot/API inbox apontando pra rede interna param | TRAZER + `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` | P |
| B5 | `sidekiq-cron 1.12 → 2.4` + `load_from_hash!(source:)` | `Gemfile`, `config/initializers/sidekiq.rb` | `NoMethodError` no boot do Sidekiq se merjar initializer sem a gem | TRAZER (par indivisível) | P |
| B6 | `rails-i18n` vira dependência do `config.rails_i18n.enabled_modules` | `Gemfile`, `config/application.rb` | Boot quebra se merjar `application.rb` sem a gem | TRAZER (par indivisível) | P |
| B7 | `puma 6 → 7` (major) | `7718f2a62c` | Precisa revalidar `config/puma.rb` e o systemd da frota | TRAZER com teste | P |
| B8 | `schedule.yml`: remove `bulk_auto_assignment_job`, adiciona job horário | `1987ac3d97`, `config/schedule.yml` | Nossos 8 jobs custom sobrevivem, mas `load_from_hash!` limpa o Redis | TRAZER ADAPTADO | P |

### 🟡 OPCIONAL — Performance (alto retorno, baixo risco)

| # | Item | Origem | Valor | Risco | Rec. | Esf. |
|---|---|---|---|---|---|---|
| P1 | Deadlock em escrita paralela de labels (counter cache de tags) | `de0bd8e71b` (#14021, INF-68) | **Alto** | Baixo | TRAZER | P |
| P2 | N+1 em `inboxes#index` (3 queries por inbox) | `dd7f5c27e5` (#14451) | Alto | Baixo | TRAZER ADAPTADO | P |
| P3 | Plano ruim no sort "Pending Response: longest first" | `fed32d5964` (#14291) | Alto | Baixo | TRAZER | P |
| P4 | Índice `(sender_type, sender_id, created_at)` em `messages` | `20260630000000` | Médio | Baixo | TRAZER ADAPTADO | P |
| P5 | Timeout + skip de e-mail IMAP problemático | `52da165cb7` (#11981) | Médio | Baixo | TRAZER | P |
| P6 | Throttle de rebuild de contador de não-lidas | `848e94bcf2` (#14980) | Baixo | Alto | DESCARTAR | — |
| P7 | 3 COUNTs de `/meta` numa query só | `a901c87ab4` (#13536) | — | — | **JÁ TEMOS** (melhor) | — |
| P8 | Índice `conversations.created_at` com `if_not_exists` | `1e33bfd553` (develop) | Baixo | Baixo | AVALIAR DEPOIS | P |
| P9 | `Redis::Alfred#delete_if_equals` / `with_lock` / `pipelined` | `lib/redis/alfred.rb` | Baixo | Baixo | AVALIAR DEPOIS | P |

### 🟡 OPCIONAL — Build / CI

| # | Item | Origem | Valor | Risco | Rec. | Esf. |
|---|---|---|---|---|---|---|
| C1 | `vite 5.4.21 → 6.4.2` + split `vite.shared.ts`/`vite.lib.config.ts`/`vitest.config.ts` | `package.json`, `vite.config.ts` | Médio | **Alto** | AVALIAR DEPOIS | M |
| C2 | `turbolinks` → `@hotwired/turbo-rails` | `package.json` | Baixo | Médio | AVALIAR DEPOIS | P |
| C3 | `permissions: contents: read` nos workflows | `2dee7457cd` (#14358) | Baixo | Nenhum | TRAZER | P |
| C4 | `NODE_OPTIONS --max-old-space-size` continua 4096 | — | — | — | **JÁ TEMOS** (e insuficiente) | — |

---

## Detalhamento — itens Alto/Médio

### 1. STACK — o que muda de runtime

**Nada muda.** Confirmado arquivo a arquivo:

| | ChatSPX (HEAD) | Upstream v4.16.2 | Muda? |
|---|---|---|---|
| `.ruby-version` | `3.4.4` | `3.4.4` | Não |
| `.nvmrc` | `24.13.0` | `24.13.0` | Não |
| `package.json engines` | node `24.x`, pnpm `10.x` | idem | Não |
| `BUNDLED WITH` | `2.5.16` | `2.5.16` | Não |
| `rails` | `7.1.5.2` | `7.1.5.2` | Não |
| Postgres / Redis | sem exigência nova | — | Não |

`git diff 899fce1c92..v4.16.2 -- .ruby-version .nvmrc docker/Dockerfile` volta **vazio**. Não há upgrade de runtime obrigatório na frota. O único componente de infra com salto major é o **Puma (6→7)**, que é gem, não runtime.

**Gems onde estamos atrás — e por quê importa:**

| Gem | Nós | Upstream | Motivo |
|---|---|---|---|
| `puma` | 6.4.3 | **7.2.1** | advisories de segurança (`7718f2a62c`) |
| `loofah` | 2.23.1 | **2.25.2** | sanitizer HTML — base do `rails-html-sanitizer` |
| `rails-html-sanitizer` | 1.6.1 | **1.7.1** | idem |
| `crass` | 1.0.6 | **1.0.7** | parser CSS usado pelo sanitizer (`e4ef2de8c8`) |
| `msgpack` | 1.8.0 | **1.8.3** | **CVE-2026-54522** (`9caceea858`) |
| `nokogiri` | 1.19.1 | **1.19.4** | patches de libxml |
| `jwt` | 2.10.1 | **2.10.3** | pinado `~> 2.10, >= 2.10.3` pelo upstream |
| `rack` | 3.2.5 | **3.2.6** | — |
| `net-imap` | 0.4.20 | **0.6.4.1** | salto grande, ligado ao canal e-mail |
| `sidekiq-cron` | 1.12.0 | **2.4.0** | major — ver B5 |
| `ssrf_filter` | **ausente** | 1.5.0 | dependência do SafeFetch |

**Gems novas que o upstream introduziu** e que só entram se vier a feature correspondente: `gemoji`, `firecrawl-sdk`, `rails-i18n` (esta última é obrigatória se merjar `config/application.rb`).

**Front:** `dompurify 3.3.2 → 3.4.11` e `video.js 7.18.1 → 7.21.1` são bumps de segurança (o do video.js veio de alerta Snyk, PR #13973). `axios ^1.13.6 → ^1.15.0`.

> **Recomendação:** fazer um PR isolado só de `Gemfile.lock` + `package.json`/`pnpm-lock.yaml` com as gems/pacotes de advisory. Não depende de merge nenhum, roda em horas, e tira 10 vulnerabilidades conhecidas da frota. **Esforço P.**

---

### 2. SEGURANÇA — o item mais importante

#### S1 — SSRF no endpoint de upload · `TRAZER` · **exposto hoje**

- **A falha:** `app/controllers/api/v1/accounts/upload_controller.rb:42` faz `uri.open` direto na URL que o cliente mandou em `external_url`. A validação (`validate_uri`, linha 37) só checa se é `URI::HTTP`. Não há filtro de IP privado, nem de redirect, nem de content-type, nem de tamanho.
- **Quem explora:** qualquer usuário autenticado da conta (agente basta). `POST /api/v1/accounts/:id/upload` com `external_url=http://169.254.169.254/latest/meta-data/iam/security-credentials/` → o conteúdo vira um blob do ActiveStorage e volta como `file_url` acessível. Também alcança `http://127.0.0.1:6379`, `http://127.0.0.1:5432`, e qualquer VM vizinha da rede.
- **Por que é grave pra nós:** a frota mistura VMs on-premise e AWS. Em AWS, isso é leitura direta de credenciais IMDS. Em on-premise, é varredura da rede interna a partir do app.
- **Patch mínimo isolável:** commit `871f2f4d56` — `Gemfile` (+`gem 'ssrf_filter', '~> 1.5'`), `lib/safe_fetch.rb` (arquivo novo, 98 linhas), `app/controllers/api/v1/accounts/upload_controller.rb`, `config/locales/en.yml` (+8 chaves de erro). **Nenhum desses arquivos foi tocado por nós** — `lib/safe_fetch.rb` nem existe aqui. Cherry-pick limpo.
- Se quiser a versão final (com `Fetcher`/`RequestOptions`/`PrivateNetworkRequest`), pegar também `661608c0b1`, `c8e551820b`, `cc612e755b`, `7c16071fc7`.

#### S2 — SSRF no download de avatar · `TRAZER` · **exposto hoje**

- **A falha:** `app/jobs/avatar/avatar_from_url_job.rb:29` — `Down.download(avatar_url, max_size: MAX_DOWNLOAD_SIZE)`. Sem filtro de IP.
- **Quem explora:** quem consegue setar `avatar_url` de um contato/usuário/inbox — inclui a **API pública de contatos** e payloads de canal. É blind SSRF (o corpo não volta pro atacante), mas permite port-scan por diferença de timing/erro e GET arbitrário na rede interna.
- **Patch mínimo:** `661608c0b1` — `app/jobs/avatar/avatar_from_url_job.rb`, `app/models/concerns/avatarable.rb` (+`ALLOWED_AVATAR_CONTENT_TYPES`, ganha `image/webp`), `lib/safe_fetch.rb`.
- ⚠️ Nosso job **divergiu**: nós mudamos a assinatura para `perform(avatarable_type, avatarable_id, avatar_url)` + `ALLOWED_AVATARABLE_TYPES` (inclui `Company`). O upstream ainda usa `perform(avatarable, avatar_url)`. O cherry-pick vai conflitar — a adaptação é trocar só o bloco `Down.download`/`rescue` por `SafeFetch.fetch`, mantendo nossa assinatura. **Meia hora de trabalho.**

#### S3 — SSRF no webhook de automações/macros · `TRAZER ADAPTADO` · **exposto hoje**

- **A falha:** `lib/webhooks/trigger.rb:35` — `RestClient::Request.execute(method: :post, url: @url, ...)`. URL vem de webhook de conta, macro, regra de automação ou agent bot. Sem filtro de destino.
- **Quem explora:** admin (ou agente com permissão de automação) cria uma automação com webhook apontando para `http://169.254.169.254/...` ou `http://10.x.x.x:8080/admin`. É blind SSRF com **POST de corpo controlado** — pior que GET, porque atinge APIs internas que mudam estado.
- **⚠️ Este é o de maior risco de merge dos três.** Traz duas consequências:
  1. `Webhooks::Trigger` é o caminho do **agent bot** e do **canal API**. Nossa integração WAHA/Evolution e nossos bots de IA podem ter URL em rede privada — após o patch, **param de funcionar** até setar `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` (ver B4). Foi exatamente o que quebrou os usuários upstream nos issues #14489 e #14494, corrigido depois por `7c16071fc7`.
  2. Nosso **motor Flow** dispara webhooks pelo mesmo caminho? Precisa ser verificado antes de aplicar — se `Flow` chama `Webhooks::Trigger`, herda o bloqueio.
- **Patch mínimo:** `c8e551820b` (`lib/webhooks/trigger.rb`, `app/jobs/agent_bots/webhook_job.rb`, `lib/safe_fetch/*`) **+ obrigatoriamente** `7c16071fc7` (a válvula `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`). Nunca traga o primeiro sem o segundo.
- ⚠️ Nosso `lib/webhooks/trigger.rb` já foi tocado por nós 3 vezes (última: `ee87f5e799`, observabilidade/GlitchTip). Conflito garantido.

#### S4 — Escalação de privilégio em custom attributes · `TRAZER` · **exposto hoje**

- **A falha:** `app/controllers/api/v1/accounts/custom_attribute_definitions_controller.rb` **não tem `check_authorization`** e **não existe** `app/policies/custom_attribute_definition_policy.rb` no nosso repo. Confirmei os dois.
- **Quem explora:** qualquer agente com `api_access_token`. A tela é escondida no dashboard, mas o endpoint é aberto — `POST/PATCH/DELETE /api/v1/accounts/:id/custom_attribute_definitions` funciona. Broken Access Control reportado externamente (CW-7038).
- **Por que dói aqui:** nossos Flows e o Captain leem/escrevem `custom_attributes` de conversa. Um agente pode apagar uma definição usada por automação em produção.
- **Patch mínimo:** `5c6ea78ce6` — 1 linha no controller (`before_action :check_authorization`) + 1 arquivo novo de policy (21 linhas). Zero conflito. **É o melhor custo-benefício de toda esta auditoria.**

#### S5 — `access_token` do agent bot exposto a agentes · `TRAZER` · **exposto hoje**

- **A falha:** `app/views/api/v1/models/_agent_bot.json.jbuilder:9` — `json.access_token resource.access_token if resource.access_token.present?`, sem checar papel. Confirmei que nosso arquivo é idêntico ao do v4.12.1.
- **Quem explora:** agente lista `GET /api/v1/accounts/:id/agent_bots`, pega o token do bot e o replay em APIs bot-autorizadas (criar mensagem como bot, manipular conversa). É escalada lateral.
- **Patch mínimo:** `13db36609d` — troca 1 linha por `... && Current.account_user&.administrator?`. Nosso arquivo também não tem a linha `json.secret` que o upstream já tinha; ao aplicar, conferir.

#### S6 — Segredos de integração em texto puro · `TRAZER` · **exposto hoje**

- **A falha:** `app/views/api/v1/models/_hook.json.jbuilder:8` — `json.settings resource.settings if Current.account_user&.administrator?`. Serializa o hash **inteiro** de settings, incluindo `api_key` da OpenAI, private key de service account do Dialogflow, refresh token do Linear.
- **Quem explora:** é admin-only, então não é escalada de privilégio — mas o segredo trafega e fica no *network tab* do browser, em log de proxy, em HAR de suporte, e em qualquer extensão instalada no navegador do admin. Para nós, a `api_key` da OpenAI é a chave que custa dinheiro.
- **Patch mínimo:** `27404b4a27` — `app/models/integrations/app.rb` (+4 linhas), `_hook.json.jbuilder` (+9/-2), `config/integration/apps.yml` (whitelist `visible_properties`). ⚠️ Conferir se nossas integrações custom (WAHA, tools do Captain) têm `visible_properties` declarado — sem isso, o filtro esconde campos que a UI precisa.

#### S7 — HMAC do widget sem comparação constant-time · `TRAZER`

- `app/controllers/api/v1/widget/contacts_controller.rb:65` e `app/controllers/public/api/v1/inboxes/contacts_controller.rb:52` usam `==` direto no digest.
- Timing attack remota contra identity validation do widget. Explorável na teoria; ruidoso e lento na prática, mas o patch é trivial e o upstream fechou 3 issues com ele (CW-6937, CW-7464, CW-7227).
- **Patch mínimo:** `1e7218d439` — 6 linhas em cada um dos 2 arquivos. Zero conflito.

#### S8 — XSS nos embeds markdown do Help Center · `TRAZER`

- `lib/custom_markdown_renderer.rb:76` — `template.gsub("%{#{var_name}}", value)`, sem escape. O `value` é capture de regex sobre a URL que o autor do artigo escreveu, e cai **dentro de atributo HTML** do iframe de embed.
- **Quem explora:** autor de artigo do Help Center. Como a nossa **Central de Ajuda roda embutida em iframe** (`embed=true`) dentro do dashboard, um artigo malicioso executa no contexto do portal. Menor porque o autor já é usuário confiável — mas em cenário multi-cliente, um cliente pode atingir o portal de outro se compartilharem host.
- **Patch mínimo:** `2192af80f4` — 1 linha (`CGI.escapeHTML(value)`).

#### S11 — Cookie de sessão · `TRAZER`

- `config/initializers/session_store.rb` nosso é a versão de 1 linha, sem `secure:` e sem `httponly:`. O upstream (`95d6aecb51`) passou a derivar `secure` de `FORCE_SSL` e forçar `httponly: true`.
- Impacto real é limitado (a sessão só serve ao dashboard `/super_admin`, a API usa token), mas é exatamente o cookie do **super admin** — o de maior valor.
- **Patch mínimo:** substituir o arquivo inteiro. Nós nunca o tocamos (`git diff` vazio). Cherry-pick limpo. ⚠️ Exige `FORCE_SSL=true` no `.env` das VMs, senão o cookie continua sem `secure`.

#### S12 — Rack::Attack · `TRAZER ADAPTADO`

Três coisas num pacote:
1. **Bypass por barra final** (`2663a8495d`): `path_without_extentions` (com o typo) usa `path[/^[^.]+/]`, então `/auth/sign_in/` **não casa** com `'/auth/sign_in'` e escapa do throttle de brute-force. Isso vale para login, super admin login, reset de senha e MFA. **É bypass real de rate limit de autenticação.** O upstream renomeou para `path_without_extensions` e normaliza a barra final.
2. **Rotas novas com throttle**: `DELETE /conversations/:id` (`b02e732dd1`), `POST /agents` + `bulk_create` + `DELETE /agents/:id` (`160732c07d`), `POST /widget/conversations/transcript` (`71fffdd2b9`), e drilldown de reports.
3. ⚠️ **Nós adicionamos 2 throttles próprios** que usam o nome antigo: `public/funnel_forms` e `public/flow_webhooks` (`config/initializers/rack_attack.rb:129` e `:135`). Se merjar a renomeação sem ajustar, o initializer levanta `NoMethodError` **no boot**. Adaptação é renomear as 2 ocorrências.

#### S14/S15 — ActiveStorage e libvips · `TRAZER`

- `config/initializers/active_storage.rb` (arquivo novo upstream, **não existe aqui**) faz três coisas: permite áudio inline (funcional), **limita byte-ranges no proxy** (`STREAMING_MAX_RANGES = 1`, chunk ≤ 100MB — defesa contra DoS por Range header, relacionado ao CVE-2026-33658 que o upstream ignorou no bundler-audit em `2b296c06fb`), e **filtra metadata forjada** em direct upload (`identified`, `analyzed`, `composed`).
- `VIPS_BLOCK_UNTRUSTED=1` (`f5eb7a954d`, develop): restringe o libvips aos loaders bem testados ao gerar variantes. Nossa frota **não roda Docker** (usa `deployment/setup_spx_24.04.sh`), então tem que entrar no `.env` de cada VM manualmente. Custo: uma linha. Requer libvips ≥ 8.13 (ignorado silenciosamente em versões antigas).

#### S17 — Autor cross-account em artigos · `TRAZER` (vem de `develop`)

- `1b487f49d8` + `651db39765`: `articles_controller` aceitava `author_id` de **qualquer conta** no create e no update, e o jbuilder serializava o autor sem verificar vínculo — vazando nome/e-mail/avatar de agente de outra conta.
- Direto no nosso ponto sensível (multi-cliente + Central de Ajuda). Patch: `before_action :validate_author` / `:discard_invalid_author` + 2 linhas de jbuilder. Como está em `develop` e não em tag, cherry-pick pelo hash.

---

### 3. PERFORMANCE

#### P1 — Deadlock em escrita paralela de labels · `TRAZER` · **maior ganho por menor esforço**

- **O que é:** cada INSERT/DELETE em `taggings` dispara `UPDATE tags SET taggings_count = ... WHERE id = ?`. Duas conversas recebendo a mesma label ao mesmo tempo serializam na mesma linha de `tags` e **deadlocam**. O upstream rastreou como INF-68.
- **Por que importa aqui:** nossas automações e Flows aplicam label em massa. Contas grandes + broadcast = exatamente o cenário do deadlock. Vale checar no GlitchTip se já temos `PG::TRDeadlockDetected` / `ActiveRecord::Deadlocked` — se tiver, este patch é a causa raiz.
- **Patch:** `de0bd8e71b` — **um arquivo novo de 10 linhas**, `config/initializers/acts_as_taggable_on.rb`, com `ActsAsTaggableOn.tags_counter = false`. Não existe aqui. Zero conflito. É seguro: o Chatwoot não lê `tags.taggings_count` em lugar nenhum (relatórios de label contam por `GROUP BY` em `taggings`).

#### P2 — N+1 em `inboxes#index` · `TRAZER ADAPTADO`

- 3 queries por inbox (channel polimórfico, avatar, working hours). Numa conta com 30 inboxes, 90 queries extras a cada carregamento do dashboard.
- **Patch:** `dd7f5c27e5` — `includes(:channel, :portal, :working_hours, { avatar_attachment: :blob })` + `weekly_schedule` deixa de fazer query por inbox (`app/models/concerns/out_of_offisable.rb:22`).
- ⚠️ Nosso `app/controllers/api/v1/accounts/inboxes_controller.rb:12-14` foi customizado (exclui a inbox de chat interno via `PrivateChat::Config`). Adaptação: aplicar o `includes` mantendo nosso `where.not`.

#### P3 — Plano ruim no sort "Pending Response: longest first" · `TRAZER`

- `app/models/concerns/sort_handler.rb:22` usa `waiting_since ASC NULLS LAST`. O planner do Postgres não consegue usar o índice com `NULLS LAST` e cai em seq scan + sort da tabela `conversations` inteira. O upstream trocou por `(waiting_since IS NULL), waiting_since ASC, created_at ASC`, que é semanticamente idêntico e indexável.
- **Patch:** 1 linha. Nosso arquivo está idêntico ao do v4.12.1. Cherry-pick limpo.

#### P4 — Índice em `messages` · `TRAZER ADAPTADO`

- `20260630000000_add_sender_created_index_to_messages.rb` adiciona `(sender_type, sender_id, created_at)` com `algorithm: :concurrently` — transforma leitura vitalícia em range scan de janela. Direto no nosso volume de `messages`.
- ⚠️ **Este timestamp colide com nossa migration `20260630000000_extend_ai_config_changes.rb`** (ver B2). Ao trazer, renomear para timestamp livre.

#### P5 — Timeout no job de IMAP · `TRAZER`

- `52da165cb7`: um e-mail malformado trava o `FetchImapEmailsJob` indefinidamente e bloqueia a inbox inteira. O patch envolve o processamento em `Timeout.timeout(EMAIL_PROCESSING_TIMEOUT_SECONDS || 60)` e marca no cache Redis e-mails que falharam 3× em 6h para pular.
- Env nova: `EMAIL_PROCESSING_TIMEOUT_SECONDS=60` (opcional, tem default).

#### P6 — Throttle de contadores não-lidos · `DESCARTAR`

`848e94bcf2` só ajusta constantes de um subsistema (`Conversations::UnreadCounts`, flags `conversation_unread_counts`/`unread_count_for_filters`) que **nós não temos** — e cujas flags caem justamente nos slots de bit que colidem com os nossos (ver B1). Não traga isoladamente.

#### P7 — `JÁ TEMOS, e melhor`

O upstream (`a901c87ab4`) juntou 3 COUNTs de `/meta` numa query com `COUNT(*) FILTER`. Nosso `app/finders/conversation_finder.rb:316` (`compute_all_counts`) **já faz isso** — e com 9 contadores numa query só, incluindo `ai_count`, `awaiting_count` e `awaiting_closure_count` que o upstream não tem. Nada a fazer.

---

### 4. BREAKING CHANGES OPERACIONAIS

#### B1 — `config/features.yml`: o remapeamento silencioso de bits 🔴

**Este é o achado mais perigoso da auditoria.**

O arquivo abre com `# DO NOT change the order of features EVER` porque a posição na lista **é** a posição do bit na coluna `accounts.feature_flags` (bigint, via `FlagShihTzu`). Nós e o upstream evoluímos o arquivo de formas **incompatíveis**:

| Bit | v4.12.1 (base comum) | **ChatSPX hoje** | **Upstream v4.16.2** |
|---:|---|---|---|
| 4 | `channel_twitter` | `channel_twitter` | **`conversation_unread_counts`** |
| 29 | `response_bot` | **`message_sequences`** | **`custom_tools`** |
| 30 | `message_reply_to` | **`internal_chat`** | `message_reply_to` |
| 31 | `insert_article_in_reply` | `insert_article_in_reply` | **`branded_email_templates`** |
| 39 | `report_v4` | **`ai_assistant_v2`** | **`captain_v1_action_classifier`** |
| 52 | `twilio_content_templates` | `twilio_content_templates` | **`captain_document_auto_sync`** |
| 57 | `quoted_email_reply` | `quoted_email_reply` | **`unread_count_for_filters`** |
| 61 | `captain_tasks` | **`kanban_cursor_loading`** | `captain_tasks` |
| 62 | `conversation_required_attributes` | **`kanban_ux_v2`** | `conversation_required_attributes` |
| 63 | `advanced_assignment` | **`captain_tasks`** | `advanced_assignment` |
| **64** | — | **`conversation_required_attributes`** ⚠️ | `whatsapp_manual_transfer` → `feature_flags_ext_1` |
| **65** | — | **`advanced_assignment`** ⚠️ | `data_import` → `feature_flags_ext_1` |

**Três problemas, em ordem de gravidade:**

1. **Já estamos estourados.** Um bigint signed tem 63 bits utilizáveis. Nós temos **65 entradas** na coluna `feature_flags`. Os bits 64 e 65 (`conversation_required_attributes`, `advanced_assignment`) não cabem — qualquer tentativa de ligá-los tende a `PG::NumericValueOutOfRange` ou grava lixo. Isso confirma a nota de memória sobre o bitmask no limite, e mostra que já passamos do limite, não estamos "perto" dele.

2. **Nós inserimos features no meio.** `kanban_cursor_loading` e `kanban_ux_v2` entraram nas posições 61-62, **empurrando** `captain_tasks`, `conversation_required_attributes` e `advanced_assignment` uma casa adiante cada. Toda conta que tinha `captain_tasks` ligada **antes** desse commit hoje lê como `kanban_cursor_loading` ligada. Vale auditar a frota: contas com Kanban "ligado sozinho" ou Captain Tasks "desligado sozinho" são sintoma disso.

3. **O merge remapeia tudo de novo.** Aceitar o `features.yml` do upstream faz, em toda conta da frota: `message_sequences` → vira `custom_tools`; `internal_chat` → volta a ser `message_reply_to` (feature some); `ai_assistant_v2` → vira `captain_v1_action_classifier`; e assim por diante. Silenciosamente, sem erro.

**O que o upstream construiu — e vale muito pra nós:**
`20260706215758_add_feature_flags_ext_2_to_accounts.rb` adiciona a coluna `feature_flags_ext_1` (bigint), e `app/models/concerns/featurable.rb` ganhou `FEATURE_FLAG_COLUMNS`, `MAX_FEATURES_PER_COLUMN = 63` e o campo `column:` por feature no YAML. **É exatamente a solução que precisamos** — e substitui com vantagem a gambiarra de `internal_attributes`.

⚠️ Note que o `Featurable` novo **valida no boot**: `raise ArgumentError, "Account feature flag column feature_flags supports up to 63 features"`. Com nossas 65 entradas, **o app não sobe** se merjarmos o concern sem antes mover 2+ features para `feature_flags_ext_1`.

**Plano recomendado (`TRAZER ADAPTADO`, esforço M):**
1. Trazer a migration `feature_flags_ext_1` + o `Featurable` novo.
2. Mover nossas features excedentes (`kanban_*`, `captain_tasks`, `internal_chat`, `message_sequences`, `ai_assistant_v2`) para `column: feature_flags_ext_1`, **no fim do arquivo**.
3. Restaurar as posições 1-63 exatamente como o upstream v4.16.2.
4. Escrever uma **migration de dados** que, para cada conta, leia o bitmask antigo com o mapa ChatSPX e regrave com o mapa novo. Sem isso, o passo 3 corrompe as flags da frota inteira.
5. Rodar em homologação e conferir conta a conta antes de qualquer VM de cliente.

#### B2 — Colisão de timestamp de migration 🔴

Dois pares batem exatamente:

| Timestamp | Upstream | Nosso |
|---|---|---|
| `20260616120000` | `add_icon_to_teams.rb` | `add_agent_id_to_messages.rb` |
| `20260630000000` | `add_sender_created_index_to_messages.rb` | `extend_ai_config_changes.rb` |

Resultado: `ActiveRecord::DuplicateMigrationVersionError` **no boot**, travando `db:migrate` em toda VM. Fix conhecido: `git mv` do arquivo upstream para um timestamp livre antes de commitar o merge. Detectar com `ls db/migrate | cut -d_ -f1 | sort | uniq -d`.

#### B3 — `api_and_webhooks` derruba a API por token 🔴

`522e3c4d3f` adicionou em `app/controllers/api/v1/accounts/base_controller.rb`:

```ruby
before_action :validate_token_api_access, if: :authenticate_by_access_token?
# → render 403 'API access is not enabled for this account' unless Current.account.api_and_webhooks_enabled?
```

`api_and_webhooks` é uma feature nova que mora em **`feature_flags_ext_1`**. Se o merge trouxer o controller mas a coluna/migration não existir, ou a flag ficar `false`, **toda integração por `api_access_token` da frota inteira retorna 403** — nossos scripts, o receptor HTTPS, integrações de cliente, tudo. O upstream já precisou de um hotfix (`eae9841eb4`) por efeitos colaterais disso.

Trazer só com B1 resolvido, e conferir que a flag nasce `true` em todas as contas existentes (o YAML tem `enabled: true`, mas contas **já criadas** não recebem default automaticamente — precisa backfill).

#### B4 — `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` 🔴

Depois de S3, todo webhook/fetch passa pelo `SsrfFilter`, que **bloqueia IP privado por padrão**. Se algum agent bot, canal API ou integração nossa apontar para `10.x`, `192.168.x`, `172.16-31.x` ou `localhost`, para de funcionar sem erro claro.

Antes de aplicar S3, levantar no banco de cada VM:
```sql
SELECT id, name, outgoing_url FROM agent_bots WHERE outgoing_url IS NOT NULL;
SELECT id, webhook_url FROM channel_api WHERE webhook_url IS NOT NULL;
SELECT id, url FROM webhooks;
```
Se houver qualquer URL privada, setar `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` no `.env` **antes** do deploy. (Ligar isso reabre parte da superfície de SSRF — é um trade-off consciente; o `PrivateNetworkRequest` do upstream ainda faz strip de headers sensíveis em cross-origin e valida CRLF.)

#### B5 — `sidekiq-cron` 1.12 → 2.4 🔴

`config/initializers/sidekiq.rb` passou de `load_from_hash` para `load_from_hash!(schedule, source: 'schedule')`, que **remove do Redis** entradas com o mesmo source que sumiram do YAML (era o TODO que o upstream tinha deixado). O parâmetro `source:` **só existe no sidekiq-cron 2.x**. Merjar o initializer sem bumpar a gem = `ArgumentError`/`NoMethodError` no boot do Sidekiq.

São um par indivisível: `Gemfile` (`sidekiq-cron >= 2.4.0`) + `config/initializers/sidekiq.rb` + `config/schedule.yml`.

⚠️ Nossos **8 jobs custom** em `schedule.yml` (`campaigns_whatsapp_dispatch_job`, `waha_refresh_groups_job`, `waha_resolve_lid_sweep_job`, `waha_inbound_reconciler_job`, `purge_orphan_blobs_job`, `conversations_orphan_watch_job`, `purge_expired_bulk_downloads_job`, `captain_conversation_eval_scheduler_job`) sobrevivem porque estão no YAML. Mas qualquer cron registrado por outro caminho some no primeiro boot pós-deploy.

#### B6 — `rails-i18n` vira obrigatória

`config/application.rb` ganhou `config.rails_i18n.enabled_modules = [:pluralization]`, que só existe com a gem `rails-i18n ~> 7.0` (adicionada no mesmo release) + o initializer `config/initializers/i18n_pluralization.rb`. ⚠️ Nós temos 13 linhas próprias em `config/application.rb` (incluindo o `Rails.autoloaders.main.collapse` do enterprise/lib) — o merge conflita. Par indivisível: Gemfile + application.rb + initializer.

Como **pt-BR é nossa prioridade de i18n**, vale conferir se a mudança de pluralização mexe em `config/locales/pt_BR.yml` (o upstream tocou nesse arquivo no período).

#### B7 — Puma 6 → 7

Major bump por advisories. Precisa revalidar `config/puma.rb` e as units systemd da frota (`chatwoot.target`). Puma 7 mudou defaults de `workers`/`threads` e o comportamento de shutdown. Não é opcional (é o fix de segurança), mas exige um ciclo de teste em homologação com carga antes de ir pra produção.

#### Variáveis de ambiente — resumo do delta

| Variável | Estado | Ação |
|---|---|---|
| `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` | nova | Setar `true` se houver webhook em rede privada (B4) |
| `EMAIL_PROCESSING_TIMEOUT_SECONDS` | nova (default 60) | Opcional |
| `VIPS_BLOCK_UNTRUSTED` | nova | Setar `1` no `.env` de cada VM (S15) |
| `RATE_LIMIT_CONVERSATION_DELETE` | nova (default 60/min) | Opcional |
| `RATE_LIMIT_AGENT_CREATE` / `RATE_LIMIT_AGENT_DELETE` | novas (100/dia, 50/dia) | Opcional |
| `RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL` | nova | Opcional |
| `FORCE_SSL` | já existia | Passa a controlar `secure` do cookie (S11) — conferir se está `true` na frota |
| `OPENAI_API_KEY` | **removida** do `.env.example` | Captain agora só lê de Super Admin → App Configs (`CAPTAIN_OPEN_AI_API_KEY`) — conferir onde nossa frota configura |

**Nenhuma variável foi renomeada ou removida de forma quebrante.** Nossas 2 vars próprias (`TZ`, `TIME_ZONE`) não colidem.

**`config/installation_config.yml`:** só adições (Captain auto-sync, Context.dev, billing multi-moeda). Nada quebra, mas o arquivo é lido no boot e faz upsert em `installation_configs` — merge cru adiciona configs de cloud que não usamos. Inócuo.

---

### 5. CI / BUILD

**`vite 5.4.21 → 6.4.2` (major)** — `AVALIAR DEPOIS`, risco Alto:
- O `vite.config.ts` foi quebrado em 4 arquivos: `vite.config.ts`, `vite.shared.ts` (aliases + vueOptions), `vite.lib.config.ts` (SDK), `vitest.config.ts` (testes). Todo o bloco `test:` saiu do `vite.config.ts`.
- **Nós customizamos `vite.config.ts`** (+29 linhas) — conflito garantido, e a nossa customização precisa ser redistribuída entre os 4 arquivos novos.
- O SDK muda de `BUILD_MODE=library vite build` para `vite build --config vite.lib.config.ts`. Nosso `package.json:15` ainda usa o modo antigo; `lib/tasks/build.rake` chama `pnpm run build:sdk`, então o contrato do rake se mantém.
- Novidades: plugin `@rollup/plugin-yaml` (permite `import` de `.yml` no front — o upstream usa pra `config/llm_models.json`) e `css.preprocessorOptions.scss.api: 'modern-compiler'`. Esse último interage com nosso `_wa-skin.scss`/`_woot.scss` — **exige validação visual** (light + dark) antes de considerar pronto.

**Memória de build:** o upstream **não mexeu** em `NODE_OPTIONS`. Continua `--max-old-space-size=4096` no `docker/Dockerfile:22`, `app.json:42` e nos scripts de deployment. Nosso `deployment/deploy.sh:98` e `setup_spx_24.04.sh:501,1095` também usam 4096 — e já sabemos por experiência que 4096 mascara OOM do Vite aqui (o `rake assets:precompile` sai com exit 0 e bundle velho). Vite 6 + Rollup 4 tendem a consumir **mais**, não menos. **Recomendação independente do merge: subir para 8192 nos nossos scripts de deploy e checar mtime do manifest após todo precompile.**

**Workflows GitHub:** `2dee7457cd` adicionou `permissions: contents: read` no topo dos workflows (hardening supply-chain). Ganho real, custo zero, sem impacto no runtime. Novo workflow `ghsa-linear-sync.yml` é interno do Chatwoot — descartar.

---

## Riscos e pegadinhas

1. **Não traga `c8e551820b` (SSRF webhook) sem `7c16071fc7`.** Você derruba os webhooks internos da frota e vai gastar horas achando por quê. O upstream fez esse erro e comeu 2 issues públicos.
2. **Não traga `app/models/concerns/featurable.rb` antes de reorganizar `features.yml`.** O `MAX_FEATURES_PER_COLUMN = 63` levanta `ArgumentError` na carga da classe — o app não sobe, e o erro aponta pro concern, não pro YAML.
3. **Não aceite `config/features.yml` do upstream em merge de 3 vias.** Git vai resolver por linha e produzir um arquivo sintaticamente válido e semanticamente destrutivo. Esse arquivo precisa ser reconciliado **à mão**, com migração de dados.
4. **Renomear `path_without_extentions` quebra nossos 2 throttles custom** (`rack_attack.rb:129,135`). Erro só aparece no boot.
5. **Os 2 timestamps de migration colididos travam a frota inteira** — não só a VM onde o merge foi feito.
6. **`Webhooks::Trigger` tem 3 commits nossos**, o último de observabilidade (`ee87f5e799`). Ao adaptar para SafeFetch, preservar nossos rescues do GlitchTip, senão os erros que acabamos de estancar voltam.
7. **`SafeFetch` valida content-type por padrão** (`image/`, `video/`). O `webhooks/trigger` upstream passa `validate_content_type: false` explicitamente. Se esquecer esse flag ao adaptar, todo webhook que responde `application/json` passa a falhar.
8. **`_hook.json.jbuilder` + `visible_properties`:** se nossas integrações custom não declararem `visible_properties` em `config/integration/apps.yml`, o patch S6 esconde campos que a UI precisa e a tela de integrações fica vazia.
9. **Backfill de `api_and_webhooks`:** o `enabled: true` do YAML só vale para contas **novas** (`before_create :enable_default_features`). Contas existentes precisam de backfill explícito, senão 403 em tudo.
10. **`FORCE_SSL`** precisa estar `true` na frota para o S11 ter efeito. Se não estiver, o patch entra e não protege nada — falso verde.

---

## Pacote mínimo obrigatório sugerido

Ordem de execução, sem depender do merge grande:

**Etapa 1 — 1 dia, risco baixo, ganho imediato**
- Bump de gems por advisory (S9) + front (S10) — só lockfiles.
- `5c6ea78ce6` custom attribute policy (S4).
- `13db36609d` agent bot token (S5).
- `1e7218d439` HMAC constant-time (S7).
- `2192af80f4` escape do markdown embed (S8).
- `de0bd8e71b` initializer acts_as_taggable (P1) — arquivo novo.
- `fed32d5964` sort_handler (P3) — 1 linha.
- `VIPS_BLOCK_UNTRUSTED=1` no `.env` da frota (S15).
- `NODE_OPTIONS=--max-old-space-size=8192` nos nossos scripts de deploy.

**Etapa 2 — 1 dia, risco baixo-médio**
- `871f2f4d56` SafeFetch + upload (S1).
- `661608c0b1` avatar SSRF adaptado à nossa assinatura (S2).
- `27404b4a27` redaction de segredos (S6) — conferindo `visible_properties`.
- `95d6aecb51` cookie de sessão (S11) + confirmar `FORCE_SSL`.
- `config/initializers/active_storage.rb` (S14).
- Corrigir os 2 timestamps de migration colididos (B2).

**Etapa 3 — 1-2 dias, risco alto, exige homologação**
- Levantar URLs privadas de webhook na frota (B4).
- `c8e551820b` + `7c16071fc7` SSRF de webhook (S3).
- Renomeação do Rack::Attack + throttles novos, ajustando nossos 2 (S12).
- Puma 7 com ciclo de teste de carga (B7).

**Etapa 4 — projeto à parte, não misturar com o resto**
- Reconciliação de `feature_flags` + migração de dados (B1) → destrava B3 e o merge grande.

---

## O que eu NÃO consegui apurar

1. **Se o motor Flow chama `Webhooks::Trigger`.** Não rastreei o caminho de webhook das nossas automações próprias. Se chamar, S3 afeta os Flows também — precisa de uma leitura de `app/services/flows/` antes de aplicar.
2. **Se existem webhooks apontando para IP privado na frota.** Requer consulta ao banco de cada VM; não fiz por ser fora do escopo read-only de código.
3. **Se o deadlock de labels (P1) já aparece no GlitchTip.** Não consultei o GlitchTip; a confirmação transformaria P1 de "prevenção" em "correção de incidente ativo".
4. **Quantas contas da frota estão com flags remapeadas por causa da inserção dos bits 61-62.** Precisa de um `rails runner` por VM comparando `feature_flags` com o mapa esperado — recomendo fazer isso **antes** de qualquer merge, para ter o "antes" registrado.
5. **Se `bundle audit` acusa outras gems** além das 8 identificadas por comparação de versão. Não rodei `bundler-audit` (exigiria `bundle install`, proibido nesta auditoria). A lista pode estar incompleta para baixo.
6. **Impacto real do `css.preprocessorOptions.scss.api: 'modern-compiler'`** no nosso skin WhatsApp. Só um build + validação visual em light e dark responde.
7. **Comportamento do `net-imap 0.4.20 → 0.6.4.1`** no nosso canal de e-mail — é um salto de duas minor, pode ter mudança de API.
