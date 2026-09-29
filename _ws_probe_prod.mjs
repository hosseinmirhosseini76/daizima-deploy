import WebSocket from 'ws'
import { execSync } from 'child_process'
import https from 'https'
import fs from 'fs'

function env(k) {
  const txt = fs.readFileSync('/var/www/daizima-backend/.env', 'utf8')
  const line = txt.split('\n').find((l) => l.startsWith(k + '='))
  return line ? line.slice(k.length + 1).trim() : ''
}

const appKey = env('REVERB_APP_KEY')
const tok = execSync(
  [
    'docker-compose',
    'exec',
    '-T',
    'app',
    'php',
    'artisan',
    'tinker',
    '--execute',
    `$u=\\App\\Models\\User::whereIn('role',['admin','super_admin','editor'])->first(); echo $u->createToken('ws-probe')->plainTextToken;`,
  ].join(' '),
  { cwd: '/var/www/daizima-backend', encoding: 'utf8', shell: '/bin/bash' },
)
  .trim()
  .split('\n')
  .pop()

console.log('TOKEN', tok.slice(0, 15) + '...')

const state = { sub: false, cart: false }
const ws = new WebSocket(
  `wss://admin.daizima.com/ws/app/${appKey}?protocol=7&client=js&version=8.4.0&flash=false`,
  { rejectUnauthorized: false },
)

function postAuth(socketId) {
  return new Promise((resolve, reject) => {
    const body = `socket_id=${encodeURIComponent(socketId)}&channel_name=${encodeURIComponent('private-admin.carts')}`
    const req = https.request(
      {
        hostname: 'admin.daizima.com',
        path: '/api/broadcasting/auth',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${tok}`,
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let d = ''
        res.on('data', (c) => (d += c))
        res.on('end', () => {
          try {
            resolve(JSON.parse(d))
          } catch (e) {
            reject(new Error(d))
          }
        })
      },
    )
    req.on('error', reject)
    req.write(body)
    req.end()
  })
}

ws.on('message', async (buf) => {
  const message = buf.toString()
  console.log('MSG', message.slice(0, 280))
  let data
  try {
    data = JSON.parse(message)
  } catch {
    return
  }
  if (data.event === 'pusher:connection_established') {
    const socket_id = JSON.parse(data.data).socket_id
    const auth = await postAuth(socket_id)
    console.log('AUTH_OK', Object.keys(auth))
    ws.send(
      JSON.stringify({
        event: 'pusher:subscribe',
        data: { channel: 'private-admin.carts', auth: auth.auth },
      }),
    )
  } else if (String(data.event || '').includes('subscription_succeeded')) {
    console.log('SUBSCRIBED')
    state.sub = true
    execSync(
      [
        'docker-compose',
        'exec',
        '-T',
        'app',
        'php',
        'artisan',
        'tinker',
        '--execute',
        `$c=\\App\\Models\\Cart::latest('id')->first(); broadcast(new \\App\\Events\\CartUpdated($c,'item_added',['product_id'=>1,'product_name'=>'PROBE','product_variation_id'=>777002,'quantity'=>1,'price'=>1,'stock_quantity'=>1,'is_available'=>true])); echo 'sent';`,
      ].join(' '),
      { cwd: '/var/www/daizima-backend', encoding: 'utf8', shell: '/bin/bash' },
    )
  } else if (message.includes('cart.updated')) {
    console.log('GOT_CART_EVENT')
    state.cart = true
    ws.close()
  }
})

ws.on('error', (e) => console.log('ERR', e.message))
ws.on('close', () => {
  console.log('CLOSE', state)
  try {
    execSync(
      `docker-compose exec -T app php artisan tinker --execute="echo \\Laravel\\Sanctum\\PersonalAccessToken::where('name','ws-probe')->delete();"`,
      { cwd: '/var/www/daizima-backend', encoding: 'utf8', shell: '/bin/bash' },
    )
  } catch {}
  process.exit(state.cart ? 0 : 2)
})

setTimeout(() => {
  console.log('TIMEOUT', state)
  try {
    ws.close()
  } catch {}
}, 20000)
