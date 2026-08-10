// detail.js
const initialEntryRef = useRef([]);

useEffect(() => {
  getDetail().then(obj => {
    initialEntryRef.current = cloneDeep(obj.entry || []);
    setEntry(obj.entry || []);
  });
}, []);

const handleRemove = id => {
  setEntry(prev => prev.filter(item => item.id !== id));
};

const handleSubmit = async () => {
  const current = form.getFieldsValue(true)?.entry || [];

  // 删掉的
  const removedEntries = initialEntryRef.current
    .filter(orig => !current.some(cur => cur.id === orig.id))
    .map(orig => ({ id: orig.id, oprInfo: { operate: 'REMOVE' } }));

  // 新增的
  const newEntries = current.filter(item => !item.id);

  // 最终要提交的变更
  const payloadEntries = type === 'add'
    ? newEntries
    : [...removedEntries, ...newEntries];

  const postData = {
    // …其他字段
    ...(payloadEntries.length > 0 && { entry: payloadEntries }),
  };

  await api.save(postData);
};
