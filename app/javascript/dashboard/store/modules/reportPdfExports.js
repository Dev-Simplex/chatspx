import ReportPdfExportsAPI from '../../api/reportPdfExports';

const POLL_INTERVAL_MS = 1500;
const MAX_POLL_ATTEMPTS = 40; // ~60s

const sleep = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export const actions = {
  // Cria o export, faz poll ate completed e resolve com a download_url assinada.
  generate: async (_store, payload) => {
    const { data } = await ReportPdfExportsAPI.create(payload);
    let { status, download_url: downloadUrl } = data;

    let attempts = 0;
    while (status !== 'completed' && status !== 'failed') {
      if (attempts >= MAX_POLL_ATTEMPTS) {
        throw new Error('PDF export timeout');
      }
      // eslint-disable-next-line no-await-in-loop
      await sleep(POLL_INTERVAL_MS);
      // eslint-disable-next-line no-await-in-loop
      const res = await ReportPdfExportsAPI.show(data.id);
      status = res.data.status;
      downloadUrl = res.data.download_url;
      attempts += 1;
    }

    if (status === 'failed') {
      throw new Error('PDF export failed');
    }
    return downloadUrl;
  },
};

export default {
  namespaced: true,
  state: {},
  getters: {},
  actions,
  mutations: {},
};
