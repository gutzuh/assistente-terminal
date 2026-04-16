#!/usr/bin/env bash
# Script de instalação do Assistente Terminal

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="assistente"
ALIAS_NAME="ai"

echo "🚀 Instalando Assistente Terminal..."
echo "Diretório do script: $SCRIPT_DIR"

# Verificar se o arquivo assistente existe
if [[ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]]; then
    echo "❌ Arquivo $SCRIPT_NAME não encontrado em $SCRIPT_DIR"
    echo "Certifique-se de que o script de instalação está na mesma pasta que o arquivo 'assistente'."
    exit 1
fi

# Verificar dependências
echo "📦 Verificando dependências..."
for cmd in curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ $cmd não encontrado. Instale com: sudo apt install $cmd (ou equivalente)"
        exit 1
    fi
done

# Copiar script para /usr/local/bin
echo "📁 Copiando $SCRIPT_NAME para $INSTALL_DIR/"
sudo cp "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Criar symlink 'ai' que aponta para 'assistente'
echo "🔗 Criando alias '$ALIAS_NAME' -> '$SCRIPT_NAME'"
sudo ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$ALIAS_NAME"

echo "✅ Instalação concluída!"
echo ""
echo "Agora você pode usar:"
echo "  assistente ia \"pergunta\""
echo "  ai \"pergunta\"            (atalho)"
echo "  comando | ai \"descreva o erro\""
