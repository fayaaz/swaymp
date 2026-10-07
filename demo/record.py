# Capture the three.js canvas to a .webm via the page's own MediaRecorder.
# Run with:  browser-harness < record.py
# Env: KB_URL (page URL), KB_OUT (output .webm path), KB_DUR (record seconds).
# Helpers (new_tab, wait_for_load, js, cdp) are pre-imported by browser-harness.
import time
import base64
import os

URL = os.environ.get("KB_URL", "http://127.0.0.1:7171/")
OUT = os.environ.get("KB_OUT", "kb_final.webm")
DUR = float(os.environ.get("KB_DUR", "37"))

new_tab(URL)
wait_for_load()
for _ in range(60):
    time.sleep(1)
    s = js("(()=>{const b=window.__built===true;"
           "const f=window.__frames?window.__frames.filter("
           "x=>x.complete&&x.naturalWidth).length:0;"
           "return b+' frames:'+f;})()")
    if s.startswith("True") and int(s.split(":")[1]) > 270:
        break
print("ready:", s)

print(js("""
(async () => {
  const vid = document.getElementById('vid');
  vid.currentTime = 0;
  await vid.play();
  const stream = renderer.domElement.captureStream(30);
  window.__rrec = new MediaRecorder(stream,
    {mimeType:'video/webm;codecs=vp9', videoBitsPerSecond: 2500000});
  window.__rchunks = [];
  window.__rrec.ondataavailable = e => { if (e.data.size) window.__rchunks.push(e.data); };
  window.__rdone = new Promise(res => { window.__rrec.onstop = res; });
  window.__rrec.start(500);
  return 'REC STARTED';
})()
"""))
time.sleep(DUR)
print(js("(async () => { window.__rrec.stop(); await window.__rdone; vid.pause();"
         "window.__rblob = new Blob(window.__rchunks,{type:'video/webm'});"
         "return 'bytes:'+window.__rblob.size+' chunks:'+window.__rchunks.length; })()"))

n = int(js("window.__rblob.size"))
STEP = 1500000
parts = []
for i in range(0, n, STEP):
    j = min(i + STEP, n)
    b64 = js(f"(async()=>{{const s=window.__rblob.slice({i},{j});"
             "const b=await s.arrayBuffer();let u=new Uint8Array(b);let s2='';"
             "for(let k=0;k<u.length;k+=8192){s2+=String.fromCharCode.apply(null,"
             "u.subarray(k,k+8192));}return btoa(s2);})()")
    parts.append(b64)
with open(OUT, "wb") as f:
    f.write(base64.b64decode("".join(parts)))
print("saved", OUT, n)
