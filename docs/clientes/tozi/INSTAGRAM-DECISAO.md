# Instagram na Tozi — documento de decisão

> **CLIENTE:** Tozi Imóveis · **CONTA:** 6 (PROD) · **VM:** 3.82.215.109
> **Frente:** `spx/tozi-ig` (worktree `chatspx-frentes/tozi-ig`, base `origin/homologacao` @ `c14a817e8`)
> **Data:** 2026-08-02 · **Status:** decisão proposta, nada executado, zero código escrito
> **Conduta e persona vivem no banco da conta 6.** Nada aqui autoriza tocar
> `enterprise/lib/captain/prompts/assistant.liquid` — aquele arquivo é compartilhado e vaza pra
> outros clientes.

Estado verificado hoje: nenhum canal Instagram existe na conta 6 nem na instância. Campo aberto.
Inboxes vivas: 61 Financeiro (Api, 7 IAs, 134 conv/30d) · 62 prestação (Api, 7 IAs, 148) ·
**91 FIXO (Whatsapp, 8 IAs, 1.652)** · 93 Notas (Api, 0) · 99 MKT 1 (Whatsapp, 0 IAs, 1).

---

## 1. O que NÃO porta do WhatsApp

Esta seção é o motivo do documento. Tudo abaixo está verificado em código ou na doc oficial da
Meta — nada é suposição.

### 1.1 Repescagem por template não existe. Ponto.

O desenho de follow-up e encerramento da `spx/followup` se apoia em duas regras que são **do
WhatsApp**, não do produto: janela de 24h que só reabre quando o cliente escreve, e HSM pra falar
fora dela. No Instagram, a segunda metade some inteira.

O que a Meta oferece no Instagram, em ordem de utilidade:

| Mecanismo | Existe no IG? | Duração | Serve pra repescagem por IA? |
|---|---|---|---|
| Janela padrão | ✅ | **24h** desde a última mensagem do cliente | — (é a janela) |
| Tag `HUMAN_AGENT` | ✅ | **7 dias** desde a última mensagem do cliente | ❌ **proibida pra bot** |
| Template / HSM | ❌ não existe | — | — |
| Sponsored messages | ❌ *"not available for IG Messaging API"* | — | — |
| One-time notification | ❌ *"not available for IG Messaging API"* | — | — |
| News messaging | ❌ *"not available for IG Messaging API"* | — | — |

**A tag de 7 dias não é a saída.** A política da Meta é explícita: o `HUMAN_AGENT` é pra
**agente humano de verdade** responder além das 24h. Usar em resposta automatizada é
descrito como uma das formas mais rápidas de perder acesso à API do app afetado — e o app é
**um por instância**, então o estrago não fica na Tozi.

E aqui está o problema real, que já está no código:

- `app/services/conversations/message_window_service.rb:55-65` — a janela do Instagram é
  `24h`, e vira `7.days` **se** `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` estiver ligada.
- `app/services/instagram/send_on_instagram_service.rb:24-31` + `base_send_service.rb:37,53` —
  quando a flag está ligada, **toda** mensagem sai carimbada `messaging_type: MESSAGE_TAG` /
  `tag: HUMAN_AGENT`. O código não distingue mensagem de humano de mensagem de assistente
  Captain. Não há branch, não há checagem de `sender`.
- `config/installation_config.yml:396` — a flag é `InstallationConfig`, ou seja
  **global da instância**, não por conta. Ligar pela Tozi liga pra todo mundo na mesma VM.

Ou seja: ligar a flag pra "ganhar 7 dias" faz a IA mandar mensagem assinada como agente humano.
É exatamente o que a política proíbe, e é global.

**Decisão proposta:** `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` fica **desligada**. A janela do
Instagram é 24h e acabou. Consequência direta pra `spx/followup`:

- **Cutucada dentro da janela** (o follow-up do agente, ≤24h) → **porta igual**, é a mesma
  mensagem livre.
- **Cadência HSM fora da janela** (`ReactivationCadenceService`, 1d/3d/7d — Bloco 4) →
  **não porta, e não tem substituto**. Não é "adaptar o template", é *não existe o mecanismo*.
- **Encerramento por inatividade** → porta, mas o critério muda: no WhatsApp fechar cedo custa
  pouco porque dá pra reabrir com HSM. No Instagram, fechou e o cliente sumiu, **acabou** —
  só ele reabre. Isso empurra pra encerrar **mais tarde** no IG, não mais cedo.

