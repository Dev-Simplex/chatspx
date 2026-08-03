---
titulo: Contrato — `distribuicao_produtos.apresentacao`
status: ACEITO pela spx/followup COM 3 EMENDAS — ver §4.1 antes de popular (o formato da §2 está incompleto sem elas)
dono_da_tabela: spx/rodizio
consumidor: spx/followup
data: 2026-08-02
migration: 20260802143722
---

# Contrato — `apresentacao` (inventário de peças por produto)

> **Quem é dono do quê:** a tabela `distribuicao_produtos` é da **spx/rodizio** — por isso a
> migration nasce lá, pra não repetir a colisão de 30/07. O **conteúdo** desta coluna e quem a
> lê é da **spx/followup**. Este documento existe pra as duas frentes concordarem **antes** de
> alguém codar contra.

## 1. O princípio (não-negociável)

> **A config descreve MATERIAL e PÚBLICO. Nunca SEQUÊNCIA.**

Quem escolhe qual peça, para quem e quando é a **IA, no contexto**. Config com ordem, prazo ou
etapa engessa o comportamento e — pior — torna impossível **testar estratégia**: se a sequência
está no banco, comparar duas abordagens vira migração de dados em vez de mudança de conduta.

**Campos que NÃO entram aqui, por mais tentadores que pareçam:** `ordem`, `passo`, `dia`,
`apos_x_horas`, `proxima_peca`, `obrigatoria`, `etapa_do_funil`. Se aparecer a necessidade, a
resposta é conduta de prompt, não coluna.

## 2. Formato proposto

```json
{
  "publico": "<texto livre: pra quem este produto serve, em linguagem natural>",
  "pecas": [
    {
      "id":        "<identificador estável da peça>",
      "tipo":      "audio | carrossel | imagem | video",
      "descricao": "<o que esta peça explica e pra quem ela serve, em linguagem natural>"
    }
  ]
}
```

- **`publico`** — orientação de público do **produto inteiro**, texto livre. É contexto para a IA
  julgar encaixe, não filtro programático.
- **`pecas[].id`** — estável. É o que a spx/followup resolve para o material real no envio (ver
  §4, questão 1). Para a rodizio é **opaco**.
- **`pecas[].tipo`** — string livre com vocabulário documentado (os quatro acima). Deliberadamente
  **não** é enum de banco: formato novo não pode exigir migration.
- **`pecas[].descricao`** — o coração do desenho. É por ela que a IA decide. Descreve **o que a
  peça explica** e **para quem serve** — não quando usar.

**Ausente ou `{}`** = produto sem material. Comportamento atual, sem efeito nenhum.

> ⚠️ **Este bloco está incompleto — leia a §4.1 antes de popular.** A followup aceitou o formato
> com três emendas: entra `pecas[].url` (sem ela não há como enviar), entra `documento` no
> vocabulário e sai `carrossel` (não é anexo, é payload interativo só do WhatsApp Cloud), e entra
> `audio_proativo` no nível do produto.

## 3. ⚠️ Restrição de segurança na hora de expor isso à IA

Esta é a **Regra #1** do projeto e ela morde exatamente aqui:

> **Nenhum exemplo copiável na tool que expuser as peças.** Nem no `description`, nem em
> `param`. Descrever a **origem** do valor, nunca um valor.

Precedente real: um `(ex: 6573)` na descrição de um parâmetro fez a IA mandar **sempre** o imóvel
6573. Uma tool de peças com `id` de exemplo vai mandar sempre aquela peça — e o sintoma (a IA
"gostou" de um carrossel) é lento de diagnosticar porque parece escolha, não bug.

O mesmo vale para o conteúdo do banco: `descricao` deve descrever a peça, não conter script de
fala pronta que a IA vá recitar.

## 4. Questões abertas — precisam da spx/followup

1. **Como o `id` vira material no envio?** Attachment, resposta rápida (canned response), template
   HSM, URL? A rodizio trata como opaco; a decisão é da followup, e ela define se o contrato
   precisa de um campo a mais (ex.: `ref`) ou se o `id` já é a chave no repositório de vocês.
2. **Peça compartilhada entre produtos.** Com jsonb por produto, material que serve a dois
   produtos é duplicado. Aceitável no volume atual e coerente com config-first — mas se a
   followup previr reuso pesado, o desenho certo é uma tabela de peças com referência, e aí a
   migration muda. Melhor decidir agora que depois de popular.
3. **Vocabulário de `tipo`.** Os quatro cobrem hoje. Confirmar se falta algum (documento/PDF?
   áudio-narrado × áudio-depoimento contam como um só?).

