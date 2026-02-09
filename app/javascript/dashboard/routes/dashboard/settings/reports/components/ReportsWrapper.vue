<template>
  <div class="reports--wrapper overflow-auto bg-n-background w-full px-6">
    <div class="max-w-[84rem] mx-auto pb-16">
      <router-view />
    </div>
  </div>
</template>

<style scoped lang="scss">
.reports--wrapper {
  background:
    radial-gradient(
        1200px 600px at 20% -10%,
        rgba(45, 196, 111, 0.08),
        transparent 60%
      ),
    radial-gradient(
        1200px 600px at 90% 0%,
        rgba(45, 196, 111, 0.06),
        transparent 55%
      ),
    rgb(var(--background-color));

  :deep() {
    .multiselect--disabled {
      @apply opacity-50 border border-n-weak rounded-md cursor-not-allowed;
    }

    .multiselect__content-wrapper {
      @apply bg-n-solid-2 border border-n-weak text-n-slate-12;
      z-index: 120;
    }

    .multiselect__tags {
      @apply bg-n-slate-1 border border-n-weak m-0 min-h-[2.875rem] pt-0;

      input[type='text'] {
        @apply bg-n-alpha-3 border-n-weak placeholder:text-n-slate-11 min-h-[2.375rem] h-[2.375rem] px-0.5 py-0 text-sm;
      }
    }

    .multiselect__placeholder {
      @apply text-n-slate-11;
    }

    .multiselect__select {
      @apply min-h-0;
    }

    .multiselect__single {
      @apply bg-n-alpha-3 text-n-slate-11;
    }

    .multiselect__input {
      @apply text-sm h-[2.375rem] mb-0 py-0;
    }

    .multiselect__tags,
    .multiselect__input,
    .multiselect {
      @apply bg-n-alpha-3 !border-n-weak text-n-slate-12 rounded-lg text-sm min-h-[2.5rem];
    }

    .multiselect {
      position: relative;
      z-index: 20;
    }

    .multiselect--active {
      z-index: 140;
    }

    .mx-input-wrapper {
      @apply bg-n-alpha-3 border-n-weak text-n-slate-12 rounded-lg text-sm;

      input {
        @apply border-n-weak text-sm;
      }
    }

    .multiselect__option {
      @apply flex items-center;
    }

    .mx-datepicker {
      .mx-input {
        background-color: transparent !important;
      }

      .mx-input-wrapper input::placeholder {
        @apply text-n-slate-11;
      }

      .mx-input-wrapper input {
        @apply text-n-slate-11;
      }
    }

    .multiselect--active:not(.multiselect--above) .multiselect__current,
    .multiselect--active:not(.multiselect--above) .multiselect__input,
    .multiselect--active:not(.multiselect--above) .multiselect__tags {
      @apply rounded-b-none;
    }
  }
}
</style>
