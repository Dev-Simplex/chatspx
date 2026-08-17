<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
// SABOTAGEM TEMPORARIA (bloco 0.5) — remover
import LStatic from 'leaflet';
import 'leaflet/dist/leaflet.css';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();

// Coordenadas fallback (centroide aproximado do Brasil) usadas enquanto o GPS
// está sendo resolvido — assim o mapa já aparece com algo desenhado em vez de
// um quadrado em branco.
const FALLBACK_LAT = -15.78;
const FALLBACK_LNG = -47.93;
const FALLBACK_ZOOM = 4;

// State
const selectedLocation = ref(null); // { lat, lng, label }
const loading = ref(false); // controla envio (footer disabled)
const geoLoading = ref(false); // overlay sobre o mapa enquanto getCurrentPosition resolve
const errorMessage = ref('');

// CEP/Número state
const cep = ref('');
const numero = ref('');
const cepLoading = ref(false);
const cepError = ref('');
let cepDebounceId = null;
let cepRequestSeq = 0;

const mapContainerRef = ref(null);
let mapInstance = null;
let markerInstance = null;
let leafletRef = null;
let reverseRequestSeq = 0;

const NOMINATIM_HEADERS = {
  // Nominatim asks every consumer to identify itself.
  'Accept-Language': 'pt-BR,en;q=0.7',
};
const NOMINATIM_SEARCH = 'https://nominatim.openstreetmap.org/search';
const NOMINATIM_REVERSE = 'https://nominatim.openstreetmap.org/reverse';
const VIACEP_URL = 'https://viacep.com.br/ws';

const cepDigits = computed(() => (cep.value || '').replace(/\D/g, ''));
const previewAddress = computed(() => selectedLocation.value?.label || '');
const canSubmit = computed(() => !!selectedLocation.value);

const close = () => {
  emit('close');
};

const formatCep = value => {
  const digits = String(value || '')
    .replace(/\D/g, '')
    .slice(0, 8);
  if (digits.length <= 5) return digits;
  return `${digits.slice(0, 5)}-${digits.slice(5)}`;
};

const onCepInput = event => {
  cep.value = formatCep(event.target.value);
};

const onNumeroInput = event => {
  numero.value = String(event.target.value || '').replace(/\D/g, '');
};

const resetState = () => {
  selectedLocation.value = null;
  loading.value = false;
  geoLoading.value = false;
  errorMessage.value = '';
  cep.value = '';
  numero.value = '';
  cepLoading.value = false;
  cepError.value = '';
};

const ensureLeaflet = async () => {
  // SABOTAGEM TEMPORARIA (bloco 0.5): usa o Leaflet importado estaticamente
  leafletRef = LStatic;
  return LStatic;
  if (leafletRef) return leafletRef;
  const [{ default: L }, iconUrlMod, iconRetinaUrlMod, shadowUrlMod] =
    await Promise.all([
      import('leaflet'),
      import('leaflet/dist/images/marker-icon.png'),
      import('leaflet/dist/images/marker-icon-2x.png'),
      import('leaflet/dist/images/marker-shadow.png'),
    ]);
  await import('leaflet/dist/leaflet.css');

  // Default icon URL workaround for bundlers.
  L.Icon.Default.mergeOptions({
    iconUrl: iconUrlMod.default || iconUrlMod,
    iconRetinaUrl: iconRetinaUrlMod.default || iconRetinaUrlMod,
    shadowUrl: shadowUrlMod.default || shadowUrlMod,
  });
  leafletRef = L;
  return L;
};

const reverseGeocode = async ({ lat, lng }) => {
  reverseRequestSeq += 1;
  const seq = reverseRequestSeq;
  try {
    const url = `${NOMINATIM_REVERSE}?format=jsonv2&lat=${lat}&lon=${lng}`;
    const res = await fetch(url, { headers: NOMINATIM_HEADERS });
    if (!res.ok) return null;
    const data = await res.json();
    if (seq !== reverseRequestSeq) return null;
    return data?.display_name || null;
  } catch {
    return null;
  }
};

