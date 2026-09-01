# SPEC — Fila de envio de fotos (a IA cumpre o que prometeu)

> Status: **especificação, não implementada**. Origem: pedido do Paulo em 17/08/2026, a partir da
> conversa 49439 da Tozi (conta 6, prod). Mede antes de desenhar — os números abaixo são reais.

---

## 1. O que quebrou, medido

Conversa 49439. O cliente apontou três imóveis e escreveu **"Tem fotos?"**. A IA chamou a
ferramenta três vezes, **no mesmo segundo**:

| # | imóvel | duração | retorno |
|---|---|---|---|
| 11281 | 5194 | 283 ms | *"Enviei um carrossel com 9 fotos…"* |
| 11282 | **2508** | **9 ms** | *"Você acabou de enviar fotos há pouco. **NÃO envie mais fotos agora**"* |
| 11283 | **9412** | **3 ms** | idem |

O freio é o `COOLDOWN = 90` do `EnviarFotosImovelTool`, cujo próprio comentário diz *"freia a
rajada multi-imóvel"*. **Ele está fazendo exatamente o que foi programado para fazer.** O defeito
é que ele não distingue dois casos opostos:

- **rajada espontânea da IA** — despejar fotos que ninguém pediu (o que ele deve frear);
- **o cliente pedindo três imóveis de uma vez** (o que ele está matando).

A própria mensagem de recusa diz *"Só envie de novo se ele pedir explicitamente"* — e ele tinha
pedido. Depois disso a IA escreveu **"Vou pegar as das outras duas pra você também"** e nunca
pegou: não existe reagendamento, o cooldown bloquearia de novo e ninguém tentou. **As fotos do
2508 e do 9412 não foram enviadas por ninguém** — nem pela IA, nem pelo consultor humano que
assumiu depois.

Agravante de diagnóstico: as três chamadas gravaram **`status = ok`**. Recusa e sucesso deixam o
mesmo rastro, então o problema é invisível no painel e em qualquer contagem por status.

---

## 2. O comportamento desejado

Descrito pelo Paulo:

```
Te enviei as fotos desse imóvel, só um instante que vou enviar do segundo.
   ~15-20s
Aqui estão as fotos do segundo imóvel. Só um momento que já mando do terceiro.
   ~30s
Pronto, aqui estão as do terceiro.
```

Duas exigências, e a segunda é a difícil:

1. A IA precisa **saber que tem tarefas pendentes** e cumpri-las.
2. Ela precisa **se certificar de que foram enviadas** — sem se confundir e sem reenviar o que já
   mandou.

---

## 3. Por que conduta não resolve isto

