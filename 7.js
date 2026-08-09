// 查询操作符枚举
const QueryOperator = {
  LIKE: "l",
  EQ: "=",
  LTE: "<=",
  LT: "<",
  GTE: ">=",
  GT: ">",
  BETWEEN: "V",
  IN: "in",
  NOTIN: "ni",
};

class QueryUtil {
  get(obj, query) {
    return getByQuery(obj, query);
  }

  getByFields(obj, eqFields, rangeFields) {
    return getSearchParams(obj, undefined, eqFields, [], rangeFields);
  }
}

function getByQuery(obj, query) {
  if (query && query.length > 0) {
    // 根据操作符进行分组
    const transfer = new Map();
    let eqFields = [];
    let inFields = [];
    let rangeFields = [];
    let greaterFields = [];
    let lessFields = [];

    query.forEach(item => {
      if (!item || item.q === undefined || item.q === QueryOperator.LIKE) {
        return;
      }

      if (item.t) {
        transfer.set(item.f, item.t);
      }

      switch (item.q) {
        case QueryOperator.EQ:
          eqFields.unshift(item.f);
          break;
        case QueryOperator.IN:
          inFields.unshift(item.f);
          break;
        case QueryOperator.BETWEEN:
          rangeFields.unshift(item.f);
          break;
        case QueryOperator.GTE:
        case QueryOperator.GT:
          greaterFields.unshift(item.f);
          break;
        case QueryOperator.LTE:
        case QueryOperator.LT:
          lessFields.unshift(item.f);
          break;
      }
    });

    return getSearchParams(
      obj,
      transfer,
      eqFields,
      inFields,
      rangeFields,
      greaterFields,
      lessFields
    );
  } else {
    return getSearchParams(obj);
  }
}

function getSearchParams(
  obj,
  transfer,
  eqFields = [],
  inFields = [],
  rangeFields = [],
  greaterFields = [],
  lessFields = []
) {
  if (obj == null) {
    return {};
  }

  const entries = Object.entries(obj);
  const result = {};
  const ranges = new Map();

  entries.forEach(([key, value]) => {
    let trueValue;

    // 应用转换函数
    if (transfer) {
      const fn = getTransferFunc(transfer, key);
      if (fn) {
        if (Array.isArray(value)) {
          trueValue = value.map(v => fn(v));
        } else {
          trueValue = fn(value);
        }
      }
      // Dayjs 对象格式化
      else if (value && value.$isDayjsObject) {
        trueValue = `${value.$y}-${value.$M + 1}-${value.$D}`;
      } else {
        trueValue = value;
      }
    } else {
      trueValue = value;
    }

    // 等于
    if (eqFields.includes(key)) {
      result[`search_EQ_${key}`] = trueValue;
      return;
    }
    // 包含
    if (inFields.includes(key)) {
      result[`search_IN_${key}`] = trueValue;
      return;
    }
    // 大于 / 大于等于
    if (greaterFields.includes(key)) {
      if (key.endsWith("Start")) {
        const realKey = key.slice(0, -5);
        result[`search_GTE_${realKey}`] = trueValue;
      } else {
        result[`search_GT_${key}`] = trueValue;
      }
      return;
    }
    // 小于 / 小于等于
    if (lessFields.includes(key)) {
      if (key.endsWith("End")) {
        const realKey = key.slice(0, -3);
        result[`search_LTE_${realKey}`] = trueValue;
      } else {
        result[`search_LT_${key}`] = trueValue;
      }
      return;
    }
    // 范围
    if (rangeFields.length) {
      for (const field of rangeFields) {
        if (field === key && Array.isArray(trueValue)) {
          ranges.set(field, { key: field, start: trueValue[0], end: trueValue[1] });
          return;
        }
        if (key === field + "Start") {
          const existing = ranges.get(field) || { key: field };
          existing.start = trueValue;
          ranges.set(field, existing);
          return;
        }
        if (key === field + "End") {
          const existing = ranges.get(field) || { key: field };
          existing.end = trueValue;
          ranges.set(field, existing);
          return;
        }
      }
    }
    // 模糊匹配
    if (trueValue !== "" && !(Array.isArray(trueValue) && !trueValue.length)) {
      result[`search_LIKE_${key}`] = trueValue;
    }
  });

  // 处理 ranges
  if (ranges.size) {
    const list = Array.from(ranges.values());

    // 只有 start
    list
      .filter(item => item.start != null && item.end == null)
      .forEach(item => {
        result[`search_GTE_${item.key}`] = item.start;
      });

    // 只有 end
    list
      .filter(item => item.start == null && item.end != null)
      .forEach(item => {
        result[`search_LTE_${item.key}`] = item.end;
      });

    // 同时有 start 和 end
    list
      .filter(item => item.start != null && item.end != null)
      .forEach(item => {
        result[`search_BETWEEN_${item.key}`] = `${item.start},${item.end}`;
      });
  }

  return result;

  // 内部：获取转换函数
  function getTransferFunc(map, name) {
    if (map.has(name)) {
      return map.get(name);
    }
    if (name.endsWith("Start")) {
      const base = name.slice(0, -5);
      if (map.has(base)) return map.get(base);
    }
    if (name.endsWith("End")) {
      const base = name.slice(0, -3);
      if (map.has(base)) return map.get(base);
    }
  }
}

const util = new QueryUtil();

export { QueryOperator };
export default util;
