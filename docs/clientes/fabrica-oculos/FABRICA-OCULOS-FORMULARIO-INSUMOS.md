# Formulário de Implantação — Atendimento com IA · Fábrica dos Óculos

Olá! Para configurarmos a inteligência artificial que vai atender os clientes de vocês no WhatsApp (apresentar produtos, cadastrar interessados, agendar visitas às lojas e, no caso dos óculos de grau sem receita, marcar a consulta e organizar o transporte até a clínica), precisamos de algumas informações.

Pode responder direto abaixo de cada pergunta. Se não souber alguma, deixe em branco e a gente resolve junto. Quanto mais completo, mais rápido entra no ar.

**Como preencher:** escreva a resposta na linha **Resposta:** de cada item. Onde houver caixinhas `[ ]`, marque com um `X`.

---

## 1. Sistema de clientes / CRM

A IA vai cadastrar cada pessoa que chega no WhatsApp como um lead. Precisamos saber onde esse cadastro deve ficar.

**1.1 — Vocês já usam algum sistema para organizar clientes e leads?**
`[ ]` Sim `[ ]` Não, hoje é tudo no WhatsApp/caderno/cabeça

**1.2 — Se sim, qual?** (ex.: RD Station, Pipedrive, Bitrix24, HubSpot, Kommo, uma planilha do Google, um sistema próprio…)
> **Resposta:** ____________________________________________

**1.3 — Quem cuida desse sistema** (nome e contato de quem pode nos dar acesso/credenciais)?
> **Resposta:** ____________________________________________

**1.4 — Quais informações vocês querem registrar de cada lead?** (marque)
`[ ]` Nome  `[ ]` Telefone  `[ ]` Cidade  `[ ]` Produto de interesse (sol/relógio/grau)
`[ ]` Tem receita? (no caso de grau)  `[ ]` Loja escolhida  `[ ]` Origem (anúncio, indicação…)
`[ ]` Outros: ____________________________________________

> *Nota para o time técnico: confirmar se o CRM tem API/integração disponível.*

---

## 2. Catálogo de produtos

A IA vai mostrar produtos aos clientes (óculos de sol, relógios, armações de grau). Precisamos saber de onde ela "puxa" essas informações.

**2.1 — Onde ficam cadastrados os produtos de vocês hoje?**
`[ ]` Um sistema/ERP (qual? _______________)
`[ ]` Uma planilha (Google Sheets / Excel)
`[ ]` Um site / loja virtual (link: _______________)
`[ ]` Catálogo em PDF / imagens
`[ ]` Não há catálogo organizado ainda

**2.2 — Esse catálogo tem o quê?** (marque o que existe)
`[ ]` Nome do produto  `[ ]` Marca  `[ ]` Preço  `[ ]` Foto  `[ ]` Categoria (sol/relógio/armação)
`[ ]` Disponibilidade/estoque  `[ ]` Outros: _______________

**2.3 — Os preços e a disponibilidade mudam com frequência?** (isso define se a IA precisa consultar "ao vivo" ou se trabalha com uma lista fixa)
> **Resposta:** ____________________________________________

**2.4 — Pode nos enviar o catálogo atual** (planilha, link ou acesso ao sistema)?
> **Resposta:** ____________________________________________

---

## 3. Lojas físicas

A IA agenda a visita do cliente na **loja mais próxima**. Precisamos da lista das lojas.

**Liste cada loja:** (copie o bloco abaixo quantas vezes precisar)

| # | Cidade | Endereço completo | Telefone da loja | Horário de funcionamento |
|---|--------|-------------------|------------------|--------------------------|
| 1 |        |                   |                  |                          |
| 2 |        |                   |                  |                          |
| 3 |        |                   |                  |                          |

**3.1 — Existe alguma cidade com mais de uma loja?** (se sim, qual?)
> **Resposta:** ____________________________________________

**3.2 — Quando a IA agenda uma visita, quem na loja deve ser avisado?** (nome/WhatsApp do responsável de cada loja, ou um grupo)
> **Resposta:** ____________________________________________

---

## 4. Clínicas parceiras (óculos de grau SEM receita) ⭐

Esta é a parte mais importante e mais nova. Quando o cliente quer óculos de grau mas **não tem receita**, a IA precisa agendar uma consulta numa clínica parceira. O processo será: a IA manda uma mensagem à clínica ("temos um cliente para o horário X — Aceitar / Sugerir outro / Recusar"), a clínica responde, e a IA confirma com o cliente.

**4.1 — Vocês já têm clínicas/óticas parceiras que fazem o exame de vista?**
`[ ]` Sim, já temos parceria firmada  `[ ]` Ainda vamos firmar  `[ ]` Não

**4.2 — Liste as clínicas parceiras:**

