import { frontendURL } from 'dashboard/helper/URLHelper';

// Endereço da conversa do lead. Abre em outra aba: quem está vigiando o rodízio não perde o
// período, o filtro e a rolagem desta tela para ir ver um lead.
export const linkDaConversa = (accountId, displayId) =>
  frontendURL(`accounts/${accountId}/conversations/${displayId}`);
