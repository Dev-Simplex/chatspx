# S-02 — Ficha duplicada trava o envio na caixa WhatsApp Cloud (422 mudo, para sempre)

**Responsavel:** Nicolas Silva
**Origem:** suporte de 24-25/09/2026 — TOZI (`tozi.chatspx.app`, conta 6). Video da agente
tentando falar com a contato "Juliana" pelo **Nova conversa** e recebendo
"Ocorreu um erro ao criar a conversa. Tente novamente mais tarde."
**Branch:** sair de `producao`, 1 PR. Conventional Commits. `bundle exec rubocop -a` / `pnpm eslint`.
Nao deployar.

---

## S-02 — O vinculo do numero pertence a outra ficha, e o codigo tenta roubar com um formato invalido

| | |
|---|---|
| Tipo | BUG (bloqueio de atendimento) |
| Valor | Cliente volta a conseguir falar com contatos cujo numero ja esta vinculado a uma ficha duplicada. Hoje sao **3 contatos** da TOZI que **nenhum agente consegue contatar** pelas caixas Cloud — e o numero cresce a cada ficha duplicada criada |
| Confianca | **PROVADO no log de producao** (requests `52d9f660-795a-42be-b64c-87162e26a989` e `37f48188-5bea-4c19-9d20-c19366af585e`, 25/09 10:20:04 e 10:20:38 -0400) |
| Ja existe? | O caminho de recuperacao existe (`update_old_contact_inbox`), mas **nunca funcionou** em caixa Cloud: 36.742 vinculos na conta 6 e **zero** com o formato que ele grava |
| Onde | `app/builders/contact_inbox_builder.rb:107-133` (`create_contact_inbox`, `update_old_contact_inbox`, `new_source_id`) · `app/models/contact_inbox.rb` (`WHATSAPP_CHANNEL_REGEX`, `validate_whatsapp_source_id`) · `app/controllers/api/v1/accounts/conversations_controller.rb` (`contact_inbox`) |
| Esforco | pequeno (backend) + pequeno (front, so a mensagem) |
| Como validar | Ver "Como validar" no fim |

---

## A cadeia, como o log mostra

```
Parameters: inbox_id 91, contact_id 103231, source_id "5565992476302",
            template tozi_venda_abertura (variaveis preenchidas: "Juliana" / "Adrian")
[ContactInboxBuilder] RecordNotUnique 5565992476302 103231 91
Handled error: ActiveRecord::RecordInvalid: Validation failed:
               Source invalid source id for whatsapp inbox. valid Regex (?-mix:^\d{1,15}\z)
Completed 422 Unprocessable Content
```

1. O agente manda a primeira mensagem pela caixa **91 ([TOZI] FIXO, `Channel::Whatsapp`/Cloud)**.
2. O `ContactInboxBuilder` tenta criar o vinculo contato↔caixa com `source_id = 5565992476302`
   (o wa_id, telefone sem `+`) e bate em `RecordNotUnique`: **esse numero ja esta vinculado a outra
   ficha** na mesma caixa.
3. O builder entao chama `update_old_contact_inbox`, que renomeia o vinculo da outra ficha para
   `new_source_id` = `"whatsapp:#{source_id}#{rand(100)}"` (`contact_inbox_builder.rb:127-133`).
4. Esse prefixo e formato do **Twilio**. Em `Channel::Whatsapp` o model exige `^\d{1,15}\z`
   (`WHATSAPP_CHANNEL_REGEX`), entao o `update!` e rejeitado, a excecao sobe e a criacao inteira
   morre em **422**.
5. O front mostra o alerta generico do modal — o agente nao tem como saber o que aconteceu.

**E permanente.** O `retry` do builder cai sempre no mesmo lugar: medidas **10 tentativas** do mesmo
par de fichas (8 em 24/09 + 2 em 25/09), todas com o mesmo erro.

## Como as duas fichas aparecem

