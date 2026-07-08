// Galeria de MODELOS (templates) de fluxo — Fase 3.3. Cada modelo é um fluxo pronto que o
// usuário escolhe para começar já montado: a galeria (FlowTemplatesGallery.vue) navega para
// `automation_canvas_new?templateKey=<key>` e o FlowCanvasView SEMEIA a definition a partir
// daqui (seedFromTemplate) — mesmo caminho, de menor risco, do seedFromRule: NADA é gravado no
// banco até o usuário revisar e clicar em Salvar (sem flows órfãos, sem 422 prematuro em ações
// enterprise). O nó `trigger` já carrega event_name/trigger_kind, então triggerPayload deriva
// o trigger_type/trigger_config correto no save — os campos trigger_type/trigger_config abaixo
// são redundância declarativa (documentação + possível criação direta futura).
//
// FORMATO das definitions: idêntico ao que o canvas produz (FlowCanvasView/flatToDefinition):
//   nó   → { id, type, action_name?, action_params?, position?, conditions?, routes?, ... }
//   edge → { from, to, branch? }   // branch só em saídas de condition ('true'|'false') / router
// action_name SEMPRE ∈ Flow::BASE_ACTION_NAMES (+ IA enterprise ai_classify). Os action_params
// espelham a forma que cada editor de config persiste (ver os *Config.vue):
//   send_message      → [string]
//   send_template     → [{ name, language, content, processed_params }]
//   assign_team       → [team_id]        (vazio = placeholder "escolha um time")
//   add_label         → [title, ...]
//   ai_classify       → [{ assistant_id, prompt, categories[], target, store, key }]
//   send_csat         → []               (sem parâmetros)
//   wait (type)       → node.wait = { value, unit, business_hours }
//   condition (type)  → node.conditions = [{ attribute_key, filter_operator, values[], ... }]
//   router (type)     → node.routes = [{ key, label, conditions[] }] + node.fallback_key
//
// PLACEHOLDERS: conteúdos de mensagem/template e algumas condições são SEMENTES em pt-BR (locale
// primário) que o usuário revisa no canvas — são dados editáveis, não texto de UI. Ver o retorno
// da tarefa para a lista do que ficou como placeholder a revisar.
//
// META de cada modelo (resolvido via i18n no componente da galeria):
//   { key, nameKey, descriptionKey, icon, family, category, badge, whatsapp,
//     trigger_type, trigger_config, definition }
//   • family   — família de nós (nodeCatalog FAMILIES) que dá o ACENTO de cor do card
//   • category — agrupamento da galeria (chave i18n AUTOMATION.TEMPLATES.CATEGORIES.*)
//   • badge    — 'official' | 'popular' | null (selo sobre a miniatura)
//   • whatsapp — mostra o chip WhatsApp (modelos pensados para WhatsApp)

