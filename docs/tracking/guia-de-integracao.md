# Guia de integração — ChatSPX no seu site

**Bloco 5.15** do `PLANO-MESTRE`. Versão **1**, 19/08/2026.

Este guia é para quem vai **instalar** o chat num site e ligar as conversões às ferramentas de
marketing. Ele assume que você nunca viu o produto por dentro, e é escrito para ser suficiente
sozinho: instalar, identificar quem está do outro lado e conferir que o evento chegou.

> **O contrato dos eventos não está aqui.** Ele mora em
> [`contrato-de-eventos.md`](./contrato-de-eventos.md) — os doze eventos, campo por campo, com tipo,
> default e o que acontece na ausência. Documento que duplica contrato diverge do contrato; quando
> este guia precisa de um nome de evento ou de um campo, ele **aponta para lá**.

---

## 1. Instalar

No painel: **Caixas de entrada → sua caixa → Configuração**. Copie o trecho `<script>` e cole antes
do `</body>` de todas as páginas onde o chat deve aparecer.

O trecho já vem pronto com o endereço do servidor e o token público do site. Ele faz três coisas:

1. baixa o `sdk.js`;
2. quando o download falha — bloqueador de conteúdo, CSP do seu site, rede do visitante — mostra um
   **link de contato alternativo**, para o visitante não ficar sem canal;
3. quando o download dá certo, chama `window.chatwootSDK.run(...)` e o chat aparece.

**Como saber que funcionou:** abra o site, abra o console do navegador e digite `window.$chatwoot`.
Se aparecer um objeto, está instalado.

> **Usa WordPress, Wix ou Google Tag Manager?** O lugar exato onde colar — e a armadilha de cada
> plataforma, que faz a instalação parecer certa e não funcionar — está em
> [`instalacao-por-plataforma.md`](./instalacao-por-plataforma.md).

### 1.1 Ajustar pelo próprio site (opcional)

Antes do trecho, você pode definir `window.chatwootSettings`. O que estiver aí **vence** o que está
configurado no painel — e a tela de aparência avisa o administrador de que há um override ativo.

```html
<script>
  window.chatwootSettings = {
    position: 'left',       // 'left' | 'right'
    type: 'expanded_bubble',// 'standard' | 'expanded_bubble'
    launcherTitle: 'Fale com a gente',
    darkMode: 'auto',       // 'light' | 'dark' | 'auto'
    hideMessageBubble: false,
  };
</script>
```

Regra de precedência, e ela vale para toda a configuração de aparência: **o banco é o padrão, o
`chatwootSettings` do site sobrescreve, e a tela declara que há override**.

---

## 2. Identificar quem está do outro lado

Sem identificação, cada visitante é anônimo e cada visita começa do zero. Com identificação, a
conversa segue a pessoa.

```js
window.$chatwoot.setUser('CRM-4711', {
  name: 'Ana Souza',
  email: 'ana@empresa.com.br',
  avatar_url: 'https://…/ana.png',
  identifier_hash: '…',        // ver 2.1
});
```

- o **primeiro argumento** é o identificador estável no seu sistema (string ou número). Não use algo
  que muda — e-mail muda; id de CRM não;
- o **segundo** precisa de pelo menos uma destas chaves: `name`, `email`, `avatar_url`;
- chamar de novo com os **mesmos** dados não faz nada: o SDK guarda um hash do que já enviou e não
  repete a chamada.

Outros dados sobre a pessoa ou a conversa:

```js
window.$chatwoot.setCustomAttributes({ plano: 'pro', mrr: 480 });
window.$chatwoot.setConversationCustomAttributes({ origem_campanha: 'black-friday' });
```

### 2.1 `identifier_hash` — a assinatura que impede alguém se passar por outro

Sem assinatura, qualquer pessoa com o console aberto chama `setUser('CRM-4711', …)` e assume a
conversa de outra. O `identifier_hash` é o HMAC do identificador, calculado **no seu servidor**, com
a chave que aparece no painel da caixa de entrada.

