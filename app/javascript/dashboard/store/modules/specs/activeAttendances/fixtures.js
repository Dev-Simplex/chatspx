export default {
  meta: { count: 2, current_page: 1 },
  payload: [
    {
      id: 11,
      status: 'open',
      created_at: 1750000000,
      last_activity_at: 1750000500,
      contact: {
        id: 1,
        name: 'Fulano',
        thumbnail: '',
        phone_number: '+5511999999999',
        email: 'fulano@example.com',
      },
      inbox: { id: 3, name: 'WhatsApp', channel_type: 'Channel::Api' },
      assignee: {
        id: 7,
        name: 'Ana',
        available_name: 'Ana',
        thumbnail: '',
        type: 'user',
      },
      team: { id: 2, name: 'Suporte' },
    },
    {
      id: 12,
      status: 'pending',
      created_at: 1750000100,
      last_activity_at: 1750000400,
      contact: {
        id: 5,
        name: 'Beltrano',
        thumbnail: '',
        phone_number: '',
        email: '',
      },
      inbox: { id: 4, name: 'Site', channel_type: 'Channel::WebWidget' },
      assignee: null,
      team: null,
    },
  ],
};
