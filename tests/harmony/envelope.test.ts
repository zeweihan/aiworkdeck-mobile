import { test } from 'node:test'
import assert from 'node:assert/strict'
import { checkEnvelope, ApiError, Unauthorized } from '../../harmony/entry/src/main/ets/model/Envelope.ets'

test('code 4010 抛 Unauthorized', () => {
  assert.throws(() => checkEnvelope({ code: 4010, message: 'not logged in' }), Unauthorized)
})

test('非零 code 抛 ApiError，带 code 与 message', () => {
  assert.throws(() => checkEnvelope({ code: 1002, message: 'bad code' }), (e: unknown) => {
    assert.ok(e instanceof ApiError)
    assert.equal((e as ApiError).code, 1002)
    assert.equal((e as ApiError).message, 'bad code')
    return true
  })
})

test('非零 code 无 message 时用 code 兜底', () => {
  assert.throws(() => checkEnvelope({ code: 500 }), (e: unknown) => {
    assert.equal((e as ApiError).message, 'code 500')
    return true
  })
})

test('code 0 不抛', () => {
  assert.doesNotThrow(() => checkEnvelope({ code: 0, data: { sessionId: 'sess-1' } }))
})

test('无 code 的裸响应不抛', () => {
  assert.doesNotThrow(() => checkEnvelope({ deviceId: 'd1', key: 'k1' }))
})
