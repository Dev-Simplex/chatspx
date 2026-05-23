<script setup>
import { ref, computed, watch, nextTick, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Cropper from 'cropperjs';
import 'cropperjs/dist/cropper.css';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  file: { type: Object, default: null },
  initialMode: {
    type: String,
    default: 'crop',
    validator: v => ['crop', 'draw', 'text'].includes(v),
  },
});

const emit = defineEmits(['apply', 'cancel']);

const { t } = useI18n();

const SWATCHES = [
  '#EF4444',
  '#F97316',
  '#EAB308',
  '#00A884',
  '#3B82F6',
  '#000000',
  '#FFFFFF',
];
const STROKE_WIDTHS = [4, 8, 16];
const ASPECT_RATIOS = [
  { key: 'free', value: NaN },
  { key: '1:1', value: 1 },
  { key: '4:3', value: 4 / 3 },
  { key: '16:9', value: 16 / 9 },
];

const currentMode = ref(props.initialMode);
const cropperImg = ref(null);
const drawCanvas = ref(null);
const drawWrapper = ref(null);
const textWrapper = ref(null);
const textInputRef = ref(null);

let cropper = null;
let cropperFlipX = 1;
let cropperFlipY = 1;
const activeAspect = ref('free');

// Draw state
const activeColor = ref('#EF4444');
const activeWidth = ref(8);
const isEraser = ref(false);
const drawPaths = ref([]);
let currentPath = null;
let drawCtx = null;
let drawing = false;
const drawImageEl = ref(null);
const drawNaturalSize = ref({ width: 0, height: 0 });

// Text state
const textItems = ref([]);
const textColor = ref('#FFFFFF');
const textSize = ref(32);
const editingTextIndex = ref(null);
const editingTextValue = ref('');
const editingTextPos = ref({ x: 0, y: 0 });
const textImageEl = ref(null);
const textNaturalSize = ref({ width: 0, height: 0 });
const textDisplaySize = ref({ width: 0, height: 0 });
let draggingTextIndex = null;
let dragOffset = { x: 0, y: 0 };

const isCropMode = computed(() => currentMode.value === 'crop');
const isDrawMode = computed(() => currentMode.value === 'draw');
const isTextMode = computed(() => currentMode.value === 'text');

const tabs = computed(() => [
  { key: 'crop', icon: 'i-lucide-crop', label: t('IMAGE_EDITOR.CROP') },
  { key: 'draw', icon: 'i-lucide-pencil', label: t('IMAGE_EDITOR.DRAW') },
  { key: 'text', icon: 'i-lucide-type', label: t('IMAGE_EDITOR.TEXT') },
]);

const destroyCropper = () => {
  if (cropper) {
    cropper.destroy();
    cropper = null;
  }
  cropperFlipX = 1;
  cropperFlipY = 1;
};

const initCropper = async () => {
  destroyCropper();
  await nextTick();
  if (!cropperImg.value) return;
  cropper = new Cropper(cropperImg.value, {
    viewMode: 1,
    dragMode: 'move',
    autoCropArea: 0.9,
    restore: false,
    guides: true,
    center: true,
    highlight: false,
    cropBoxMovable: true,
    cropBoxResizable: true,
    toggleDragModeOnDblclick: false,
  });
};

const setAspect = key => {
  if (!cropper) return;
  activeAspect.value = key;
  const found = ASPECT_RATIOS.find(a => a.key === key);
  cropper.setAspectRatio(found ? found.value : NaN);
};

const rotateLeft = () => cropper?.rotate(-90);
const rotateRight = () => cropper?.rotate(90);
const flipHorizontal = () => {
  if (!cropper) return;
  cropperFlipX = -cropperFlipX;
  cropper.scaleX(cropperFlipX);
};
const flipVertical = () => {
  if (!cropper) return;
  cropperFlipY = -cropperFlipY;
  cropper.scaleY(cropperFlipY);
};
const resetCrop = () => {
  if (!cropper) return;
  cropperFlipX = 1;
  cropperFlipY = 1;
  activeAspect.value = 'free';
  cropper.reset();
};

