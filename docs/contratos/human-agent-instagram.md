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

## 4. ⚠️ A pergunta que precede tudo

**A tag vale na API que o SPX usa?** O SPX conecta pelo *Instagram API with Instagram Login*
(`graph.instagram.com`, `enable_fb_login: '0'`), enquanto a documentação da `HUMAN_AGENT` está no
*Messenger Platform*. São produtos diferentes, e não está confirmado que o mesmo `messaging_type:
MESSAGE_TAG` seja aceito no endpoint que usamos.

**Teste decisivo, barato e sem cliente no meio:** a inbox **56 (Midwest, conta 3)** é do próprio
Paulo. A janela dela abriu em 18/08 14:47 (−04) e fecha 24h depois. Passado esse prazo, um envio
**com** e outro **sem** a tag respondem a pergunta de uma vez: se o com-tag passa e o sem-tag é
recusado, a capacidade existe.

**Não desenhar nada antes dessa resposta.** Se a tag não valer nesta API, todo o resto deste
contrato é inútil e a janela de 24h é o teto real.

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

## 7. Decisão do Paulo

1. **Pedir a feature Human Agent** no app `Business MW` (`478777497423728`)? Passa por App Review e
   verificação de negócio — é o item de maior prazo externo deste contrato.
2. Vale a pena **antes de o time migrar para o painel**? Hoje eles respondem pelo app do Instagram e
   não sentem o bloqueio; o ganho aparece junto com a migração, não antes.
3. Se a §4 responder que a tag **não** vale nesta API, aceitamos 24h como teto e o assunto morre —
   ou vale reavaliar o produto (por exemplo, avisar o atendente antes de a janela fechar, em vez de
   bloquear depois)?

## 8. Não-objetivos

- **Não** é cadência proativa. A tag alarga a resposta a quem falou com você; passados os 7 dias,
  nada sai. Instagram não tem template, e reabordagem continua sem solução.
- **Não** substitui o `private_replies` de comentário, que tem janela própria.
- **Não** muda WhatsApp, que tem 24h reais e HSM para o resto.