**A única repescagem legítima que sobra no Instagram é migrar a conversa pro WhatsApp enquanto a
janela está viva.** Ver §4.3 — isso muda a conduta, não só a infra.

### 1.2 Carrossel de fotos — não porta, e falha calada

O carrossel do WhatsApp é `interactive_payload` do Cloud API
(`enviar_fotos_imovel_tool.rb:128-172` → `whatsapp_cloud_service.rb:313-323`). O Instagram não
tem equivalente nesse caminho, e o serviço de envio do IG **nem olha** `content_attributes`:
`Instagram::BaseSendService#perform_reply` (`base_send_service.rb:8-13`) manda anexos e depois
texto, só isso.

A mensagem de carrossel é criada com `content: "📷 Carrossel: N fotos do imóvel X"` e **zero
attachments**. Numa inbox Instagram, o cliente receberia **essa frase literal e nenhuma foto**.
Não é erro visível em log — é degradação silenciosa na cara do cliente.

Isso **só morde se a mesma assistente servir os dois canais**, que é o que eu recomendo em §3.
`fotos_carrossel` é config de **assistente**, não de inbox. Então a §3 obriga um conserto:
a tool precisa olhar `conversation.inbox.channel_type` antes de escolher o caminho do carrossel,
e cair no envio de imagem uma-a-uma fora do WhatsApp Cloud. Isso é cirúrgico (uma condição no
`carrossel_ativo?`) e alinhado com o que a `spx/followup` já decidiu no contrato de peças:
carrossel *"não é anexo: é `interactive_payload` do WhatsApp Cloud"*, e por isso saiu do
vocabulário.

O caminho não-carrossel (`send_photo` → `Down.download` → attachment) **porta**, com limites
novos: **PNG/JPEG, 8MB, até 10 anexos por mensagem**. O `max_size: 15MB` do `send_photo` é
maior que o teto do IG — foto entre 8 e 15MB passa no download e é recusada pela Meta.

### 1.3 Áudio — porta como anexo, mas o formato atual quebra

`Captain::ElevenLabsTtsService` gera MP3 e **converte pra OGG/Opus** antes de anexar
(`eleven_labs_tts_service.rb:52-53`, `content_type: 'audio/ogg'`) — que é o formato de voice
note do WhatsApp.

O Instagram aceita **AAC, M4A, WAV, MP4** (25MB). **OGG não está na lista. MP3 também não.**
Então `responder_em_audio` não funciona no Instagram nem com a conversão, nem sem ela — precisa
de um terceiro formato (M4A/AAC). O ffmpeg já é dependência de produção
(`app/services/audio/waveform_extractor.rb`), então é trabalho pequeno, mas **é trabalho**.

E tem a parte que não se conserta com código: no WhatsApp o voice note é PTT, com onda e
velocidade. No Instagram é anexo de áudio. A intenção de UX ("mandei um áudio pra você") não
é a mesma coisa dos dois lados.

### 1.4 Localização — não existe

O WhatsApp tem mensagem de localização e `location_request` interativo. O Instagram não lista
localização entre os tipos suportados, e o código do canal só sabe mapear
`image | audio | video | file` (`base_send_service.rb:81-85`). Não porta, e não tem contorno.

### 1.5 Anexo e texto — os limites mudam

| | WhatsApp | Instagram |
|---|---|---|
| Texto | ~4.096 chars | **1.000 _bytes_ UTF-8** |
| Imagem | jpeg/png, limite maior | **PNG/JPEG, 8MB**, ≤10 por msg |
| Vídeo | até 16MB (>16MB vira documento) | MP4/OGG/AVI/MOV/WebM, **25MB** |
| Documento | vários tipos | **PDF só**, 25MB |
| Áudio | OGG/Opus (voice note) | AAC/M4A/WAV/MP4, 25MB |

**1.000 bytes, não 1.000 caracteres.** Em PT-BR acentuado cada "ã/ç/é" custa 2 bytes, então o
teto real fica perto de 500–900 caracteres. A conduta atual salva a gente por acidente: o
humanizer está em **280 chars/500ms**, o que mantém cada pedaço em ≤560 bytes no pior caso.
Vale confirmar no `behavior` real da conta antes de ligar, e vale saber que o teto morde se
alguém desligar o humanizer ou se uma tool devolver um bloco longo de uma vez. Não há split por
tamanho no `Instagram::BaseSendService` — o que passar de 1.000 bytes é recusado pela Meta.