// ---------- Draw helpers ----------
const redrawPaths = () => {
  if (!drawCtx || !drawCanvas.value) return;
  drawCtx.clearRect(0, 0, drawCanvas.value.width, drawCanvas.value.height);
  drawPaths.value.forEach(path => {
    drawCtx.save();
    drawCtx.lineCap = 'round';
    drawCtx.lineJoin = 'round';
    drawCtx.strokeStyle = path.color;
    drawCtx.lineWidth = path.width;
    drawCtx.globalCompositeOperation = path.isEraser
      ? 'destination-out'
      : 'source-over';
    drawCtx.beginPath();
    path.points.forEach((pt, idx) => {
      if (idx === 0) drawCtx.moveTo(pt.x, pt.y);
      else drawCtx.lineTo(pt.x, pt.y);
    });
    drawCtx.stroke();
    drawCtx.restore();
  });
};

const setupDrawCanvas = async () => {
  await nextTick();
  if (!drawCanvas.value || !drawImageEl.value) return;
  const img = drawImageEl.value;
  if (!img.complete) {
    await new Promise(resolve => {
      img.onload = resolve;
      img.onerror = resolve;
    });
  }
  drawNaturalSize.value = {
    width: img.naturalWidth || img.width,
    height: img.naturalHeight || img.height,
  };
  drawCanvas.value.width = drawNaturalSize.value.width;
  drawCanvas.value.height = drawNaturalSize.value.height;
  drawCtx = drawCanvas.value.getContext('2d');
  redrawPaths();
};

const getCanvasPoint = e => {
  const rect = drawCanvas.value.getBoundingClientRect();
  const scaleX = drawCanvas.value.width / rect.width;
  const scaleY = drawCanvas.value.height / rect.height;
  return {
    x: (e.clientX - rect.left) * scaleX,
    y: (e.clientY - rect.top) * scaleY,
  };
};

const onDrawPointerDown = e => {
  if (!drawCtx) return;
  drawing = true;
  drawCanvas.value.setPointerCapture(e.pointerId);
  currentPath = {
    points: [getCanvasPoint(e)],
    color: activeColor.value,
    width: activeWidth.value,
    isEraser: isEraser.value,
  };
  drawPaths.value.push(currentPath);
  redrawPaths();
};

const onDrawPointerMove = e => {
  if (!drawing || !currentPath) return;
  currentPath.points.push(getCanvasPoint(e));
  redrawPaths();
};

const onDrawPointerUp = e => {
  if (!drawing) return;
  drawing = false;
  try {
    drawCanvas.value.releasePointerCapture(e.pointerId);
  } catch (err) {
    // ignore
  }
  currentPath = null;
};

const undoDraw = () => {
  drawPaths.value.pop();
  redrawPaths();
};

const clearDraw = () => {
  drawPaths.value = [];
  redrawPaths();
};

// ---------- Text helpers ----------
const updateTextDisplaySize = () => {
  if (!textImageEl.value) return;
  const rect = textImageEl.value.getBoundingClientRect();
  textDisplaySize.value = { width: rect.width, height: rect.height };
};

const setupTextStage = async () => {
  await nextTick();
  if (!textImageEl.value) return;
  const img = textImageEl.value;
  if (!img.complete) {
    await new Promise(resolve => {
      img.onload = resolve;
      img.onerror = resolve;
    });
  }
  textNaturalSize.value = {
    width: img.naturalWidth || img.width,
    height: img.naturalHeight || img.height,
  };
  updateTextDisplaySize();
};

const getTextStagePoint = e => {
  const rect = textImageEl.value.getBoundingClientRect();
  const scaleX = textNaturalSize.value.width / rect.width;
  const scaleY = textNaturalSize.value.height / rect.height;
  return {
    x: (e.clientX - rect.left) * scaleX,
    y: (e.clientY - rect.top) * scaleY,
  };
};

