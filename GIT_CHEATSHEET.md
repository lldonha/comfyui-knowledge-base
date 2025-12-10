# 🎯 Git Cheatsheet - Guia Rápido

## Fluxo Visual

```
┌─────────────────────────────────────────────────────────────────┐
│                     SEU COMPUTADOR                              │
│                                                                 │
│   📁 Arquivos      ──►   📦 Staging    ──►   💾 Commit         │
│   (modificados)         (preparados)        (salvo local)       │
│                                                                 │
│                           git add .         git commit -m "..."│
└─────────────────────────────────────────────────────────────────┘
                                                    │
                                                    │ git push
                                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ☁️  GITHUB                               │
│                                                                 │
│   Repositório remoto (backup + histórico na nuvem)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                                    │
                                                    │ git pull
                                                    ▼
                              (baixa atualizações se houver)
```

---

## 📋 Comandos do Dia a Dia

### Ver situação atual
```bash
git status
```
Mostra: arquivos modificados, adicionados, deletados

### Salvar alterações
```bash
git add .                    # Prepara TODOS os arquivos
git commit -m "Descrição"    # Salva snapshot local
git push                     # Envia para GitHub
```

### Atalho: Tudo em uma linha
```bash
git add . && git commit -m "Minha alteração" && git push
```

---

## 📝 Boas Mensagens de Commit

```bash
# ✅ BOM - Diz O QUE foi feito
git commit -m "Adicionado suporte a Civitai"
git commit -m "Corrigido bug no rate limiter"
git commit -m "Atualizado prompt do Gemini para melhor extração"

# ❌ RUIM - Vago demais
git commit -m "update"
git commit -m "fix"
git commit -m "mudanças"
```

### Emojis opcionais (fica bonito no GitHub)
```bash
git commit -m "🚀 Versão inicial"
git commit -m "🐛 Corrigido bug X"
git commit -m "✨ Nova funcionalidade Y"
git commit -m "📝 Atualizada documentação"
git commit -m "🔧 Ajuste de configuração"
```

---

## 🔍 Ver Histórico

```bash
# Lista de commits (resumido)
git log --oneline

# Exemplo de saída:
# a1b2c3d ✨ Adicionado workflow de backup
# e4f5g6h 🐛 Corrigido rate limit
# i7j8k9l 🚀 Versão inicial
```

```bash
# Ver o que mudou em um arquivo
git diff nome_do_arquivo.py

# Ver mudanças do último commit
git show
```

---

## ⏪ Desfazer Coisas

```bash
# Descartar mudanças em um arquivo (CUIDADO: perde alterações!)
git checkout -- nome_do_arquivo.py

# Voltar um commit (mantém arquivos, desfaz commit)
git reset --soft HEAD~1

# Voltar arquivo para versão do último commit
git restore nome_do_arquivo.py
```

---

## 🌿 Branches (Avançado - para depois)

Branches permitem trabalhar em features separadas:

```bash
# Criar e mudar para nova branch
git checkout -b minha-feature

# Voltar para main
git checkout main

# Juntar branch na main
git merge minha-feature
```

---

## ❓ Problemas Comuns

### "Não consigo dar push"
```bash
# Primeiro baixe atualizações
git pull

# Depois tente novamente
git push
```

### "Commitei arquivo errado"
```bash
# Remove do último commit (antes do push)
git reset --soft HEAD~1
```

### "Quero ignorar um arquivo"
Adicione o nome no `.gitignore`:
```
arquivo_secreto.env
pasta_grande/
*.log
```

---

## 🔐 Autenticação GitHub

O GitHub não aceita mais senha. Use **Personal Access Token**:

1. Vá em: https://github.com/settings/tokens
2. "Generate new token (classic)"
3. Marque: `repo` (acesso total a repositórios)
4. Copie o token gerado
5. Use como senha quando git pedir

Para salvar e não pedir toda vez:
```bash
git config --global credential.helper store
# Na próxima vez que pedir, vai salvar
```

---

## 📱 Alternativa: GitHub Desktop

Se preferir interface gráfica:
- Download: https://desktop.github.com/
- Mais visual, menos comandos
- Bom para quem está começando
