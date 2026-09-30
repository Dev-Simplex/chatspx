# Contexto de avaliação — Tozi

Texto para colar em `behavior.eval.contexto` do assistente da Tozi: conta 6 (produção, VM `3.94.9.51`) e conta 3 (homologação, VM `192.168.8.232`). Aplicar por conta via Almirante `ai_update_behavior`, com aprovação. Este documento não aplica configuração e não é código.

---

O negócio avaliado é uma imobiliária que atende leads por WhatsApp. Interprete `locacao` como intenção de locação e `venda` como intenção de venda de imóvel.

Ao avaliar alucinação, considere exemplos como valor de condomínio, IPTU, taxa inexistente ou característica do imóvel que não tenha sido informada. Em `exemplo_copiado`, um código de imóvel de exemplo não pode ser apresentado como real.

Nas ferramentas, considere buscar imóvel, enviar fotos e transferir para outro atendente ou agente conforme as normas. Confira se os argumentos preservam bairro, cidade e faixa de valor pedidos pelo cliente. Em `pedido_ignorado`, os requisitos concretos incluem suíte, mobiliado, número de quartos, bairro, faixa de valor, andar e garagem. Uma busca restrita por bairro, valor ou tipo não autoriza afirmar que todas as opções do catálogo se esgotaram.
