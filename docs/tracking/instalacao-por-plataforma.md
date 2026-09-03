# Instalar o ChatSPX em WordPress, Wix e Google Tag Manager

**Bloco 5.22** do `PLANO-MESTRE` (decisão **D8**). Versão **1**, 19/08/2026.

Este documento é a continuação da **§1 do
[`guia-de-integracao.md`](./guia-de-integracao.md)**, que ensina a instalação genérica ("copie o
trecho e cole antes do `</body>`"). Aqui está **onde exatamente colar** em cada uma das três
plataformas mais comuns — e, em cada uma, **a armadilha que faz a instalação parecer certa e não
funcionar**.

> **O trecho é sempre o mesmo.** Você o copia uma vez, no painel: **Caixas de entrada → sua caixa →
> Configuração**. Nada nesta página pede para editar o trecho, e você não deve editá-lo: ele já vem
> com o endereço do servidor e o token público do seu site. O que muda entre as plataformas é o
> **lugar** onde ele é colado.

**Como saber que deu certo, em qualquer uma das três:** abra o site publicado, abra o console do
navegador e digite `window.$chatwoot`. Se aparecer um objeto, está instalado. Se aparecer
`undefined`, vá para a §4.

**Os nomes de menu mudam.** As três plataformas renomeiam telas sem aviso. Quando o nome não bater,
procure pela **função** descrita aqui — "onde se cola código que vale para o site inteiro" — e não
pelo rótulo exato.

---

## 1. WordPress

### 1.1 Onde colar

**A armadilha do WordPress é a atualização do tema.** O caminho que todo tutorial ensina — editar
`footer.php` em **Aparência → Editor de arquivos do tema** — funciona no mesmo dia e **é apagado na
próxima atualização do tema**. Nada avisa: o chat simplesmente some do site, semanas depois, sem
ninguém ter mexido nele. Se você já colou lá, o chat vai sumir.

Use um destes dois, nesta ordem de preferência:

**(a) Um plugin de inserção de código no cabeçalho/rodapé** — é o caminho recomendado, e o mais
curto. Qualquer plugin da categoria serve (procure por "insert headers and footers" no repositório
de plugins). O código fica guardado no **banco do site**, não no tema, e por isso sobrevive tanto à
atualização do tema quanto à troca dele.

1. **Plugins → Adicionar novo**, instale e ative um plugin de inserção de código;
2. abra as configurações dele e procure o campo do **rodapé** (`footer`, "antes do `</body>`");
3. cole o trecho e salve.

**(b) Um tema filho** (*child theme*), se você já tiver um. Cole o trecho no `footer.php` **do tema
filho**, imediatamente antes de `</body>`. O tema filho não é sobrescrito quando o tema pai é
atualizado. Não vale a pena criar um tema filho só para isso — se você não tem um, use (a).

**Não use** o bloco "HTML personalizado" do editor de páginas: ele vale só para **aquela** página, e
o chat precisa estar em todas.

### 1.2 A segunda armadilha: plugins de cache e otimização

Se o site usa um plugin de cache (os nomes mais comuns: WP Rocket, LiteSpeed Cache, W3 Total Cache,
Autoptimize), ele pode **adiar, combinar ou minificar** o nosso trecho. O sintoma é característico:
o chat aparece para você, que está logado no admin (o cache costuma ser desligado para
administradores), e **não aparece para o visitante**.

O que fazer, na ordem:

1. **limpe o cache** depois de colar o trecho — antes de concluir que não funcionou;
2. abra o site numa **janela anônima** (é a única forma de ver o que o visitante vê);
3. se ainda não aparecer, procure nas opções de JavaScript do plugin de cache uma lista de
   **exclusões** e acrescente `sdk.js`. As opções costumam chamar-se "Adiar JavaScript" ("Delay
   JavaScript execution"), "Combinar arquivos JS" ou "Carregar JS adiado".

> **Por que isso não quebra sozinho:** o nosso trecho já espera 8 segundos e, se o `sdk.js` não
> chegou, mostra um **link de contato alternativo** no lugar do chat. Se você vir esse link no seu
> site, o download está sendo bloqueado — e é exatamente este item que resolve.

---

## 2. Wix

### 2.1 A restrição que vem antes de tudo: o plano

**Adicionar código personalizado no Wix exige um plano pago.** No plano gratuito a tela de código
personalizado não existe, e **não há caminho alternativo** — o editor de páginas do Wix não aceita
`<script>`, e o app de HTML embutido (`Embed → HTML iframe`) roda dentro de um **iframe isolado**,
onde o chat apareceria preso a um retângulo da página em vez de flutuar sobre o site.

Se o site está no plano gratuito, a instalação não é possível até o plano ser alterado. Descobrir
isso na primeira linha economiza a tarde de quem ia tentar.

### 2.2 Onde colar

1. no **painel do site** (não no editor de páginas): **Configurações → Código personalizado**;
2. **+ Adicionar código**;
3. cole o trecho no campo de código;
4. **Adicionar código a páginas:** escolha **Todas as páginas**, e **Carregar código uma vez**;
5. **Colocar código em:** escolha **Corpo - fim** (`Body - end`);
6. dê um nome ao trecho (ex.: "ChatSPX") e **aplique**.

### 2.3 A armadilha do Wix: o código não roda antes de publicar

O Wix **não executa código personalizado no editor nem na pré-visualização** — só no site
**publicado**. É o erro mais comum: a pessoa cola, olha a pré-visualização, não vê o chat e conclui
que errou o passo.

Depois de aplicar, **publique o site** e confira no endereço público, em janela anônima.

---

## 3. Google Tag Manager

### 3.1 Tag de **HTML personalizado**, nunca um template

Crie a tag assim:

1. **Tags → Nova → Configuração da tag → HTML personalizado**;
2. cole o trecho no campo de HTML;
3. **Acionamento:** `All Pages` (Todas as páginas, tipo *Pageview*);
4. deixe **"Suportar document.write" DESMARCADO** — o nosso trecho não usa `document.write`, e
   marcar essa opção muda a forma como o GTM injeta o HTML sem nenhum ganho para nós;
5. salve, use o **Modo de visualização** para conferir que a tag dispara, e **publique o contêiner**.

**Por que HTML personalizado e não um template da galeria.** Templates do GTM rodam em *sandboxed
JavaScript*: um dialeto restrito, sem acesso a `document`, sem closures livres e com uma lista
fechada de APIs permitidas. O nosso trecho cria um elemento `<script>`, guarda estado em variáveis
de escopo e publica `window.chatwootSDK` — nada disso existe naquele dialeto. Um template exigiria
reescrever o carregador inteiro para a sandbox e submetê-lo à aprovação da galeria. A tag de HTML
personalizado roda JavaScript normal, e é para isso que ela existe.

### 3.2 O `dataLayer` do seu contêiner continua sendo seu

Esta é a garantia que mais importa para quem já mede o site pelo GTM, e ela é **verificada por
teste** a cada mudança nossa:

- **nada nosso reatribui `window.dataLayer`.** Onde precisamos dele, escrevemos
  `window.dataLayer = window.dataLayer || []` — que **estende** o array que já existe. Reatribuir
  apagaria tudo o que o `gtm.js` já enfileirou, inclusive antes de nós;
- **nada nosso reatribui `window.gtag`**, pelo mesmo motivo;
- o trecho de instalação em si **não toca no `dataLayer`**: ele só baixa o `sdk.js`.

Os eventos do chat aparecem no seu `dataLayer` com o prefixo `chatspx_`. Para vê-los, com o site
aberto:

```js
window.dataLayer.filter(evento => String(evento.event).startsWith('chatspx_'));
```

Cada um deles pode virar um acionador de tag no seu contêiner, como qualquer evento seu. A lista
completa, com os campos de cada um, está em
[`contrato-de-eventos.md` §2](./contrato-de-eventos.md).

### 3.3 A armadilha do GTM: uma exceção derruba as tags seguintes

Dentro de um contêiner do GTM, as tags de um mesmo acionamento rodam **em sequência, no mesmo
contexto**. Uma exceção **síncrona** lançada por uma tag interrompe as **tags seguintes** — o site
continua no ar, mas para de medir, e o sintoma aparece dias depois num relatório vazio. É um defeito
difícil de rastrear, porque a tag culpada não é a que parou de funcionar.

**Por isso os métodos de dados do ChatSPX nunca lançam exceção síncrona.** `track()`, `setUser()`,
`updateUser()`, `setCustomAttributes()` e os demais devolvem uma **`Promise`**: quando o argumento
está errado, a `Promise` é rejeitada e o erro aparece no console — **as tags seguintes do seu
contêiner continuam rodando**. Você pode chamá-los de dentro de uma tag do GTM sem `try/catch`:

```html
<script>
  window.$chatwoot.track('chatspx_orcamento_pedido', { valor: 990 });
</script>
```

Se você **quiser** tratar o erro, encadeie — `.catch()` funciona normalmente:

```html
<script>
  window.$chatwoot
    .track('chatspx_orcamento_pedido', { valor: 990 })
    .catch(function (erro) { /* seu tratamento */ });
</script>
```

> **Atenção à ordem.** `window.$chatwoot` só existe depois que o `sdk.js` carrega. Numa tag que
> dispara junto com a instalação, ele ainda pode ser `undefined`. Use o evento
> `chatwoot:ready` como acionador da sua tag, ou proteja a chamada com `window.$chatwoot &&`.

---

## 4. O chat não apareceu — o que conferir, nesta ordem

Vale para as três plataformas.

| # | Conferir | Se for isso |
|---|---|---|
| 1 | Você **publicou**? (Wix: publicar o site · GTM: publicar o contêiner · WordPress: limpar o cache) | é o motivo mais comum dos três |
| 2 | `window.$chatwoot` no console do site **publicado**, em janela anônima | `undefined` → o `sdk.js` não carregou; siga para (3) |
| 3 | Apareceu um **link de contato alternativo** no canto em vez do chat? | o download do `sdk.js` foi bloqueado: bloqueador de conteúdo, CSP do site (`script-src` precisa permitir o domínio do ChatSPX) ou plugin de cache adiando JS (§1.2) |
| 4 | A caixa tem **domínios permitidos** configurados e o seu não está na lista? | acrescente o domínio na configuração da caixa |
| 5 | O trecho está em **todas** as páginas, e não só na inicial? | WordPress: você usou o bloco de HTML de uma página só (§1.1) · Wix: o código foi aplicado a uma página em vez de "Todas as páginas" · GTM: o acionador não é `All Pages` |

---

## 5. O que este documento não cobre

| Assunto | Onde está |
|---|---|
| identificar o usuário, `identifier_hash`, disparar eventos | [`guia-de-integracao.md`](./guia-de-integracao.md) |
| nomes e campos de cada evento | [`contrato-de-eventos.md`](./contrato-de-eventos.md) |
| configurar Pixel, GA4 e Google Ads | `guia-de-integracao.md` §3.2 |
| outras plataformas (Shopify, Webflow, Squarespace, VTEX) | não coberto; o caminho genérico da §1 do guia costuma servir — o lugar a procurar é sempre "onde se cola código antes do `</body>` em todas as páginas" |