| ficha | nome | telefone | vinculo na caixa 91 |
|---|---|---|---|
| 102780 (21/09) | Juliana Aguiar | +5565992476**382** | segura o `source_id` **5565992476302** |
| 103231 (24/09) | Juliana | +5565992476**302** | nenhum — e a que trava |

Um digito trocado na digitacao. Como a Meta devolve o **wa_id real**, o vinculo da ficha errada
ficou com o numero certo, e a ficha certa nao consegue mais criar o dela. Ver
[[t44-ficha-duplicada-tozi]].

## Tamanho do problema (medido na conta 6, so leitura)

- 36.742 vinculos em caixas `Channel::Whatsapp`;
- 15.028 com wa_id diferente do telefone da ficha — **normal**, e o nono digito;
- **3 pares em colisao real** (fichas que travam ao tentar enviar):
  `103231 ↔ 102780`, `102270 ↔ 83488`, `98288 ↔ 73673`;
- **0** vinculos com o formato `whatsapp:` — a prova de que a renomeacao nunca gravou.

---

## Fix

### A. Nao roubar o vinculo da outra ficha (principal)

Em caixa `Channel::Whatsapp`, quando o `source_id` ja pertence a **outra** ficha, o certo nao e
renomear o vinculo alheio — se funcionasse, partiria a thread do outro contato em silencio. O
`create` deve recusar com um erro de negocio:

- **422** com `error_code: 'contact_inbox_conflict'` e `meta` com `id`/`name`/`phone_number` da ficha
  que segura o numero;
- front (`ComposeConversation.vue`, ja preparado pelo PR #225 para ler o corpo do erro): "Este numero
  ja pertence a ficha **Juliana Aguiar**. Mescle as fichas para continuar." — com link para a ficha.

### B. `new_source_id` valido por canal (defesa)

Onde a renomeacao continuar valendo (Twilio/SMS), manter o formato atual; em `Channel::Whatsapp`
gerar **so digitos** (`^\d{1,15}\z`). Hoje `@inbox.whatsapp? || @inbox.sms? || @inbox.twilio?` joga
o prefixo do Twilio tambem na Cloud — e e so isso que produz o 422.

### C. Rake de leitura para achar os travados

`rake spx:contact_inbox_colisoes[account_id]` — lista os pares em colisao (foi assim que os 3 da TOZI
apareceram). Serve para varrer as outras VMs antes de alguem abrir chamado.

### Fora deste PR

- **Mesclar/corrigir as 3 fichas da TOZI** e destravar os contatos: e escrita em producao de cliente,
  decisao do dono ([[tozi-nao-tocar]]).
- **Identificacao dos contatos na busca** (telefone, caixa, quem atende, selo de ficha duplicada):
  task irmã, ja pedida — e a prevencao para que duas fichas quase identicas nao convivam ate virar
  bloqueio de envio.

---

## Como validar

**Specs (request):**

1. Contato A com vinculo `5565992476302` na caixa Cloud; contato B com telefone `+5565992476302`.
   `POST /conversations` para B responde **422** com `error_code: 'contact_inbox_conflict'`, a
   mensagem **nao** e criada e o vinculo de A **continua intacto** (hoje: 422 do Rails e o vinculo de
   A sobrevive por acidente, porque o update falha).
2. Mesmo cenario em caixa Twilio: comportamento atual preservado.
3. Contato sem conflito: cria normalmente (nao regredir).

**Em campo (staging nicolas):** criar duas fichas com o mesmo numero numa caixa `Channel::Whatsapp`,
tentar o Nova conversa pela segunda e conferir a mensagem — hoje some no erro generico.

**Na TOZI (so leitura):** repetir a consulta dos pares em colisao e conferir que os 3 sumiram depois
que as fichas forem mescladas.

---

## Contexto

O agente so viu "Ocorreu um erro ao criar a conversa. Tente novamente mais tarde." e tentou 10 vezes.
O PR **#225** (S-01) ja faz o modal mostrar o erro que o backend manda; falta o backend mandar uma
frase que o agente entenda, em vez de `Source invalid source id for whatsapp inbox. valid Regex ...`.
