# MISSÃO: IAs enviam ÁUDIO (voice note) no WhatsApp — ElevenLabs, voz exclusiva por agente

> Abrir sessão no repo principal (`chatspx/`), partir da **`homologacao`** atualizada, commit direto
> nela. Multi-tenant: capability genérica, TUDO configurável por conta/assistente, zero hardcode Tozi.
> Enterprise overlay: `rg` nas duas árvores antes de editar. Validar na conta 3 (`.232`).

## Objetivo

Cada IA (Captain assistant) poder responder com **áudio** (voice note de WhatsApp, bolha de PTT) em
vez de texto, com **voz exclusiva por agente** via ElevenLabs. As vozes da Tozi já existem na coleção
do Paulo: **"my voices" → collection `tozi`** (`collectionId=mWeIVooSzTkZQ43vTppD`,
https://elevenlabs.io/app/voice-lab?collectionId=mWeIVooSzTkZQ43vTppD).

**Gatilho v1 (escopo desta missão): SÓ quando o cliente pedir áudio** ("manda áudio", "não consigo
ler agora", pedido explícito). O "momento ideal" inteligente de mandar áudio é **conversa futura com
o Paulo** — NÃO especular agora. A missão entrega a CAPABILITY; a conduta de uso vai no
`config['instructions']` de cada agente depois, por conta, pelo caminho governado.

## Conhecimento acumulado do vault (NÃO redescobrir — já pagamos por essas lições)

Fontes: `Obsidian/wiki/ia-automacao/elevenlabs.md`, `clientes/moreira-solar-elevenlabs.md`,
`aprendizados/transcricao-audio.md`.

1. **Modelo por voz, não fixo:** `eleven_v3` = mais natural/emotivo (default), MAS voz clonada
   simples pode sair MELHOR no `eleven_multilingual_v2` (caso Géssica: v3 exigiria Professional
   Voice Clone com 30min de áudio limpo). → `voice_model` configurável POR assistente, default v3.
2. **⚠️ Audio tags (`[excited]`, `[whisper]`) só funcionam no v3** — o multilingual_v2 LÊ AS TAGS
   LITERALMENTE. Se o texto puder conter tags, gatear por modelo.
3. **Voice settings de partida** (validados nos projetos): `stability 0.5` · `similarity_boost 0.75`
   · `style 0` · `use_speaker_boost true` · `speed 1.0`. Configuráveis por assistente, com esses defaults.
4. **Formato:** ElevenLabs gera MP3 → converter pra **OGG/Opus** (ffmpeg) antes de enviar
   (`audio/ogg; codecs=opus`) — é o que faz o WhatsApp renderizar como VOICE NOTE (bolha de mic) e
   não como arquivo. Padrão já provado nos projetos com WAHA. **Checar se a VM tem ffmpeg**; se não,
   decidir (instalar × gem) e documentar.
5. **Whisper transcreve, ElevenLabs fala** — nunca inverter (regra absoluta do vault).
6. **Custo é por caractere** → cap de tamanho do texto falado (configurável, sugerir ~800 chars) e
   sem multi-sample na v1.
7. Auth: header `xi-api-key`. A key do content-studio é de OUTRO projeto — **não reusar**: criar
   credencial própria (abaixo).

## Arquitetura proposta (validar antes de codar, mas não reinventar)

- **Tool pública** (ex.: `responder_em_audio`): recebe o texto a falar → TTS ElevenLabs (voz+modelo
  +settings do assistente) → ffmpeg → OGG/Opus → envia como voice note pelo canal da conversa.
  ⭐ REGRA #1 na descrição da tool: zero exemplos copiáveis.
- **Transcript visível:** a mensagem gravada carrega o TEXTO falado no `content` + attachment do
  áudio — dashboard mostra, e o juiz do Eval enxerga o que foi dito (o tool-trace F2 já grava a
  chamada sozinho via TraceRecorder — de graça).
- **Config por assistente (banco):** `config['voice_id']` (da coleção tozi) ·
  `config['voice_model']` (default `eleven_v3`) · `config['voice_settings']` (defaults acima) ·
  opt-in de áudio por assistente. Sem voice_id configurado → tool indisponível pro agente.
- **Credencial por conta:** `ELEVENLABS_API_KEY` via InstallationConfig/por-conta, seguindo o padrão
  keys-por-propósito (mesmo desenho das keys OpenAI por propósito, STATE 16/07). Nunca em código,
  nunca em log.
- **Canal — dois caminhos de envio:** conta 6 Tozi = **WhatsApp Cloud API oficial** (upload media →
  `media_id` → send `type: audio`); outras contas = WAHA (`mimetype audio/ogg; codecs=opus`).
  Reusar a mecânica de envio de mídia que a `enviar_fotos_imovel_tool` já usa — achar o caminho
  comum, cobrir os DOIS canais.
- **Falha nunca bloqueia:** ElevenLabs fora/timeout/sem crédito → responde em TEXTO normal e loga.
  Cliente jamais fica sem resposta por causa do áudio.

## Key pra TESTE (já localizada e validada — 22/07)

A key pessoal do Paulo está em **`C:/Users/paulo/Workspaces/content-studio/video/.env`**
(`ELEVENLABS_API_KEY`, 51 chars, validada com HTTP 200 na `GET /v2/voices`). **Usar pra
desenvolvimento/teste na conta 3.** NUNCA colar a key em chat/log/commit — ler do arquivo.
Em produção: credencial própria por conta (InstallationConfig), não a pessoal.

## Vozes da coleção tozi (listadas via API em 22/07 — 9 vozes, todas `professional`)

| voice_id | Nome |
|---|---|
| `UZ8QqWVrz7tMdxiglcLh` | Livia — Warm, Expressive and Calm |
| `OB6x7EbXYlhG4DDTB1XU` | Michelle — Youthful, Vibrant and Bold |
| `5EtawPduB139avoMLQgH` | Thais — Youthful and Feminine |
| `KHmfNHtEjHhLK9eER20w` | Fernanda — Formal and Neutral |
| `gX4eTo1XOTTALJXnDro4` | Greta — Warm & Conversational |
| `7iqXtOF3wl3pomwXFY7G` | Fernanda — Formal, Polite and Direct |
| `GM2UA3fbsIaLHcswCDX9` | Nina M. |
| `PZMcMFpToj1IIYF0QDwX` | Marianne — Customer service |
| `GDzHdQOi6jjf8zaXhCYD` | Raquel — Expressive and Energetic |

Obs.: são vozes **professional** (não clones simples) → o default `eleven_v3` deve funcionar bem;
a lição Géssica (multilingual_v2) fica como fallback configurável, não como default.
**Mapa APROVADO pelo Paulo/time em 22/07** (amostras `C:/Users/paulo/Downloads/vozes-tozi/`, geradas
no `eleven_v3` com os settings default — **a key tem acesso ao V3, provado**). Este é o mapa a aplicar
no config de cada assistente (conta 6; espelhar na conta 3 pra teste):

| Agente | Voz | voice_id |
|---|---|---|
| Clara #7 (recepção) | Marianne — Customer service | `PZMcMFpToj1IIYF0QDwX` |
| Júlia #13 (vendas) | Raquel — Expressive and Energetic | `GDzHdQOi6jjf8zaXhCYD` |
| Bruna #14 (locação) | Livia — Warm, Expressive and Calm | `UZ8QqWVrz7tMdxiglcLh` |
| Letícia #15 | Thais — Youthful and Feminine | `5EtawPduB139avoMLQgH` |
| Marina #16 | Fernanda — Formal and Neutral | `KHmfNHtEjHhLK9eER20w` |
| Rafa #17 | Nina M. | `GM2UA3fbsIaLHcswCDX9` |
| Sofia #19 (leads Meta) | Michelle — Youthful, Vibrant and Bold | `OB6x7EbXYlhG4DDTB1XU` |

Reservas pra troca: Greta (`gX4eTo1XOTTALJXnDro4`) e Fernanda 2 (`7iqXtOF3wl3pomwXFY7G`).
O mapa aplicado vai no banco (config por conta), não no código — só depois do OK do time.

## Critério de aceite (provar na conta 3 / `.232`)

1. Cliente pede áudio → IA responde **voice note** (bolha de PTT no WhatsApp real, não arquivo).
2. Transcript do áudio visível na conversa do dashboard; tool-trace gravado.
3. Dois agentes com vozes DIFERENTES → áudios saem com as vozes certas (exclusividade provada).
4. Sem `voice_id` ou key → agente responde texto normal, sem erro pro cliente.
5. Falha simulada da API ElevenLabs → fallback texto, sem exceção não tratada.
6. `rubocop -a` limpo · duas árvores verificadas · migration só se necessária (config JSONB já cobre).

## Fora de escopo (NÃO fazer)

- "Momento ideal" de mandar áudio além do pedido explícito (conversa futura com o Paulo).
- Clonagem de vozes novas, multi-sample, cache de áudio.
- Conduta nos prompts dos agentes (vai por conta, via caminho governado, depois do deploy).

## Ao final

- Atualizar `chatspx/.claude/STATE.md` (capability + o que falta: mapa de vozes, conduta, deploy prod).
- **Vault (obrigatório):** salvar em `Obsidian/clientes/tozi.md` a coleção (`mWeIVooSzTkZQ43vTppD`),
  o mapa voz↔assistente aplicado e gotchas novos descobertos; indexar com `kg_insert_text`.
