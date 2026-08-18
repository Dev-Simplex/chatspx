# I1 — BACKEND / INGESTÃO: autor de grupo extraído do texto e gravado como dado

> Worker I1 · 27/07/2026 · VM 192.168.8.232 (homologação) · branch `homologacao`
> **Nada commitado.** Tudo no working tree, como manda o briefing.

---

## 1. O que mudou

### Arquivos novos

| Arquivo | Papel |
|---|---|
| `app/services/whatsapp/group_sender_extractor.rb` | Separa o autor do texto. Devolve `content` limpo + `sender` no shape do C2. |
| `app/services/whatsapp/lid_phone_cache.rb` | Cache Redis `waha:lid_pn:{session}:{lid}` — **contrato combinado com o I3**. |
| `app/services/whatsapp/group_sender_phone_resolver.rb` | LID → telefone: cache → WAHA → lista (com circuito e lock). |
| `app/jobs/whatsapp/resolve_group_sender_phone_job.rb` | Resolve o telefone **fora do request** e atualiza `content_attributes`. |
| `spec/services/whatsapp/group_sender_extractor_spec.rb` | 19 exemplos. |
| `spec/services/whatsapp/lid_phone_cache_spec.rb` | 14 exemplos. |
| `spec/services/whatsapp/group_sender_phone_resolver_spec.rb` | 15 exemplos. |
| `spec/jobs/whatsapp/resolve_group_sender_phone_job_spec.rb` | 8 exemplos. |
| `spec/controllers/public/api/v1/inboxes/messages_controller_spec.rb` | 12 exemplos (grupo × 1:1). |

> ⚠️ **Fora da lista de propriedade original:** criei `app/jobs/whatsapp/resolve_group_sender_phone_job.rb`
> e `spec/jobs/whatsapp/resolve_group_sender_phone_job_spec.rb`. São arquivos **novos**, em diretório
> vazio até então (`app/jobs/whatsapp/` não existia), com nome específico — zero risco de colisão com
> outro worker. O requisito "resolução assíncrona" não tinha como caber em `app/services/`.

### Arquivo alterado

`app/controllers/public/api/v1/inboxes/messages_controller.rb`:

- `create:13` / `:19` — chama `schedule_group_sender_phone_resolution` **depois** do `@message.save!`.
- `message_params:84` + `base_message_params:88` — o hash original virou base intocada.
- `with_group_sender:107` — o coração: só age quando `waha_multi_participant_chat?`.
- `waha_multi_participant_chat?:126` / `waha_broadcast_chat?:132` — grupo (C1) ou broadcast (ver §4.1).
- `resolve_sender_phone:143` / `group_waha_session_name:150` / `schedule_group_sender_phone_resolution:156`.

`permitted_params` **não foi tocado**: continua `params.permit(:content, :echo_id, :source_id)`.
O `content_attributes` é montado pelo servidor a partir do próprio texto — nada do cliente entra
(há spec cobrindo tentativa de injeção).

---

## 2. Comportamento

### Conversa de grupo (`conversation.group? == true`)

```
IN   content = "👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\nQual Wi-Fi está?"
OUT  content            = "Qual Wi-Fi está?"
     content_attributes = { 'group_sender' => { 'name' => 'Rogerio José Da Silva',
                                                'lid'  => '229480102662169',
                                                'phone' => nil } }
```

- Se o LID já está no cache Redis, o `phone` entra **junto com a mensagem** e nenhum job é enfileirado.
- Se não está, a mensagem entra com `phone => nil` e o job resolve depois (o `after_update_commit`
  do `Message` já dispara `message.updated` no websocket — o front recebe de graça).

### Conversa 1:1

**Zero diferença.** `with_group_sender` retorna os atributos intocados antes de qualquer trabalho.
Há spec explícito provando que até um texto 1:1 que *imita* o formato de grupo passa incólume.

### Casos cobertos pelo extrator

| Entrada | `sender` | `content` |
|---|---|---|
| `👥 *‎Nome (123@lid)*\n\ntexto` | name + lid | `texto` |
| `👥 *Angela Tozi*\n\ntexto` | só name | `texto` |
| `👥 *+55 66 99999-1234*\n\noi` | só phone | `oi` |
| `👥 *5566999991234@c.us*\n\noi` | só phone | `oi` |
| `👥 *229480102662169@lid*\n\ntexto` | só lid | `texto` |
| `👥 *Nome (123@lid)*\n` (anexo) | name + lid | `nil` |
| `👥 *Nome (123@lid)*` (sem quebra) | name + lid | `nil` |
| sem prefixo (1:1) | `nil` | intacto |
| `👥 * *\n\ntexto` (miolo vazio) | `nil` | `texto` |

