#!/bin/bash
# ComfyUI Knowledge Base - Git Setup Helper
# Execute este script para configurar o repositório git

set -e

echo "=========================================="
echo "  Git Setup Helper"
echo "=========================================="

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar se git está instalado
if ! command -v git &> /dev/null; then
    echo -e "${RED}Git não está instalado!${NC}"
    echo "Instale com: sudo apt install git"
    exit 1
fi

# Verificar se já é um repositório git
if [ -d ".git" ]; then
    echo -e "${YELLOW}Este diretório já é um repositório git${NC}"
    echo ""
    echo "Comandos úteis:"
    echo "  git status          # Ver mudanças"
    echo "  git add .           # Adicionar mudanças"
    echo "  git commit -m 'msg' # Salvar snapshot"
    echo "  git push            # Enviar para GitHub"
    exit 0
fi

echo ""
echo -e "${YELLOW}Passo 1: Configurando Git...${NC}"

# Verificar se git está configurado
if [ -z "$(git config --global user.name)" ]; then
    read -p "Seu nome (para commits): " git_name
    git config --global user.name "$git_name"
fi

if [ -z "$(git config --global user.email)" ]; then
    read -p "Seu email: " git_email
    git config --global user.email "$git_email"
fi

echo -e "${GREEN}✓${NC} Git configurado como: $(git config --global user.name) <$(git config --global user.email)>"

echo ""
echo -e "${YELLOW}Passo 2: Inicializando repositório...${NC}"

git init
echo -e "${GREEN}✓${NC} Repositório inicializado"

echo ""
echo -e "${YELLOW}Passo 3: Criando primeiro commit...${NC}"

# Garantir que .env não será commitado
if [ -f ".env" ]; then
    echo -e "${YELLOW}!${NC} Arquivo .env encontrado - será ignorado (não vai para o GitHub)"
fi

git add .
git commit -m "🚀 Versão inicial do ComfyUI Knowledge Base

- Schema PostgreSQL com rate limiting
- Workflows n8n (Individual, Discover, Batch, Monitor, Query API)
- Video Analyzer com Gemini 1.5 Flash
- Extração automática de frames
- Documentação completa"

echo -e "${GREEN}✓${NC} Primeiro commit criado"

echo ""
echo "=========================================="
echo -e "${GREEN}  Repositório local configurado!${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}Próximo passo: Conectar ao GitHub${NC}"
echo ""
echo "1. Crie um repositório em: https://github.com/new"
echo "   - Nome sugerido: comfyui-knowledge-base"
echo "   - Marque como 'Private'"
echo "   - NÃO adicione README ou .gitignore"
echo ""
echo "2. Execute o comando (substitua SEU_USUARIO):"
echo ""
echo -e "   ${GREEN}git remote add origin https://github.com/SEU_USUARIO/comfyui-knowledge-base.git${NC}"
echo -e "   ${GREEN}git branch -M main${NC}"
echo -e "   ${GREEN}git push -u origin main${NC}"
echo ""
echo "3. O GitHub vai pedir seu usuário e senha/token"
echo "   - Use um Personal Access Token ao invés de senha"
echo "   - Crie em: https://github.com/settings/tokens"
echo ""
echo "=========================================="
echo ""
echo "Comandos do dia a dia:"
echo ""
echo "  git status              # Ver o que mudou"
echo "  git diff                # Ver detalhes das mudanças"
echo "  git add .               # Adicionar todas as mudanças"
echo "  git add arquivo.py      # Adicionar arquivo específico"
echo "  git commit -m 'mensagem' # Salvar snapshot"
echo "  git push                # Enviar para GitHub"
echo "  git pull                # Baixar atualizações do GitHub"
echo "  git log --oneline       # Ver histórico de commits"
echo ""