```ruby
OpenSSL::HMAC.hexdigest('sha256', ENV['CHATSPX_HMAC_TOKEN'], 'CRM-4711')
```

```js
crypto.createHmac('sha256', process.env.CHATSPX_HMAC_TOKEN).update('CRM-4711').digest('hex');
```

**Nunca calcule o HMAC no navegador**: a chave iria junto para a página, e aí ela deixa de ser
chave. Se a caixa estiver com identificação **obrigatória**, uma chamada sem assinatura válida é
recusada.

---

## 3. Conferir que o evento chegou

### 3.1 O que sai sozinho

A maior parte dos eventos não precisa de código seu: eles saem do próprio produto quando o fato
acontece — chat carregado, conversa iniciada, pré-chat enviado, lead, conversa resolvida. A lista
completa, com quando cada um dispara e quais campos leva, está em
[`contrato-de-eventos.md` §2](./contrato-de-eventos.md).

Todo evento nasce com um **`event_id`** único. É ele que permite à Meta juntar o que veio do
navegador com o que veio do servidor e **não contar a mesma conversão duas vezes**.

### 3.2 Onde configurar os destinos

No painel: **Caixas de entrada → sua caixa → Rastreio**. São quatro sub-abas:

| Sub-aba | O que você põe lá |
|---|---|
| **Meta** | o Pixel ID e o modo teste |
| **Google** | o Measurement ID do GA4 e a conversão do Google Ads (`AW-…/rótulo`) |
| **Eventos** | para qual nome cada evento do ChatSPX vai, em cada destino, e quais estão ativos |
| **Diagnóstico** | o que saiu, para onde, com qual status |

**O que você põe ali é público.** Pixel ID e Measurement ID já aparecem no código-fonte de qualquer
site que use as tags — não há nada a esconder neles. **Credencial não vai aí**: token da Meta e API
Secret do GA4 permitem escrever em nome da sua conta e moram em cofre cifrado, num campo separado que
**nunca re-exibe** o valor depois de guardado.

### 3.3 Conferir, do jeito mais rápido para o mais completo

**a) No próprio navegador (30 segundos).** Com o site aberto, veja o `dataLayer`:

```js
window.dataLayer.filter(evento => String(evento.event).startsWith('chatspx_'));
```

**b) No modo teste da Meta.** Ligue **Modo teste** na sub-aba Meta e cole o código que o Gerenciador
de Eventos te dá (`TEST12345`). Os eventos aparecem em *Testar eventos* sem sujar os números reais.
Ele **desliga sozinho em 7 dias** — um teste esquecido ligado por um mês vira relatório errado.

**c) No painel de Diagnóstico.** Mostra cada tentativa de entrega: horário, evento, destino, status
HTTP e os **nomes** dos campos enviados. Nunca os valores — nem em claro, nem com hash: um painel de
diagnóstico que exibe e-mail de lead é um vazamento com interface.

### 3.4 Disparar um evento a partir do site

Para os fatos que só o seu site conhece — um orçamento pedido, um plano escolhido, um formulário
enviado fora do chat — use `track()`:

```js
window.$chatwoot.track('chatspx_orcamento_pedido', { valor: 990, plano: 'pro' });
```

**Uma chamada, dois destinos.** O evento é gravado no nosso servidor (que gera um `event_id`
próprio) e entra no `dataLayer` da sua página. Você não escreve `dataLayer.push` nenhum, e os dois
lados falam do mesmo fato.

**O nome tem de casar com `/^chatspx_[a-z0-9_]{0,32}$/`** — prefixo `chatspx_`, depois só
minúsculas, dígitos e `_`, no máximo 32 caracteres (40 no total, que é o limite do GA4). São as
mesmas regras da §1 do [`contrato-de-eventos.md`](./contrato-de-eventos.md).

