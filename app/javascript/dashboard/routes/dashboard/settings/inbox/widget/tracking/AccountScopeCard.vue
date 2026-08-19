<script setup>
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';

/**
 * O que e da CONTA, mostrado aqui em somente leitura.
 *
 * Quem configura pixel precisa VER o modo de consentimento vigente, a retencao
 * do log e o interruptor geral — mesmo sem poder mudar nada disso na tela da
 * inbox. Esconder o que vale para todas as caixas faz o administrador
 * configurar contra uma regra que ele nao sabe que existe.
 */
defineProps({
  consentMode: { type: String, default: '' },
  killSwitch: { type: Boolean, default: false },
  retentionDays: { type: Number, default: 0 },
  dpaAccepted: { type: Boolean, default: false },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak"
    data-testid="account-scope-card"
  >
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.TITLE') }}
      </span>
      <span class="text-xs text-n-slate-10">
        {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.READ_ONLY') }}
      </span>
    </div>

    <dl class="grid gap-x-6 gap-y-1 sm:grid-cols-2">
      <div class="flex justify-between gap-2 text-sm">
        <dt class="text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.CONSENT') }}
        </dt>
        <dd class="text-n-slate-12" data-testid="account-consent">
          {{ consentMode || t('INBOX_WIDGET.TRACKING.ACCOUNT.UNSET') }}
        </dd>
      </div>
      <div class="flex justify-between gap-2 text-sm">
        <dt class="text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.KILL_SWITCH') }}
        </dt>
        <dd class="text-n-slate-12" data-testid="account-kill-switch">
          {{
            killSwitch
              ? t('INBOX_WIDGET.TRACKING.ACCOUNT.KILL_ON')
              : t('INBOX_WIDGET.TRACKING.ACCOUNT.KILL_OFF')
          }}
        </dd>
      </div>
      <div class="flex justify-between gap-2 text-sm">
        <dt class="text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.RETENTION') }}
        </dt>
        <dd class="text-n-slate-12" data-testid="account-retention">
          {{
            retentionDays
              ? t('INBOX_WIDGET.TRACKING.ACCOUNT.RETENTION_DAYS', {
                  days: retentionDays,
                })
              : t('INBOX_WIDGET.TRACKING.ACCOUNT.UNSET')
          }}
        </dd>
      </div>
      <div class="flex justify-between gap-2 text-sm">
        <dt class="text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.DPA') }}
        </dt>
        <dd class="text-n-slate-12" data-testid="account-dpa">
          {{
            dpaAccepted
              ? t('INBOX_WIDGET.TRACKING.ACCOUNT.DPA_YES')
              : t('INBOX_WIDGET.TRACKING.ACCOUNT.DPA_NO')
          }}
        </dd>
      </div>
    </dl>

    <Banner v-if="killSwitch" color="amber" data-testid="kill-switch-warning">
      <span class="text-n-amber-12">
        {{ t('INBOX_WIDGET.TRACKING.ACCOUNT.KILL_WARNING') }}
      </span>
    </Banner>
  </div>
</template>
