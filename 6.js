import React from 'react'
import { Form, DatePicker, Row, Col } from 'antd'

const SyncDateWithOnChange = () => {
  const [form] = Form.useForm()

  // 当“发生时间”变化时，直接同步到“记录时间”
  const handleCaseDateChange = (date) => {
    form.setFieldsValue({ recordDate: date })
  }

  return (
    <Form
      form={form}
      layout="inline"
      initialValues={{ caseDate: null, recordDate: null }}
    >
      <Row gutter={16}>
        <Col span={6}>
          <Form.Item label="发生时间" name="caseDate">
            <DatePicker
              showTime
              style={{ width: '100%' }}
              onChange={handleCaseDateChange}
            />
          </Form.Item>
        </Col>

        <Col span={6}>
          <Form.Item label="记录时间" name="recordDate">
            <DatePicker
              showTime
              style={{ width: '100%' }}
            />
          </Form.Item>
        </Col>
      </Row>
    </Form>
  )
}

export default SyncDateWithOnChange
