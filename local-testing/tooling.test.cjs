const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { dirname, join } = require('node:path');
const { createServer } = require('node:http');

// Exercise the actual CLI consumers of the two temporary security overrides.
// No Firebase clients, credentials, or external endpoints are used.
const cliRequire = createRequire(require.resolve('firebase-tools/package.json'));

test('CLI gaxios can send a multipart request with the overridden UUID library', async () => {
  let received;
  const server = createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = { type: req.headers['content-type'], body: Buffer.concat(chunks).toString() };
    res.end('ok');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const { request } = cliRequire('gaxios');
    const response = await request({
      url: `http://127.0.0.1:${server.address().port}/`, method: 'POST',
      multipart: [{ headers: { 'Content-Type': 'text/plain' }, content: 'local-fixture' }],
      noProxy: ['127.0.0.1'], timeout: 2000,
    });
    assert.equal(response.data, 'ok');
    assert.match(received.type, /^multipart\/related; boundary=[0-9a-f-]{36}$/);
    const boundary = received.type.split('boundary=')[1];
    assert.equal(received.body, `--${boundary}\r\nContent-Type: text/plain\r\n\r\nlocal-fixture\r\n--${boundary}--`);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});

test('CLI Pub/Sub trace propagation remains compatible with the overridden core library', () => {
  const pubsubEntry = cliRequire.resolve('@google-cloud/pubsub');
  const pubsubRequire = createRequire(pubsubEntry);
  const telemetry = require(join(dirname(pubsubEntry), 'telemetry-tracing.js'));
  const api = pubsubRequire('@opentelemetry/api');
  const { W3CTraceContextPropagator } = pubsubRequire('@opentelemetry/core');
  const context = { traceId: '1234567890abcdef1234567890abcdef', spanId: '1234567890abcdef', traceFlags: 1 };
  const message = {};
  const wasEnabled = telemetry.isEnabled();
  telemetry.setGloballyEnabled(true);
  try {
    telemetry.injectSpan({ spanContext: () => context }, message);
    assert.equal(message.attributes.googclient_traceparent, `00-${context.traceId}-${context.spanId}-01`);
    const extracted = new W3CTraceContextPropagator().extract(api.ROOT_CONTEXT, message, telemetry.pubsubGetter);
    assert.deepEqual(api.trace.getSpanContext(extracted), { ...context, isRemote: true });
  } finally {
    telemetry.setGloballyEnabled(wasEnabled);
  }
});
