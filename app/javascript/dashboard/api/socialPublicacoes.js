/* global axios */
import ApiClient from './ApiClient';

// Publicações onde algum comentário chegou. O cache que esta lista mostra é o mesmo dado que a
// IA precisa para responder um comentário — sem legenda ela não sabe do que se fala.
class SocialPublicacoesAPI extends ApiClient {
  constructor() {
    super('social_publicacoes', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }
}

export default new SocialPublicacoesAPI();
