/* global axios */
import ApiClient from './ApiClient';

// Comentários públicos capturados do Instagram — SPEC em docs/SPEC-instagram-social.md.
// Leitura apenas na Fase 1: responder é a fatia seguinte.
class SocialComentariosAPI extends ApiClient {
  constructor() {
    super('social_comentarios', { accountScoped: true });
  }

  getAll({ publicacaoId, incluirProprios, pagina } = {}) {
    return axios.get(this.url, {
      params: {
        publicacao_id: publicacaoId,
        incluir_proprios: incluirProprios,
        pagina,
      },
    });
  }

  // `forma` é 'publica' (aparece embaixo do post) ou 'privada' (cai no direct do autor).
  // Passa pelo portão do piloto no servidor mesmo vindo de clique humano.
  responder(id, { forma, texto }) {
    return axios.post(`${this.url}/${id}/responder`, { forma, texto });
  }
}

export default new SocialComentariosAPI();