O **corpo nunca é alterado** além da remoção do prefixo: asteriscos, parênteses aninhados e até um
`(123@lid)` literal no meio do texto do usuário chegam inteiros. `Fulano (Suporte) (123@lid)`
preserva o parêntese que é parte do nome (o JID é ancorado no fim da string).

---

## 3. Cache — o contrato com o I3

```
chave  waha:lid_pn:{session}:{lid}      lid SÓ DÍGITOS, sem "@lid"
valor  telefone em DÍGITOS PUROS       ex.: "556699949191" — sem "+", sem "@c.us"
       string VAZIA = cache negativo    ("a WAHA não conhece este LID agora")
TTL    7 dias (positivo) · 10 min (negativo)
```

Confere com o contrato que o coordenador travou com o I3. **Não construí nada que dependa de
receber JID cru** — a normalização em `read`/`write` é puramente defensiva (idempotente sobre um
valor já limpo), então continua correta com o I3 normalizando na escrita.

`write`/`write_many`/`key` toleram o JID cru dos dois lados
(`"229480102662169@lid" => "5566999991234@c.us"`) e normalizam. O I3 pode chamar

```ruby
Whatsapp::LidPhoneCache.write_many(session_name, pares)   # => nº de entradas gravadas
```

direto com o payload de `/groups`. `pares` aceita **Hash** (`{lid => phone}`) **ou Array de pares**
(`[[lid, phone], ...]`) — a versão só-Hash fazia o lote virar no-op silencioso quando o parser de
participantes devolvia array. Escrita em pipeline, porque `/groups` traz ~900 pares de uma vez.

**Confirmado em campo:** ao rodar a validação, as três chaves de teste **já estavam populadas** —
ou seja, o I3 e eu estamos de fato escrevendo/lendo o mesmo espaço de chaves.

Redis fora do ar não derruba nada: toda operação do cache degrada para `nil`/`false` com log
(spec cobre, inclusive uma ingestão completa com o Redis simulado em queda).

---

## 4. Como testei

### Dado real — extrator contra as 548 mensagens legadas

`RAILS_ENV=production bundle exec rails runner` **somente leitura**:

```
total de mensagens contendo 👥 : 543
  começam com o prefixo        : 514
  parseadas corretamente       : 514  (100,0%)   falhas: 0
  só-prefixo (anexo, sem corpo):  12
as outras 29                   : têm 👥 no MEIO do texto (notificações internas do próprio
                                 ChatSPX, "🚨 Nova mensagem do cliente") — corretamente NÃO tocadas
```

Nenhuma classe de mensagem quebrou. **Zero** mensagens começam com `👥` sem casar o extrator.

Três exemplos entrada → saída (telefones/LIDs mascarados):

```
msg #24458
  IN  : "👥 *‎Rogerio José Da Silva (2294*********69@lid)*\n\nEstá com luz vermelha acesa?"
  OUT : content="Está com luz vermelha acesa?"
        group_sender={"name"=>"Rogerio José Da Silva", "lid"=>"2294*********69", "phone"=>nil}

msg #24120
  IN  : "👥 *Tecnologia (2677*********53@lid)*\n\n🚨 **Conversa aguardando há 20h 7min**..."
  OUT : content="🚨 **Conversa aguardando há 20h 7min**..."
        group_sender={"name"=>"Tecnologia", "lid"=>"2677*********53", "phone"=>nil}

msg #24967   (anexo: prefixo e mais nada)
  IN  : "👥 *‎Rogerio José Da Silva (2294*********69@lid)*\n"
  OUT : content=nil
        group_sender={"name"=>"Rogerio José Da Silva", "lid"=>"2294*********69", "phone"=>nil}
```

### Dado real — resolver + cache contra a WAHA (somente GET)

```
sessão Simplex (WORKING)
  1ª resolução (HTTP)   -> "5566******91"  em 432ms
  2ª resolução (cache)  -> "5566******91"  em   1ms      <- sem round-trip
  3 LIDs reais do dump resolveram: 2294…69, 2603…02, 2677…53

sessão simplexteste (não existe na WAHA)
  1ª tentativa  : ConnectionError após 16.168ms  -> job reagenda com backoff
  2ª tentativa  : nil em 3ms                     -> circuito aberto, não tocou a rede
```

