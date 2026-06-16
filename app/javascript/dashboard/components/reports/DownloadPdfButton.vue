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
        if (downloadUrl) {
          window.open(downloadUrl, '_blank');
        }
      } catch (error) {
        useAlert(
          this.$t('REPORT.DOWNLOAD_PDF_FAILED', {
            default: 'Erro ao gerar o PDF do relatório',
          })
        );
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<template>
  <V4Button
    :label="$t('REPORT.DOWNLOAD_PDF', { default: 'Baixar PDF' })"
    icon="i-lucide-file-down"
    size="sm"
    variant="outline"
    :is-loading="loading"
    @click="onClick"
  />
</template>
