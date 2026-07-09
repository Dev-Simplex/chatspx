# Handoff — Conciliação Homologação (conta 3) → VM Tozi (conta 6)

> Resumo do que mudou na **homologação (.232 = chatspx.app, conta 3)** nesta sessão, pra portar à **VM de produção Tozi (AWS, conta 6)**.
> Data: 2026-06-27.
>
> **Regra de ouro da conciliação:** há **dois tipos** de mudança — (A) **código** (está em git, `origin/homologacao`) e (B) **config dos agentes** (vive no **DB por conta**, NÃO é git). A VM é a **conta 6**, com agentes próprios (Clara #7, Júlia #13, Bruna #14, Letícia #15, Marina #16, Rafa #17). O código se traz por deploy normal; a config de prompt precisa ser **re-aplicada** nos agentes da conta 6.

---

## A) Código — git (`origin/homologacao`), 5 commits

Range: `27e605843..c29789ad8`. **Sem migrations novas.**

| Commit | O quê | Arquivos |
|---|---|---|
| `46047d026` | `buscar_imovel` aceita **`codigo`** (cliente manda código digitado/foto de placa → busca exata no Vista por `Codigo`, URL via `ImoCodigo`) + **nova tool `buscar_lugar`** (Google **Places API New** `searchText`) pra desambiguar proximidade por NOME de lugar | `buscar_imovel_tool.rb`, `buscar_lugar_tool.rb`, `config/agents/tools.yml` |
| `b45f3f578` | **Keys Vista/Google por conta** (multi-tenant): lê de `Account.custom_attributes` com **fallback ENV**. Fecha vazamento cross-conta no SELECT do geocoding | `buscar_imovel_tool.rb`, `buscar_lugar_tool.rb` |
| `ddd9450df` | **Regras de conduta compartilhadas no template** (não-inventar fato/nome/endereço/valor/link; pessoa-pelo-nome = acolhe sem confirmar/negar; `[IGNORAR]` só pra espera de humano). **Os 6 agentes herdam** automaticamente | `enterprise/lib/captain/prompts/assistant.liquid` |
| `80e2a9c9c` | **Replay-guard chunk-aware** (mata "papagaio": fallback que re-emitia fala antiga do histórico quando `output` vinha vazio + humanizer quebrava em bolhas) | `agent_runner_service.rb` |
| `c29789ad8` | **Enxuga aviso de fora-do-horário** no template (curto, sem citar horário específico — matava a alucinação "já passamos das 18h") | `enterprise/lib/captain/prompts/assistant.liquid` |

**Como trazer pra VM:** mergear `homologacao → producao` (ou cherry-pick desses 5), depois na VM `git reset --hard origin/producao` (NÃO `pull` — há untracked que trava). `db:migrate:status` antes (0 pendentes esperadas) → **restart worker** (web opcional; nada de frontend mudou).

> ⚠️ Como o template `assistant.liquid` é **compartilhado por toda a instância**, os dois commits de template (`ddd9450df`, `c29789ad8`) valem pros 6 agentes da conta 6 **sem trabalho extra**. NÃO duplicar essas regras nos prompts dos agentes.

---

## B) Config dos agentes — DB, conta 3 → **re-aplicar na conta 6** (Júlia #13 + Bruna #14)

Estas mudanças NÃO estão em git (são `config['instructions']` / `config['tools']` por agente). Re-aplicar nos agentes de **busca** da conta 6 (Júlia vendas #13, Bruna locação #14).

### B1. Anexar `'buscar_lugar'` ao `config['tools']` dos agentes de busca
Sem isso a tool nova **não é anexada** ao agente (o tools.yml só registra; o agente precisa listar).
⚠️ **Slug é SINGULAR: `buscar_lugar`** (o `classify` singulariza — `buscar_lugares` vira `BuscarLugare` e NÃO resolve).

### B2. Bloco "# Regras de busca de imóvel" (append nas instructions de Júlia #13 + Bruna #14)
```
# Regras de busca de imóvel (siga à risca)
- Proximidade / ponto de referência ("perto de X", "trabalho na X", "moro perto da Y"): X é a REFERÊNCIA — chame buscar_lugar(X) pra pegar as unidades REAIS (NUNCA use o endereço do escritório da Tozi). A lista que a tool devolve é PRA VOCÊ se localizar; NÃO recite os endereços pro cliente. Se houver mais de uma unidade, pergunte como um humano perguntaria: curto, só com o que diferencia (a rua ou o bairro de cada uma) — ex.: cliente diz "trabalho na Ronta" → "Tem mais de uma Ronta, você trabalha na da Tarumãs ou na da Perimetral?". Se a pessoa JÁ disse que trabalha/mora na X, a pergunta é EM QUAL unidade ela está — nunca "qual fica perto do seu trabalho" (o trabalho é a própria X). Definida a unidade, use a lat/lng dela no buscar_imovel.
- Código de imóvel: se o cliente mandar um código (digitado OU em foto de placa/anúncio), chame buscar_imovel com codigo. Não diga que não achou sem antes buscar por código.
- Link do site: NUNCA invente nem monte o link. Use SOMENTE a URL que o buscar_imovel retorna em cada imóvel.
- Endereço x localização (PIN só quando pedirem): se o cliente perguntar ONDE FICA ou pedir o ENDEREÇO, responda com TEXTO — a rua/bairro (campo Endereco do buscar_imovel), sem segurar ("o consultor passa na visita"). Só mande o PIN de localização (enviar_localizacao_imovel) quando ele pedir EXPLICITAMENTE a localização/o pin (ex.: "me manda a localização", "manda o pin"). Nunca mande pin como resposta a "onde fica?" — isso é texto.
```

### B3. Ajuste de valor (só Bruna locação #14)
Na seção "# Entender o cliente", trocar:
`faixa de aluguel que cabe no bolso (sem contar condomínio e IPTU)` → `faixa de valor de aluguel`
(o "sem contar condomínio e IPTU" estava vazando literal na conversa — robótico).

> As **regras de conduta** (não-inventar / pessoa-pelo-nome / `[IGNORAR]`) NÃO entram aqui — elas já vêm do **template** (commit `ddd9450df`).

---

## C) Credenciais por conta (multi-tenant)

- `buscar_imovel` (Vista) e `buscar_lugar` (Google) agora leem a key de `Account.custom_attributes`, **com fallback pra ENV**.
- **Conta 6 (Tozi) NÃO precisa de mudança pra funcionar** — segue pegando `TOZI_VISTA_API_KEY` do `.env` (fallback). Opcional, se quiser tirar do ENV: setar `Account(6).custom_attributes['vista_api_key']` + `['vista_base_url']`.
- `buscar_lugar` (Google): sem `custom_attributes['google_maps_key']` nem `ENV['GOOGLE_MAPS_API_KEY']`, ele **reusa a key do custom tool de geocoding da própria conta** (escopado por `account_id`). Conferir que a conta 6 tem esse custom tool com key válida.
- **Ativar "Places API (new)"** no projeto Google da key (o `searchText` é da API nova; a legada está negada).
- 🔴 **SEGURANÇA:** a Google key está **exposta no repo público** (endpoint_url do geocoding tool). **Rotacionar** + idealmente migrar pra `custom_attributes` (que hoje é texto plano, sem cripto — endurecer).

---

## D) Checklist pós-deploy na VM (conta 6)

- [ ] `rails db:migrate:status` (0 pendentes) **antes** de qualquer restart.
- [ ] `git reset --hard origin/producao` (não `pull`) → precompile (só se web) → **restart worker**.
- [ ] Anexar `'buscar_lugar'` ao `config['tools']` de Júlia #13 + Bruna #14 (slug singular).
- [ ] Append do bloco "# Regras de busca" (B2) em Júlia #13 + Bruna #14.
- [ ] Trocar a linha de valor (B3) em Bruna #14.
- [ ] Ativar Places API (new) na conta Google + conferir custom tool de geocoding na conta 6.
- [ ] Rotacionar a Google key exposta.
- [ ] Smoke test: "trabalho na Ronta, quero casa perto" (desambiguação curta) · "código 9819" (busca exata) · "onde fica?" (texto) vs "me manda a localização" (pin) · fora do horário (aviso curto, sem inventar hora).

---

## E) Notas

- **business_hours** (conta 3): seg–sex 07:30–11:30 e 13:30–17:30, **sáb 09:00–11:30**, tz America/Cuiabá, nos 6 agentes. É a tela "Horário comercial" do agente (`behavior['business_hours']`). Conferir/alinhar na conta 6 se preciso.
- Helpers usados na sessão (não versionar): `Temp/hml.sh` (.232 LAN). ⚠️ Só rodar via **arquivo de script** (aspas simples/parênteses inline quebram o `bash -lc` e podem vazar a senha Cortex).
- Tudo testado E2E ao vivo na conta 3 (conv 525): proximidade, busca+distância, pin, fotos, papagaio (0 em 54 msgs), fora-do-horário enxuto.