Nome fora disso é **recusado na hora**, com a expressão na mensagem de erro. Não há correção
automática, e é de propósito: se `track('lead')` virasse `chatspx_lead` sozinho, o seu evento se
misturaria ao Lead que o produto já emite, na sua conta de anúncios.

**Não mande dado pessoal em `properties`.** E-mail, telefone e nome (`email`, `phone_number`,
`first_name`, `em`, `ph`…) fazem o servidor recusar o evento com 422, e a ponte de tags os descarta
antes de publicar — inclusive dentro de objetos aninhados. Não é implicância: o `dataLayer` é
legível por qualquer script da página, inclusive os que você não instalou. Quando o dado pessoal é
necessário para o destino (a Meta, por exemplo), quem o envia é o **servidor**, que normaliza e
aplica hash antes.

`track()` devolve uma `Promise` e **nunca lança**, mesmo com nome errado — um `throw` dentro de uma
tag do GTM interromperia as tags seguintes do seu contêiner. O erro aparece no console e na
`Promise` rejeitada, que você pode encadear com `.catch`.

Chamar `track()` duas vezes com o mesmo nome cria **dois** eventos: cada chamada carrega a própria
chave de idempotência. O que não duplica é o reenvio da **mesma** chamada quando a rede falha.

**E para no `dataLayer`.** O evento próprio do seu site **não** dispara Meta, GA4 nem Google Ads
sozinho — quem decide o que fazer com ele é você, no seu GTM, com as regras da sua conta. Os eventos
que disparam tags são os da tabela da sub-aba **Eventos**, porque para esses você configurou o nome
de destino de cada um.

**O caminho para ver um evento de ponta a ponta, sem escrever código:**

1. instale (passo 1) e abra o chat no site;
2. mande uma mensagem como visitante — isso cria a conversa;
3. no painel, **resolva** a conversa;
4. o servidor grava `chatspx_conversation_resolved` e o entrega aos destinos ativos;
5. confira pela alínea (a) ou (c) acima.

---

## 4. Perguntas que aparecem sempre

**O chat não apareceu.** Confira, nesta ordem: (1) `window.$chatwoot` existe no console? Se não, o
`sdk.js` não carregou — veja bloqueador de conteúdo e a CSP do site (`script-src` precisa permitir o
domínio do ChatSPX); (2) apareceu o link de contato alternativo em vez do chat? Então o download
falhou mesmo; (3) a caixa tem **domínios permitidos** configurados e o seu não está na lista?

**O evento não chegou ao destino.** Veja o **Diagnóstico**: se não há linha nenhuma, o evento não
saiu — confira se ele está **ativo** na sub-aba Eventos. Se há linha com erro, a mensagem do destino
está ali.

**Conversão contada em dobro.** É o que o `event_id` existe para evitar. Confira que o mesmo evento
não está configurado duas vezes (uma pelo nosso destino e outra por uma tag manual sua no GTM).

**Dá para ter pixels diferentes por site?** Sim — a configuração é **por caixa de entrada**. Uma
agência com dez clientes tem dez caixas, cada uma com o seu pixel.

**Preciso de consentimento (LGPD)?** O modo de consentimento é definido **para a conta inteira** e
aparece em somente leitura na tela de rastreio da caixa. Quem configura pixel precisa ver a regra
vigente, mesmo sem poder mudá-la ali.

---

## 5. O que este guia não cobre

| Assunto | Onde está / quando entra |
|---|---|
| campos e tipos de cada evento | [`contrato-de-eventos.md`](./contrato-de-eventos.md) |
| guardar token da Meta / API Secret do GA4 | bloco **5.02** (cofre cifrado) |
| leitura do log de entregas na tela | bloco **5.14** |
| instalação em WordPress, Wix e GTM, passo a passo | [`instalacao-por-plataforma.md`](./instalacao-por-plataforma.md) |