export const FLOW_TEMPLATES = [
  // 1 · Boas-vindas — conversation_created → send_message → add_label.
  {
    key: 'welcome',
    nameKey: 'AUTOMATION.TEMPLATES.ITEMS.WELCOME.NAME',
    descriptionKey: 'AUTOMATION.TEMPLATES.ITEMS.WELCOME.DESCRIPTION',
    icon: 'i-lucide-hand',
    family: 'msg',
    category: 'welcome',
    badge: 'official',
    whatsapp: true,
    trigger_type: 'conversation_event',
    trigger_config: { event_name: 'conversation_created' },
    definition: {
      nodes: [
        {
          id: 'n1',
          type: 'trigger',
          event_name: 'conversation_created',
          position: { x: 280, y: 40 },
        },
        {
          id: 'n2',
          type: 'action',
          action_name: 'send_message',
          action_params: [
            'Olá {{contact.name}}! 👋 Que bom ter você por aqui. Em que podemos ajudar hoje?',
          ],
          position: { x: 280, y: 200 },
        },
        {
          id: 'n3',
          type: 'action',
          action_name: 'add_label',
          action_params: ['lead-novo'],
          position: { x: 280, y: 360 },
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ],
    },
  },

  // 2 · Drip WhatsApp — o preset pedido. trigger → send_template → wait(1 dia) →
  // condition(ainda sem resposta?) → send_template (2ª cutucada) no ramo 'true'.
  {
    key: 'drip_whatsapp',
    nameKey: 'AUTOMATION.TEMPLATES.ITEMS.DRIP_WHATSAPP.NAME',
    descriptionKey: 'AUTOMATION.TEMPLATES.ITEMS.DRIP_WHATSAPP.DESCRIPTION',
    icon: 'i-lucide-droplets',
    family: 'msg',
    category: 'drip',
    badge: 'popular',
    whatsapp: true,
    trigger_type: 'conversation_event',
    trigger_config: { event_name: 'conversation_created' },
    definition: {
      nodes: [
        {
          id: 'n1',
          type: 'trigger',
          event_name: 'conversation_created',
          position: { x: 280, y: 40 },
        },
        {
          id: 'n2',
          type: 'action',
          action_name: 'send_template',
          action_params: [
            {
              name: '',
              language: 'pt_BR',
              content:
                '1ª mensagem do drip: dê as boas-vindas ou apresente a oferta. Selecione aqui um template aprovado do WhatsApp.',
              processed_params: {},
            },
          ],
          position: { x: 280, y: 200 },
        },
        {
          id: 'n3',
          type: 'wait',
          wait: { value: 1, unit: 'days', business_hours: false },
          position: { x: 280, y: 360 },
        },
        {
          id: 'n4',
          type: 'condition',
          // Placeholder: "conversa ainda ABERTA" ≈ cliente não respondeu/não foi resolvido.
          // Ramo 'true' → manda a 2ª cutucada. Revise para o seu sinal real de resposta/opt-out.
          conditions: [
            {
              attribute_key: 'status',
              filter_operator: 'equal_to',
              values: ['open'],
              custom_attribute_type: '',
            },
          ],
          position: { x: 280, y: 520 },
        },
        {
          id: 'n5',
          type: 'action',
          action_name: 'send_template',
          action_params: [
            {
              name: '',
              language: 'pt_BR',
              content:
                '2ª cutucada: o cliente ainda não respondeu. Reforce a oferta com um novo template aprovado.',
              processed_params: {},
            },
          ],
          position: { x: 120, y: 700 },
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
        { from: 'n3', to: 'n4' },
        { from: 'n4', to: 'n5', branch: 'true' },
      ],
    },
  },

  // 3 · Triagem por IA — trigger → ai_classify(categorias) → router(rotas) → assign_team.
  // As rotas do router nascem SÓ com rótulo (conditions:[]) — o editor escafolda uma linha de
  // condição pronta; configure cada rota para ler o atributo `ai_category` que a IA grava.
  {
    key: 'ai_triage',
    nameKey: 'AUTOMATION.TEMPLATES.ITEMS.AI_TRIAGE.NAME',
    descriptionKey: 'AUTOMATION.TEMPLATES.ITEMS.AI_TRIAGE.DESCRIPTION',
    icon: 'i-lucide-bot',
    family: 'ai',
    category: 'triage',
    badge: 'popular',
    whatsapp: true,
    trigger_type: 'conversation_event',
    trigger_config: { event_name: 'conversation_created' },
    definition: {
      nodes: [
        {
          id: 'n1',
          type: 'trigger',
          event_name: 'conversation_created',
          position: { x: 300, y: 40 },
        },
        {
          id: 'n2',
          type: 'action',
          action_name: 'ai_classify',
          action_params: [
            {
              assistant_id: null,
              prompt:
                'Leia a primeira mensagem do cliente e classifique a intenção em uma das categorias.',
              categories: ['vendas', 'suporte', 'financeiro'],
              target: 'conversation',
              store: 'custom',
              key: 'ai_category',
            },
          ],
          position: { x: 300, y: 200 },
        },
        {
          id: 'n3',
          type: 'router',
          routes: [
            { key: 'route_1', label: 'Vendas', conditions: [] },
            { key: 'route_2', label: 'Suporte', conditions: [] },
            { key: 'route_3', label: 'Financeiro', conditions: [] },
          ],
          fallback_key: 'fallback',
          position: { x: 300, y: 360 },
        },
        {
          id: 'n4',
          type: 'action',
          action_name: 'assign_team',
          action_params: [],
          position: { x: 0, y: 540 },
        },
        {
          id: 'n5',
          type: 'action',
          action_name: 'assign_team',
          action_params: [],
          position: { x: 300, y: 540 },
        },
        {
          id: 'n6',
          type: 'action',
          action_name: 'assign_team',
          action_params: [],
          position: { x: 600, y: 540 },
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
        { from: 'n3', to: 'n4', branch: 'route_1' },
        { from: 'n3', to: 'n5', branch: 'route_2' },
        { from: 'n3', to: 'n6', branch: 'route_3' },
      ],
    },
  },

  // 4 · Pesquisa CSAT — conversation_resolved → wait(10 min) → send_csat.
  {
    key: 'csat_survey',
    nameKey: 'AUTOMATION.TEMPLATES.ITEMS.CSAT_SURVEY.NAME',
    descriptionKey: 'AUTOMATION.TEMPLATES.ITEMS.CSAT_SURVEY.DESCRIPTION',
    icon: 'i-lucide-star',
    family: 'msg',
    category: 'csat',
    badge: 'official',
    whatsapp: true,
    trigger_type: 'conversation_event',
    trigger_config: { event_name: 'conversation_resolved' },
    definition: {
      nodes: [
        {
          id: 'n1',
          type: 'trigger',
          event_name: 'conversation_resolved',
          position: { x: 280, y: 40 },
        },
        {
          id: 'n2',
          type: 'wait',
          wait: { value: 10, unit: 'minutes', business_hours: false },
          position: { x: 280, y: 200 },
        },
        {
          id: 'n3',
          type: 'action',
          action_name: 'send_csat',
          action_params: [],
          position: { x: 280, y: 360 },
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ],
    },
  },

  // 5 · Atendimento por palavra-chave — trigger keyword → assign_team → send_message.
  {
    key: 'keyword_handoff',
    nameKey: 'AUTOMATION.TEMPLATES.ITEMS.KEYWORD_HANDOFF.NAME',
    descriptionKey: 'AUTOMATION.TEMPLATES.ITEMS.KEYWORD_HANDOFF.DESCRIPTION',
    icon: 'i-lucide-key-round',
    family: 'trigger',
    category: 'keyword',
    badge: null,
    whatsapp: true,
    trigger_type: 'keyword',
    trigger_config: {
      keywords: ['atendente', 'humano', 'falar com alguém'],
      match: 'contains',
    },
    definition: {
      nodes: [
        {
          id: 'n1',
          type: 'trigger',
          trigger_kind: 'keyword',
          keywords: ['atendente', 'humano', 'falar com alguém'],
          match: 'contains',
          position: { x: 280, y: 40 },
        },
        {
          id: 'n2',
          type: 'action',
          action_name: 'assign_team',
          action_params: [],
          position: { x: 280, y: 200 },
        },
        {
          id: 'n3',
          type: 'action',
          action_name: 'send_message',
          action_params: [
            'Perfeito! Já estou chamando um atendente humano para falar com você. 🙌',
          ],
          position: { x: 280, y: 360 },
        },
      ],
      edges: [
        { from: 'n1', to: 'n2' },
        { from: 'n2', to: 'n3' },
      ],
    },
  },
];

// Modelo pelo key (usado pelo FlowCanvasView#seedFromTemplate). Retorna null se não existir.
export function flowTemplateByKey(key) {
  if (!key) return null;
  return FLOW_TEMPLATES.find(template => template.key === key) || null;
}
