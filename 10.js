import React, { useEffect, useState } from 'react';
import { Cascader, message } from 'antd';

const transformData = (list) => {
  return list.map(p => ({
    value: p.code,
    label: p.name,
    children: p.children?.map(c => ({
      value: c.code,
      label: c.name,
      children: c.children?.map(d => ({
        value: d.code,
        label: d.name
      })) || []
    })) || []
  }));
};

const JsonRegionCascader = ({ onChange }) => {
  const [options, setOptions] = useState([]);

  useEffect(() => {
    fetch('/pcas-code.json')
      .then(res => res.json())
      .then(data => setOptions(transformData(data)))
      .catch(() => message.error('加载地区数据失败'));
  }, []);

  const handleChange = (value, selectedOptions) => {
    if (onChange) {
      const [province, city, district] = selectedOptions.map(opt => opt.label);
      onChange({ province, city, district });
    }
  };

  return (
    <Cascader
      options={options}
      onChange={handleChange}
      placeholder="请选择省市区"
      style={{ width: 360 }}
      changeOnSelect
    />
  );
};

export default JsonRegionCascader;
