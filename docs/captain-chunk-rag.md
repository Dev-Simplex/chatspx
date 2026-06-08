# Captain — Chunk-based RAG (knowledge por documento)

Subsistema de RAG **baseado em chunk** para o Captain, complementar à FAQ (Q&A) existente.
Genérico e multi-tenant (escopado por `account_id` + `assistant_id`) — nasce com a Tozi, serve qualquer cliente.

## Por quê

A knowledge do Captain era **só FAQ**: documento → LLM gera pares pergunta/resposta → só as Q&A são embeddadas. Isso engessa conhecimento que não é Q&A (playbooks, procedimentos, tabelas, táticas) e perde o que o gerador de FAQ não capturar. Este subsistema adiciona o caminho **chunk → embedding → retrieval de passagem**, que é o padrão moderno e preserva qualquer tipo de conteúdo.

## Arquitetura

```
Document (URL/PDF/conteúdo)
   │  after_commit (quando available)
   ├─ ResponseBuilderJob  → FAQ Q&A  → embedding   (mode: faq | hybrid)
   └─ ChunkBuilderJob     → chunks                  (mode: chunks | hybrid)
          │ DocumentChunkingService (recursivo, overlap)
          │ ContextualChunkService  (opcional: LLM situa o chunk no doc — Anthropic contextual retrieval)
          ▼
       Captain::DocumentChunk (content + contextual_content + embedding vector(1536) + content_search tsvector)
          │ after_commit → UpdateEmbeddingJob (embedda contextual_content||content)
          ▼
   Retrieval: DocumentChunk.hybrid_search(query)
          = vetor (cosine, HNSW) ⊕ full-text (tsvector) fundidos por Reciprocal Rank Fusion
          ▼
   Tool do agente: search_knowledge  (ao lado de faq_lookup)
```

## Componentes

| Arquivo | Papel |
|---|---|
| `db/migrate/20260528120000_create_captain_document_chunks.rb` | tabela + índice HNSW (fallback ivfflat) + GIN full-text |
| `enterprise/app/models/captain/document_chunk.rb` | modelo, `has_neighbors`, `hybrid_search`, RRF |
| `enterprise/app/services/captain/llm/document_chunking_service.rb` | splitter recursivo (parágrafo→frase→hard), com overlap |
| `enterprise/app/services/captain/llm/contextual_chunk_service.rb` | contexto por chunk (opcional) |
| `enterprise/app/jobs/captain/documents/chunk_builder_job.rb` | ingestão: chunk + contextualiza + cria chunks |
| `enterprise/app/services/captain/tools/search_knowledge_tool.rb` | tool de retrieval híbrido p/ o agente |
| `config/agents/tools.yml` | registra `search_knowledge` |
| Edições em `captain/document.rb`, `captain/assistant.rb` | wiring + config |

## Configuração (por Assistant, em `config`)

- `knowledge_mode`: `faq` (padrão/legado) · `chunks` · `hybrid`
- `contextual_chunks`: `true` (padrão quando chunk ativo) · `false` (economiza custo de ingestão)

`faq` é o default → **contas existentes não mudam de comportamento**. Para ativar chunk-RAG numa assistant:

```ruby
assistant.update!(config: assistant.config.merge('knowledge_mode' => 'hybrid'))
```

O tool `search_knowledge` é injetado automaticamente na assistant quando `chunk_knowledge_enabled?`. Para os **scenarios** (ex.: Júlia/Bruna/Letícia) usarem, vincule `search_knowledge` à lista de tools de cada scenario (via API/painel ou script de apply).

## Retrieval híbrido

`Captain::DocumentChunk.hybrid_search(query, assistant_id:, account_id:, limit: 8, candidates: 30)`:
1. **vetor**: embedda a query → `nearest_neighbors(cosine)` top-N
2. **full-text**: `websearch_to_tsquery('simple')` + `ts_rank` top-N
3. **fusão**: Reciprocal Rank Fusion (k=60) → top `limit`

Sem dependência externa. **Ponto de extensão:** aplicar um reranker (cross-encoder/Cohere) sobre o resultado fundido.

## Exclusão / atualização (limpeza de vetores)

- `Document has_many :document_chunks, dependent: :destroy` → apagar o documento **apaga os chunks e seus embeddings**.
- Reprocessar (`ChunkBuilderJob`) faz `destroy_all` antes de recriar → sem lixo.

## Deploy

1. `bundle exec rails db:migrate` (cria `captain_document_chunks`). Requer extensão `vector`; HNSW precisa pgvector ≥ 0.5 (há fallback ivfflat).
2. Reiniciar o Rails (carregar modelo/tool/yml).
3. Ativar `knowledge_mode` nas assistants desejadas.
4. (Re)criar/atualizar documentos → jobs de chunk + embedding rodam na fila `low`.

## Verificação

- Specs: `bundle exec rspec spec/enterprise/services/captain/llm/document_chunking_service_spec.rb spec/enterprise/models/captain/document_chunk_spec.rb spec/enterprise/jobs/captain/documents/chunk_builder_job_spec.rb`
- Sanidade de retrieval: criar documento, aguardar jobs, `Captain::DocumentChunk.hybrid_search('termo', assistant_id: X)`.

## Pendências conhecidas (follow-up)

- **PDF → content:** o ChunkBuilderJob usa `document.content`. PDFs hoje vão pela pipeline de FAQ (OpenAI file). Para chunk-RAG de PDF, extrair texto do PDF para `content` na ingestão. URLs e conteúdo de texto já funcionam.
- **Reranker:** deixado como ponto de extensão (RRF já entrega boa precisão sem dependência).
- **Bind automático do `search_knowledge` nos scenarios:** hoje manual (API/script).
- **Embedding model:** segue `text-embedding-3-small` (config da conta). Avaliar modelo maior se precisão exigir.
