// Two flow records, intentionally out of id order so getFlows sorting is meaningful.
export default [
  {
    id: 2,
    name: 'Follow-up automático',
    description: 'Envia follow-up após 24h',
    active: true,
    definition: {
      nodes: [
        { id: 'n1', type: 'trigger', event_name: 'conversation_created' },
        {
          id: 'n2',
          type: 'action',
          action_name: 'send_message',
          action_params: { message: 'Olá' },
        },
      ],
      edges: [{ from: 'n1', to: 'n2' }],
    },
  },
  {
    id: 1,
    name: 'Boas-vindas',
    description: 'Marca label e atribui time',
    active: false,
    definition: {
      nodes: [{ id: 'n1', type: 'trigger', event_name: 'conversation_opened' }],
      edges: [],
    },
  },
];
