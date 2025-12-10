#!/bin/bash
# ComfyUI Knowledge Base - Setup Script
# Execute este script para configurar o ambiente

set -e

echo "=========================================="
echo "  ComfyUI Knowledge Base - Setup"
echo "=========================================="

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Diretório base
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-/data/comfyui_kb}"

echo -e "\n${YELLOW}1. Verificando dependências...${NC}"

# Verificar Python
if command -v python3 &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Python3 encontrado: $(python3 --version)"
else
    echo -e "  ${RED}✗${NC} Python3 não encontrado"
    exit 1
fi

# Verificar yt-dlp
if command -v yt-dlp &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} yt-dlp encontrado: $(yt-dlp --version)"
else
    echo -e "  ${YELLOW}!${NC} yt-dlp não encontrado, instalando..."
    pip install yt-dlp --break-system-packages
fi

# Verificar FFmpeg
if command -v ffmpeg &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} FFmpeg encontrado"
else
    echo -e "  ${RED}✗${NC} FFmpeg não encontrado"
    echo "    Instale com: apt install ffmpeg"
    exit 1
fi

# Verificar psql
if command -v psql &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} PostgreSQL client encontrado"
else
    echo -e "  ${YELLOW}!${NC} psql não encontrado (opcional para setup manual)"
fi

echo -e "\n${YELLOW}2. Instalando dependências Python...${NC}"

pip install --break-system-packages \
    psycopg2-binary \
    google-generativeai \
    requests \
    python-dotenv

echo -e "  ${GREEN}✓${NC} Dependências Python instaladas"

echo -e "\n${YELLOW}3. Criando estrutura de diretórios...${NC}"

mkdir -p "$DATA_DIR"/{frames,videos,workflows,exports}
chmod 755 "$DATA_DIR"

echo -e "  ${GREEN}✓${NC} Diretórios criados em $DATA_DIR"

echo -e "\n${YELLOW}4. Verificando arquivo de configuração...${NC}"

ENV_FILE="$BASE_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" << 'EOF'
# ComfyUI Knowledge Base - Configuração
# Copie este arquivo para .env e preencha as variáveis

# PostgreSQL
DB_HOST=host.docker.internal
DB_PORT=5432
DB_NAME=cosmic
DB_USER=lucas
DB_PASSWORD=

# APIs
GEMINI_API_KEY=your_gemini_api_key_here
YOUTUBE_API_KEY=your_youtube_api_key_here
GITHUB_TOKEN=your_github_token_here

# Diretórios
DATA_DIR=/data/comfyui_kb
EOF
    echo -e "  ${YELLOW}!${NC} Arquivo .env criado. Configure suas API keys!"
else
    echo -e "  ${GREEN}✓${NC} Arquivo .env já existe"
fi

echo -e "\n${YELLOW}5. Verificando conexão com PostgreSQL...${NC}"

# Carregar .env se existir
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

if [ -n "$DB_HOST" ] && command -v psql &> /dev/null; then
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Conexão com PostgreSQL OK"
        
        # Verificar se schema existe
        TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'creators'")
        
        if [ "$TABLE_COUNT" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} Schema já existe"
        else
            echo -e "  ${YELLOW}!${NC} Schema não encontrado. Execute:"
            echo "    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $BASE_DIR/schema.sql"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Não foi possível conectar ao PostgreSQL"
        echo "    Verifique as configurações no .env"
    fi
else
    echo -e "  ${YELLOW}!${NC} Pulando verificação do PostgreSQL"
fi

echo -e "\n${YELLOW}6. Verificando API Keys...${NC}"

if [ -n "$GEMINI_API_KEY" ] && [ "$GEMINI_API_KEY" != "your_gemini_api_key_here" ]; then
    echo -e "  ${GREEN}✓${NC} GEMINI_API_KEY configurada"
else
    echo -e "  ${RED}✗${NC} GEMINI_API_KEY não configurada"
    echo "    Obtenha em: https://aistudio.google.com/app/apikey"
fi

if [ -n "$YOUTUBE_API_KEY" ] && [ "$YOUTUBE_API_KEY" != "your_youtube_api_key_here" ]; then
    echo -e "  ${GREEN}✓${NC} YOUTUBE_API_KEY configurada"
else
    echo -e "  ${YELLOW}!${NC} YOUTUBE_API_KEY não configurada (opcional)"
    echo "    Obtenha em: https://console.cloud.google.com/apis/credentials"
fi

echo -e "\n${YELLOW}7. Criando scripts auxiliares...${NC}"

# Script para executar análise
cat > "$BASE_DIR/analyze.sh" << 'EOF'
#!/bin/bash
# Analisa um vídeo específico
source "$(dirname "$0")/.env" 2>/dev/null
python3 "$(dirname "$0")/video_analyzer.py" "$@"
EOF
chmod +x "$BASE_DIR/analyze.sh"

# Script para processar batch
cat > "$BASE_DIR/batch.sh" << 'EOF'
#!/bin/bash
# Processa batch de vídeos pendentes
source "$(dirname "$0")/.env" 2>/dev/null
python3 "$(dirname "$0")/video_analyzer.py" --batch "$@"
EOF
chmod +x "$BASE_DIR/batch.sh"

echo -e "  ${GREEN}✓${NC} Scripts auxiliares criados"

echo -e "\n${GREEN}=========================================="
echo "  Setup concluído!"
echo "==========================================${NC}"

echo -e "\n${YELLOW}Próximos passos:${NC}"
echo "1. Configure suas API keys no arquivo .env"
echo "2. Execute o schema SQL no PostgreSQL:"
echo "   psql -h \$DB_HOST -p \$DB_PORT -U \$DB_USER -d \$DB_NAME -f schema.sql"
echo "3. Importe os workflows JSON no n8n"
echo "4. Configure as credenciais nos workflows do n8n"
echo ""
echo "Para analisar um vídeo:"
echo "  ./analyze.sh --video-url 'https://www.youtube.com/watch?v=VIDEO_ID'"
echo ""
echo "Para processar batch:"
echo "  ./batch.sh --limit 10"
echo ""
