// PDND wrapper para Kanban (P1-07).
// Substitui vue-draggable-plus + lógica manual mouseDownTime/200ms.
//
// Exporta:
//   - makeKanbanCardDraggable(elRef, { itemId, stageId })
//   - makeKanbanColumnDropTarget(elRef, { stageId, scrollableRef })
//   - useKanbanBoardMonitor(boardStore)
//
// Em mobile (<768px) o drag é desabilitado — caminho primário é long-press
// + bottom sheet (P1-10).

import {
  draggable,
  dropTargetForElements,
  monitorForElements,
} from '@atlaskit/pragmatic-drag-and-drop/element/adapter';
import { autoScrollForElements } from '@atlaskit/pragmatic-drag-and-drop-auto-scroll/element';
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine';
import { onMounted, onUnmounted, unref } from 'vue';

const isMobileViewport = () =>
  typeof window !== 'undefined' &&
  window.matchMedia &&
  window.matchMedia('(max-width: 767px)').matches;

export function makeKanbanCardDraggable(elRef, opts = {}) {
  let cleanup;
  onMounted(() => {
    const el = unref(elRef);
    if (!el || isMobileViewport()) return;
    cleanup = draggable({
      element: el,
      getInitialData: () => ({
        kind: 'kanban-card',
        itemId: opts.itemId,
        fromStageId: opts.stageId,
      }),
      onDragStart: () => {
        el.classList.add('is-dragging');
        el.setAttribute('aria-grabbed', 'true');
      },
      onDrop: () => {
        el.classList.remove('is-dragging');
        el.setAttribute('aria-grabbed', 'false');
      },
    });
  });
  onUnmounted(() => cleanup?.());
}

export function makeKanbanColumnDropTarget(elRef, opts = {}) {
  let cleanup;
  onMounted(() => {
    const el = unref(elRef);
    if (!el) return;
    const cleanups = [
      dropTargetForElements({
        element: el,
        getData: () => ({ kind: 'kanban-column', stageId: opts.stageId }),
        canDrop: ({ source }) => source.data.kind === 'kanban-card',
        onDragEnter: () => el.classList.add('is-drop-over'),
        onDragLeave: () => el.classList.remove('is-drop-over'),
        onDrop: () => el.classList.remove('is-drop-over'),
      }),
    ];
    const scroller = unref(opts.scrollableRef);
    if (scroller) {
      cleanups.push(
        autoScrollForElements({
          element: scroller,
        })
      );
    }
    cleanup = combine(...cleanups);
  });
  onUnmounted(() => cleanup?.());
}

export function useKanbanBoardMonitor(boardStore) {
  let cleanup;
  onMounted(() => {
    cleanup = monitorForElements({
      canMonitor: ({ source }) => source.data.kind === 'kanban-card',
      onDrop: ({ source, location }) => {
        const target = location.current.dropTargets[0];
        if (!target || target.data.kind !== 'kanban-column') return;
        const fromStageId = source.data.fromStageId;
        const toStageId = target.data.stageId;
        const { itemId } = source.data;
        if (fromStageId === toStageId) return;
        boardStore.moveItem({ itemId, toStageId }).catch(() => {
          // erro já reverte via rollback no store
        });
      },
    });
  });
  onUnmounted(() => cleanup?.());
}
