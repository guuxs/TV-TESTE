#!/bin/bash

# --- Configurações ---
# URL para download do pacote TeamViewer .deb
# SEMPRE verifique a URL mais recente no site oficial do TeamViewer para garantir que está baixando a versão correta.
TEAMVIEWER_DEB_URL="https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"

# Nome do arquivo que será salvo após o download
TEAMVIEWER_DEB_FILENAME="teamviewer_amd64.deb"

# Diretório temporário para download e instalação
TEMP_DIR="/tmp/teamviewer_installer"

# Seu Token de Atribuição do TeamViewer
# Substitua "SEU_TOKEN_DE_ATRIBUICAO_AQUI" pelo seu token real do TeamViewer Management Console.
TEAMVIEWER_ASSIGNMENT_TOKEN="SEU_TOKEN_DE_ATRIBUICAO_AQUI" # <<<<< PREENCHA AQUI SEU TOKEN REAL
DEVICE_ALIAS=$(hostname) # Pode ser ajustado para um nome fixo se preferir
TEAMVIEWER_GROUP="SeuGrupoPadrao" # <<<<< PREENCHA AQUI O NOME DO GRUPO NO TEAMVIEWER


# --- ADVERTÊNCIA CRÍTICA E FUNDAMENTAL ---
# ESTE SCRIPT NÃO RESOLVERÁ O ERRO "Remote script execution requires user consent".
# O erro ocorre ANTES que este script sequer comece a rodar.
# A causa do problema está em uma política de segurança do Intune/MDE que exige consentimento para
# a instalação de software de terceiros em seu ambiente Linux, e que não é configurável via a interface
# do Intune que você acessa.
# NENHUM comando dentro do script (wget, dpkg, sudo, etc.) pode contornar essa exigência PRÉ-EXECUÇÃO.
# A única solução provável é através do suporte da Microsoft.
# --- FIM DA ADVERTÊNCIA CRÍTICA ---


echo "--- Iniciando a instalação automatizada do TeamViewer no Ubuntu (wget + dpkg) ---"

# 1. Criar e navegar para o diretório temporário
echo "Criando diretório temporário: $TEMP_DIR"
mkdir -p "$TEMP_DIR" || { echo "Erro: Não foi possível criar o diretório temporário $TEMP_DIR. Verifique as permissões."; exit 1; }
cd "$TEMP_DIR" || { echo "Erro: Não foi possível mudar para o diretório $TEMP_DIR. Saindo."; exit 1; }

# 2. Baixar o pacote TeamViewer .deb
echo "Baixando o pacote TeamViewer de: $TEAMVIEWER_DEB_URL"
wget -q --show-progress "$TEAMVIEWER_DEB_URL" -O "$TEAMVIEWER_DEB_FILENAME"
if [ $? -ne 0 ]; then
    echo "Erro: Falha ao baixar o pacote TeamViewer. Verifique a URL e a conexão com a internet."
    cd ~; rm -rf "$TEMP_DIR"; exit 1
fi
echo "Download concluído."

# 3. Instalar o TeamViewer usando dpkg e resolver dependências
echo "Instalando o TeamViewer via dpkg e resolvendo dependências..."
sudo dpkg -i "./$TEAMVIEWER_DEB_FILENAME"

if [ $? -ne 0 ]; then
    echo "Aviso: Instalação dpkg falhou. Tentando corrigir dependências com apt --fix-broken install..."
    sudo apt update -y # Sempre bom fazer update antes de fix-broken
    sudo apt --fix-broken install -y
    if [ $? -ne 0 ]; then
        echo "Erro: Falha ao corrigir dependências. Tentando instalar novamente o pacote .deb..."
        sudo dpkg -i "./$TEAMVIEWER_DEB_FILENAME"
        if [ $? -ne 0 ]; then
            echo "Erro fatal: Instalação final do TeamViewer falhou após correção de dependências."
            cd ~; rm -rf "$TEMP_DIR"; exit 1
        fi
    fi
fi

# 4. Iniciar/Verificar o serviço TeamViewer
echo "Verificando e iniciando o serviço TeamViewer..."
sudo systemctl daemon-reload
sudo systemctl enable teamviewerd
sudo systemctl start teamviewerd
sleep 5
sudo systemctl status teamviewerd | grep "Active: active (running)" || echo "Aviso: Serviço TeamViewer não parece estar ativo."

# 5. Configurar política de acesso para visualização remota (Full Access)
echo "Configurando política de acesso para visualização remota (FullAccess)..."
sudo teamviewer setup config default Policy.IncomingConnectionPolicy "FullAccess"

# 6. Atribuir o TeamViewer à sua conta (usando o token)
if [ -n "$TEAMVIEWER_ASSIGNMENT_TOKEN" ] && [ "$TEAMVIEWER_ASSIGNMENT_TOKEN" != "SEU_TOKEN_DE_ATRIBUICAO_AQUI" ]; then
    echo "Atribuindo o TeamViewer à sua conta usando o token..."
    sudo teamviewer setup assign --alias "$DEVICE_ALIAS" --group "$TEAMVIEWER_GROUP" --grant-easy-access --token "$TEAMVIEWER_ASSIGNMENT_TOKEN"
    if [ $? -ne 0 ]; then
        echo "Aviso: Falha ao atribuir o TeamViewer. Verifique o token e os nomes."
    else
        echo "TeamViewer atribuído com sucesso."
    fi
else
    echo "Nenhum token de atribuição válido fornecido. Pulando a atribuição automática."
fi

# 7. Limpar arquivos temporários
echo "Limpando arquivos temporários..."
cd ~; rm -rf "$TEMP_DIR" || echo "Aviso: Falha ao remover o diretório temporário."

echo "--- Instalação do TeamViewer concluída! ---"
echo "O TeamViewer foi instalado, o serviço iniciado, visualização remota liberada e o dispositivo atribuído à sua conta."
echo "Certifique-se de que não há firewalls locais bloqueando o TeamViewer (portas 5938, 80, 443)."

exit 0