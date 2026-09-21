# Catálogo de produtos no Chat SPX

> **Documento mestre.** As issues do repositório são resumos que apontam para cá. Se houver
> divergência entre uma issue e este arquivo, **este arquivo vale**.
>
> Mockup navegável: https://chat.simplexsolucoes.com.br/catalogo-mockup.html
> (mockup estático, dados fictícios, não é o sistema)

## A dor

Hoje o cliente final precisa sair do WhatsApp para ver produto em site, PDF ou link externo.
Cada saída da conversa é uma chance de perder a venda. O objetivo é o atendente mandar o produto
dentro da conversa, com foto, preço e descrição, sem o cliente sair dali.

## O que a pesquisa concluiu, e o que ela muda

Foi validado antes de qualquer linha de código. Três achados mandam no projeto inteiro.

### 1. A WAHA não tem catálogo. Nenhum.

Testado na instância de produção (`wapi.chatspx.app`, WAHA 2026.8.2, engine GOWS, tier PLUS).
Os sete caminhos plausíveis respondem 404, com a chave autenticando normalmente no mesmo momento
(`/api/sessions` devolve 200):

```
/api/{sessao}/catalog            404
/api/{sessao}/catalogs           404
/api/{sessao}/products           404
/api/{sessao}/business/catalog   404
/api/{sessao}/business/products  404
/api/{sessao}/business/profile   404
/api/{sessao}/orders             404
```

