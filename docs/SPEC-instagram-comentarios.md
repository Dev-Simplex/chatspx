# SPEC — comentários no Instagram: ler, responder e levar pra DM

> **Nomeada por capacidade, não por cliente, de propósito.** O caso que motiva é a BigStore, mas
> tudo aqui é código compartilhado e precisa nascer agnóstico e gateado por conta — a mesma regra
> que foi violada quando conduta de óticas da Fábrica vazou pra Tozi.
>
> Levantado em 11/08/2026 **lendo o código**, não os docs. Cada afirmação abaixo tem arquivo e
> linha. O que eu **não** verifiquei está marcado como pergunta aberta — a maior parte é do lado da
> API da Meta, que não dá pra responder de dentro do repo.

---

## 1. O pedido, decomposto

O pedido original: *"a IA responde comentários; se o comentário merecer, vira DM; e tem campanha do
tipo 'comente QUERO e receba um cupom exclusivo na DM'. Também tem análise do conteúdo para
responder um comentário, e para responder uma DM que veio de um story."*

São **cinco capacidades distintas**, em estados muito diferentes:

| capacidade | estado |
|---|---|
| IA responde DM que veio de **story** | ✅ **funciona hoje** |
| Receber **comentário** de post | ❌ não existe — e há uma armadilha (§3) |
| **Responder** comentário publicamente | ❌ não existe |
| **Comentário → DM** (`private_replies`) | ❌ não existe, zero ocorrências no repo |
| IA ver o **conteúdo do post** comentado | ❌ não existe |

---

## 2. O que já funciona: story → DM

Quando alguém responde a um story, o anexo chega com `file_type: :ig_story` — enum próprio, **não**
`:image` (`app/models/attachment.rb:43`, onde `ig_reel => 9, ig_post => 10, ig_story => 11`). O
builder do canal já baixa o arquivo (`app/builders/messages/instagram/base_message_builder.rb:122`).

E o Captain **enxerga** esse story: o `attachment_parts` separa os `:ig_story` que são imagem e os
manda como visão para o modelo
(`enterprise/app/services/captain/open_ai_message_builder_service.rb:~65`). O comentário no próprio
código explica o porquê: sem isso, o story caía no balde genérico e o agente recebia apenas
`"User has shared an attachment"` — cego exatamente ao que o cliente estava respondendo.

**Limite conhecido:** story em **vídeo** fica de fora, porque o Captain não lê vídeo. Segue como nota
de texto.

**Consequência prática:** a parte "responder DM que veio de story" **não precisa de código novo**.
É balde 1 — conduta no banco da conta. Pode entregar valor antes de qualquer PR.

---

## 3. 🔴 A armadilha: comentário chega como `changes` e é descartado em silêncio

Duas coisas, e a ordem entre elas importa:

**(a) O canal não assina comentários.** `Channel::Instagram#subscribe`
(`app/models/channel/instagram.rb:45-53`) assina exatamente:

```ruby
subscribed_fields: %w[messages message_reactions messaging_seen]
```

`comments` não está na lista. Por isso nenhum comentário chega hoje, e por isso a armadilha (b)
ainda não mordeu ninguém.

**(b) Se assinar, o comentário é engolido.** O `Webhooks::InstagramEventsJob` só processa
`entry[:messaging]`, que são as DMs. O `entry[:changes]` — que é exatamente por onde a Meta entrega
comentário — é classificado como **evento de teste**
(`app/jobs/webhooks/instagram_events_job.rb:54-66`):

```ruby
def test_event?(entry)
  entry[:changes].present?
end
```

E o `Instagram::TestEventService` só age se `sender.id == '12334' && recipient.id == '23245'`
(`app/services/instagram/test_event_service.rb`). Um comentário real não casa, então `perform`
devolve `false` e **nada acontece**.

O modo de falha é o pior tipo: sem erro, sem exceção, sem retry — e logado como
`"Processing Instagram test webhook event"`, que manda quem for depurar para o lugar errado.

> **Primeira coisa que esta frente conserta:** separar "evento de teste" de "mudança de verdade".
> Hoje `changes.present?` significa as duas coisas.

---

## 4. O que falta, peça por peça

**4.1 Ingest de comentário.** Assinar `comments` e rotear `entry[:changes]` por `field`, em vez de
tratar tudo como teste. Decisão de modelagem que vem junto: **um comentário vira uma conversa?**
Uma thread por post? Um tipo de mensagem novo? Isso define o resto — e vale lembrar que a inbox do
Instagram herda o mesmo `lock_to_single_conversation` que rege o WhatsApp, com as consequências que
já conhecemos.

