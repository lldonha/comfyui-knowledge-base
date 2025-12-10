# 📡 ComfyUI KB - Exemplos de API

## Base URL
```
http://localhost:5678/webhook/comfyui-kb
```

---

## 🔍 Buscar Vídeos

```bash
# Busca por texto
curl "http://localhost:5678/webhook/comfyui-kb/search?q=controlnet"

# Busca por técnica
curl "http://localhost:5678/webhook/comfyui-kb/search?technique=img2img"

# Busca por dificuldade
curl "http://localhost:5678/webhook/comfyui-kb/search?difficulty=beginner"

# Combinado
curl "http://localhost:5678/webhook/comfyui-kb/search?q=flux&difficulty=intermediate&limit=10"
```

---

## ➕ Adicionar Criador

```bash
curl -X POST http://localhost:5678/webhook/comfyui-kb/discover \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.youtube.com/@pixaroma",
    "autoFollow": true
  }'
```

---

## 🎬 Analisar Vídeo

```bash
curl -X POST http://localhost:5678/webhook/comfyui-kb/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://www.youtube.com/watch?v=VIDEO_ID"
  }'
```

---

## 📋 Listar

```bash
# Vídeos
curl "http://localhost:5678/webhook/comfyui-kb/videos"
curl "http://localhost:5678/webhook/comfyui-kb/videos?status=completed"

# Criadores
curl "http://localhost:5678/webhook/comfyui-kb/creators"

# Técnicas
curl "http://localhost:5678/webhook/comfyui-kb/techniques"

# Detalhes de vídeo
curl "http://localhost:5678/webhook/comfyui-kb/video/123"
```

---

## 📊 Estatísticas

```bash
curl "http://localhost:5678/webhook/comfyui-kb/stats"
```

Resposta:
```json
{
  "total_creators": 5,
  "total_videos": 150,
  "analyzed_videos": 120,
  "pending_jobs": 12,
  "top_techniques": ["txt2img", "controlnet"]
}
```

---

## 🐍 Exemplo Python

```python
import requests

BASE = "http://localhost:5678/webhook/comfyui-kb"

# Buscar tutoriais de ControlNet
r = requests.get(f"{BASE}/search", params={"q": "controlnet", "limit": 5})
for video in r.json()["results"]:
    print(f"📺 {video['title']}")
    print(f"   Técnicas: {', '.join(video['techniques_shown'])}")
```

---

## 📦 Exemplo JavaScript

```javascript
const BASE = 'http://localhost:5678/webhook/comfyui-kb';

// Adicionar canal
fetch(`${BASE}/discover`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ url: 'https://www.youtube.com/@pixaroma' })
})
.then(r => r.json())
.then(console.log);
```
