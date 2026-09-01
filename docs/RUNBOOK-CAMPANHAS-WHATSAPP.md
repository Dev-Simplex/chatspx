---
titulo: Runbook — campanhas de WhatsApp (motor nativo)
status: vigente
data: 2026-08-25
tags: [spx, campanhas, disparo, whatsapp, runbook]
---

# Runbook — campanhas de WhatsApp

Motor nativo `Campaigns::Whatsapp::*`. **Não** é o `Spx::Tozi::DisparoLeadJob` (motor antigo,
12/min, ainda presente no código e usado nas campanhas 1 e 2 de junho).

> Escrito a partir do código, depois de 2.752 disparos do Urban DeVille (campanhas #7 a #16,
> Tozi conta 6, inbox 99). O que está aqui foi lido no motor, não lembrado. Os números de
> operação vêm do `.claude/STATE.md`.

---

## 0. Antes de tudo — leia o relógio da VM

```ruby
Time.current  # NUNCA deduzir a hora do fio da conversa
```

Em 22/08 uma campanha foi montada como "sexta 19h" quando era **sábado 11h**. O script abortou
sozinho, mas só porque tinha a guarda. Sem ela, 100+ pessoas receberiam disparo fora de hora.

---

## 1. Configurar

A campanha é uma linha em `campaigns`. O que o motor lê:

| Campo | O que faz |
|---|---|
| `inbox_id` | Precisa ser inbox **WhatsApp Cloud API**. `whatsapp_blast?` exige `inbox_type == 'Whatsapp'` **e** `template_name` presente — sem template, a campanha é ignorada pelo scheduler em silêncio |
| `template_name` / `template_language` | HSM **aprovado** no WABA |
| `target_team_id` | Time que a conversa recebe. Ela nasce **fechada e sem agente**; o reply reabre |
| `dispatch_assignee_id` | Dono opcional das respostas. ⚠️ **Só em inbox SEM IA** — atribuir humano dispara `reset_agent_bot_when_assignee_present` e cala o agente |
| `pacing_seconds` | Ritmo. Ver §2 |
| `dispatch_status` | `draft` / `scheduled` / `running` / `paused` / `completed` / `failed` (prefixo `dispatch_`) |

### `dispatch_config` (jsonb) — o resto mora aqui

| Chave | Efeito |
|---|---|
| `quiet_hours` | `{start:, end:}` — **janela de SILÊNCIO, não de envio**. `{start: 18, end: 8}` cala das 18h às 8h, ou seja envia 08:00–17:59 |
| `timezone` | Fuso da janela. Sem isso cai em `Time.zone` da aplicação. **Não** usa `inbox.timezone` (nasce `UTC` e ninguém revisa) |
| `health_gate` | `true` → pausa o tick se a qualidade do número estiver **RED**. Qualidade desconhecida **não** bloqueia |
| `header` | Header do template (ex.: imagem). Upload por resumable: `POST /{APP_ID}/uploads` → `POST /{upload_id}` com `Authorization: OAuth` e `file_offset: 0` |
| `default_params` | Params aplicados a todos, sobrescritos pelos do destinatário |
| `default_ddd` | Recupera número sem DDD na lista. Sem isso, número de 8-9 dígitos é descartado |
| `blocklist_labels` | Labels de contato que excluem da audiência (ex.: corretores) |
| `dedup` | Como cortar quem já recebeu disparo. Ver **§7** |

### ⚠️ A janela é por HORA CHEIA

`quiet_hours?` compara `Time.current.hour` — inteiro. **16:30 não é expressável.** Ou aceita
16h, ou alguém precisa dar `dispatch_running!` na hora.

Janela que cruza a meia-noite funciona (`start > end` → `hour >= start || hour < end`).

---

## 2. Ritmo — o teto é 60/min, medido

```ruby
batch_size = 60 / pacing_seconds   # por tick de 1 minuto
MAX_BATCH  = 200                   # teto por tick
```

| `pacing_seconds` | Ritmo |
|---|---|
| 20 | 3/min |
| 12 | 5/min |
| 1 | **60/min — o máximo prático** |

