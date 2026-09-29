# Contrato — Módulo de Campanhas

> Estado em 01/09/2026. O **motor está pronto e provado** (10.349 envios, 6 falhas), a **API está
> completa** e a **tela usa quase nada disso**. Esta frente é, quase toda, frontend — mais uma
> fatia de compliance que nunca funcionou.

---

## 1. O que já existe (medido, não suposto)

### Motor — `Campaigns::Whatsapp::*`

| serviço | papel |
|---|---|
| `AudienceBuilderService` | higiene da lista: normaliza, deduplica e devolve **quem entra, quem sai e por quê** |
| `ListLoaderService` | materializa os `campaign_recipients` aplicando exatamente as mesmas regras |
| `RecipientDispatchService` | envia um destinatário |
| `DispatchSchedulerJob` | varre `Campaign.dispatch_running` a cada minuto e despacha o lote |

Os 9 motivos de descarte já implementados: `telefone_invalido`, `telefone_fixo`,
`numero_suspeito`, `bloqueado`, `optou_por_sair`, `ja_disparado`, `ja_na_campanha`,
`atendimento_ativo`, `duplicado_na_lista`.

### API — `Api::V1::Accounts::CampaignsController`

| rota | o que faz | a tela usa? |
|---|---|---|
| `POST /:id/audience_preview` | roda a higiene e devolve stats + amostra de aceitos + **rejeitados com motivo** + quantos foram omitidos | **não** |
| `POST /:id/recipients` | materializa a lista | **não** |
| `POST /:id/start` | promove a `dispatch_running` | **não** |
| `POST /:id/pause` | pausa | **não** |
| `GET /:id/stats` | analítico | sim |

`campaign_params` já aceita `target_team_id`, `pacing_seconds`, `dispatch_assignee_id`,
`template_name`, `template_language` e `dispatch_config: {}`.

### Tela

- **Listagem** (`WhatsAppCampaignsPage`): lista, abre detalhe, exclui.
- **Analítico** (`WhatsAppCampaignDetail`): KPIs (total, alcançados, lidos, respondidos, falhas),
  taxa de entrega e leitura, distribuição por corretor, **falhas por código de erro**, conversas
  com último reply e agente. **É a parte boa.**
- **Criação** (`WhatsAppCampaignForm`): coleta título, inbox, template, data e etiquetas.

---

## 2. O problema

**A criação pela tela não produz campanha que dispare.** Três desconexões:

1. **A audiência não conversa.** A tela envia `audience: [{id, type: 'Label'}]`; o motor
   materializa `campaign_recipients` a partir de `rows`. O `AudienceBuilderService` não lê
   etiqueta em lugar nenhum.
2. **Nenhum parâmetro do motor está no formulário** — nem `target_team_id`, que sem o qual o
   envio acontece e é marcado `failed`.
3. **Não há como pôr em execução.** O scheduler só varre `dispatch_running`; a tela cria em
   `draft` e não existe botão de promover, pausar ou retomar.

O sintoma está nos dados: as campanhas **#4, #5 e #6 estão `paused` com 1.621 de 1.621
enviados** — completaram e ninguém marcou, porque a transição é manual no console.

E o botão "Nova campanha" está **visível e clicável**: quem preencher recebe "sucesso" e a
campanha nunca sai. É pior que não ter o botão.

---

## 3. Compliance: o opt-out nunca funcionou

`ContactFlowSuppression` tem **zero linhas na conta 6** — e na instância inteira. Dois furos,
ambos fora do arquivo que consulta:

1. **O gravador é inalcançável.** `handle_incoming_opt_out` só roda dentro do `run_flows`, que
   exige `account.flows_engine_enabled?` — **falso nessa conta**. Opt-out é compliance e não
   pode depender de o cliente ter o motor de Flows ligado.
2. **O matcher exige match exato** da mensagem inteira contra `parar|sair|stop|cancelar`.
   Medido: **zero** mensagens da conta casam isso desde sempre. Ninguém escreve "PARAR" sozinho.

Consequência medida: **452 contatos já pediram para parar** por escrito e **12 receberam disparo
depois disso** — um deles pediu em janeiro e recebeu em agosto.

### A regra que a medição desenha

O match exato existe por um bom motivo, documentado no código: evitar que *"não vou **parar** de
procurar"* descadastre alguém. Trocar por substring reintroduz esse defeito — e pior, a amostra
real mostra o que seria suprimido por engano:

> *"Nao tenho interesse em compra no momento. **Gostaria de algumas opções de casa para locação**"*
> *"não tenho interesse no momento não. **Inclusive eu to com um terreno pra colocar a venda**"*