## 4.1 Respostas da spx/followup (02/08) — vindas de implementar `enviar_peca`

**1. O `id` vira material por URL, e sim: o contrato precisa de um campo a mais — agora.**

O envio real é `Down.download(url)` → `msg.attachments.build(file_type:, file: { io: ... })`,
exatamente o caminho que `enviar_fotos_imovel` e `responder_em_audio` já usam. É o único que se
comporta igual nos dois tipos de canal em jogo: a inbox 91 é `Channel::Whatsapp` e as 61/62 são
`Channel::Api`. Por isso as outras opções caem:

- **canned response** é ferramenta de humano no dashboard (o atendente digita `/atalho`); não há
  caminho de agente pra ela, e ela resolveria pra um anexo do ActiveStorage de qualquer jeito.
- **template HSM** serve pra reabrir conversa FORA da janela de 24h. Mandar material no meio de
  uma conversa viva não é caso de template — e template não reabre janela nenhuma.

Então: **`pecas[].url`** (string). Peça sem `url` continua aparecendo na lista — a `descricao` já
ajuda a IA a falar sobre o material — mas o envio recusa explicitamente em vez de estourar na
frente do cliente. Já implementado assim.

**2. Duplicação aceita no volume atual — com uma convenção que custa zero e salva a medição.**

Tabela normalizada não se paga aqui: são poucas peças por produto, e o custo real da duplicação é
editar a mesma descrição em N lugares, não integridade. Mas tem um efeito que não é óbvio: se a
mesma peça compartilhada receber ids diferentes em cada produto, **medir conversão por peça em
`captain_tool_calls.args` fragmenta o número em N**, e o experimento de marketing morre.

Convenção: **`id` é estável por CONTA, não por produto.** A mesma peça usa o mesmo id em todos os
produtos que a oferecem. Isso mantém a agregação correta mesmo duplicada — e se um dia a tabela
normalizada vier, os ids já nascem únicos.

**3. Falta `documento`; e `carrossel` não deveria estar no vocabulário ainda.**

- **`documento`** — sim, falta. PDF é real neste vertical (tabela de preços, ficha do
  empreendimento). Mapeia pra `file_type: :file`.
- **`carrossel`** — recomendo **tirar por enquanto**. Ele não é anexo: é `interactive_payload` do
  WhatsApp Cloud, e não existe em `Channel::Api` (inboxes 61/62). Cadastrar carrossel hoje cria
  peça que o operador vê no catálogo e que nunca vai embora. Minha tool recusa com mensagem
  explícita se aparecer, então não é perigoso — é só inútil, e inútil no catálogo confunde.
- áudio-narrado × áudio-depoimento: **um só tipo**. A diferença é de conteúdo, e conteúdo já é o
  trabalho da `descricao` — é por ela que a IA decide. Tipo é só como o material vira mensagem.

Vocabulário proposto: **`audio | imagem | video | documento`**.

**4. Proposta minha (não estava nas perguntas): `audio_proativo` (bool, nível do produto).**

Permissão de o agente **tomar a iniciativa** de responder em voz neste produto. Não é peça nem
sequência — é política de público, irmã do `publico`. Áudio de empresa é mais invasivo que texto:
o que converte em MCMV irrita investidor. Ausente = `false`, e o áudio **a pedido do cliente**
segue funcionando como sempre. Já consumido pela `responder_em_audio`.

**Sobre a §3 (Regra #1): confirmado, e tem uma amplificação que vale escrever.**

Minhas tools não têm id de exemplo em `description` nem em `param` — o param descreve a origem
("o id exato que a `listar_pecas` devolveu nesta conversa"), nunca um valor. Mas o risco não para
na tool: a **`descricao` do banco vai literal para o contexto do modelo** quando a `listar_pecas`
responde. Descrição com frase pronta **vai ser recitada** — e aí o sintoma é ainda pior de
diagnosticar, porque não está em lugar nenhum do código. `descricao` descreve a peça; não é copy.

## 5. Estado

- ✅ Migration escrita e **aditiva/inerte** — `20260802143722`, aplicar com alvo.
- ✅ Leitores no model `Spx::Distribuicao::Produto` (`publico_alvo`, `pecas`) — para as duas
  frentes lerem do mesmo lugar em vez de cada uma parsear o hash.
- ⏳ **Formato aguardando aceite da spx/followup.** Enquanto não houver aceite, ninguém deve
  popular a coluna: mudar formato com dado dentro custa migração de conteúdo.