const onTextStageClick = e => {
  if (e.target.closest('[data-text-item]')) return;
  if (editingTextIndex.value !== null) return;
  const pt = getTextStagePoint(e);
  editingTextIndex.value = -1;
  editingTextValue.value = '';
  editingTextPos.value = pt;
  nextTick(() => textInputRef.value?.focus());
};

const commitText = () => {
  const value = editingTextValue.value.trim();
  if (value) {
    if (editingTextIndex.value === -1) {
      textItems.value.push({
        text: value,
        x: editingTextPos.value.x,
        y: editingTextPos.value.y,
        color: textColor.value,
        size: textSize.value,
        fontFamily: 'sans-serif',
      });
    } else if (editingTextIndex.value >= 0) {
      textItems.value[editingTextIndex.value].text = value;
    }
  }
  editingTextIndex.value = null;
  editingTextValue.value = '';
};

const onTextInputKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    commitText();
  }
};

const onTextItemPointerDown = (e, idx) => {
  e.stopPropagation();
  const pt = getTextStagePoint(e);
  const item = textItems.value[idx];
  draggingTextIndex = idx;
  dragOffset = { x: pt.x - item.x, y: pt.y - item.y };
  e.currentTarget.setPointerCapture(e.pointerId);
};

const onTextItemPointerMove = e => {
  if (draggingTextIndex === null) return;
  const pt = getTextStagePoint(e);
  const item = textItems.value[draggingTextIndex];
  item.x = pt.x - dragOffset.x;
  item.y = pt.y - dragOffset.y;
};

const onTextItemPointerUp = e => {
  if (draggingTextIndex === null) return;
  try {
    e.currentTarget.releasePointerCapture(e.pointerId);
  } catch (err) {
    // ignore
  }
  draggingTextIndex = null;
};

const onTextItemDblClick = idx => {
  const item = textItems.value[idx];
  editingTextIndex.value = idx;
  editingTextValue.value = item.text;
  editingTextPos.value = { x: item.x, y: item.y };
  nextTick(() => textInputRef.value?.focus());
};

// ---------- Apply ----------
const loadImage = src =>
  new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });

const apply = async () => {
  const baseSrc = props.file?.resource || props.file?.thumb;
  if (!baseSrc) {
    emit('cancel');
    return;
  }

  let baseCanvas;
  if (isCropMode.value && cropper) {
    baseCanvas = cropper.getCroppedCanvas();
  } else {
    const img = await loadImage(baseSrc);
    baseCanvas = document.createElement('canvas');
    baseCanvas.width = img.naturalWidth || img.width;
    baseCanvas.height = img.naturalHeight || img.height;
    baseCanvas.getContext('2d').drawImage(img, 0, 0);
  }

  const finalCanvas = document.createElement('canvas');
  finalCanvas.width = baseCanvas.width;
  finalCanvas.height = baseCanvas.height;
  const ctx = finalCanvas.getContext('2d');
  ctx.drawImage(baseCanvas, 0, 0);

  if (drawPaths.value.length && drawCanvas.value) {
    ctx.drawImage(
      drawCanvas.value,
      0,
      0,
      finalCanvas.width,
      finalCanvas.height
    );
  }

  if (textItems.value.length) {
    const naturalW = textNaturalSize.value.width || finalCanvas.width;
    const naturalH = textNaturalSize.value.height || finalCanvas.height;
    const scaleX = finalCanvas.width / naturalW;
    const scaleY = finalCanvas.height / naturalH;
    textItems.value.forEach(item => {
      ctx.save();
      ctx.fillStyle = item.color;
      ctx.textBaseline = 'top';
      ctx.font = `${item.size * Math.max(scaleX, scaleY)}px ${item.fontFamily}`;
      ctx.fillText(item.text, item.x * scaleX, item.y * scaleY);
      ctx.restore();
    });
  }

  finalCanvas.toBlob(
    blob => {
      if (blob) emit('apply', blob);
      else emit('cancel');
    },
    'image/jpeg',
    0.92
  );
};

