---
titulo: Módulo Rede Social — Instagram no SPX
status: LEVANTAMENTO — capacidades MEDIDAS na conta da BigStore em 18/08/2026
motivador: BigStore (conta 7), mas o desenho nasce agnóstico
substitui: docs/SPEC-instagram-comentarios.md (que tratava só de comentários e errava o bloqueio)
---

# Módulo Rede Social — Instagram no SPX

> **Tudo abaixo foi testado contra a conta real da BigStore** (`bigstoreutilidades`,
> `17841468839878751`) com o token da inbox 57, na noite de 17→18/08/2026. Onde eu não testei,
> está dito. Nada aqui vem só de documentação da Meta.

---

## 1. O achado que muda o plano

A spec anterior dizia que comentário exigia escopo com revisão da Meta, e tratava o resto como
território desconhecido. **Errado nos dois pontos.** A permissão de comentários estava em
`Standard access`, ativa, sem análise pendente — o que faltava era o SPX **pedir** o escopo
(`REQUIRED_SCOPES` tinha só dois) e **assinar** o campo (`Channel::Instagram#subscribe` tinha três
strings fixas). As duas coisas foram resolvidas em 18/08 sem deploy, e o webhook de comentário
chegou com payload completo.

E o levantamento de capacidade mostrou que **a maior parte do que se quer construir já está
liberada com o token de hoje**. O que falta de verdade é um escopo só: insights.

---

## 2. Matriz medida

### ✅ Já funciona, com o token que está no ar

| capacidade | endpoint | medido |
|---|---|---|
| Perfil da conta | `me?fields=followers_count,follows_count,media_count` | 184.547 seguidores · 300 seguindo · 1.067 publicações |
| Bio, site, foto | `me?fields=biography,website,profile_picture_url` | 200 |
| **Curtidas por publicação** | `me/media?fields=like_count,comments_count` | 218 curtidas no reel mais recente |
| Tipo de mídia | `media_product_type` | distingue `REELS` de feed |
| Comentários (texto) | `{media}/comments` | 155 lidos em 12 publicações |
| **Autor do comentário** | `fields=from{id,username}` | `@pauloseze` — antes vinha vazio |
| **Se a pessoa SEGUE a conta** | `{user-id}?fields=is_user_follow_business` | `true`, tanto pelo id do comentário quanto pelo IGSID da DM |
| Seguidores do usuário | `fields=follower_count` | 866 |
| **Publicações onde a conta foi MARCADA** | `me/tags` | 200, com conteúdo real (UGC) |
| Stories ativos | `me/stories` | 3 stories |
| Transmissões ao vivo | `me/live_media` | 200 (vazio) |
| **Webhook de comentário** | `field: comments` | ✅ provado ponta a ponta, ver §3 |

### 🔒 Exige `instagram_business_manage_insights` (403 hoje)

| capacidade | endpoint |
|---|---|
| Alcance, salvamentos, compartilhamentos por publicação | `{media}/insights?metric=reach,saved,shares` |
| Alcance e visitas de perfil por dia | `me/insights?metric=reach&period=day` |
| Série histórica de seguidores | `me/insights?metric=follower_count&period=day` |
| Cota de publicação restante | `me/content_publishing_limit` |

### 🔒 Exige `instagram_business_content_publish`

Publicar e agendar: `POST /{ig-user}/media` (cria o container) → `POST /{ig-user}/media_publish`.
Suporta imagem, vídeo/reel, carrossel e story. **Não testado** — é escrita, e a conta é de cliente.

### ❌ Não existe. Ponto.

- **Evento de "novo seguidor".** O Instagram **não** manda webhook quando alguém segue. Dá para
  saber **quantos** (`followers_count`, e a série com o escopo de insights), nunca **quem**.
  Qualquer promessa de "avisar quando fulano seguir" é impossível nesta API.
- **Quem curtiu.** A lista de quem curtiu não é exposta para conta profissional. Só o número.
- **Webhook de curtida.** Não existe campo. Curtida se acompanha por número, não por evento.

