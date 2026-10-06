<script>
import { useAlert } from 'dashboard/composables';
import V4Button from 'dashboard/components-next/button/Button.vue';

export default {
  name: 'DownloadPdfButton',
  components: { V4Button },
  props: {
    // 'nps' | 'csat' | ... — seleciona template/resolver no backend
    reportType: { type: String, required: true },
    // { from, to, user_ids, inbox_id, team_id } (mesmo requestPayload da view)
    filters: { type: Object, default: () => ({}) },
  },
  data() {
    return { loading: false };
  },
  methods: {
    async onClick() {
      if (this.loading) return;
      this.loading = true;
      try {
        const downloadUrl = await this.$store.dispatch(
          'reportPdfExports/generate',
          { reportType: this.reportType, ...this.filters }
        );
        // Link com `download` em vez de window.open: o PDF leva segundos para ficar pronto e,
        // passado o clique, o navegador bloqueia a janela nova em silêncio. A URL já vem como
        // anexo (disposition: attachment), então o arquivo baixa sem sair da tela.
        if (downloadUrl) {
          const link = document.createElement('a');
          link.href = downloadUrl;
          link.download = '';
          link.click();
        }
      } catch (error) {
        useAlert(this.$t('REPORT.DOWNLOAD_PDF_FAILED'));
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<template>
  <V4Button
    :label="loading ? $t('REPORT.GENERATING_PDF') : $t('REPORT.DOWNLOAD_PDF')"
    icon="i-lucide-file-down"
    size="sm"
    variant="outline"
    :is-loading="loading"
    @click="onClick"
  />
</template>
