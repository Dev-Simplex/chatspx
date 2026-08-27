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
import NextSelect from 'dashboard/components-next/select/Select.vue';

const timeSlots = generateTimeSlots(30);

// Em 24 h a lista já sobe na ordem do relógio: 00:00 → 23:59. Não há mais o que
// agrupar (o agrupamento AM/PM só existia para separar as duas metades do dia).
const timeOptions = timeSlots.map(slot => ({ value: slot, label: slot }));

export default {
  components: {
    Icon,
    NextSelect,
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
  },
  emits: ['update'],
  computed: {
    fromTimeSlots() {
      return timeOptions;
    },
    toTimeSlots() {
      // Fechar à meia-noite se diz 23:59; 00:00 só faz sentido como hora de abrir.
      return timeOptions.filter(option => option.value !== MIDNIGHT);
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
    totalHours() {
      if (this.timeSlot.openAllDay) return '24h';

      const totalMinutes = differenceInMinutes(this.toDate, this.fromDate);
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
          this.$emit('update', {
            ...this.timeSlot,
            from: MIDNIGHT,
            to: END_OF_DAY,
            valid: true,
            openAllDay: value,
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
    <td class="ltr:pl-4 ltr:pr-3 rtl:pl-3 rtl:pr-4">
      <div class="flex items-center gap-2 min-h-16">
        <input
          v-model="isDayEnabled"
          name="enable-day"
          class="m-0"
          type="checkbox"
          :title="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.ENABLE')"
        />
        <span class="text-body-main text-n-slate-12 font-medium">
          {{ dayName }}
        </span>
      </div>
    </td>
    <td class="py-3 ltr:pr-3 rtl:pl-3">
      <div v-if="isDayEnabled" class="flex flex-col gap-1.5">
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <input
              v-model="isOpenAllDay"
              name="enable-open-all-day"
              class="m-0"
              type="checkbox"
              :title="$t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')"
            />
            <span class="text-body-main text-n-slate-12">{{
              $t('INBOX_MGMT.BUSINESS_HOURS.ALL_DAY')
            }}</span>
          </div>
          <NextSelect
            v-model="fromTime"
            :options="fromTimeSlots"
            :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            :disabled="isOpenAllDay"
          />
          <div class="flex items-center">
            <Icon icon="i-lucide-minus size-4" />
          </div>
          <NextSelect
            v-model="toTime"
            :options="toTimeSlots"
            :placeholder="$t('INBOX_MGMT.BUSINESS_HOURS.DAY.CHOOSE')"
            :disabled="isOpenAllDay"
          />
        </div>
        <span v-if="hasError" class="error text-label-small text-n-ruby-9">
          {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.VALIDATION_ERROR') }}
        </span>
      </div>
      <span v-else class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.UNAVAILABLE') }}
      </span>
    </td>
    <td class="py-3 ltr:pr-3 rtl:pl-3">
      <span
        v-if="isDayEnabled && !hasError"
        class="label bg-n-blue-3 text-n-blue-11 text-label-small inline-block px-2 py-1 rounded-lg cursor-default whitespace-nowrap"
      >
        {{ totalHours }}
      </span>
    </td>
  </tr>
</template>