> Vale dizer isso ao cliente antes de desenhar tela: "novo seguidor" e "quem curtiu" são as duas
> coisas que todo mundo pede primeiro e as duas que a plataforma não entrega.

---

## 3. O payload de comentário (real, capturado em 18/08 02:31:40)

```json
{"object": "instagram",
 "entry": [{"id": "17841468839878751", "time": 1787020299,
   "changes": [{"field": "comments",
     "value": {"id": "18096877037297620",
               "text": "Top",
               "from": {"id": "1737491620526400", "username": "pauloseze"},
               "media": {"id": "17959910835171280", "media_product_type": "REELS"}}}]}]}
```

Três detalhes que mudam o código:

1. **O canal se acha por `entry[0].id`**, não por `messaging.recipient.id` como nas DMs. O
   `find_channel` atual não serve para este caminho.
2. O `value.id` é o endereço da resposta pública (`POST /{comment-id}/replies`) **e** da resposta
   privada (§4).
3. Hoje esse payload é classificado como **evento de teste** e descartado sem rastro
   (`Webhooks::InstagramEventsJob#test_event?` = `entry[:changes].present?`). Observado: o job
   rodou e a inbox continuou com as mesmas 1.055 conversas. O discriminador correto está no
   próprio comentário do arquivo — payload de teste tem `entry.id == "0"` e sender `12334`.

---

## 4. "Comente QUERO e receba o link na DM"

É a campanha que o cliente mais pede, e **as três peças foram verificadas** — menos o envio.

| passo | como | estado |
|---|---|---|
| detectar a palavra | `value.text` do webhook | ✅ provado |
| saber quem é | `value.from.id` + `username` | ✅ provado |
| **checar se segue** | `{from.id}?fields=is_user_follow_business` | ✅ **provado — devolveu `true`** |
| mandar na DM | `POST /{ig-id}/messages` com `recipient: {comment_id: ...}` | ⚠️ **não testado** (é envio) |

**Regras da Meta a respeitar** (a confirmar na doc antes de implementar): a resposta privada tem
janela a partir do comentário e é **uma por comentário**. Isso muda o desenho: a tentativa precisa
ser idempotente e registrada, porque não há segunda chance.

**A trava de "só quem segue" é decisão de produto, não técnica.** Ela funciona; a pergunta é o que
fazer com quem **não** segue — responder publicamente convidando a seguir, ignorar, ou mandar
assim mesmo. Cada opção tem um custo de imagem diferente.

---

## 5. O formato: a página **Rede Social**

Item de topo na sidebar (operação diária, ao lado de Conversas e Kanban — não em Configurações),
gateado por conta e admin-only. Abas:

**① Comentários** — a primeira e a que resolve o pedido original ("ver onde está"). Lista com a
publicação (miniatura + legenda), autor com `@`, texto, hora, se a pessoa segue, e **o que a IA
respondeu — ou que não respondeu e por quê**. Filtros por publicação e por respondido. Ação de
responder à mão. É aqui que mora a auditoria que a decisão "comentário não vira conversa" tirou.

**② Publicações** — cada post com curtidas, comentários e, com o escopo de insights, alcance,
salvamentos e compartilhamentos. **O cache de publicações que essa aba precisa é o MESMO dado que
a IA precisa para responder comentário** (sem legenda e mídia ela responde "quanto custa?" sem
saber do quê). Tela e cérebro são a mesma obra — é o argumento mais forte para fazer as duas juntas.

**③ Campanhas de comentário** — a regra "comente X → manda Y na DM", com condição de seguidor,
contador de entregas e a lista de quem recebeu. Nasce desligada.

**④ Marcações (UGC)** — `me/tags` já funciona hoje e ninguém está olhando: são publicações de
terceiros marcando a marca. Para varejo é conteúdo de graça e prova social. **É a capacidade de
maior retorno por menor esforço da lista inteira.**