const cancel = () => emit('cancel');

const onKeydown = e => {
  if (e.key === 'Escape') cancel();
};

// ---------- Lifecycle / watchers ----------
const resetAllState = () => {
  destroyCropper();
  drawPaths.value = [];
  textItems.value = [];
  editingTextIndex.value = null;
  editingTextValue.value = '';
  isEraser.value = false;
  activeAspect.value = 'free';
};

watch(
  () => props.show,
  async newVal => {
    if (newVal) {
      currentMode.value = props.initialMode;
      window.addEventListener('keydown', onKeydown);
      await nextTick();
      if (isCropMode.value) initCropper();
      else if (isDrawMode.value) setupDrawCanvas();
      else if (isTextMode.value) setupTextStage();
    } else {
      window.removeEventListener('keydown', onKeydown);
      resetAllState();
    }
  }
);

watch(currentMode, async (newMode, oldMode) => {
  if (!props.show) return;
  if (oldMode === 'crop') destroyCropper();
  await nextTick();
  if (newMode === 'crop') initCropper();
  else if (newMode === 'draw') setupDrawCanvas();
  else if (newMode === 'text') setupTextStage();
});

watch(
  () => props.initialMode,
  newMode => {
    if (props.show) currentMode.value = newMode;
  }
);

onBeforeUnmount(() => {
  destroyCropper();
  window.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-150 ease-out"
      enter-from-class="opacity-0 scale-95"
      enter-to-class="opacity-100 scale-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-95"
    >
      <div
        v-if="show"
        class="fixed inset-0 z-[9200] flex flex-col bg-wa-pane-light dark:bg-wa-pane-dark"
        role="dialog"
        aria-modal="true"
      >
        <!-- Header -->
        <div
          class="flex h-[60px] items-center justify-between border-b border-n-weak px-4"
        >
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('IMAGE_EDITOR.TITLE') }}
          </h2>
          <div class="flex items-center gap-1">
            <button
              v-for="tab in tabs"
              :key="tab.key"
              type="button"
              class="flex h-9 items-center gap-1.5 rounded-lg px-3 text-sm font-medium transition-colors"
              :class="
                currentMode === tab.key
                  ? 'bg-wa-teal text-white'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
              @click="currentMode = tab.key"
            >
              <Icon :icon="tab.icon" class="size-4" />
              <span>{{ tab.label }}</span>
            </button>
          </div>
          <button
            type="button"
            class="flex size-9 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="cancel"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <!-- Canvas central -->
        <div
          class="flex flex-1 items-center justify-center overflow-hidden bg-wa-pane-light p-8 dark:bg-wa-pane-dark"
        >
          <!-- CROP -->
          <div
            v-show="isCropMode"
            class="flex h-full w-full items-center justify-center"
          >
            <img
              v-if="file"
              ref="cropperImg"
              :src="file.thumb || file.resource"
              class="block max-w-full max-h-full"
              alt=""
            />
          </div>

          <!-- DRAW -->
          <div
            v-show="isDrawMode"
            ref="drawWrapper"
            class="relative flex max-h-full max-w-full items-center justify-center"
          >
            <img
              v-if="file"
              ref="drawImageEl"
              :src="file.thumb || file.resource"
              class="block max-h-[calc(100vh-200px)] max-w-full select-none"
              alt=""
              draggable="false"
            />
            <canvas
              ref="drawCanvas"
              class="absolute inset-0 h-full w-full touch-none"
              :class="isEraser ? 'cursor-cell' : 'cursor-crosshair'"
              @pointerdown="onDrawPointerDown"
              @pointermove="onDrawPointerMove"
              @pointerup="onDrawPointerUp"
              @pointercancel="onDrawPointerUp"
            />
          </div>

          <!-- TEXT -->
          <div
            v-show="isTextMode"
            ref="textWrapper"
            class="relative flex max-h-full max-w-full items-center justify-center"
          >
            <img
              v-if="file"
              ref="textImageEl"
              :src="file.thumb || file.resource"
              class="block max-h-[calc(100vh-200px)] max-w-full cursor-text select-none"
              alt=""
              draggable="false"
              @click="onTextStageClick"
              @load="updateTextDisplaySize"
            />
            <div
              v-for="(item, idx) in textItems"
              :key="idx"
              data-text-item
              class="absolute cursor-move select-none whitespace-pre font-sans leading-none"
              :style="{
                left: `${(item.x / (textNaturalSize.width || 1)) * 100}%`,
                top: `${(item.y / (textNaturalSize.height || 1)) * 100}%`,
                color: item.color,
                fontSize: `${
                  item.size *
                  (textDisplaySize.width / (textNaturalSize.width || 1))
                }px`,
              }"
              @pointerdown="onTextItemPointerDown($event, idx)"
              @pointermove="onTextItemPointerMove"
              @pointerup="onTextItemPointerUp"
              @pointercancel="onTextItemPointerUp"
              @dblclick="onTextItemDblClick(idx)"
            >
              {{ item.text }}
            </div>
            <input
              v-if="editingTextIndex !== null"
              ref="textInputRef"
              v-model="editingTextValue"
              type="text"
              class="absolute rounded border border-wa-teal bg-black/40 px-2 py-1 text-white outline-none"
              :style="{
                left: `${
                  (editingTextPos.x / (textNaturalSize.width || 1)) * 100
                }%`,
                top: `${
                  (editingTextPos.y / (textNaturalSize.height || 1)) * 100
                }%`,
                color: textColor,
                fontSize: `${
                  textSize *
                  (textDisplaySize.width / (textNaturalSize.width || 1))
                }px`,
              }"
              @keydown="onTextInputKeydown"
              @blur="commitText"
            />
          </div>
        </div>

        <!-- Toolbar contextual -->
        <div class="flex h-16 items-center gap-2 border-t border-n-weak px-4">
          <!-- CROP toolbar -->
          <template v-if="isCropMode">
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.ROTATE_LEFT')"
              :aria-label="t('IMAGE_EDITOR.ROTATE_LEFT')"
              @click="rotateLeft"
            >
              <Icon icon="i-lucide-rotate-ccw" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.ROTATE_RIGHT')"
              :aria-label="t('IMAGE_EDITOR.ROTATE_RIGHT')"
              @click="rotateRight"
            >
              <Icon icon="i-lucide-rotate-cw" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.FLIP_H')"
              :aria-label="t('IMAGE_EDITOR.FLIP_H')"
              @click="flipHorizontal"
            >
              <Icon icon="i-lucide-flip-horizontal" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.FLIP_V')"
              :aria-label="t('IMAGE_EDITOR.FLIP_V')"
              @click="flipVertical"
            >
              <Icon icon="i-lucide-flip-vertical" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.RESET')"
              :aria-label="t('IMAGE_EDITOR.RESET')"
              @click="resetCrop"
            >
              <Icon icon="i-lucide-refresh-ccw" class="size-5" />
            </button>
            <div class="mx-2 h-6 w-px bg-n-weak" />
            <button
              v-for="ratio in ASPECT_RATIOS"
              :key="ratio.key"
              type="button"
              class="flex h-10 items-center justify-center rounded-lg px-3 text-sm font-medium transition-colors"
              :class="
                activeAspect === ratio.key
                  ? 'bg-wa-teal text-white'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
              @click="setAspect(ratio.key)"
            >
              {{ ratio.key }}
            </button>
          </template>

          <!-- DRAW toolbar -->
          <template v-if="isDrawMode">
            <div class="flex items-center gap-1.5">
              <button
                v-for="color in SWATCHES"
                :key="color"
                type="button"
                class="size-8 rounded-full border border-n-weak transition-all"
                :class="
                  activeColor === color && !isEraser
                    ? 'ring-2 ring-wa-teal ring-offset-2 ring-offset-wa-pane-light dark:ring-offset-wa-pane-dark'
                    : ''
                "
                :style="{ backgroundColor: color }"
                :aria-label="color"
                @click="
                  activeColor = color;
                  isEraser = false;
                "
              />
            </div>
            <div class="mx-2 h-6 w-px bg-n-weak" />
            <div class="flex items-center gap-1.5">
              <button
                v-for="w in STROKE_WIDTHS"
                :key="w"
                type="button"
                class="flex size-9 items-center justify-center rounded-full border-2 transition-colors"
                :class="
                  activeWidth === w
                    ? 'border-wa-teal'
                    : 'border-n-weak hover:border-n-slate-9'
                "
                :aria-label="`${w}px`"
                @click="activeWidth = w"
              >
                <span
                  class="rounded-full bg-n-slate-12"
                  :style="{ width: `${w}px`, height: `${w}px` }"
                />
              </button>
            </div>
            <div class="mx-2 h-6 w-px bg-n-weak" />
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg transition-colors"
              :class="
                isEraser
                  ? 'bg-wa-teal text-white'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
              "
              :title="t('IMAGE_EDITOR.ERASER')"
              :aria-label="t('IMAGE_EDITOR.ERASER')"
              @click="isEraser = !isEraser"
            >
              <Icon icon="i-lucide-eraser" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.UNDO')"
              :aria-label="t('IMAGE_EDITOR.UNDO')"
              :disabled="!drawPaths.length"
              @click="undoDraw"
            >
              <Icon icon="i-lucide-undo" class="size-5" />
            </button>
            <button
              type="button"
              class="flex size-10 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              :title="t('IMAGE_EDITOR.CLEAR')"
              :aria-label="t('IMAGE_EDITOR.CLEAR')"
              :disabled="!drawPaths.length"
              @click="clearDraw"
            >
              <Icon icon="i-lucide-trash-2" class="size-5" />
            </button>
          </template>

          <!-- TEXT toolbar -->
          <template v-if="isTextMode">
            <div class="flex items-center gap-1.5">
              <button
                v-for="color in SWATCHES"
                :key="color"
                type="button"
                class="size-8 rounded-full border border-n-weak transition-all"
                :class="
                  textColor === color
                    ? 'ring-2 ring-wa-teal ring-offset-2 ring-offset-wa-pane-light dark:ring-offset-wa-pane-dark'
                    : ''
                "
                :style="{ backgroundColor: color }"
                :aria-label="color"
                @click="textColor = color"
              />
            </div>
            <div class="mx-2 h-6 w-px bg-n-weak" />
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-11">{{ `${textSize}px` }}</span>
              <input
                v-model.number="textSize"
                type="range"
                min="16"
                max="72"
                step="1"
                class="h-1.5 w-40 cursor-pointer appearance-none rounded-full bg-n-alpha-2 accent-wa-teal"
              />
            </div>
          </template>
        </div>

        <!-- Footer -->
        <div
          class="flex h-14 items-center justify-end gap-2 border-t border-n-weak px-4"
        >
          <button
            type="button"
            class="flex h-10 items-center justify-center rounded-lg px-4 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
            @click="cancel"
          >
            {{ t('IMAGE_EDITOR.CANCEL') }}
          </button>
          <button
            type="button"
            class="flex h-10 items-center justify-center rounded-lg bg-wa-teal px-4 text-sm font-medium text-white transition-colors hover:bg-wa-teal-dark"
            @click="apply"
          >
            {{ t('IMAGE_EDITOR.APPLY') }}
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
