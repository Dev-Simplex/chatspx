import { ref } from 'vue';

export const useLoadWithRetry = (config = {}) => {
  const maxRetry = config.max_retry || 3;
  const backoff = config.backoff || 1000;

  const isLoaded = ref(false);
  const hasError = ref(false);

  const loadWithRetry = async url => {
    const attemptLoad = () => {
      return new Promise((resolve, reject) => {
        const img = new Image();

        img.onload = () => {
          isLoaded.value = true;
          hasError.value = false;
          resolve();
        };

        img.onerror = () => {
          reject(new Error('Failed to load image'));
        };

        img.src = url;
      });
    };

    const sleep = ms => {
      return new Promise(resolve => {
        setTimeout(resolve, ms);
      });
    };

    const retry = async (attempt = 0) => {
      try {
        await attemptLoad();
      } catch (error) {
        if (attempt + 1 >= maxRetry) {
          hasError.value = true;
          isLoaded.value = false;
          return;
        }
        await sleep(backoff * (attempt + 1));
        await retry(attempt + 1);
      }
    };

    await retry();
  };

  return {
    isLoaded,
    hasError,
    loadWithRetry,
  };
};

// A mesma retentativa para uma LISTA de <img>/<video> (faixa de midias, quadros do album), onde um
// composable por imagem nao cabe num v-for. A miniatura de uma midia recem-chegada pode ser pedida antes
// de o arquivo chegar ao disco (a corrida medida dura ate ~3,6s); o servidor responde 404 sem cache e
// aqui a peca tenta de novo com o mesmo espacamento do useLoadWithRetry (1s, 2s). O `retry` na URL e so
// para o src mudar e o navegador pedir de novo. Esgotadas as tentativas, `hasFailed` fica verdadeiro.
export const useImageListRetry = (config = {}) => {
  const maxRetry = config.max_retry || 3;
  const backoff = config.backoff || 1000;

  const attempts = ref({});
  const failed = ref({});

  const retrySrc = (key, src) => {
    const attempt = attempts.value[key] || 0;
    if (!src || !attempt) return src;
    return `${src}${src.includes('?') ? '&' : '?'}retry=${attempt}`;
  };

  const onLoadError = key => {
    const attempt = attempts.value[key] || 0;
    if (attempt + 1 >= maxRetry) {
      failed.value = { ...failed.value, [key]: true };
      return;
    }
    setTimeout(
      () => {
        attempts.value = { ...attempts.value, [key]: attempt + 1 };
      },
      backoff * (attempt + 1)
    );
  };

  const hasFailed = key => !!failed.value[key];

  return { retrySrc, onLoadError, hasFailed };
};