**⑤ Agenda** — programar publicação (exige o escopo de publish). O agendamento é nosso: guardamos
e publicamos na hora, com o `ScheduledMessage` já existente como precedente de desenho.

**⑥ Painel** — seguidores, evolução, e o que os insights permitirem.

---

## 6. Fases sugeridas

1. **Comentários ponta a ponta** — roteamento por `field`, cache de publicações, aba ①+②
   (sem insights), resposta pública. Já está tudo destravado; é só código nosso.
2. **Marcações** — aba ④. Barata, e provavelmente a que o cliente mais gosta de ver.
3. **Campanha "comente X"** — aba ③, depois de confirmar as regras de janela da resposta privada.
4. **Insights** — pedir `instagram_business_manage_insights` (mesmo caminho do de comentários:
   ver se está em `Standard access` no Business MW) e completar ② e ⑥.
5. **Publicação/agenda** — aba ⑤. É a de maior risco operacional: publicar errado é público e
   permanente.

---

## 7. Multi-tenant — o que precisa mudar antes de qualquer coisa

Duas constantes globais fingem que toda box é igual, e **as duas quebram outros clientes** se
alguém acrescentar um item sem pensar:

- **`Instagram::IntegrationHelper::REQUIRED_SCOPES`** — vira a tela de consentimento de toda conta
  em toda box. Escopo que o app da VM não tem faz o OAuth falhar por escopo inválido, e **ninguém
  mais conecta Instagram naquela box**. A Tozi usa outro app (`SPX Lead Ads Tozi`), com outro
  conjunto de permissões.
- **`Channel::Instagram#subscribe`** — manda a lista inteira numa chamada só e engole o erro com
  `rescue StandardError; true`. Se a chamada falhar, o canal pode ficar **sem assinatura nenhuma** e
  o DM morre em silêncio.

As duas precisam virar configuráveis (por instalação ou por conta), com a falha visível. É a
primeira tarefa da frente, antes de qualquer feature.

---

## 8. Armadilhas conhecidas

- **Post em colab não entrega comentário** para o app da conta — dono compartilhado muda a rota.
  Descoberto ao vivo: o comentário no reel de inauguração nunca chegou. A BigStore usa colab em
  lançamento, então isso não é borda: **declarar como limitação antes de prometer cobertura**.
- **A Meta omite em silêncio quando falta permissão.** Pedir `username` sem o escopo devolve
  `HTTP 200` com o campo ausente, não erro. Todo diagnóstico aqui tem que ser por **capacidade**
  (o campo veio?), nunca por status HTTP.
- **Reconectar a inbox é a operação mais perigosa do módulo.** O callback casa o canal por
  `me.user_id`; autorizar logado na conta errada **cria uma inbox nova** — foi o incidente de
  04/08, quando o perfil pessoal do Paulo virou a inbox 100.
- **O escopo não sobrevive à tela.** Reconectar pelo botão do SPX hoje minta só dois escopos e
  **perde** a permissão de comentários. Até o §7 ser resolvido, ninguém deve reconectar por lá.
- **`me/insights` responde 403 com "Application does not have permission"** — mensagem genérica que
  não nomeia o escopo. Não perder tempo procurando outra causa.

---

## 9. Perguntas em aberto

1. **A lista completa de campos de webhook** do Instagram no painel do Business MW — o print
   cortou depois de `comments` e `live_comments`. Saber o que mais existe muda o §5.
2. **`instagram_business_manage_insights` está em `Standard access`?** Se estiver, ② e ⑥ saem sem
   revisão, como aconteceu com comentários.
3. **Regras exatas da resposta privada** (janela e limite por comentário) — pesquisa na doc da
   Meta, não dá para deduzir do repo.
4. **Quem não segue, o que recebe?** (§4) — decisão de produto.
5. **Agendamento de post entra?** É a aba de maior risco: publicação errada é pública e permanente,
   e provavelmente pede aprovação de duas pessoas, como o deploy.