No projeto da WAHA, a [issue #940](https://github.com/devlikeapro/waha/issues/940) pede exatamente
isso e está **aberta desde maio de 2025**, sem responsável, sem PR, sem resposta do mantenedor. A
[#2026](https://github.com/devlikeapro/waha/issues/2026) foi fechada como duplicata dela.

**Consequência:** nas caixas WAHA o catálogo nativo não existe e não vai existir por decisão nossa.
O máximo é foto com preço mais menu numerado.

### 2. No oficial, o catálogo tem que morar na Meta

Confirmado na [documentação de catálogos da Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/catalogs-overview/):
o inventário é carregado para a Meta via Commerce Manager ou Commerce API e conectado ao WABA.
Para enviar é preciso `catalog_id` mais `product_retailer_id`. **Não existe** enviar produto que
só existe no nosso banco.

Formatos disponíveis: mensagem de catálogo, produto único, multi-produto (máximo 30 itens) e
carrossel de produtos.

O espelhamento é automatizável pelo endpoint
[`POST /{catalog_id}/items_batch`](https://developers.facebook.com/docs/marketing-api/reference/product-catalog/items_batch/),
que aceita criação e atualização em lote. Limite de `200 + 40 × número de catálogos` chamadas por
hora, folgado para sincronização de produto.

**Desenho que decorre disso:** nosso banco é a fonte, o catálogo da Meta é o espelho. Cada cliente
com WABA próprio significa um catálogo Meta próprio.

### 3. Metade do caminho de envio já está pronto

O `WhatsappCloudService` tem passthrough genérico: qualquer payload gravado em
`content_attributes['interactive_payload']` sai direto para a Meta via `send_raw_interactive`
(`app/services/whatsapp/providers/whatsapp_cloud_service.rb:8`). Mensagem de produto é um objeto
`interactive`, então **enviar produto no oficial reaproveita código que já roda em produção**.

Na WAHA o `outbound_special_message_service.rb` já sabe mandar enquete (`send_interactive_poll`)
e menu numerado (`send_text_menu`), que é a base do fallback.

### O que não dá para aproveitar

O Chatwoot upstream não tem catálogo. Existe issue aberta, "Add support for Catalog API in
WhatsApp Cloud", não implementada. O único `catalog` no código upstream é tipo de template do
Twilio, que não serve. É construção do zero.

## Decisão pendente de produto

**Vale construir o fallback da WAHA, ou o catálogo nasce só para número oficial?**

Só oficial: projeto menor, fica de fato parecido com o WhatsApp, atinge poucos clientes.
Com WAHA: entra o bloco de fallback e é preciso combinar com o cliente que ali não fica idêntico.

Enquanto não decidir, as tasks marcadas `[WAHA]` ficam bloqueadas.

## Armazenamento de imagem: não é o gargalo

Levantado porque foi preocupação levantada no início. A conclusão é que **já está resolvido**.

- `image_processing` já está no Gemfile, com vips e mini_magick disponíveis.
- O código já gera variante redimensionada (`attachment.rb:69`, `avatarable.rb:14`,
  `resize_to_fill: [250, nil]`).
- Conta de guardanapo: 10 mil produtos a 200 KB dão 2 GB. O `storage/` da `.229` já tem **390 GB**.
  Imagem de produto é ruído estatístico perto de mídia de conversa.

Trocar para S3 ou R2 agora resolve um problema que o catálogo não cria. O crescimento de anexo de
conversa é real e merece projeto próprio, mas **não este**.

### A pegadinha que morde

A Meta recebe uma `image_url` do produto, busca e faz cache. Hoje
`config.active_storage.service_urls_expire_in = 30.minutes`
(`config/environments/production.rb:46`). URL assinada que expira em 30 minutos não serve.

**A foto de produto precisa de rota pública e estável.** É pequeno, mas se ninguém tratar antes,
aparece como "a foto não aparece no catálogo" com tudo pronto.

## Escopo do MVP

### Entra

Cadastro de produto com foto, preço, promocional, SKU, estoque e categoria. Aba Catálogo com busca
e filtro. Envio do produto na conversa. API e webhook para o ERP. Import CSV. Espelho na Meta para
caixas oficiais.

### Fica de fora, e é defensável

Carrinho, pedidos, variações de produto, coleções, multi-moeda. Nada disso é necessário para matar
a dor. Entram depois se o uso pedir.

## Divisão do trabalho

A costura foi escolhida para os dois **não encostarem nos mesmos arquivos**.

| | Nicolas | Thalysson |
|---|---|---|
| **Frente** | Dados e integração | Canal e interface |
| **Arquivos** | `app/models/`, `app/controllers/api/`, `db/migrate/` | `app/javascript/dashboard/`, `app/services/whatsapp/`, `enterprise/` |

Única dependência dura: **C1 (migration e model) bloqueia C6 e C7**. Nicolas entrega primeiro,
depois correm em paralelo.

---

# As tasks

Numeradas `C1` a `C10`. Cada issue do repositório repete o essencial e aponta para cá.

## Nicolas, dados e integração

### C1 · Migration e model de produto `bloqueia C6, C7`

Tabelas `catalog_products` e `catalog_categories`, com `account_id` e isolamento multi-conta igual
ao resto do banco. Campos: nome, descrição, preço, preço promocional, SKU, estoque, categoria,
visível, destaque, `meta_product_id`, `meta_synced_at`.

Imagem por ActiveStorage (`has_many_attached`), reaproveitando o que já existe. A primeira é capa.

**Atenção.** Timestamp de migration com **segundos reais** (`date +%Y%m%d%H%M%S`), nunca hora
redonda. Conferir `git ls-tree origin/producao db/migrate/ --name-only | sort | tail` **antes** de
escolher. Timestamp duplicado levanta `DuplicateMigrationVersionError` e **nenhuma** migration roda.

SKU é único por conta. É a chave de idempotência do ERP inteiro.

### C2 · CRUD interno e policy

Controller em `app/controllers/api/v1/accounts/`, strong params, policy no padrão do repositório.

**Atenção.** Há um defeito conhecido no projeto onde strong params fechado mais `update!` em campo
jsonb apaga chaves silenciosamente. Não repetir o padrão: em jsonb, mesclar, nunca substituir.

### C3 · API pública para o ERP

Endpoints sob `/api/v1/accounts/:id/catalogo`, autenticados por token de escopo da conta.

```
GET    /produtos          lista paginada
POST   /produtos          cria ou atualiza pelo SKU
PUT    /produtos/:sku     atualiza preço e estoque
DELETE /produtos/:sku     tira do catálogo
POST   /produtos/lote     até 500 por chamada
```

Idempotente por SKU: mandar o mesmo SKU duas vezes atualiza, não duplica. Produto que some do ERP
é desativado, **não apagado**, para não perder histórico de envio.

**Atenção.** Isolamento por conta é obrigatório. O ERP de um cliente não pode enxergar dado de
outro. Seguir como o resto da API garante isso.

### C4 · Webhook de saída

Eventos: `produto.criado`, `produto.atualizado`, `estoque.alterado`, `produto.removido`,
`produto.enviado_no_chat`. Reaproveitar o mecanismo de webhook que já existe, não criar outro.
Retentativa em 1, 5 e 30 minutos.

### C5 · Import CSV

Para o cliente pequeno que não tem ERP, que é a maioria. Import assíncrono com relatório de erro
por linha. Procurar o importador de contatos e usar como molde.

## Thalysson, canal e interface

### C6 · Aba Catálogo `depende de C1`

Grade de produtos, busca por nome e SKU, filtro por categoria, selo de estoque, selo de espelhado
na Meta. Ação "Enviar no chat" no hover do card. Tela 1 do mockup.

**Atenção.** Tailwind puro, sem CSS custom, sem `<style scoped>`, sem estilo inline. Tema escuro
obrigatório. Sem `hover:scale`. Componentes em `components-next/`. i18n em **`en` e `pt_BR`**,
os dois, que neste fork não é opcional.

### C7 · Tela de cadastro do produto `depende de C1`

Formulário com upload de foto, campos e painel lateral com os interruptores, status de
sincronização e preview de como o cliente vê. Tela 2 do mockup.

**Inclui a pegadinha da URL pública e estável da foto** descrita acima. Resolver aqui.

### C8 · Enviar produto na conversa

Botão de catálogo no composer, seletor de produto, e a bolha do produto renderizada na conversa.
Tela 3 do mockup. Bolha em `components-next/`, que é obrigatório para message bubble.

Persistir o produto enviado em `content_attributes` para a bolha reconstruir depois.

### C9 · Espelho na Meta e envio oficial

Sincronizar produto para o catálogo da Meta via `items_batch`, guardando `meta_product_id`.
Enviar produto único e multi-produto **reaproveitando o `interactive_payload`** que já existe,
sem caminho de envio novo.

Um catálogo Meta por conta. Tratar limite de taxa e o estado "ainda não sincronizado".

### C10 · Fallback WAHA `[WAHA]` `bloqueada pela decisão de produto`

Produto vira foto com legenda de preço, e multi-produto vira álbum mais menu numerado,
reaproveitando `send_text_menu`. Não fica idêntico, é o teto do canal.

A tela precisa deixar claro para o atendente que naquela caixa o formato é outro. Esconder isso
vira reclamação depois.

---

## Armadilhas que valem para todo mundo

- **Overlay enterprise.** Antes de editar qualquer lógica core, procurar nas **duas** árvores:
  `rg -n "CatalogProduct|CatalogoController" app enterprise`.
- **Migration.** Segundos reais, conferir `origin/producao` antes.
- **i18n.** `en` **e** `pt_BR`. Os outros idiomas são da comunidade, não traduzir.
- **Branding.** Nunca hardcodar "Chatwoot", usar `replaceInstallationName`.
- **Branch.** A de integração é `producao`, não `main`.
- **Specs.** Só escrever se pedido, conforme a convenção do repositório.