### 1.6 As duas lacunas de plataforma — **não são minhas**

Confirmadas em código e valem pra Tozi tanto quanto pra BigStore (ver
`Obsidian/aprendizados/captain-v2-limitacoes-instagram-multimodal.md`):

- **Comentário público não é processado** —
  `Webhooks::InstagramEventsJob::SUPPORTED_EVENTS = [:message, :read]`
  (`app/jobs/webhooks/instagram_events_job.rb:6`), reconfirmado hoje no `origin/homologacao`.
- **Story reply chega como anexo mas não vira visão pro LLM** — `ig_story` é enum diferente de
  `:image`, cai no branch genérico do `Captain::OpenAiMessageBuilderService#attachment_parts`.

**Verificado hoje: a `spx/bigstore-ig` não tem um único commit** — a branch está em
`1345f6796` (merge de `master`), diff vazio contra `origin/homologacao`. Os dois arquivos estão
intocados. **Esta frente não encosta neles.** Ver §6.

### 1.7 O que eu confirmei que NÃO é problema

- **Gate do router:** `only_contact_phones` vazia nas oito assistentes → contato sem telefone
  não é bloqueado.
- **`skip_groups`:** `RouterService` testa `contact.identifier.end_with?('@g.us')`
  (`router_service.rb:54-58`, mais `waha_whatsapp_chat_id`/`_jid`) — WhatsApp puro, nunca casa
  no Instagram. Inofensivo. Fica registrado que é código com forma de WhatsApp num caminho que
  agora serve outro canal.

---

## 2. O que isso muda pra `spx/followup` — em uma frase

O desenho dela continua válido **dentro** da janela. Fora dela, o Instagram não tem a peça
central: **não existe repescagem por template**, e a tag de 7 dias é proibida pra IA. Qualquer
cadência que assuma "fora da janela eu mando HSM" precisa de um ramo por canal, não de um
parâmetro. Sugiro que a `spx/followup` leia a §1.1 antes de fechar o desenho de encerramento —
o critério de "quando fechar" muda de sinal no Instagram.

---

## 3. DECISÃO — quem atende no Instagram

**Recomendação: nenhuma persona nova. Clara #7 recebe, e transfere pras especialistas de sempre
(Júlia #13 vendas, Bruna #14 locação, Letícia suporte, Marina captação).** Exatamente o fluxo da
inbox 91.

Não é a opção conservadora — é a que o Paulo já decidiu duas vezes, e a alternativa é repetir um
erro que acabou de ser desfeito:

1. **2026-07-16, RMKT × lead frio:** *"Decisão: uma Sofia só (não IA separada — mesmo
   job/knowledge/gates; IA nova = manutenção dobrada + drift)."* A diferença virou dois pontos
   de conduta dentro da mesma IA, não uma IA nova.
2. **2026-07-28, consolidação Sofia → Júlia:** *"agente se separa por **especialidade**
   (vendas/locação/…), nunca por **origem** (Meta, site, direct). Origem vira contexto, não
   identidade. A Sofia tinha nascido por origem e já estava divergindo da Júlia."*

**Instagram é origem.** Uma "persona do Instagram" nasce pelo mesmo defeito da Sofia, e o
diagnóstico daquela consolidação mostra exatamente como o estrago aparece: Júlia com 41 FAQs
contra 6 da Sofia, catálogo duplicado byte-a-byte, tabela ETNA só num lado, e lead caindo do
lado errado da fronteira. Cinco dias atrás. Não vale repetir por um canal com ~0 conversas.

O produto, aliás, **já trata Instagram como origem**: os leads Meta carimbam
`Origem (fb→Facebook, ig→Instagram)` como custom attribute de conversa (defs 75-79, 181+ leads
com backfill). A máquina de "origem é contexto" existe e está rodando.

**O que muda, então, é conduta ciente de canal — não persona duplicada.** Ver §4.

> ⚠️ **Tensão que preciso registrar, não resolver sozinho:** o levantamento de hoje lista
> **Sofia #19 com volume relevante**, mas o STATE.md diz que a consolidação Sofia → Júlia foi
> **executada em prod** em 28/07. Ou a Sofia sobreviveu como assistente ativa apesar da
> consolidação, ou o volume medido é anterior. Isso não muda a recomendação (se ela sobreviveu
> por origem, é mais um argumento a favor), mas **precisa ser conferido antes de plugar
> qualquer IA na inbox nova** — se a fronteira Sofia×Júlia ainda vaza, o Instagram vai vazar
> junto.

