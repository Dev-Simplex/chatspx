# S-03 — Busca de contato mostra só o nome: não dá para saber quem é quem

**Responsavel:** Nicolas Silva
**Origem:** pedido do dono em 25/09/2026 — *"precisa melhorar a identificação dos contatos do chat
spx, porque pesquisei por juliana no chat da tozi e apareceram várias, preciso saber quem é quem"*.
Nasceu do mesmo chamado da [[S-02]]: duas fichas "Juliana" quase idênticas travaram o envio.
**Branch:** sair de `producao`, 1 PR. Conventional Commits. `bundle exec rubocop -a` / `pnpm eslint`.
Nao deployar.

---

## S-03 — O identificador que existe (telefone) é justamente o que a lista não mostra

| | |
|---|---|
| Tipo | UX / prevenção de erro |
| Valor | O agente escolhe a ficha certa na hora de abrir atendimento. Hoje, numa base de 35.765 contatos (TOZI), buscar por um primeiro nome devolve várias linhas idênticas — e escolher a errada significa mandar mensagem para outra pessoa, ou travar no erro da S-02 |
| Confianca | CONFIRMADO: li o código do seletor |
| Onde | `app/javascript/dashboard/components-next/NewConversation/components/ContactSelector.vue:68-76` (monta o rótulo) e `:81-88` (rótulo do já escolhido) · busca global: `app/javascript/dashboard/modules/search/components/SearchResultContactItem.vue` (essa já mostra telefone/e-mail) |
| Esforco | pequeno (F1) · médio (F2, precisa de backend) |
| Como validar | Ver "Como validar" no fim |

---

## O defeito, em duas linhas de código

```js
// ContactSelector.vue:68-70
return props.contacts?.map(({ name, id, thumbnail, email, ...rest }) => ({
  label: email ? `${name} (${email})` : name,
```

O rótulo de cada opção é **`nome (e-mail)`**, e sem e-mail vira **só o nome**. Contato de WhatsApp
quase nunca tem e-mail — então a lista mostra "Juliana", "Juliana", "Juliana". O **telefone**, que é
o único identificador que esses contatos têm, não aparece em lugar nenhum da escolha.

A incoerência está no mesmo arquivo: **depois** de escolher, `selectedContactLabel` (`:81-88`) já usa
o telefone como alternativa ao e-mail. Ou seja, o dado está ali, na mão, e só não é usado no momento
em que o agente precisa decidir.

---

## Fix

### F1 — Telefone na linha, sempre (é o que resolve a queixa)

Cada opção passa a mostrar **duas linhas**: nome em cima; telefone formatado embaixo (e o e-mail
quando houver). O telefone já vem no payload da busca — o próprio filtro do
`createContactSearcher` (`composeConversationHelper.js:294-296`) descarta contato sem
`phoneNumber` nem `email`, então ele está disponível. Formatar com o `formatPhoneDisplay` que o
arquivo já importa.

### F2 — Selo de ficha duplicada

Quando o mesmo número (ou o mesmo wa_id, contando as variantes do nono dígito) aparece em mais de
uma ficha, marcar as duas com um selo **"ficha duplicada"** e um atalho para mesclar. O backend da
busca de contatos passa a devolver `duplicate_of: <id>` — a mesma consulta usada no rake da
[[S-02]] resolve isso.

É esta metade que evita o chamado: as duas Julianas da TOZI conviveram três dias até virar bloqueio
de envio.

### F3 — Contexto de atendimento na linha (se o payload já trouxer)

Última atividade e a caixa da última conversa ("há 2 dias · [TOZI] prestacao"). É o que responde
"essa é a Juliana que já falou comigo?" sem abrir cada ficha. Ordenar os resultados pela última
atividade, em vez da ordem do banco.

### Fora deste PR

- A **busca global** (lupa → aba Contatos) já mostra telefone, e-mail, cidade/país e data — não
  precisa de mudança.
- A lista lateral de conversas mostra nome + prévia. Mexer nela afeta a tela mais usada do produto;
  se valer, vira task própria.

---

## Como validar

1. Duas fichas com o mesmo primeiro nome e telefones diferentes. Abrir **Nova conversa**, digitar o
   nome: cada opção mostra o telefone, e dá para escolher sem abrir as fichas. Hoje as duas linhas
   são idênticas.
2. Duas fichas com o **mesmo** telefone: as duas aparecem com o selo de duplicada (F2).
3. Contato com e-mail e sem telefone: continua mostrando o e-mail (não regredir).
4. Em campo, na TOZI (só leitura): buscar "juliana" e conferir que as fichas 103231 e 102780 agora
   se distinguem — são elas que causaram a [[S-02]].

---

## Contexto

Prevenção, não só conforto: a S-02 mostrou que duas fichas parecidas não terminam em confusão, e sim
em **bloqueio de envio** — e o agente passa a tentar dez vezes sem saber por quê.
