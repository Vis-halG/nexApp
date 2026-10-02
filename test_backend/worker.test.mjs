import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../push_worker/worker.js';

test('capabilities reflect configured services without exposing secrets', async () => {
  const response = await worker.fetch(new Request('https://app.test/capabilities'),{AUDD_API_TOKEN:'secret'});
  assert.deepEqual(await response.json(),{recognition:true,humming:false});
});
test('share pages escape hostile metadata and expose only valid application links', async () => {
  const data = Buffer.from(JSON.stringify({id:'track',title:'<script>alert(1)</script>'})).toString('base64url');
  const response = await worker.fetch(new Request(`https://app.test/share/track?data=${data}`),{});
  const html = await response.text(); assert.equal(response.status,200); assert.ok(!html.includes('<script>')); assert.ok(html.includes('&lt;script&gt;')); assert.ok(html.includes('nexmusic://share/track'));
  assert.equal(response.headers.get('Referrer-Policy'),'no-referrer');
});
test('malformed, private and oversized share links fail', async () => {
  for (const id of ['local:1','private:1']) { const data=Buffer.from(JSON.stringify({id,title:'Private'})).toString('base64url'); assert.equal((await worker.fetch(new Request(`https://app.test/share/track?data=${data}`),{})).status,400); }
  assert.equal((await worker.fetch(new Request('https://app.test/share/track?data=bad'),{})).status,400);
  assert.equal((await worker.fetch(new Request('https://app.test/share/room/short'),{})).status,400);
});
test('recognition rejects unauthenticated requests before sending audio to a provider', async () => {
  const response = await worker.fetch(new Request('https://app.test/recognize',{method:'POST',body:'RIFFaudio'}),{SERVICE_ACCOUNT:'{"project_id":"demo-test"}',AUDD_API_TOKEN:'secret'});
  assert.equal(response.status,401);
});
test('Android association includes only valid public certificate fingerprints', async () => {
  const response = await worker.fetch(new Request('https://app.test/.well-known/assetlinks.json'),{APP_SHA256:Array(32).fill('AB').join(':')});
  assert.equal((await response.json())[0].target.package_name,'com.thenex.nex_music');
  assert.deepEqual(await (await worker.fetch(new Request('https://app.test/.well-known/assetlinks.json'),{APP_SHA256:'bad'})).json(),[]);
});
