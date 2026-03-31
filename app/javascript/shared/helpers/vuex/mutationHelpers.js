export const set = (state, data) => {
  state.records = data;
};

export const create = (state, data) => {
  state.records.push(data);
};

export const setSingleRecord = (state, data) => {
  const recordIndex = state.records.findIndex(record => record.id === data.id);
  if (recordIndex > -1) {
    state.records.splice(recordIndex, 1, data);
  } else {
    create(state, data);
  }
};

export const update = (state, data) => {
  const index = state.records.findIndex(record => record.id === data.id);
  if (index > -1) {
    state.records.splice(index, 1, data);
  }
};

/* when you don't want to overwrite the whole object */
export const updateAttributes = (state, data) => {
  const index = state.records.findIndex(record => record.id === data.id);
  if (index > -1) {
    state.records.splice(index, 1, { ...state.records[index], ...data });
  }
};

export const updatePresence = (state, data) => {
  state.records = state.records.map(element => ({
    ...element,
    availability_status: data[element.id] || 'offline',
  }));
};

export const updateSingleRecordPresence = (
  records,
  { id, availabilityStatus }
) => {
  const index = records.findIndex(record => record.id === Number(id));
  if (index > -1) {
    records.splice(index, 1, {
      ...records[index],
      availability_status: availabilityStatus,
    });
  }
};

export const destroy = (state, id) => {
  state.records = state.records.filter(record => record.id !== id);
};