`Conversation#group?` conferido no banco: conversa 12 = `true`, conversa 8 = `false`.

### Suíte

```
bundle exec rspec  (meus 5 arquivos + o spec público pré-existente)
  76 examples, 0 failures        — rodado com 5 seeds diferentes, estável

bundle exec rubocop  (meus arquivos)
  no offenses detected
```

O spec pré-existente `spec/controllers/public/api/v1/inbox/messages_controller_spec.rb`
(1:1, anexo, vCard) roda verde — **sem regressão no caminho antigo**.

---

## 4.1 Broadcast (lista de transmissão) — o que o dado real diz

O coordenador levantou que a WAHA injeta o prefixo quando
`isJidGroup(chatId) || isJidBroadcast(chatId)`, e apontou a conversa `display_id=490` como caso
de broadcast com 12 mensagens legadas. **Medi antes de mexer, e o quadro é outro:**

| Medição (RAILS_ENV=production, somente leitura) | Resultado |
|---|---|
| `@broadcast` em `contacts.identifier`, `contacts.custom_attributes`, `contact_inboxes.source_id`, `conversations.additional_attributes` | **0 em todas** |
| Mensagens em `display_id=490` começando com `👥` | **0** |
| Conversas com mensagem iniciando em `👥` | 8 · **7 são `group? == true`** |
| A única não-grupo (`display_id=415`) | **1** mensagem, e é `message_type=outgoing` |
| Mensagens com `@lid` em conversa não-grupo | 35 → **34 no meio do texto** + 1 prefixo outgoing |

As 12 mensagens da conv 490 são **notas privadas internas** (`outgoing`, `private=true`,
`sender=User#1`) — automação do ChatSPX **citando** uma mensagem de grupo dentro de uma conversa 1:1:

```
*📱 Enviado do WhatsApp*

🚨 **Nova mensagem do cliente!**
👤 **Responsável:** Jorge Miguel
🙍 **Cliente:** Vendas Realizare (GROUP)

💬 **Mensagem (às 19:05):**
"👥 **Atila Ferreira (1162*********70@lid)**
 https://www.instagram.com/p/..."
```

Não é broadcast. O `@lid` está **no meio do texto, dentro de aspas**, e o produtor é nosso, não a
WAHA. A única mensagem não-grupo que de fato começa com `👥` é `outgoing` — **não passa pelo meu
caminho**, que só cria `message_type: :incoming`.

**Decisão.** Mandei um `ask` ao coordenador com estes fatos e a recomendação; **ele expirou por
timeout (15 min) sem resposta**. Segui a recomendação, que é a opção aditiva e reversível: o
mecanismo do fonte da WAHA é real e vale para o futuro, então adicionei broadcast ao guard — mas por
**sinal estrutural**, nunca pelo texto:

```ruby
def waha_multi_participant_chat?
  @conversation&.group? || waha_broadcast_chat?   # custom_attributes[...] termina em '@broadcast'
end
```

`Conversation#group?` **não foi tocado** (contrato C1 intacto); o predicado de broadcast é privado
do controller. Isso preserva a regra dura "1:1 de verdade não muda em nada" — o gatilho continua
sendo o JID do chat, não o conteúdo.

Medi o impacto do guard novo sobre **todas as 2.521 conversas** da base:

```
conversas totais                                   : 2.521
group? == true (já tratadas antes desta mudança)   :    90
broadcast detectado                                :     0
broadcast E não-grupo (delta real do guard novo)   :     0   <- ZERO regressão
sufixos de JID que existem na base                 : @c.us (51), @lid (14), @g.us (12)
```

**Honestidade:** não há uma única conversa de broadcast nesta base, então o caminho novo não foi
exercitado com dado real — é código à espera do caso, coberto por spec sintético. O lado bom é que
isso também prova que **nenhuma** conversa existente muda de comportamento.

**Recado para o I5, diferente do que foi passado:** o que precisa ser saneado na exibição fora de
grupo **não é** o prefixo `👥 *…*` no início — são os **34** casos de `(...@lid)` no **meio** do
texto, em notas privadas de automação. Limpar só o prefixo deixa esses 34 mostrando o identificador.

