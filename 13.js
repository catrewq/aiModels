import React from 'react';
import { Form, Input, DatePicker, Button, Input as AntdInput } from 'antd';
import dayjs from 'dayjs';

export default function InlineDatePicker() {
  const [form] = Form.useForm();
  const dateTimePattern = /^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}$/;

  return (
    <Form form={form} layout="vertical">
      <Form.Item label="发生时间" style={{ marginBottom: 0 }}>
        <Input.Group compact>
          {/* 1. 主体输入框 */}
          <Form.Item
            name="caseDate"
            noStyle
            rules={[
              { required: true, message: '请输入发生时间' },
              { pattern: dateTimePattern, message: '格式必须为 YYYY-MM-DD HH:mm:ss' },
              () => ({
                validator(_, val) {
                  if (!val || dayjs(val, 'YYYY-MM-DD HH:mm:ss').isValid()) {
                    return Promise.resolve();
                  }
                  return Promise.reject(new Error('请输入有效的日期和时间'));
                }
              })
            ]}
          >
            <AntdInput
              placeholder="YYYY-MM-DD HH:mm:ss"
              style={{ width: '90%' }}
            />
          </Form.Item>

          {/* 2. 嵌入末尾的 DatePicker */}
          <DatePicker
            showTime
            format="YYYY-MM-DD HH:mm:ss"
            style={{ width: '10%' }}
            onChange={(_, dateString) => {
              form.setFieldsValue({ caseDate: dateString });
            }}
            value={
              form.getFieldValue('caseDate')
                ? dayjs(form.getFieldValue('caseDate'), 'YYYY-MM-DD HH:mm:ss')
                : null
            }
          />
        </Input.Group>
      </Form.Item>

      <Form.Item>
        <Button
          type="primary"
          onClick={() => {
            form.validateFields()
              .then(values => console.log('提交数据：', values))
              .catch(err => console.log('校验失败：', err));
          }}
        >
          提交
        </Button>
      </Form.Item>
    </Form>
  );
}
