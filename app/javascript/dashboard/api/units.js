import ApiClient from './ApiClient';

class UnitsAPI extends ApiClient {
  constructor() {
    super('units', { accountScoped: true });
  }
}

export default new UnitsAPI();
