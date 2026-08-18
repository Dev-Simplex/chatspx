---
titulo: Contrato — janela de 7 dias no Instagram (tag `HUMAN_AGENT`)
status: PROPOSTA — aguardando decisão do Paulo (§7) e a resposta da §4
motivador: BigStore (conta 7), mas vale para toda conta com inbox de Instagram
data: 2026-08-18
---

# Contrato — janela de 7 dias no Instagram

> **A restrição de 24h não é invenção do SPX.** Fora dela a Meta recusa mensagem livre no
> Instagram, e o `MessageWindowService` só reflete isso. O que o SPX faz de errado é **nunca usar**
> o caminho oficial de 7 dias — e não conseguir usá-lo, do jeito que está implementado.

## 1. O que está medido

Na BigStore (conta 7, inbox 57), em 18/08/2026:

- **1.003 das 1.146 conversas não resolvidas estão com o composer bloqueado** — 87,5%.
- Mas em 60 dias, só **44 de 1.281 respostas (3,4%)** saíram depois de 24h, e a maioria delas é
  `mencionou você na conversa`, não atendimento.

Os dois números juntos: **a dor hoje é latente, não aguda** — porque o time responde pelo **app do
Instagram**, onde não existe bloqueio nenhum (2.643 saídas por `external_echo` em 30 dias). No dia
em que eles migrarem para o painel, que é o objetivo do produto, os 87,5% viram atrito imediato.

## 2. Como está hoje, e por que ninguém liga

`Conversations::MessageWindowService#instagram_messaging_window` já sabe devolver 7 dias:

```ruby
def meta_messaging_window(config_key)
  GlobalConfigService.load(config_key, nil) ? MESSAGING_WINDOW_7_DAYS : MESSAGING_WINDOW_24_HOURS
end
```

A chave está **desligada** (`ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT = nil`). E ligar, hoje, faz duas
coisas erradas de uma vez:

1. **É `InstallationConfig` global** — vale para toda conta da box. Não existe "ligar só para a
   BigStore".
2. **Carimba `HUMAN_AGENT` em tudo que sai**, sem condição nenhuma
   (`Instagram::BaseSendService#merge_human_agent_tag`): assistente, AgentBot e humano saem pelo
   mesmo caminho, dentro **e** fora da janela. Uma resposta automática na hora 30 sairia declarando
   à Meta que **um humano a escreveu**.

## 3. O que a Meta exige

Verificado na doc oficial em 18/08:

- A janela é de **7 dias, contada da mensagem do usuário**.
- A feature chama-se **Human Agent** e **passa por App Review**, com **verificação de negócio**.
- O uso é para **representante humano respondendo manualmente**, quando o caso não se resolve na
  janela padrão. Conteúdo automatizado não é o propósito da tag.
- A Meta declara que **monitora uso indevido**.

Ou seja: não é uma chave que se liga: é um pedido formal, e o que se promete no pedido tem que ser
o que o código faz.

## 4. ✅ RESPONDIDO — a tag vale nesta API, e falta só App Review

A dúvida era se a `HUMAN_AGENT` valeria no *Instagram API with Instagram Login*
(`graph.instagram.com`), já que a documentação dela vive no *Messenger Platform*.

**Testado ao vivo em 18/08**, na conversa 1 da inbox 57 (contato do próprio Paulo, janela fechada
havia 75h — sem cliente no meio). Dois envios, e o formato do erro é a resposta:

```
1. SEM a tag  → 403 · code 10 · subcode 2534022
   "Essa mensagem foi enviada fora do período permitido."

2. COM a tag  → 403 · code 10
   "To use 'Human Agent', your use of this endpoint must be reviewed and
    approved by Facebook."
```

O segundo erro **não recusa o parâmetro** — recusa a **feature não aprovada**, e ainda diz *"your
use of **this endpoint**"*. Ou seja:

- a janela de 24h é real e é a Meta que aplica (erro 1 prova);
- **o caminho de 7 dias existe nesta API** e está a uma App Review de distância (erro 2 prova).

Nenhuma das duas mensagens foi entregue (as duas voltaram 403).

**Consequência de prioridade:** a App Review vira o **caminho crítico**, porque é o único item com
prazo externo. O código do §5 é pequeno e pode ser feito em paralelo — mas sem a aprovação ele não
muda nada na prática.

## 5. O desenho correto

Três condições, todas obrigatórias, para a tag ser aplicada:

| condição | por quê |
|---|---|
| conta optou (`custom_attributes['instagram_human_agent']`) | a global não deixa escolher cliente |
| remetente é `User` (humano) | assistente e AgentBot **nunca** herdam o crachá |
| a mensagem está **fora** das 24h | dentro da janela a tag é desnecessária, e usá-la é ruído |

Com isso a tag passa a significar o que a Meta pretende, e o pedido de App Review descreve o
comportamento real: *só o atendente humano, só quando passou da janela padrão*.

## 6. O efeito colateral que precisa de guarda

`can_reply?` é **por conversa**, não por remetente. Dando 7 dias à conta, o composer abre para o
humano — mas o mesmo `can_reply?` libera o **follow-up da IA** (a guarda que o PR #35 colocou no
`FollowupJob`). Uma cutucada automática no quinto dia sairia **sem** a tag (o remetente é
assistente) e a Meta recusaria.

Hoje isso ao menos **falha visível**, porque o PR #58 fez a exceção marcar a mensagem como
`failed`. Mas falhar não é o objetivo: **o caminho automático deve continuar preso às 24h**,
independente da janela da conta. Quem ganha os 7 dias é o humano, não o motor.

## 7. O que fazer, e por que é urgente

A urgência não estava clara para mim até o Paulo apontar a assimetria que decide tudo:

> **No WhatsApp, janela fechada tem saída — o template (HSM). No Instagram não tem nenhuma.**

Não existe template no Instagram. Passadas as 24h, o atendente simplesmente **não consegue
responder** pelo painel, e o único jeito é sair do produto e usar o app do Instagram — que é
exatamente o que o time da BigStore faz hoje, com 2.643 respostas por fora em 30 dias. O bloqueio
não é inconveniência: é o produto perdendo o atendimento para o aplicativo do cliente.

**Caminho crítico:** pedir a feature **Human Agent** no app `Business MW` (`478777497423728`), em
`Revisão do app → Permissões e recursos`. Exige verificação de negócio. É o único item com prazo
externo — o código do §5 é pequeno e sai em paralelo.

**O que o pedido descreve é o §5, literalmente:** atendente humano respondendo manualmente, só
fora da janela padrão, nunca automação. Se o pedido e o código contarem a mesma história, a
aprovação é a descrição do comportamento real — não uma promessa a cumprir depois.

## 8. Não-objetivos

- **Não** é cadência proativa. A tag alarga a resposta a quem falou com você; passados os 7 dias,
  nada sai. Instagram não tem template, e reabordagem continua sem solução.
- **Não** substitui o `private_replies` de comentário, que tem janela própria.
- **Não** muda WhatsApp, que tem 24h reais e HSM para o resto.
