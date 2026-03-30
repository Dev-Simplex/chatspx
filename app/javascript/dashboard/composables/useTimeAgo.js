import { ref, onUnmounted } from 'vue';
import { dynamicTime } from 'shared/helpers/timeHelper';

const MINUTE_IN_MS = 60000;
const HOUR_IN_MS = MINUTE_IN_MS * 60;
const DAY_IN_MS = HOUR_IN_MS * 24;

const subscribers = new Map();
let timerId = null;
let nextId = 0;

function getRefreshInterval(timestamp) {
  const timeDiff = Date.now() - timestamp * 1000;
  if (timeDiff > DAY_IN_MS) return DAY_IN_MS;
  if (timeDiff > HOUR_IN_MS) return HOUR_IN_MS;
  return MINUTE_IN_MS;
}

function tick() {
  let minInterval = DAY_IN_MS;
  subscribers.forEach(entry => {
    entry.lastActivityDisplay.value = dynamicTime(entry.lastActivityTimestamp);
    entry.createdAtDisplay.value = dynamicTime(entry.createdAtTimestamp);
    const interval = getRefreshInterval(entry.lastActivityTimestamp);
    if (interval < minInterval) minInterval = interval;
  });

  if (subscribers.size > 0) {
    timerId = setTimeout(tick, minInterval);
  } else {
    timerId = null;
  }
}

function startTimer() {
  if (timerId !== null) return;
  let minInterval = DAY_IN_MS;
  subscribers.forEach(entry => {
    const interval = getRefreshInterval(entry.lastActivityTimestamp);
    if (interval < minInterval) minInterval = interval;
  });
  timerId = setTimeout(tick, minInterval);
}

function stopTimer() {
  if (timerId !== null) {
    clearTimeout(timerId);
    timerId = null;
  }
}

export function useTimeAgo(lastActivityTimestamp, createdAtTimestamp) {
  const lastActivityDisplay = ref(dynamicTime(lastActivityTimestamp));
  const createdAtDisplay = ref(dynamicTime(createdAtTimestamp));

  const id = nextId;
  nextId += 1;

  const entry = {
    lastActivityTimestamp,
    createdAtTimestamp,
    createdAtDisplay,
    lastActivityDisplay,
  };

  subscribers.set(id, entry);

  if (subscribers.size === 1) {
    startTimer();
  }

  function update(newLastActivity, newCreatedAt) {
    entry.lastActivityTimestamp = newLastActivity;
    entry.createdAtTimestamp = newCreatedAt;
    lastActivityDisplay.value = dynamicTime(newLastActivity);
    createdAtDisplay.value = dynamicTime(newCreatedAt);
  }

  onUnmounted(() => {
    subscribers.delete(id);
    if (subscribers.size === 0) {
      stopTimer();
    }
  });

  return { lastActivityDisplay, createdAtDisplay, update };
}
