import json, ssl, subprocess, threading, urllib.request

try:
    import websocket
except ImportError:
    import os
    os.system("pip3 install websocket-client -q")
    import websocket


def env(k: str) -> str:
    with open("/var/www/daizima-backend/.env", encoding="utf-8") as f:
        for line in f:
            if line.startswith(k + "="):
                return line.split("=", 1)[1].strip()
    return ""


app_key = env("REVERB_APP_KEY")

php_token = r"""$u=\App\Models\User::whereIn('role',['admin','super_admin','editor'])->first(); echo $u->createToken('ws-probe')->plainTextToken;"""
tok = subprocess.check_output(
    ["docker-compose", "exec", "-T", "app", "php", "artisan", "tinker", "--execute", php_token],
    cwd="/var/www/daizima-backend",
    text=True,
).strip().splitlines()[-1]
print("TOKEN", tok[:15] + "...")

state = {"cart": False, "sub": False, "events": 0}


def on_msg(ws, message):
    state["events"] += 1
    print("MSG", message[:280])
    try:
        data = json.loads(message)
    except Exception:
        return
    if data.get("event") == "pusher:connection_established":
        socket_id = json.loads(data["data"])["socket_id"]
        req = urllib.request.Request(
            "https://admin.daizima.com/api/broadcasting/auth",
            data=f"socket_id={socket_id}&channel_name=private-admin.carts".encode(),
            headers={
                "Authorization": f"Bearer {tok}",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, context=ssl._create_unverified_context(), timeout=10) as r:
            auth = json.loads(r.read().decode())
        print("AUTH_OK")
        ws.send(
            json.dumps(
                {
                    "event": "pusher:subscribe",
                    "data": {"channel": "private-admin.carts", "auth": auth["auth"]},
                }
            )
        )
    elif data.get("event") in (
        "pusher_internal:subscription_succeeded",
        "pusher:subscription_succeeded",
    ):
        print("SUBSCRIBED")
        state["sub"] = True
        php_broadcast = r"""$c=\App\Models\Cart::latest('id')->first(); broadcast(new \App\Events\CartUpdated($c,'item_added',['product_id'=>1,'product_name'=>'PROBE','product_variation_id'=>777002,'quantity'=>1,'price'=>1,'stock_quantity'=>1,'is_available'=>true])); echo 'sent';"""
        subprocess.check_call(
            ["docker-compose", "exec", "-T", "app", "php", "artisan", "tinker", "--execute", php_broadcast],
            cwd="/var/www/daizima-backend",
        )
    elif "cart.updated" in message:
        print("GOT_CART_EVENT")
        state["cart"] = True
        ws.close()


def on_err(ws, err):
    print("ERR", err)


wsapp = websocket.WebSocketApp(
    f"wss://admin.daizima.com/ws/app/{app_key}?protocol=7&client=js&version=8.4.0&flash=false",
    on_message=on_msg,
    on_error=on_err,
)
th = threading.Thread(
    target=lambda: wsapp.run_forever(sslopt={"cert_reqs": ssl.CERT_NONE}),
    daemon=True,
)
th.start()
th.join(timeout=25)
print("RESULT", state)

php_cleanup = r"""echo \Laravel\Sanctum\PersonalAccessToken::where('name','ws-probe')->delete();"""
subprocess.call(
    ["docker-compose", "exec", "-T", "app", "php", "artisan", "tinker", "--execute", php_cleanup],
    cwd="/var/www/daizima-backend",
)
