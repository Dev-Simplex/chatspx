<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const assessments = computed(() => [
  {
    id: 'disc',
    number: '01',
    eyebrow: t('ASSESSMENTS.DISC.EYEBROW'),
    title: t('ASSESSMENTS.DISC.TITLE'),
    description: t('ASSESSMENTS.DISC.DESCRIPTION'),
    questions: 25,
    duration: 8,
    accent: 'bg-[#8052ff]',
  },
  {
    id: 'career',
    number: '02',
    eyebrow: t('ASSESSMENTS.CAREER.EYEBROW'),
    title: t('ASSESSMENTS.CAREER.TITLE'),
    description: t('ASSESSMENTS.CAREER.DESCRIPTION'),
    questions: 24,
    duration: 7,
    accent: 'bg-[#ffb829]',
  },
  {
    id: 'emotional',
    number: '03',
    eyebrow: t('ASSESSMENTS.EMOTIONAL.EYEBROW'),
    title: t('ASSESSMENTS.EMOTIONAL.TITLE'),
    description: t('ASSESSMENTS.EMOTIONAL.DESCRIPTION'),
    questions: 60,
    duration: 15,
    accent: 'bg-[#15846e]',
  },
]);
</script>

<template>
  <main
    class="relative size-full overflow-y-auto bg-black font-sans text-white"
  >
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 overflow-hidden"
    >
      <span
        class="absolute left-[8%] top-[13%] size-1 rotate-45 bg-[#8052ff] motion-safe:animate-pulse"
      />
      <span
        class="absolute left-[24%] top-[72%] size-1.5 rotate-45 bg-[#ffb829] motion-safe:animate-ping"
      />
      <span
        class="absolute right-[12%] top-[18%] size-1 rotate-45 bg-[#15846e] motion-safe:animate-pulse"
      />
      <span
        class="absolute right-[31%] top-[54%] size-1 rotate-45 bg-[#8052ff] motion-safe:animate-ping"
      />
      <span
        class="absolute bottom-[9%] right-[8%] size-1.5 rotate-45 bg-[#ffb829] motion-safe:animate-pulse"
      />
      <div
        class="absolute -right-48 -top-48 size-[38rem] rounded-full bg-[#8052ff]/10 blur-3xl motion-safe:animate-pulse"
      />
    </div>

    <div
      class="relative mx-auto max-w-[1280px] px-6 py-12 md:px-12 md:py-20 xl:px-16"
    >
      <header class="grid gap-10 lg:grid-cols-[1.25fr_0.75fr] lg:items-end">
        <div>
          <p
            class="mb-5 text-xs font-semibold uppercase tracking-[0.2em] text-[#ffb829]"
          >
            {{ t('ASSESSMENTS.EYEBROW') }}
          </p>
          <h1
            class="max-w-4xl text-5xl font-normal leading-[0.95] tracking-[-0.04em] sm:text-6xl lg:text-[78px]"
          >
            {{ t('ASSESSMENTS.TITLE') }}
          </h1>
        </div>
        <p
          class="max-w-lg text-lg font-extralight leading-relaxed text-[#bdbdbd]"
        >
          {{ t('ASSESSMENTS.DESCRIPTION') }}
        </p>
      </header>

      <section class="mt-20 lg:mt-28" :aria-label="t('ASSESSMENTS.LIST_LABEL')">
        <article
          v-for="assessment in assessments"
          :key="assessment.id"
          class="group grid gap-6 border-t border-white/15 py-10 transition-colors duration-500 hover:border-[#8052ff] md:grid-cols-[5rem_1fr_auto] md:items-start md:py-14"
        >
          <span class="text-sm font-semibold tracking-[0.18em] text-[#9a9a9a]">
            {{ assessment.number }}
          </span>

          <div class="max-w-3xl">
            <div class="mb-4 flex items-center gap-3">
              <span class="size-2 rotate-45" :class="assessment.accent" />
              <p
                class="text-xs font-semibold uppercase tracking-[0.16em] text-[#bdbdbd]"
              >
                {{ assessment.eyebrow }}
              </p>
            </div>
            <h2
              class="text-3xl font-normal leading-tight tracking-[-0.04em] transition-colors duration-300 group-hover:text-[#ffb829] sm:text-[42px]"
            >
              {{ assessment.title }}
            </h2>
            <p
              class="mt-5 max-w-2xl text-base font-extralight leading-relaxed text-[#9a9a9a] sm:text-lg"
            >
              {{ assessment.description }}
            </p>
            <div
              class="mt-6 flex gap-6 text-xs uppercase tracking-[0.12em] text-[#9a9a9a]"
            >
              <span>{{
                t('ASSESSMENTS.QUESTIONS', { count: assessment.questions })
              }}</span>
              <span>{{
                t('ASSESSMENTS.DURATION', { minutes: assessment.duration })
              }}</span>
            </div>
          </div>

          <button
            type="button"
            disabled
            class="mt-2 inline-flex min-h-11 items-center justify-center rounded-3xl bg-[#8052ff] px-6 py-3 text-sm font-semibold uppercase tracking-[0.08em] text-white opacity-60 transition-shadow duration-300 hover:shadow-[0_0_32px_rgba(128,82,255,0.45)] disabled:cursor-not-allowed md:justify-self-end"
            :title="t('ASSESSMENTS.SOON')"
          >
            {{ t('ASSESSMENTS.SOON') }}
          </button>
        </article>
      </section>

      <footer
        class="mt-10 flex items-center gap-3 pb-8 text-sm font-extralight text-[#9a9a9a]"
      >
        <span class="size-1.5 rotate-45 bg-[#8052ff]" />
        {{ t('ASSESSMENTS.FOOTER') }}
      </footer>
    </div>
  </main>
</template>