| # | Nome da clínica | Cidade | WhatsApp de contato | Pessoa responsável |
|---|-----------------|--------|---------------------|--------------------|
| 1 |                 |        |                     |                    |
| 2 |                 |        |                     |                    |
| 3 |                 |        |                     |                    |

**4.3 — IMPORTANTE: as clínicas conseguem (e topam) responder mensagens pelo WhatsApp para confirmar os agendamentos?**
`[ ]` Sim, respondem rápido pelo WhatsApp
`[ ]` Sim, mas costumam demorar
`[ ]` Não tenho certeza
`[ ]` Não — o agendamento com a clínica é feito por telefone/pessoalmente

> *Esta resposta define se a IA fecha a consulta sozinha ou se um atendente de vocês ajuda nesse passo. Seja sincero aqui — é o que mais impacta o projeto.*

**4.4 — Como funciona o pagamento da consulta?** (a Fábrica paga a clínica? o cliente paga? é cortesia?)
> **Resposta:** ____________________________________________

**4.5 — Há convênios/planos envolvidos** que a IA precise perguntar ao cliente?
> **Resposta:** ____________________________________________

---

## 5. Transporte até a clínica

Vocês oferecem **levar o cliente até a clínica** como parte do serviço. Precisamos entender como isso acontece.

**5.1 — Como é feito esse transporte hoje?**
`[ ]` Carro/motorista próprio da Fábrica
`[ ]` Parceiro (táxi, Uber, motorista terceirizado)
`[ ]` Reembolso ao cliente
`[ ]` Ainda não fazemos / vamos começar agora

**5.2 — A IA deve agendar o transporte automaticamente, ou apenas avisar um responsável de vocês para organizar?**
`[ ]` Agendar automático  `[ ]` Só avisar um responsável (quem? _______________)

**5.3 — Há alguma regra?** (ex.: só transporta dentro da cidade, raio máximo, horários)
> **Resposta:** ____________________________________________

---

## 6. WhatsApp e mensagens

**6.1 — Qual número de WhatsApp será usado no atendimento dos clientes?**
> **Resposta:** ____________________________________________

**6.2 — Esse número já é um WhatsApp Business com API oficial (Meta), ou é um WhatsApp comum/Business no celular?**
`[ ]` API oficial (Meta Cloud API)  `[ ]` WhatsApp comum/Business no celular  `[ ]` Não sei

**6.3 — As mensagens para as clínicas devem sair do mesmo número dos clientes, ou de um número separado?**
`[ ]` Mesmo número  `[ ]` Número separado (qual? _______________)  `[ ]` Tanto faz / decidam vocês

**6.4 — Vocês têm logo, identidade visual e nome oficial** que devemos usar nas mensagens?
> **Resposta:** ____________________________________________

> *Nota para o time técnico: para enviar a 1ª mensagem e as confirmações fora da janela de 24h, precisaremos aprovar modelos (HSM) na Meta — cuidamos disso.*

---

## 7. Conteúdo para a IA "saber" responder

Para a IA atender bem, ela precisa conhecer a empresa e os produtos. Nos enviem (ou descrevam) o máximo que puderem:

`[ ]` Apresentação da empresa (história, diferenciais, missão)
`[ ]` Como funciona o serviço de **consulta + transporte** (passo a passo, o que está incluído, prazos)
`[ ]` Linhas de produto e marcas que trabalham
`[ ]` Faixas de preço / formas de pagamento / parcelamento
`[ ]` Política de garantia e troca
`[ ]` Perguntas que os clientes mais fazem (FAQ)
`[ ]` Objeções comuns ("tá caro", "vou pensar", "fica longe") e como vocês costumam responder
`[ ]` Tom de voz desejado (formal? descontraído? "de casa"?)

> **Anexem os materiais que tiverem** (PDFs, fotos, áudios de atendimento, prints). Áudios de bons vendedores atendendo são ouro — ajudam a IA a falar como vocês.

---

## 8. Tom e limites do atendimento

**8.1 — Em que horários a IA deve atender?**
`[ ]` 24 horas, todos os dias  `[ ]` Horário comercial (qual? _______________)

**8.2 — O que a IA NÃO pode fazer/dizer?** (ex.: não dar desconto, não prometer prazo de entrega, não falar de assunto X)
> **Resposta:** ____________________________________________

**8.3 — Quando a IA deve passar a conversa para um atendente humano?** (ex.: reclamação, pedido de desconto, dúvida técnica)
> **Resposta:** ____________________________________________

---

### Contato para dúvidas no preenchimento

Qualquer dúvida, fale com a Simplex. Pode devolver este formulário preenchido + os anexos por aqui mesmo.

**Preenchido por:** ____________________  **Data:** ____ /____ /______