Já foi tentado por outro caminho e falhou de forma medida: uma promessa no texto (*"vou pegar as
das outras duas"*) **não é estado**. O modelo não tem onde guardar a pendência, e no turno
seguinte o histórico só mostra que ele prometeu — não que deve.

> **Tarefa pendente tem que ser estado persistido, não intenção declarada no prompt.**

O mesmo já se provou aqui em 12/08: três versões de conduta, ~200 execuções, ponteiro imóvel.
O que move é marcador estrutural.

---

## 4. Desenho proposto

### 4.1 Inverter o contrato do cooldown: **enfileirar em vez de recusar**

Hoje, cooldown ativo → recusa. Passa a ser:

| situação | hoje | proposto |
|---|---|---|
| primeiro pedido | envia | envia |
| cooldown ativo, **código novo** | **recusa** | **enfileira** + retorna *"agendado, avise o cliente que vem em seguida"* |
| cooldown ativo, mesmo código | recusa | recusa (inalterado) |
| código já entregue por completo | recusa | recusa (inalterado) |
| código fora da busca da conversa | recusa | recusa (inalterado — trava anti-alucinação) |

A trava anti-alucinação (`codigos_conhecidos`) roda **antes** de enfileirar: só entra na fila
código que apareceu numa busca desta conversa.

### 4.2 Estado

Em `conversation.custom_attributes` — mesmo lugar onde já vivem `fotos_offset_<cod>` e
`fotos_ultimo_envio_at`, que continuam sendo a **fonte da verdade do que já saiu**:

```
fotos_fila        => ["2508", "9412"]     # ordenada, deduplicada, sem código já entregue
fotos_fila_desde  => <epoch>              # para expirar fila órfã
```

`fotos_offset_<cod>` **não muda de papel**: é ele que responde "já mandei?". A fila é só a lista
de trabalho.

### 4.3 Drenagem

`Spx::Tozi::FotosFilaJob` (ou nome genérico — ver §7), agendado com
`set(wait: INTERVALO_ENTRE_LOTES)`:

1. relê a conversa e a fila (o estado pode ter mudado);
2. avalia os **portões de cancelamento** (§4.5) — se algum fechar, esvazia a fila e sai;
3. tira o primeiro código; se `fotos_offset_<cod>` já cobre o teto, descarta e segue;
4. envia o lote (o mesmo caminho de hoje: carrossel ou foto a foto);
5. grava `fotos_offset_<cod>` **antes** de reagendar;
6. se sobrou fila, reagenda.

Intervalo sugerido: **20 s**, alinhado ao que o Paulo descreveu e folgado para o WhatsApp
entregar o carrossel anterior.

### 4.4 Quem narra

**O job, não a IA** — e o mínimo possível. A narração da IA é justamente o que se descontrolou
(ela prometeu e não cumpriu; e em outro ponto imitou o rótulo do carrossel e mandou uma linha sem
foto). O carrossel já traz `imóvel <código>` no corpo de cada card, então uma linha por lote
basta, ou nenhuma.

A IA anuncia **uma vez**, no turno em que enfileira — que é o que o retorno da ferramenta pede.

### 4.5 Portões de cancelamento (o que impede foto chegando fora de hora)

A fila é descartada, sem enviar, se no momento da drenagem:

- um **humano assumiu** a conversa (`assignee_id` presente) — hoje o handoff não solta o espelho,
  então isso é real e frequente;
- a conversa foi **resolvida**;
- o cliente **mudou de assunto** — sinal mínimo: chegou mensagem nova do cliente depois do
  enfileiramento que não é reação às fotos. *(A definir; começar sem este portão e medir.)*
- a fila **expirou** (`fotos_fila_desde` mais velho que ~5 min).

### 4.6 Tetos

- **máximo 3 imóveis** na fila. Pedido maior → oferecer o link da galeria, como já se faz hoje.
- `MAX_POR_IMOVEL` (9) continua valendo por imóvel.

---

## 5. Garantia anti-duplicata

É o requisito que o Paulo destacou, e o desenho o resolve em três camadas:

1. **A fila é deduplicada na entrada** — código já presente não entra duas vezes.
2. **`fotos_offset_<cod>` é checado na hora do envio**, não na hora do enfileiramento. Se o imóvel
   já saiu por outro caminho no intervalo, o item vira no-op.
3. **O offset é gravado antes de reagendar.** O Sidekiq entrega ao menos uma vez; sem isso, um
   retry reenviaria o mesmo lote.

---

## 6. Critério de aceite (verificável)

1. Cliente pede fotos de 3 imóveis num turno → recebe **os 3**, espaçados, **cada um uma vez**.
2. Cliente pede fotos do **mesmo** imóvel duas vezes → recebe o próximo lote, nunca o mesmo.
3. Um humano assume no meio da fila → **nenhuma foto pendente é enviada**.
4. Fila com código fora da busca da conversa → recusado no enfileiramento (trava preservada).
5. Job executado duas vezes para o mesmo item → **um** envio.
6. Conversa sem fila → caminho de hoje, byte a byte.

Medir com o histórico real da conversa 49439, que tem o pedido de três imóveis num turno só.

---

## 7. Decisões em aberto

- **Namespace:** isto não é específico da Tozi — qualquer conta com carrossel de fotos tem o mesmo
  problema. Nasce genérico (`Captain::`), não em `Spx::Tozi::`.
- **Ligar por conta?** Segue o princípio do produto (comportamento novo é opt-in por conta).
  Sugestão: chave em `assistant.config` junto de `fotos_carrossel`.
- **Portão de "mudou de assunto"** (§4.5): começar sem ele. É o mais difícil de acertar e o menos
  perigoso de faltar, porque a fila expira em minutos.

## 8. Fora de escopo

- Mudar o `COOLDOWN` em si — ele continua válido contra rajada espontânea; o que muda é o que
  acontece quando ele dispara.
- O rótulo do carrossel no histórico: **já corrigido** em commit separado nesta mesma frente.
