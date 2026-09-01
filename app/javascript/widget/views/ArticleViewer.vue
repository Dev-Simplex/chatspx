<script>
import IframeLoader from 'shared/components/IframeLoader.vue';

export default {
  name: 'ArticleViewer',
  components: {
    IframeLoader,
  },
};
</script>

<template>
  <div class="bg-n-solid-1 h-full">
    <!-- A frase do estado vazio vem daqui porque ela é do catálogo do widget:
         `PORTAL.IFRAME_LOAD_ERROR` está traduzida nos 56 locales e, até este
         bloco, não era lida por componente nenhum. -->
    <IframeLoader
      :url="$route.query.link"
      :error-message="$t('PORTAL.IFRAME_LOAD_ERROR')"
    />
  </div>
</template>
