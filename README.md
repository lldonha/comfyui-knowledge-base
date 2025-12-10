# 🧠 ComfyUI Knowledge Base

Sistema ético de coleta, análise e organização de conteúdo sobre ComfyUI usando IA.

## 🎯 O que faz?

- **Descobre** criadores de conteúdo ComfyUI (YouTube, GitHub)
- **Analisa** vídeos com Gemini 1.5 Flash (extrai técnicas, nodes, timestamps)
- **Extrai** frames importantes automaticamente
- **Organiza** tudo em banco PostgreSQL pesquisável
- **Respeita** rate limits e direitos dos criadores

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│  ENTRADA                                                    │
│  ├─ POST /analyze    → Analisa vídeo individual            │
│  ├─ POST /discover   → Adiciona novo criador               │
│  └─ Cron 6h          → Verifica atualizações               │
├─────────────────────────────────────────────────────────────┤
│  PROCESSAMENTO (n8n + PostgreSQL)                          │
│  ├─ Job Queue com prioridades                              │
│  ├─ Rate Limiter atômico (Gemini: 15/min, 1500/dia)       │
│  └─ Retry automático com backoff                           │
├─────────────────────────────────────────────────────────────┤
│  ANÁLISE (Gemini 1.5 Flash)                                │
│  ├─ Upload direto do vídeo                                 │
│  ├─ Extração de timestamps importantes                     │
│  ├─ Identificação de nodes e técnicas                      │
│  └─ Resumo em PT-BR e EN                                   │
├─────────────────────────────────────────────────────────────┤
│  SAÍDA                                                      │
│  ├─ GET /search?q=   → Busca por texto/técnica            │
│  ├─ GET /videos      → Lista vídeos                        │
│  ├─ GET /stats       → Estatísticas do sistema             │
│  └─ Frames extraídos em /data/frames/                      │
└─────────────────────────────────────────────────────────────┘
```

## 📦 Componentes

| Arquivo | Descrição |
|---------|-----------|
| `schema.sql` | Schema PostgreSQL completo (15 tabelas, views, funções) |
| `video_analyzer.py` | Script Python para análise com Gemini |
| `setup.sh` | Script de instalação |
| `n8n_workflow_*.json` | Workflows n8n (5 arquivos) |

## 🚀 Instalação

### Pré-requisitos

- PostgreSQL 14+
- n8n (Docker ou instalado)
- Python 3.10+
- yt-dlp, FFmpeg
- API Keys: Gemini, YouTube Data (opcional)

### Passo a Passo

```bash
# 1. Clonar repositório
git clone https://github.com/lldonha/comfyui-knowledge-base.git
cd comfyui-knowledge-base

# 2. Configurar ambiente
cp .env.example .env
# Edite .env com suas credenciais

# 3. Criar banco de dados
psql -h localhost -U seu_usuario -d seu_banco -f schema.sql

# 4. Instalar dependências Python
pip install psycopg2-binary google-generativeai yt-dlp

# 5. Importar workflows no n8n
# Acesse n8n → Import → Cole cada JSON
```

## 🔧 Configuração (.env)

```env
# PostgreSQL
DB_HOST=localhost
DB_PORT=5432
DB_NAME=cosmic
DB_USER=lucas
DB_PASSWORD=sua_senha

# APIs
GEMINI_API_KEY=sua_chave_gemini
YOUTUBE_API_KEY=sua_chave_youtube  # opcional

# Diretórios
DATA_DIR=/data/comfyui_kb
```

## 📡 API Endpoints

### Adicionar Criador
```bash
curl -X POST http://localhost:5678/webhook/comfyui-kb/discover \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.youtube.com/@pixaroma"}'
```

### Analisar Vídeo
```bash
curl -X POST http://localhost:5678/webhook/comfyui-kb/analyze \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.youtube.com/watch?v=VIDEO_ID"}'
```

### Buscar
```bash
# Por texto
curl "http://localhost:5678/webhook/comfyui-kb/search?q=controlnet"

# Por técnica
curl "http://localhost:5678/webhook/comfyui-kb/search?technique=img2img"

# Por dificuldade
curl "http://localhost:5678/webhook/comfyui-kb/search?difficulty=beginner"
```

### Estatísticas
```bash
curl "http://localhost:5678/webhook/comfyui-kb/stats"
```

## 💰 Custos Estimados

| Recurso | Limite Gratuito | Uso por 66 vídeos |
|---------|-----------------|-------------------|
| Gemini Flash | 1500 req/dia | ~70 requisições |
| YouTube Data | 10000 quota/dia | ~10 quota |
| **Total** | **$0** | **Dentro do free tier** |

## 🛡️ Princípios Éticos

- ✅ Usa apenas APIs públicas oficiais
- ✅ Respeita rate limits com margem de 30-50%
- ✅ Armazena apenas metadados e análises, não conteúdo
- ✅ Mantém atribuição aos criadores
- ✅ Permite opt-out (deletar fonte)
- ❌ Não redistribui conteúdo protegido

## 📊 Consultas SQL Úteis

```sql
-- Estatísticas por criador
SELECT * FROM v_creator_stats;

-- Vídeos sobre ControlNet
SELECT v.title, va.summary_pt 
FROM videos v
JOIN video_analysis va ON v.id = va.video_id
WHERE 'controlnet' = ANY(va.techniques_shown);

-- Top nodes mais mencionados
SELECT unnest(custom_nodes_mentioned) as node, COUNT(*) as mentions
FROM video_analysis
GROUP BY node ORDER BY mentions DESC;

-- Jobs pendentes
SELECT job_type, status, COUNT(*) 
FROM job_queue GROUP BY job_type, status;
```

## 🔄 Fluxo de Desenvolvimento

```bash
# Ver mudanças
git status

# Salvar e enviar
git add .
git commit -m "Descrição da mudança"
git push
```

## 📝 Roadmap

- [ ] Suporte a GitHub (workflows .json)
- [ ] Suporte a Civitai
- [ ] Busca semântica com embeddings
- [ ] Dashboard web de visualização
- [ ] Export para Obsidian/Notion

## 📄 Licença

Uso pessoal. Respeite os direitos dos criadores de conteúdo.

---

Desenvolvido com 🤖 Claude + ☕ Café