const setMarker = async ({ lat, lng, label }) => {
  const L = await ensureLeaflet();
  if (!mapInstance) return;
  if (markerInstance) {
    markerInstance.setLatLng([lat, lng]);
  } else {
    markerInstance = L.marker([lat, lng], { draggable: true }).addTo(
      mapInstance
    );
    markerInstance.on('dragend', async event => {
      const { lat: newLat, lng: newLng } = event.target.getLatLng();
      selectedLocation.value = {
        lat: newLat,
        lng: newLng,
        label: t('CONVERSATION.LOCATION.LOADING'),
      };
      const newLabel = await reverseGeocode({ lat: newLat, lng: newLng });
      selectedLocation.value = {
        lat: newLat,
        lng: newLng,
        label: newLabel || `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`,
      };
    });
  }
  mapInstance.setView([lat, lng], 15);
  selectedLocation.value = {
    lat,
    lng,
    label: label || `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
  };
};

const initMap = async (lat = FALLBACK_LAT, lng = FALLBACK_LNG, zoom = 13) => {
  let L;
  try {
    L = await ensureLeaflet();
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[LocationPicker] ensureLeaflet failed', err);
    return;
  }
  // Esperar 2 ticks: o primeiro garante que o re-render do v-if foi aplicado;
  // o segundo cobre casos de Transition que adiam a inserção real no DOM.
  await nextTick();
  await nextTick();
  if (!mapContainerRef.value) {
    // eslint-disable-next-line no-console
    console.warn('[LocationPicker] mapContainerRef is null after nextTick');
    return;
  }
  if (mapInstance) {
    mapInstance.invalidateSize();
    return;
  }
  try {
    mapInstance = L.map(mapContainerRef.value, {
      zoomControl: true,
      attributionControl: true,
    }).setView([lat, lng], zoom);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(mapInstance);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[LocationPicker] L.map init failed', err);
    return;
  }
  // The map needs a tick after first paint to compute its size.
  setTimeout(() => mapInstance && mapInstance.invalidateSize(), 50);
  // Segunda invalidação: cobre casos onde o container ainda estava com
  // dimensões 0 logo após o Transition de abertura (~150ms).
  setTimeout(() => mapInstance && mapInstance.invalidateSize(), 250);
};

const fetchNominatim = async params => {
  const url = `${NOMINATIM_SEARCH}?${params.toString()}`;
  const res = await fetch(url, { headers: NOMINATIM_HEADERS });
  if (!res.ok) return [];
  const data = await res.json();
  return Array.isArray(data) ? data : [];
};

const geocodeAddress = async addressString => {
  const trimmed = (addressString || '').trim();
  if (trimmed.length < 3) return null;
  // Tentativa 1: limitando ao Brasil (caso de uso principal).
  let data = await fetchNominatim(
    new URLSearchParams({
      format: 'jsonv2',
      q: trimmed,
      countrycodes: 'br',
      limit: '1',
      addressdetails: '0',
      'accept-language': 'pt-BR',
    })
  );
  // Tentativa 2: sem countrycodes — heurística do Nominatim às vezes não
  // classifica o endereço como BR mesmo sendo.
  if (data.length === 0) {
    data = await fetchNominatim(
      new URLSearchParams({
        format: 'jsonv2',
        q: trimmed,
        limit: '1',
        addressdetails: '0',
        'accept-language': 'pt-BR',
      })
    );
  }
  if (data.length === 0) return null;
  const item = data[0];
  const lat = parseFloat(item.lat);
  const lng = parseFloat(item.lon);
  if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
  return { lat, lng };
};

const lookupCep = async digits => {
  cepRequestSeq += 1;
  const seq = cepRequestSeq;
  try {
    const res = await fetch(`${VIACEP_URL}/${digits}/json/`);
    if (!res.ok) {
      if (seq === cepRequestSeq)
        cepError.value = t('CONVERSATION.LOCATION.CEP_NOT_FOUND');
      return null;
    }
    const data = await res.json();
    if (seq !== cepRequestSeq) return null;
    if (!data || data.erro) {
      cepError.value = t('CONVERSATION.LOCATION.CEP_NOT_FOUND');
      return null;
    }
    return {
      logradouro: data.logradouro || '',
      bairro: data.bairro || '',
      localidade: data.localidade || '',
      uf: data.uf || '',
    };
  } catch {
    if (seq === cepRequestSeq)
      cepError.value = t('CONVERSATION.LOCATION.CEP_NOT_FOUND');
    return null;
  }
};

const buildAddressString = (parts, withNumber) => {
  const { logradouro, bairro, localidade, uf } = parts;
  const cityState = [localidade, uf].filter(Boolean).join(' - ');
  const head =
    withNumber && numero.value ? `${logradouro}, ${numero.value}` : logradouro;
  const left = [head, bairro].filter(Boolean).join(' - ');
  return [left, cityState].filter(Boolean).join(', ');
};

const buildAddressNoBairro = (parts, withNumber) => {
  const { logradouro, localidade, uf } = parts;
  const cityState = [localidade, uf].filter(Boolean).join(' - ');
  const head =
    withNumber && numero.value ? `${logradouro}, ${numero.value}` : logradouro;
  return [head, cityState].filter(Boolean).join(' - ');
};

const resolveAndPlot = async () => {
  cepError.value = '';
  errorMessage.value = '';
  if (cepDigits.value.length !== 8) return;
  cepLoading.value = true;
  try {
    const parts = await lookupCep(cepDigits.value);
    if (!parts) return;
    const fullAddress = buildAddressString(parts, true);
    let coords = await geocodeAddress(fullAddress);
    if (!coords) {
      // Fallback: alguns bairros não estão indexados no Nominatim — tentar sem bairro.
      coords = await geocodeAddress(buildAddressNoBairro(parts, true));
    }
    if (!coords) {
      // Última tentativa: sem número (alguns logradouros não têm numeração indexada).
      coords = await geocodeAddress(buildAddressNoBairro(parts, false));
    }
    if (!coords) {
      // ViaCEP não retorna lat/lng; sem geocodificação não temos pra onde mover o pin.
      errorMessage.value = t('CONVERSATION.LOCATION.NOT_FOUND');
      return;
    }
    if (!mapInstance) {
      await initMap(coords.lat, coords.lng, 16);
    }
    await setMarker({ lat: coords.lat, lng: coords.lng, label: fullAddress });
  } finally {
    cepLoading.value = false;
  }
};

const autoLocate = async () => {
  errorMessage.value = '';
  if (!('geolocation' in navigator)) {
    errorMessage.value = t('CONVERSATION.LOCATION.GPS_UNAVAILABLE');
    return;
  }
  // getCurrentPosition exige contexto seguro (HTTPS ou localhost). Sem isso falha
  // silenciosamente em alguns browsers — avisa antes de tentar.
  if (window.isSecureContext === false) {
    errorMessage.value = t('CONVERSATION.LOCATION.GPS_INSECURE_CONTEXT');
    return;
  }
  geoLoading.value = true;
  try {
    navigator.geolocation.getCurrentPosition(
      async position => {
        const { latitude, longitude, accuracy } = position.coords;
        // Sanity check: precisão pior que 5km geralmente significa fallback IP/WiFi,
        // não GPS — avisa o usuário pra revisar permissões, mas não bloqueia.
        if (typeof accuracy === 'number' && accuracy > 5000) {
          errorMessage.value = t('CONVERSATION.LOCATION.GPS_LOW_ACCURACY');
        }
        if (!mapInstance) {
          await initMap(latitude, longitude, 15);
        } else {
          mapInstance.setView([latitude, longitude], 15);
        }
        const label = await reverseGeocode({ lat: latitude, lng: longitude });
        await setMarker({
          lat: latitude,
          lng: longitude,
          label: label || `${latitude.toFixed(5)}, ${longitude.toFixed(5)}`,
        });
        geoLoading.value = false;
      },
      error => {
        if (error && error.code === error.PERMISSION_DENIED) {
          errorMessage.value = t('CONVERSATION.LOCATION.GPS_DENIED');
        } else if (error && error.code === error.POSITION_UNAVAILABLE) {
          errorMessage.value = t('CONVERSATION.LOCATION.GPS_UNAVAILABLE');
        } else if (error && error.code === error.TIMEOUT) {
          errorMessage.value = t('CONVERSATION.LOCATION.GPS_TIMEOUT');
        } else {
          errorMessage.value = t('CONVERSATION.LOCATION.GPS_UNAVAILABLE');
        }
        geoLoading.value = false;
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  } catch (e) {
    errorMessage.value = t('CONVERSATION.LOCATION.GPS_UNAVAILABLE');
    geoLoading.value = false;
  }
};

watch(cep, () => {
  cepError.value = '';
  if (cepDebounceId) clearTimeout(cepDebounceId);
  if (cepDigits.value.length !== 8) return;
  cepDebounceId = setTimeout(() => resolveAndPlot(), 300);
});

watch(numero, () => {
  if (cepDebounceId) clearTimeout(cepDebounceId);
  // Só re-resolve quando já temos CEP completo — número sozinho não vira endereço.
  if (cepDigits.value.length !== 8) return;
  cepDebounceId = setTimeout(() => resolveAndPlot(), 300);
});

const submit = () => {
  if (!selectedLocation.value) return;
  emit('select', {
    latitude: selectedLocation.value.lat,
    longitude: selectedLocation.value.lng,
    address: selectedLocation.value.label,
  });
};

const onKeyDown = event => {
  if (!props.show) return;
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
};

watch(
  () => props.show,
  async isOpen => {
    if (isOpen) {
      resetState();
      await initMap(FALLBACK_LAT, FALLBACK_LNG, FALLBACK_ZOOM);
      autoLocate();
    } else if (mapInstance) {
      mapInstance.remove();
      mapInstance = null;
      markerInstance = null;
    }
  },
  // O parent usa v-if + :show=true ao mesmo tempo, então o componente nasce
  // com show=true. immediate:true garante que o watch dispare no mount;
  // flush:'post' garante que rode depois do v-if/Transition aplicar no DOM
  // (caso contrário mapContainerRef.value é null e initMap falha silenciosamente).
  { immediate: true, flush: 'post' }
);

onBeforeUnmount(() => {
  if (cepDebounceId) clearTimeout(cepDebounceId);
  if (mapInstance) {
    mapInstance.remove();
    mapInstance = null;
    markerInstance = null;
  }
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        role="dialog"
        aria-modal="true"
        aria-labelledby="location-picker-modal-title"
        class="fixed inset-0 z-[1000] flex items-start justify-center px-4 pt-[8vh] pb-8 bg-n-alpha-black1 backdrop-blur-[4px]"
        @click.self="close"
        @keydown="onKeyDown"
      >
        <div
          class="w-full max-w-2xl flex flex-col bg-n-solid-1 dark:bg-[#233138] border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] rounded-xl shadow-[0_8px_32px_rgba(11,20,26,0.18)] overflow-hidden max-h-[90vh]"
          @click.stop
        >
          <header
            class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-slate-3 dark:border-n-slate-7"
          >
            <div class="flex items-center gap-2">
              <span class="i-lucide-map-pin size-5 text-n-brand" />
              <h2
                id="location-picker-modal-title"
                class="text-base font-medium text-n-slate-12"
              >
                {{ t('CONVERSATION.LOCATION.MODAL_TITLE') }}
              </h2>
            </div>
            <button
              type="button"
              class="flex items-center justify-center size-8 rounded-md text-n-slate-11 hover:bg-n-slate-3 dark:hover:bg-n-slate-7"
              :aria-label="t('GENERAL.CLOSE')"
              @click="close"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </header>

          <div class="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-4">
            <div
              v-if="errorMessage"
              class="flex items-start gap-2 px-3 py-2 rounded-lg bg-n-amber-3/30 dark:bg-n-amber-3/10 border border-n-amber-12/20 text-sm text-n-amber-12"
            >
              <span class="i-lucide-alert-triangle size-4 mt-0.5 shrink-0" />
              <span>{{ errorMessage }}</span>
            </div>

            <div class="relative">
              <div
                ref="mapContainerRef"
                data-testid="location-map"
                class="w-full h-[300px] rounded-lg border border-n-slate-4 dark:border-n-slate-7 bg-n-slate-2 dark:bg-n-slate-9 overflow-hidden z-0"
              />
              <div
                v-if="geoLoading"
                class="absolute inset-0 flex items-center justify-center rounded-lg bg-n-solid-1/70 dark:bg-[#202c33]/70 backdrop-blur-sm z-[1000]"
              >
                <div class="flex flex-col items-center gap-2">
                  <span
                    class="i-lucide-loader-2 size-6 animate-spin text-n-brand"
                  />
                  <span class="text-sm text-n-slate-12">
                    {{ t('CONVERSATION.LOCATION.LOADING_LOCATION') }}
                  </span>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-[1fr_120px] gap-3">
              <div class="flex flex-col gap-1">
                <label
                  for="location-cep-input"
                  class="text-xs font-medium text-n-slate-11"
                >
                  {{ t('CONVERSATION.LOCATION.CEP_LABEL') }}
                </label>
                <div
                  class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 transition-colors duration-150 cursor-text bg-n-solid-1 dark:bg-[#202c33] border border-[rgba(11,20,26,0.08)] dark:border-[#2a3942]"
                >
                  <input
                    id="location-cep-input"
                    :value="cep"
                    type="text"
                    inputmode="numeric"
                    autocomplete="postal-code"
                    maxlength="9"
                    data-testid="location-cep-input"
                    :placeholder="t('CONVERSATION.LOCATION.CEP_PLACEHOLDER')"
                    class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
                    @input="onCepInput"
                  />
                  <span
                    v-if="cepLoading"
                    class="i-lucide-loader-2 size-4 animate-spin text-n-brand shrink-0"
                    aria-hidden="true"
                  />
                </div>
              </div>
              <div class="flex flex-col gap-1">
                <label
                  for="location-numero-input"
                  class="text-xs font-medium text-n-slate-11"
                >
                  {{ t('CONVERSATION.LOCATION.NUMBER_LABEL') }}
                </label>
                <div
                  class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 transition-colors duration-150 cursor-text bg-n-solid-1 dark:bg-[#202c33] border border-[rgba(11,20,26,0.08)] dark:border-[#2a3942]"
                >
                  <input
                    id="location-numero-input"
                    :value="numero"
                    type="text"
                    inputmode="numeric"
                    autocomplete="off"
                    data-testid="location-numero-input"
                    :placeholder="t('CONVERSATION.LOCATION.NUMBER_PLACEHOLDER')"
                    class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
                    @input="onNumeroInput"
                  />
                </div>
              </div>
            </div>

            <div
              v-if="cepError"
              class="flex items-start gap-2 px-3 py-2 rounded-lg bg-n-amber-3/30 dark:bg-n-amber-3/10 border border-n-amber-12/20 text-sm text-n-amber-12"
            >
              <span class="i-lucide-alert-triangle size-4 mt-0.5 shrink-0" />
              <span>{{ cepError }}</span>
            </div>

            <div
              v-if="previewAddress"
              data-testid="location-preview"
              class="flex items-start gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 dark:bg-n-alpha-black2 border border-n-slate-4 dark:border-n-slate-7 text-sm text-n-slate-12"
            >
              <span
                class="i-lucide-map-pin size-4 mt-0.5 text-n-brand shrink-0"
              />
              <span class="flex-1">
                {{
                  t('CONVERSATION.LOCATION.PREVIEW', {
                    address: previewAddress,
                  })
                }}
              </span>
            </div>
          </div>

          <footer
            class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-slate-3 dark:border-n-slate-7 bg-n-alpha-1 dark:bg-n-alpha-black2"
          >
            <button
              type="button"
              class="px-4 py-2 rounded-md text-sm font-medium text-n-slate-12 hover:bg-n-slate-3 dark:hover:bg-n-slate-7 transition-colors"
              @click="close"
            >
              {{ t('CONVERSATION.LOCATION.CANCEL') }}
            </button>
            <button
              type="button"
              data-testid="location-submit"
              class="px-4 py-2 rounded-md text-sm font-medium bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              :disabled="!canSubmit || loading"
              @click="submit"
            >
              {{ t('CONVERSATION.LOCATION.SEND') }}
            </button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
