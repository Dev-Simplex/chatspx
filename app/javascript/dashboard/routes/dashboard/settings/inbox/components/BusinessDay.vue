<script>
import parse from 'date-fns/parse';
import differenceInMinutes from 'date-fns/differenceInMinutes';
import {
  generateTimeSlots,
  TIME_FORMAT,
  MIDNIGHT,
  END_OF_DAY,
} from '../helpers/businessHour';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// A lista de 30 em 30 minutos SÓ serve para os horários padrão de quando o dia é ligado
// (00:00 e 08:00). Os campos são de hora livre: uma unidade que abre 07:48 não tinha como ser
// cadastrada, e o banco sempre aceitou qualquer minuto (working_hour.rb).
const timeSlots = generateTimeSlots(30);

// Mesmo estilo dos campos de hora do editor de regras do calendário (UnitForm.vue).
const CAMPO_HORA =
  'reset-base h-10 w-28 px-3 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-surface-1 text-n-slate-12 disabled:opacity-50';

export default {
  components: {
    Icon,
  },
  props: {
    dayName: {
      type: String,
      required: true,
    },
    timeSlot: {
      type: Object,
      default: () => ({
        from: '',
        to: '',
      }),
    },
    // Parada para o almoço: só a grade da UNIDADE oferece. A da caixa de entrada
    // alimenta mensagem de ausência e widget, e continua com uma faixa por dia.
    showBreak: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update'],
  computed: {
    campoHora() {
      return CAMPO_HORA;
    },
    isDayEnabled: {
      get() {
        return Boolean(this.timeSlot.from && this.timeSlot.to);
      },
      set(value) {
        const newSlot = value
          ? {
              ...this.timeSlot,
              from: timeSlots[0],
              to: timeSlots[16],
              valid: true,
              openAllDay: false,
            }
          : {
              ...this.timeSlot,
              from: '',
              to: '',
              valid: false,
              openAllDay: false,
            };
        this.$emit('update', newSlot);
      },
    },
    fromTime: {
      get() {
        return this.timeSlot.from;
      },
      set(value) {
        const fromDate = parse(value, TIME_FORMAT, new Date());
        const valid = differenceInMinutes(this.toDate, fromDate) / 60 > 0;
        this.$emit('update', {
          ...this.timeSlot,
          from: value,
          valid,
        });
      },
    },
    toTime: {
      get() {
        return this.timeSlot.to;
      },
      set(value) {
        const toDate = parse(value, TIME_FORMAT, new Date());
        if (value === MIDNIGHT) {
          this.$emit('update', {
            ...this.timeSlot,
            to: value,
            valid: true,
          });
        } else {
          const valid = differenceInMinutes(toDate, this.fromDate) / 60 > 0;
          this.$emit('update', {
            ...this.timeSlot,
            to: value,
            valid,
          });
        }
      },
    },
    fromDate() {
      return parse(this.fromTime, TIME_FORMAT, new Date());
    },
    toDate() {
      return parse(this.toTime, TIME_FORMAT, new Date());
    },
    hasBreak: {
      get() {
        return Boolean(this.timeSlot.breakFrom && this.timeSlot.breakTo);
      },
      set(value) {
        this.$emit('update', {
          ...this.timeSlot,
          breakFrom: value ? '12:00' : '',
          breakTo: value ? '13:00' : '',
        });
      },
    },
    breakFrom: {
      get() {
        return this.timeSlot.breakFrom || '';
      },
      set(value) {
        this.$emit('update', { ...this.timeSlot, breakFrom: value });
      },
    },
    breakTo: {
      get() {
        return this.timeSlot.breakTo || '';
      },
      set(value) {
        this.$emit('update', { ...this.timeSlot, breakTo: value });
      },
    },
    breakMinutes() {
      if (!this.hasBreak) return 0;
      const inicio = parse(this.breakFrom, TIME_FORMAT, new Date());
      const fim = parse(this.breakTo, TIME_FORMAT, new Date());
      return Math.max(differenceInMinutes(fim, inicio), 0);
    },
    totalHours() {
      if (this.timeSlot.openAllDay) return '24h';

      // As horas do dia descontam a parada: quem abre 08–18 com uma hora de almoço
      // atende 9h, não 10h.
      const totalMinutes =
        differenceInMinutes(this.toDate, this.fromDate) - this.breakMinutes;
      const [h, m] = [Math.floor(totalMinutes / 60), totalMinutes % 60];

      return [h && `${h}h`, m && `${m}m`].filter(Boolean).join(' ') || '0m';
    },
    hasError() {
      return !this.timeSlot.valid;
    },
    isOpenAllDay: {
      get() {
        return this.timeSlot.openAllDay;
      },
      set(value) {
        if (value) {
          // A pausa sai junto: dia de 24 h não tem almoço, e como os controles dela
          // ficam escondidos aqui, um valor esquecido fecharia a unidade sem que
          // ninguém visse por quê (a faixa dizia "24h" e o meio-dia dizia fechada).
          this.$emit('update', {
            ...this.timeSlot,
            from: MIDNIGHT,
            to: END_OF_DAY,
            valid: true,
            openAllDay: value,
            breakFrom: '',
            breakTo: '',
          });
        } else {
          this.$emit('update', {
            ...this.timeSlot,
            from: '09:00',
            to: '17:00',
            valid: true,
            openAllDay: value,
          });
        }
      },
    },
  },
};
</script>

<template>
  <tr>
    <td class="py-3 align-top ltr:pl-4 ltr:pr-3 rtl:pl-3 rtl:pr-4">
      <label class="flex items-center gap-2 h-10 m-0 cursor-pointer">
        <input
          v-model="isDayEnabled"
          name="enable-day"
          class="m-0"
          type="checkbox"
          :title="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.ENABLE')"
        />
        <span
          class="text-body-main text-n-slate-12 font-medium whitespace-nowrap"
        >
          {{ dayName }}
        </span>
      </label>
    </td>
    <td class="py-3 align-top ltr:pr-3 rtl:pl-3">
      <!-- As duas faixas (dia todo e almoço) dividem a MESMA grade: sem isso cada linha media
           a própria largura, o campo da tarde caía para baixo e a coluna de horas desalinhava. -->
      <div
        v-if="isDayEnabled"
        class="grid grid-cols-[minmax(11.5rem,max-content)_7rem_1.25rem_7rem] items-center gap-x-3 gap-y-2"
      >
        <label class="flex items-center gap-2 m-0 cursor-pointer">
          <input
            v-model="isOpenAllDay"
            name="enable-open-all-day"
            class="m-0"
            type="checkbox"
            :title="$t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')"
          />
          <span class="text-body-main text-n-slate-12 whitespace-nowrap">{{
            $t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')
          }}</span>
        </label>
        <input
          v-model="fromTime"
          type="time"
          :class="campoHora"
          :disabled="isOpenAllDay"
          :aria-label="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
        />
        <Icon icon="i-lucide-minus size-4" class="justify-self-center" />
        <input
          v-model="toTime"
          type="time"
          :class="campoHora"
          :disabled="isOpenAllDay"
          :aria-label="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
        />
        <template v-if="showBreak && !isOpenAllDay">
          <label class="flex items-center gap-2 m-0 cursor-pointer">
            <input
              v-model="hasBreak"
              name="enable-break"
              class="m-0"
              type="checkbox"
            />
            <span class="text-body-main text-n-slate-11 whitespace-nowrap">
              {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.BREAK') }}
            </span>
          </label>
          <template v-if="hasBreak">
            <input v-model="breakFrom" type="time" :class="campoHora" />
            <Icon icon="i-lucide-minus size-4" class="justify-self-center" />
            <input v-model="breakTo" type="time" :class="campoHora" />
          </template>
        </template>
        <span
          v-if="hasError"
          class="col-span-4 error text-label-small text-n-ruby-9"
        >
          {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.VALIDATION_ERROR') }}
        </span>
      </div>
      <span
        v-else
        class="flex items-center h-10 text-body-main text-n-slate-11"
      >
        {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.UNAVAILABLE') }}
      </span>
    </td>
    <td class="py-3 align-top ltr:pr-3 rtl:pl-3">
      <div class="flex items-center gap-2 h-10 whitespace-nowrap">
        <span
          v-if="isDayEnabled && !hasError"
          class="label bg-n-blue-3 text-n-blue-11 text-label-small inline-block px-2 py-1 rounded-lg cursor-default"
        >
          {{ totalHours }}
        </span>
        <!-- "Copiar para os demais dias" mora aqui, preenchido por quem usa o componente: a grade da
             unidade passa o slot; a da caixa de entrada não, e a coluna fica igual à de antes. -->
        <slot name="acoes" />
      </div>
    </td>
  </tr>
</template>