São leads quentes. O critério não pode ser substring nem comprimento (*"Obrigada, mas não tenho
interesse."* tem 34 caracteres e é opt-out legítimo).

**O critério é a dominância:** a mensagem é opt-out quando, removidas a frase de recusa, as
saudações e as cortesias, **não sobra pedido nenhum**. Medido em 7.145 mensagens: 305 contêm
frase de recusa, **233 são dominadas por ela** (232 contatos), e as 72 restantes têm pedido junto
e são mantidas — incluindo a captação de terreno acima.

A regra erra para o lado de **não** suprimir. Falso negativo custa um disparo a mais; falso
positivo cala um cliente ativo.

---

## 4. As fatias

### F1 · Opt-out que grava *(compliance — independe da tela)*

- Gravar a supressão **fora do `run_flows`**, para não depender do motor de Flows.
- Reconhecer recusa por **dominância**, mantendo o match exato atual como caminho separado.
- Backfill dos contatos que já pediram, com a mesma regra.
- **Aceite:** a tabela deixa de ter zero linhas; um disparo novo para quem pediu para parar passa
  a ser barrado pelo `optou_por_sair` que o `AudienceBuilderService` já consulta.

### F2 · Controles de execução *(tira o console da operação diária)*

- No detalhe: **iniciar, pausar, retomar**, com o progresso que o `dispatch_state` já devolve
  (`pending` / `total`).
- Estado visível: `draft` · `scheduled` · `running` · `paused` · `completed` · `failed`.
- **Aceite:** pausar e retomar uma campanha sem abrir console.

### F3 · Criar campanha: lista por upload

- **Modelo baixável** (CSV) para o operador sanitizar a lista antes de subir — some a classe de
  erro "o arquivo não tinha as colunas certas".
- Upload → `audience_preview` → **a tela mostra quem entra, quem sai e por quê**, com o total
  real (o nome do arquivo mente: listas "200" e "380" tinham 100 e 81 linhas).
- Campos do motor no formulário: time, corretor do disparo, pacing, janela de silêncio,
  health gate, template + parâmetros, header de imagem.
- **Aceite:** uma campanha criada inteiramente pela tela dispara igual às criadas por script.

### F4 · Criar campanha: lista por segmento

- Construtor de público sobre a base: **etiqueta, time, campanha anterior, origem, recência,
  status de conversa**. Combinável.
- Desemboca no **mesmo** `audience_preview`, então a higiene e o preview não duplicam.
- **Aceite:** montar o público sem planilha, com a mesma tela de conferência.

### F5 · Analítico

O que já existe fica. Falta o que a operação pede e não tem: **progresso ao vivo** durante o
disparo e o **estado de saúde do número** ao lado dos números da campanha.

---

## 5. Decisões registradas

- **Upload primeiro, segmento depois** (Paulo, 01/09): o upload é o que o motor já espera e o
  único caminho provado; o segmento reaproveita o mesmo preview.
- **Modelo de planilha baixável** (Paulo, 01/09): o operador sanitiza contra um formato conhecido
  em vez de descobrir o formato pelo erro.
- **Opt-out entra na frente** (Paulo, 01/09).
- **O blaster nativo continua desativado.** `Campaign#execute_campaign` é no-op para WhatsApp de
  propósito: quem dispara é o `DispatchSchedulerJob`, com pacing, janela e health gate. Nada
  nesta frente reativa o loop nativo.

---

## 6. O que o Paulo exige do módulo (28/09/2026) — o alvo, não o estado

> *"Hoje praticamente eu faço tudo pelo backend aqui com Claude."* Cada campanha da Tozi e da
> Fábrica passa por uma sessão de Claude no console. O módulo só está pronto quando o operador do
> cliente faz sozinho, pela tela, tudo o que a sessão faz hoje. Tarefa: **CHAT-167**.

**O trabalho que hoje é feito à mão e precisa estar na tela:**

1. **Receber a lista** do cliente, organizar e sanitizar (formato, E.164, colunas).
2. **Barrar** duplicados, lista negra/opt-out e **contato com conversa em atendimento**.
3. **Planejar a cadência:** ondas, pacing, horários, e se haverá repescagem.
4. **Desenhar os templates:** variações e categoria. Liga com o gerenciador de templates.
5. **Definir o que acontece depois do disparo:** quem responde a resposta (a IA, um time, o
   rodízio ou um usuário definido), qual template, se há resposta automática.
6. **Respeitar a unidade:** cada unidade com as suas regras (horário, time, responsável). Faltou
   isso na Fábrica, em 25/09: uma campanha por loja montada à mão (`spx-os/clientes/fabrica-atacadao-oculos-conversation-log.md`, 25/09).

**Medição (funil por campanha e por template):** disparos → entregues → respondidos →
qualificados → perdidos; custo, retorno, custo por lead qualificado, conversões e ranking dos
melhores templates.

**Kanban que se move sozinho:** cada destinatário vira um card que avança pelo que acontece
(entregue, respondeu, qualificou, perdeu) sem ninguém arrastar.

**Relação com o follow-up:** a repescagem (`docs/contratos/eixo-followup.md`, engrenagem 3) é a
continuação natural de uma campanha ativa depois que a janela fecha.