**Medido em 21/08 (campanha #13, Kettlen):** 200 enviadas em 4 minutos, **zero falha, zero
throttle**, número GREEN imediatamente depois. É 5× o ritmo mais rápido do motor antigo.

60/min é o teto porque `batch_size` já satura em `pacing_seconds = 1`. Ir além exigiria mudar
o tick, não a configuração.

---

## 3. Carregar a lista

```ruby
rows = [{ name: 'Fulano', phone: '66 99292-7211', params: { '1' => 'Fulano' } }, ...]

# PREVIEW — não persiste nada
Campaigns::Whatsapp::AudienceBuilderService.new(campaign:, rows:).perform
# => Result(accepted:, rejected:, stats:)

# CARREGAR — mesmas regras, agora grava campaign_recipients pendentes
Campaigns::Whatsapp::ListLoaderService.new(campaign:, rows:, blocklist_phones:).perform
```

O loader é **idempotente**: rodar de novo não reinsere (o builder descarta como `ja_na_campanha`).

### Chave canônica = DDD + últimos 8 dígitos

`+5566992927211`, `+556692927211` e `66 9929-2721` são a **mesma pessoa**. Deduplicar pela
string e164 deixaria as três passarem e o lead levaria o disparo em triplicata.

### Motivos de descarte, na ordem em que são avaliados

`telefone_invalido` · `telefone_fixo` · `numero_suspeito` · `bloqueado` · `optou_por_sair` ·
`ja_disparado` · `ja_na_campanha` · `atendimento_ativo` · `duplicado_na_lista`

- **`telefone_fixo`** — 8 dígitos começando em 2-5. Não recebe WhatsApp, e pôr o 9º dígito
  produziria um celular que não existe.
- **`numero_suspeito`** — mesmo dígito 7+ vezes (`66999999999`): preenchimento para escapar de
  campo obrigatório.
- **`optou_por_sair`** — vem **antes** de `ja_disparado` de propósito: quem pediu PARAR depois de
  ter recebido sairia contado como já-disparado e o número de compliance da tela sairia menor do
  que é. ⚠️ Ver a ressalva do opt-out no próprio serviço — o gravador da supressão nasce inerte
  em conta sem o motor de Flows.
- **`atendimento_ativo`** — conversa não-resolvida na inbox. **Disparo não atropela atendimento.**

### ⚠️ `template_params` é `{'1' => valor}`

Não `{'body' => [valor]}`. Com o formato errado o HSM sai **sem erro e sem o nome**
("Oi , sou a Kettlen..."). O `ListLoaderService` já assume `{'1' => nome}` quando há nome e
não há params — mas script escrito à mão precisa acertar sozinho.

**Como conferir:** leia o **texto enviado** do primeiro destinatário, não o status. Status só
diz que a Meta aceitou.

---

## 4. Disparar

```ruby
campaign.dispatch_running!    # o scheduler pega no próximo tick (1/min)
campaign.dispatch_paused!     # pausa; retomar segue de onde parou
```

A fonte de verdade é a tabela `campaign_recipients`, **não** a fila do Sidekiq. Reivindicação
atômica (`CampaignRecipient#claim!`) torna ticks concorrentes seguros contra duplicata.

Campanha criada já em `dispatch_running` fora da janela fica muda e **acorda sozinha** — não
precisa de ninguém apertando botão na hora.

### O que acontece com cada destinatário

1. Contato em atendimento ativo → `skipped`, não envia
2. Cria/reusa contato e conversa (reconcilia o 9º dígito da ficha)
3. Envia o HSM
4. Seta o time e **fecha a conversa sem agente**
5. `sent` + `sent_at`

Falha marca `failed` com `external_error` e **não derruba o lote**. Uma campanha com config
ruim também não para as outras — o `rescue` no `find_each` é proposital.

---

## 5. Medir

```ruby
campaign.campaign_recipients.group(:status).count
# pending / processing / sent / failed / skipped / delivered / read / replied
```

| Métrica | Como |
|---|---|
| Taxa de resposta | `replied / sent`. Referências reais: **6,6%** (#8, 998 enviadas) e **9%** (#9, 300) |
| Falhas | `external_error`. `131026` = número sem WhatsApp — **não é cobrado**, não é problema de qualidade |
| Qualidade do número | `Whatsapp::HealthService#fetch_health_status` → `quality_rating`. GREEN após 2.752 disparos |
| Fila gerada | conversas abertas no `target_team`. ⚠️ o Urban terminou com **148 abertas** na Kettlen |

### O roteamento da resposta não é automático

O lead responde → a conversa reabre no time → e **fica sem dono** se o time tem
`allow_auto_assign = false`. Foi o caso do time 62: João e Cibele atribuíam **na mão**, uma a
uma, com até 13 min de espera.

Conserto: regra de automação `conversation_opened` + `inbox_id` + `team_id` → `assign_agent`
(regras #70 a #74 na Tozi). ⚠️ **`conversation_opened` só dispara na transição resolvida→aberta** —
conversa já aberta que recebe mensagem nova não passa pela regra.

---

## 6. Armadilhas que já custaram caro

- 🔴 **O pool de elegíveis encolhe sozinho.** Os "livres" caíram de 47 para 25 em um dia porque
  o corte *conversa aberta* subiu de 90 para 210. **Recontar sempre no instante de montar a
  campanha** — contagem de ontem não vale.
- ⚠️ **Copy que mente sobre a pessoa é o caminho curto para bloqueio.** O template do Urban diz
  *"há um tempo você procurava apartamento para comprar"*. Mandar isso para o público de **casa
  MCMV** (Pacaembu) afirma uma falsidade sobre quem recebe. Em 22/08, 103 pessoas que nunca
  falaram com a Tozi receberam essa frase — se a qualidade cair, é o primeiro lugar a olhar.
- ⚠️ **Variável não pode abrir o corpo do template** — a Meta rejeita (`2388299`). O corpo
  precisa começar com texto.

---

## 7. Dedup — os dois motores e o corte configurável

O `AudienceBuilderService` lê "já disparou" em **dois lugares**, porque os dois motores gravam
de formas diferentes:

| Motor | Onde grava | Data do disparo |
|---|---|---|
| Novo (`Campaigns::Whatsapp`) | `campaign_recipients` | `sent_at`, com fallback para `created_at` |
| Antigo (`Spx::Tozi::DisparoLeadJob`) | `campaign_id` **na conversa** | da **campanha** (`scheduled_at` → `created_at`) |

> ⚠️ **Por que a data do motor antigo vem da campanha, não da conversa:** ele **reusa** a conversa
> que já existe e só carimba o `campaign_id`. `conversations.created_at` pode ser meses anterior
> ao envio — datar por ele encolheria a janela em silêncio.

**Histórico:** até 25/08/2026 o corte lia só `campaign_recipients`. As campanhas 1 e 2 (~6.100
pessoas em junho) eram invisíveis, e **294 pessoas receberam disparo duas vezes**.

### O corte — `dispatch_config['dedup']`

Tudo opcional. Ausente = o corte mais largo: *já disparou alguma vez, por qualquer motor, sai.*

| Chave | Efeito | Ausente significa |
|---|---|---|
| `window_days` | Só conta disparo dos últimos N dias | histórico inteiro — o "pra sempre" |
| `campaign_ids` | Só conta disparo **destas** campanhas | todas |
| `sources` | Quais motores entram: `recipients` e/ou `conversations` | os dois |

```json
{ "dedup": { "window_days": 90, "sources": ["recipients", "conversations"] } }
```

⚠️ `sources` com nome que não existe cai no corte mais largo (os dois motores). Config errada
nunca vira disparo em dobro.

### A decisão que este corte destrava

Com `window_days` ausente, quem recebeu disparo em junho fica inelegível **para sempre** — e as
duas bases prontas encolhem de ~10.600 para **4.823**. Com `"window_days": 90`, a coorte de junho
(**~5.800**) volta a ser elegível.

**É decisão de campanha, não de código** — e agora ela é expressável sem tocar em Ruby.

---

## 8. Inventário de audiência (22/08/2026)

| | |
|---|---|
| Contatos com telefone | 30.292 |
| Já receberam algum disparo | 13.980 |
| Recusaram | 361 |
| Nunca receberam nada | 15.276 |

⚠️ Os 15.276 **não são uma base**: é todo mundo que já falou com a Tozi por qualquer canal, sem
produto, segmento nem recência.

Prontas para virar volume: **4.823** (Pacaembu/motoristas) + **~5.800** (junho) — as duas
travadas na mesma coisa: **a copy**, não a lista.
