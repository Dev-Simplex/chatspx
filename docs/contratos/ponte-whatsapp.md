---
titulo: Contrato — ponte para o WhatsApp (sair do canal sem saída)
status: PROPOSTA — ideia do Paulo em 18/08, desenho meu; aguarda decisão na §7
motivador: BigStore (loop lojista→cliente) e Tozi (lead de anúncio pedindo WhatsApp)
data: 2026-08-18
---

# Contrato — ponte para o WhatsApp

## 1. O problema, e por que esta é a saída

Está medido e fechado (ver [`human-agent-instagram.md`](human-agent-instagram.md)): **o Instagram
não tem escapatória fora da janela de 24h.** Não há template, as outras tags do Messenger a Meta
ignora, e o teste cruzado provou que nem o n8n antigo conseguia — ele só escondia a falha.

O WhatsApp **tem** escapatória: o template. Então a saída não é furar a parede do Instagram — é
**mudar de canal enquanto a porta ainda está aberta**, usando as 24h que existem para obter
telefone e consentimento.

> **A janela do Instagram deixa de ser o prazo do atendimento e passa a ser o prazo da ponte.**

E isso não é truque: no Brasil as pessoas falam num canal e pedem para serem chamadas no WhatsApp.
A ponte é o pedido delas, atendido.

## 2. Os dois casos reais, que são diferentes

**Tozi — o lead que pede para ser chamado.** Cliente vê o anúncio, pergunta preço, recebe as fotos,
e pede WhatsApp. A IA coleta o telefone e dispara um template. **A conta tem WABA**, então a
conversa continua dentro do SPX, no outro canal.

**BigStore — o loop lojista→cliente.** Cliente pergunta disponibilidade num sábado à noite; a loja
responde na segunda. Hoje essa resposta **não chega** (é o defeito silencioso que a §1 documenta).
A ponte aqui é outra: passadas ~12 a 20h sem retorno da loja, a IA **avisa dentro da janela** que
ainda não teve resposta e oferece continuar pelo WhatsApp; se o cliente aceita, o telefone vai para
a loja, **que fala com ele do próprio número**. A BigStore **não tem WABA** no SPX — nem precisa.

A diferença importa: um caso é *o SPX falando por WhatsApp*, o outro é *o SPX entregando o contato
para um humano falar*.

## 3. O que já existe e pode ser reusado

- Envio de template por conversa: `ScheduledMessages` com `template_params`, e o
  `Whatsapp::SendOnWhatsappService` entregando dentro **ou fora** da janela.
- Abertura de conversa por template com contato novo: `Meta::LeadAds::CreateConversationService`
  faz exatamente isso hoje para lead de formulário — cria contato, conversa e manda o HSM.
- Normalização de telefone BR: `Whatsapp::PhoneNumberNormalizationService` (variantes 12/13
  dígitos), que já resolveu a fábrica de duplicatas de junho.
- Motor de campanha e `hook_setting` com `campaign_overrides`, para escolher template por conta.

**O que não existe:** uma **tool** que a IA chame para fazer isso a pedido do cliente, dentro da
conversa. É a peça nova.

## 4. O desenho

Tool `chamar_no_whatsapp`, opt-in por conta, com o template configurável:

1. **Recebe o telefone que a pessoa escreveu**, como ela escreveu.
2. **Normaliza e valida.** Número inválido ou sem WhatsApp precisa voltar para a IA como fato —
   `131026` (número sem WhatsApp) é comum e já mordeu nos disparos. A IA pede de novo, não promete.
3. **Registra o consentimento** na conversa: quem pediu, quando, em que canal. É o que sustenta o
   template como *utility* e o que protege numa reclamação.
4. **Abre a conversa no WhatsApp** e dispara o template — reusando o caminho do lead de formulário.
5. **Devolve à IA o que aconteceu**, com a mesma disciplina do PR #62: se não deu, ela diz que não
   deu; não promete um contato que não vai existir.

Na BigStore, o passo 4 muda: em vez de abrir conversa no SPX, o telefone entra no pedido que já vai
para a loja.

## 5. As armadilhas — todas já mordidas antes neste repo

- **Categoria do template.** "A pessoa pediu para ser chamada" é *utility*. Se a redação virar
  oferta, a Meta reclassifica como *marketing* — muda preço e muda regra. O template tem que ser
  seco: identifica a marca, lembra o pedido, abre espaço.
- **Duplicata de contato.** A pessoa vira contato de Instagram **e** de WhatsApp. Em junho isso
  gerou 275 contatos duplicados e um mutirão de consolidação. O contato precisa ser o mesmo (merge),
  senão o histórico racha e o atendente atende às cegas.
- **Quem fica dono da conversa.** Depois da ponte existem duas conversas vivas. A do Instagram
  deveria encerrar apontando para a outra, senão o time responde nos dois lugares.
- **Telefone digitado errado.** Não dá para confiar no que a pessoa escreveu. Ver passo 2.
- **A ponte não é desculpa para sumir.** Se o template falhar, o cliente ficou sem resposta nos dois
  canais. O retorno da tool precisa dizer isso, e a conduta precisa saber o que fazer.

## 6. O gatilho do follow-up (caso BigStore)

A IA cutuca **dentro da janela** — entre 12h e 20h sem resposta da loja — dizendo que ainda não
teve retorno e oferecendo o WhatsApp. Três cuidados:

- **Tem que ser dentro das 24h.** Passou disso, não sai nada, e o cliente fica sem nada.
- **Uma vez só.** Cutucada repetida em canal de rede social é o caminho mais curto para o bloqueio.
- **Não pode virar promessa de prazo.** O que a IA sabe é que a loja ainda não respondeu — não sabe
  quando vai responder.

## 7. Decisão do Paulo

1. **Confirmar as duas formas** (Tozi com WABA · BigStore sem) ou unificar numa só?
2. **O template da Tozi**: criar novo (*utility*, seco) ou reusar algum dos aprovados?
3. **Merge de contato entre canais**: fazer junto, ou aceitar contato separado na primeira versão e
   pagar o preço do histórico partido?
4. A ponte **fecha** a conversa do Instagram, ou deixa as duas abertas?

## 8. Por que isto tem prioridade sobre a análise do Human Agent

As duas resolvem o mesmo problema, mas:

- A ponte **não depende da Meta** — nem de análise, nem de escopo, nem de prazo externo.
- Ela **acerta a intenção do cliente**, que pediu WhatsApp. A `HUMAN_AGENT` só devolve a resposta no
  canal onde ele talvez não esteja mais olhando.
- E ela vale para **qualquer canal sem saída** — TikTok, e-mail, o que vier.

A análise do Human Agent continua valendo, para o caso de quem **não** quer dar o telefone. Mas a
ponte é o caminho que sai de casa sozinho.