---

## 4. O público e a conduta

### 4.1 O público do Instagram é o mesmo do WhatsApp?

Honestamente: **não dá pra saber antes do canal existir** — e eu não vou inventar um perfil.
Mas não precisa esperar: **a Tozi já tem esse dado**. Os leads Meta carimbam `Origem = Instagram`
por conversa (def 75-79), com 181+ leads já backfilled, e cada um tem conversa, transcrição e
resultado.

**Como responder com dado real, sem tocar em nada:** script read-only na conta 6 comparando os
leads `Origem = Instagram` contra `Origem = Facebook` e contra o inbound orgânico da inbox 91 —
intenção (venda × locação × suporte), faixa de valor, taxa de qualificação, tempo até resposta.
Se o recorte Instagram já se comporta diferente hoje, a conduta nasce sabendo disso; se não,
uma preocupação a menos. É a diferença entre desenhar em cima de um palpite e derivar de um
sinal que já existe.

Isso é a **próxima tarefa depois deste documento**, e não depende de credencial nenhuma.

### 4.2 O que da conduta atual NÃO funciona lá

Três pontos, todos verificados na spec de comportamento
(`docs/clientes/tozi/EQUIPE-AGENTES-IA.md`):

| Ponto da conduta | Onde | Problema no IG |
|---|---|---|
| *"pessoa real **no WhatsApp**"* | `response_guidelines` (§3), replicado nas 6 | Menção literal ao canal errado. Precisa virar neutro. |
| *"o foco da conversa fica **no WhatsApp**"* | regra de links (§3, Paulo 11/06) | A premissa **inverte** — ver §4.3. |
| *"recepcionista da Tozi… primeiro contato da imobiliária **no WhatsApp**"* | prompt da Clara (§4) | Idem, e é a primeira frase do prompt dela. |

Foto e link **funcionam** no Instagram (link em DM é clicável). A regra "sem links por padrão" é
decisão de produto, não restrição de canal — **mantenho como está**, por consistência de
comportamento entre canais.

### 4.3 "Manda seu WhatsApp" no Instagram não é vício — é a jogada certa

No WhatsApp, puxar o cliente pro WhatsApp é redundante. No Instagram, é **a única forma de
recuperar a capacidade de reabrir a conversa**: o WhatsApp tem HSM, o Instagram não tem nada
(§1.1). Um lead que sai do Instagram com o WhatsApp registrado é um lead repescável; um que fica
só no Instagram tem 24h e depois depende exclusivamente de ele voltar.