**Se o coordenador discordar:** reverter é trocar `waha_multi_participant_chat?` de volta por
`@conversation&.group?` em `with_group_sender:107` e apagar os dois métodos (`:126` e `:132`) mais
a constante do topo — 6 linhas de código e um bloco de spec.

---

## 5. Decisões que o coordenador precisa saber

**1. Divergência deliberada com o helper JS.** `parseLegacyGroupContent` faz um `gsub` global
removendo `(\d{8,}@lid)` de **todo** o corpo. Aqui no Ruby o corpo **não é tocado** — só o prefixo
sai. Motivo: em mensagem nova o corpo é texto do usuário, e mutilar texto legítimo é pior do que
deixar um identificador escapar num caso improvável. Para o histórico já gravado o JS continua
sendo a autoridade, e ali o gsub faz sentido.

**2. O Ruby aceita o prefixo sem quebra de linha; o JS exige `\n{1,2}`.** Meu regex fecha com
`(?:\n{1,2}|\z)`, o do front com `\n{1,2}`. Consequência: uma mensagem gravada como
`"👥 *Nome (id@lid)*"` (sem `\n` nenhum) é limpa na ingestão daqui pra frente, mas o front **não**
saneia esse formato no histórico. Não achei nenhuma ocorrência assim no banco (as 12 de anexo têm
`\n`), então é hipotético — mas se o I4/I5 quiser alinhar, é acrescentar `|$` ao regex do helper.
**Não editei o arquivo JS**, conforme o briefing.

**3. Circuit breaker novo.** Medição: sessão inexistente na WAHA **não devolve 404** — estoura o
read timeout. E o `Net::HTTP` faz um retry interno automático, então o custo real é **~16s**, não 8s.
Sem freio, cada mensagem de um grupo em inbox com sessão morta (a inbox 43 tem 98 mensagens e a
sessão `simplexteste` não existe) seguraria um worker do Sidekiq por 16s e ainda reagendaria 3×.
Criei `waha:lid_pn:circuit:{session}` com TTL 60s, no mesmo padrão de `Waha::MessageStatusSyncService`
e do `Waha::GroupSyncService` do I3. Não contorna o timeout do `ApiService` — só evita repeti-lo.

**4. Erro da WAHA é classificado, não engolido em bloco.**
`NotFoundError` → cache negativo (conhecimento estável, não repete). `ConnectionError` → propaga
para o job aplicar backoff (15s / 60s / 300s, 3 tentativas) e abre o circuito. Nada disso toca o
request: **o caminho de ingestão nunca chama a WAHA** — há um spec que quebra se alguém mover essa
chamada para dentro do request.

**5. Fallback da lista popula o cache inteiro.** Quando o lookup direto falha, o resolver puxa
`GET /api/{session}/lids` (até 500) e grava **todos** os pares de uma vez — um job paga, os
participantes seguintes acertam no cache. Protegido por lock (`waha:lid_pn_list_lock:{session}`,
5 min) para N jobs simultâneos não repetirem a listagem.

---

## 6. Riscos e o que ficou de fora

| | |
|---|---|
| **Histórico não foi tocado** | As 514 mensagens já gravadas continuam com o prefixo no `content`. Por desenho — o saneamento é na exibição (I4/I5). |
| **Inbox sem `waha_session_name`** | Não resolve telefone (fica `nil`). As conversas 12 e 8 estão na inbox 2, que tem `waha_session_name = nil`. O **nome** do autor continua saindo normalmente — só o telefone falta. |
| **Sessão `simplexteste` está morta** | Inbox 43 (98 msgs) vai bater no circuito e ficar sempre com `phone => nil`. Não é regressão: hoje não há telefone nenhum. |
| **`group_sender` não é retroativo** | Vale só para mensagens novas. Backfill seria escrita em massa no banco — fora do escopo e proibido pelo briefing. |
| **Um usuário 1:1 pode "imitar" o formato** | Só em grupo o extrator roda, então isso não afeta 1:1. Dentro de um grupo, uma pessoa que digite `👥 *fulano*` + linha em branco teria o texto reinterpretado como autor. Aceito: é o preço de o produtor externo não ter um campo estruturado. |
| **Sem migration, sem coluna, sem tabela** | Cumprido. Nada de `db/`. |

**Não fiz:** commit, restart, precompile, deploy, SSH para outra VM, POST na WAHA, nem edição em
arquivo de outro worker.
