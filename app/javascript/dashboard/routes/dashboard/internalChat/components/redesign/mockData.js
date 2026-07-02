// Chat interno — REDESIGN visual (protótipo). Dados fictícios que espelham o
// contrato que o backend real vai fornecer depois, para o wire ser trivial.
//
// Contrato:
//   conversation: {
//     id, name, isGroup, avatarSrc, iconName, presence ('online'|'offline'|null),
//     time (label pronto), unreadCount, favorited,
//     lastMessage: { preview, fromMe }   // fromMe → prefixo "Você:"
//   }
//   threadItem (message list): um de
//     { type: 'day', id, label }
//     { type: 'unread', id, label }
//     { type: 'message', id, mine, senderName, avatarSrc, content, time, read }

export const currentUser = {
  id: 'me',
  name: 'João Almeida',
};

// Pessoas com quem ainda não há conversa (para o "nova conversa"/"contato").
export const availableContacts = [
  { id: 101, name: 'Larissa Carvalho', presence: 'online' },
  { id: 102, name: 'Thiago Mendes', presence: 'offline' },
  { id: 103, name: 'Carolina Dias', presence: 'online' },
  { id: 104, name: 'Bruno Azevedo', presence: 'offline' },
  { id: 105, name: 'Renata Barros', presence: 'online' },
  { id: 106, name: 'Gustavo Rocha', presence: 'offline' },
];

export const conversations = [
  {
    id: 1,
    name: 'André Martins',
    isGroup: false,
    avatarSrc: null,
    presence: 'online',
    time: '10:24',
    unreadCount: 2,
    favorited: true,
    lastMessage: { preview: 'Perfeito! Pode me enviar.', fromMe: true },
  },
  {
    id: 2,
    name: 'Juliana Prado',
    isGroup: false,
    avatarSrc: null,
    presence: 'online',
    time: '09:15',
    unreadCount: 1,
    favorited: false,
    lastMessage: { preview: 'Claro, já atualizei aqui.', fromMe: false },
  },
  {
    id: 3,
    name: 'Equipe Comercial',
    isGroup: true,
    avatarSrc: null,
    iconName: 'i-lucide-users',
    presence: null,
    time: '08:47',
    unreadCount: 3,
    favorited: false,
    lastMessage: { preview: 'Marcos: Bom dia, pessoal!', fromMe: false },
  },
  {
    id: 4,
    name: 'Marcos Vinícius',
    isGroup: false,
    avatarSrc: null,
    presence: 'offline',
    time: 'Ontem',
    unreadCount: 0,
    favorited: false,
    lastMessage: { preview: 'Pode me enviar o relatório?', fromMe: false },
  },
  {
    id: 5,
    name: 'Suporte',
    isGroup: true,
    avatarSrc: null,
    iconName: 'i-lucide-headset',
    presence: null,
    time: 'Ontem',
    unreadCount: 0,
    favorited: false,
    lastMessage: { preview: 'Camila: Ticket #1258 resolvido', fromMe: false },
  },
  {
    id: 6,
    name: 'Camila Santos',
    isGroup: false,
    avatarSrc: null,
    presence: 'online',
    time: 'Seg',
    unreadCount: 0,
    favorited: true,
    lastMessage: { preview: 'Obrigada!', fromMe: false },
  },
  {
    id: 7,
    name: 'RH & Departamento Pessoal',
    isGroup: true,
    avatarSrc: null,
    iconName: 'i-lucide-users',
    presence: null,
    time: 'Sex',
    unreadCount: 0,
    favorited: false,
    lastMessage: { preview: 'Fernanda: Documentos atualizados', fromMe: false },
  },
  {
    id: 8,
    name: 'Lucas Ferreira',
    isGroup: false,
    avatarSrc: null,
    presence: 'offline',
    time: 'Sex',
    unreadCount: 0,
    favorited: false,
    lastMessage: { preview: 'Beleza, dá uma olhada lá', fromMe: false },
  },
];

// Threads por conversa (só a do André está preenchida no protótipo).
export const threadsByConversation = {
  1: [
    { type: 'day', id: 'd1', label: 'Hoje' },
    {
      type: 'message',
      id: 'm1',
      mine: false,
      senderName: 'André Martins',
      content: 'Bom dia, João! Tudo bem?',
      time: '10:21',
    },
    {
      type: 'message',
      id: 'm2',
      mine: true,
      content: 'Bom dia, André! Tudo ótimo e com você?',
      time: '10:21',
      read: true,
    },
    {
      type: 'message',
      id: 'm3',
      mine: false,
      senderName: 'André Martins',
      content:
        'Tudo bem também! Preciso daquele relatório de vendas do último mês, você consegue me enviar?',
      time: '10:22',
    },
    {
      type: 'message',
      id: 'm4',
      mine: true,
      content: 'Claro! Já estou finalizando aqui e te envio em alguns minutos.',
      time: '10:23',
      read: true,
    },
    {
      type: 'message',
      id: 'm5',
      mine: false,
      senderName: 'André Martins',
      content: 'Perfeito! Obrigado 👍',
      time: '10:23',
    },
    {
      type: 'message',
      id: 'm6',
      mine: true,
      content: 'Pode deixar! Qualquer coisa me chama.',
      time: '10:24',
      read: true,
    },
    { type: 'unread', id: 'u1', label: '2 mensagens não lidas' },
    {
      type: 'message',
      id: 'm7',
      mine: false,
      senderName: 'André Martins',
      content: 'Você conseguiu gerar o relatório?',
      time: '10:24',
    },
    {
      type: 'message',
      id: 'm8',
      mine: false,
      senderName: 'André Martins',
      content: 'Perfeito! Pode me enviar.',
      time: '10:24',
    },
  ],
};

export const getThread = conversationId =>
  threadsByConversation[conversationId] || [
    { type: 'day', id: 'd0', label: 'Hoje' },
  ];