Então a conduta no Instagram deve **buscar ativamente a migração pro WhatsApp** enquanto a
janela está viva — não como despedida, mas como continuidade ("te mando as fotos e os detalhes
no WhatsApp"). Isso é uma diretriz **nova**, específica do canal, e é o principal ganho de
desenho deste documento.

Detalhe operacional que decorre: no Instagram o contato **não tem telefone**. Se ele passar o
número, é preciso decidir se vira contato novo, se funde com o contato de WhatsApp existente, ou
se fica só como atributo. **Questão em aberto** — merece decisão antes do go-live, porque
contato duplicado polui funil, follow-up e medição.

---

## 5. Infra — o que eu preciso do Paulo, de uma vez

Nada disso eu consigo levantar sozinho: depende de acesso ao Business Manager e de App Review
da Meta. **A App Review é o caminho crítico — leva dias/semanas, não horas.** Vale começar por ela.

**Decisões que só o Paulo toma:**
1. **Qual conta do Instagram** vira o canal (`@toziimoveis`?). Precisa ser **Professional/Business**.
2. **Confirmar que a flag `HUMAN_AGENT` fica desligada** (§1.1) — é decisão de risco de
   plataforma, e é global da instância, não só da Tozi.

**Acessos e credenciais:**

3. **App da Meta** — usar o app existente do SPX ou criar um novo pra Instagram? (Nota: a
   permissão é do app, e a punição por mau uso do `HUMAN_AGENT` também.)
4. **`INSTAGRAM_APP_ID`** e **`INSTAGRAM_APP_SECRET`** do app escolhido.
5. **Acesso ao Business Manager** (admin) pra vincular a conta IG ao app e conceder as permissões.
6. **App Review aprovada nas 3 permissões** — sem isso o canal não sai do modo dev:
   - `instagram_business_basic` (metadados da conta)
   - `instagram_business_manage_messages` (receber e responder DM)
   - `human_agent` — **avaliar se pedimos**. Dado que a decisão é não usar a tag pra IA, pedir
     essa permissão só faz sentido se o time humano for atender fora das 24h pelo painel. Se
     não for, **não pedir** reduz superfície de review e de risco.
7. **Screencasts pra App Review** (a Meta exige um por permissão): username/ID/foto aparecendo
   na inbox; mensagem chegando em tempo real e resposta do agente voltando pro Instagram; e,
   se pedirmos `human_agent`, resposta a conversa com mais de 24h.
8. **Credenciais de teste** (usuário não-super-admin no painel) + instruções de login pro
   revisor da Meta.
9. **App icon, URL de política de privacidade e categoria** preenchidos no Basic Settings do app.

**O que eu resolvo sem o Paulo:** `INSTAGRAM_VERIFY_TOKEN` (a gente gera), URL de callback
(deriva do `FRONTEND_URL` da VM de prod), e a assinatura dos webhooks — o
`Channel::Instagram#subscribe` já inscreve `messages`, `message_reactions` e `messaging_seen`
automaticamente no `after_create_commit` (`app/models/channel/instagram.rb:45-57`).

**Nota técnica que muda o que pedir:** existem dois caminhos de conexão, e eles **não têm as
mesmas capacidades**. O `Channel::Instagram` usa **Instagram Login** (`graph.instagram.com`,
`instagram_concern.rb`); o `Channel::FacebookPage` com `instagram_id` usa o caminho Messenger
(`graph.facebook.com`), que tem generic/button/product templates e quick replies — coisas que o
caminho Instagram Login não expõe. **Nenhum dos dois importa hoje**, porque
`Instagram::BaseSendService` só sabe mandar texto e anexo em qualquer um dos casos. Estou
recomendando **Instagram Login** (`Channel::Instagram`) por ser o caminho de primeira classe no
código e não exigir Página do Facebook no meio. Se um dia quisermos quick replies, essa escolha
volta à mesa.

---

## 6. Coordenação com a `spx/bigstore-ig`

Verificado hoje: **a frente não tem nenhum commit** (branch em `1345f6796`, diff vazio contra
`origin/homologacao`). Os dois arquivos disputados estão intocados, então dá pra combinar a
fronteira antes de existir conflito, em vez de depois.

**Proposta de fronteira, com um dono só por arquivo:**

| Terreno | Dono | Arquivos |
|---|---|---|
| Comentários públicos (`SUPPORTED_EVENTS`) | **bigstore-ig** | `app/jobs/webhooks/instagram_events_job.rb` |
| Story reply → visão do LLM | **bigstore-ig** | `enterprise/app/services/captain/open_ai_message_builder_service.rb` |
| Canal/conduta/janela da Tozi | **tozi-ig** | config da conta 6, `enviar_fotos_imovel_tool.rb`, `responder_em_audio_tool.rb` |

As duas correções da bigstore-ig são **de plataforma e servem a Tozi de graça** — não há motivo
pra duplicar. Em troca, o que esta frente descobriu e vale pra BigStore igual: §1.1 (não existe
HSM no IG, e a tag de 7 dias é proibida pra bot — vale pra qualquer cliente com IA no IG), §1.3
(OGG não passa) e §1.5 (1.000 **bytes**).

**Pendência:** confirmar com a bigstore-ig que ela aceita a fronteira antes de qualquer uma das
duas escrever código nesses arquivos.

---

## 7. Próximos passos, na ordem

1. **Paulo decide** os itens 1 e 2 da §5 e providencia 3-9. *(caminho crítico — App Review)*
2. **Conferir a tensão Sofia #19 × consolidação** (§3) — read-only na conta 6.
3. **Comparar o público `Origem = Instagram` contra o resto** (§4.1) — read-only, não depende
   de credencial. **É o próximo passo natural desta frente.**
4. Combinar a fronteira com a `spx/bigstore-ig` (§6).
5. Passar a §1.1 e a §2 pra `spx/followup` antes de ela fechar o desenho de encerramento.
6. Só então: criar o canal, ajustar conduta ciente de canal (§4.2/§4.3), consertar
   carrossel (§1.2) e formato de áudio (§1.3).

**Nada de código antes do passo 1 e do passo 4.**