**4.2 Resposta pública ao comentário.** É outro endpoint da Graph, não o de mensagem. O
`Instagram::SendOnInstagramService` hoje só sabe `POST /{ig_id}/messages`
(`app/services/instagram/send_on_instagram_service.rb:15-19`). Responder comentário é um serviço
novo, irmão desse.

**4.3 `private_replies` — comentário vira DM.** **Zero ocorrências no repositório inteiro.** É a peça
que sustenta a campanha *"comente QUERO e receba o cupom na DM"*, e é capacidade nova de verdade.
⚠️ A janela do `private_replies` na Meta tem regras próprias (prazo a partir do comentário, uma
resposta por comentário) — **isso precisa ser pesquisado na doc da Meta**, não dá pra deduzir do
repo.

**4.4 A IA ver o post comentado.** Esta é a mais subestimada. Para responder *"quanto custa?"* num
comentário, o agente precisa da **mídia e da legenda do post** — hoje ele teria só o texto do
comentário. O caminho conceitual já existe e está provado pelo story (§2): baixar a mídia e entregar
como visão ao modelo. O que muda é a origem do dado — outro campo da API. Reusar o desenho do
`attachment_parts` é o caminho barato.

**4.5 A campanha "comente X".** É 4.1 + 4.2 + 4.3 mais um gatilho por palavra-chave e a entrega do
cupom. **Nasce desligada e por conta** — nenhuma conta muda de comportamento pelo merge.

---

## 5. `HUMAN_AGENT` — decisão do Paulo, não da frente

`Instagram::SendOnInstagramService#merge_human_agent_tag`
(`app/services/instagram/send_on_instagram_service.rb:24-32`):

```ruby
global_config = GlobalConfig.get('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')
return params unless global_config['ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT']
params[:messaging_type] = 'MESSAGE_TAG'
params[:tag] = 'HUMAN_AGENT'
```

É **GlobalConfig**: chave da instância inteira, não por conta. Ligada, ela carimba **toda** mensagem
de **todos** os canais Instagram — Tozi, Fábrica e BigStore juntos. A tag `HUMAN_AGENT` dá janela de
7 dias e, pela política da Meta, **é para atendimento humano, não para bot**.

Mexer nisso atinge todos os clientes de uma vez. **Não tocar sem decisão explícita.** Se a
necessidade for por conta, o gate precisa deixar de ser global — e isso é mudança de contrato.

---

## 6. Sem HSM, a cadência não existe no Instagram

Não há template no Instagram. Fora da janela de 24h, **nada sai**. Todos os motores do SPX
(disparo, follow-up, reativação) pressupõem template — no Instagram, cada um precisa de ramo por
canal, ou cala.

Isso conversa direto com o `private_replies`, que é justamente um caminho de mensagem fora do fluxo
normal — e é mais uma razão para pesquisar as regras dele antes de desenhar cadência.

---

## 7. Perguntas abertas

1. **Comentário vira conversa?** Define modelagem, inbox, atribuição e como o eval enxerga isso.
2. **Regras do `private_replies` na Meta** — prazo, limite por comentário, permissões. Pesquisa
   externa, não dá pra responder do repo.
3. **Qual app Meta serve a `.232`?** A regra de **um app por VM** vale porque o webhook do produto
   tem UMA URL por app. Qual app está lá decide o que é possível para a BigStore.
4. **Contradição não resolvida nos docs:** o STATE de 04/08 diz que a BigStore foi conectada na
   `.232`; o apanhado de 10/08 diz que a frente `bigstore-ig` não tem canal nem credencial de app.
   As duas podem ser verdade (a inbox existe; a frente de desenvolvimento não tem app próprio pra
   testar) — **conferir ao vivo antes de planejar.**
5. **Teto de 1.000 caracteres** por mensagem no Instagram: o humanizer da conta precisa respeitar.

---

## 8. Como verificar o que está escrito aqui

```bash
grep -n "subscribed_fields" app/models/channel/instagram.rb
sed -n '54,66p' app/jobs/webhooks/instagram_events_job.rb
grep -rn "private_replies" app enterprise lib     # deve devolver vazio
grep -n "ig_story" enterprise/app/services/captain/open_ai_message_builder_service.rb
sed -n '24,32p' app/services/instagram/send_on_instagram_service.rb
```

O que **não** foi verificado e não deve ser tratado como fato: qualquer afirmação sobre o
comportamento da API da Meta (janelas, limites, permissões de `private_replies`). Isso é pesquisa
externa — e foi confundir leitura com medição que estragou o dia 10/08.
