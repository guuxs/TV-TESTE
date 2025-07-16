#!/bin/bash
set -e  # Sair imediatamente se um comando falhar
set -x  # Imprimir comandos e argumentos à medida que são executados (útil para depuração)

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
TEAMVIEWER_GROUP="ManagedByIntune" # <<<<< PREENCHA AQUI O NOME DO GRUPO NO TEAMVIEWER (ou use um padrão)


# --- ADVERTÊNCIA CRÍTICA E FUNDAMENTAL (MANTIDA) ---
# ESTE SCRIPT NÃO RESOLVERÁ O ERRO "Remote script execution requires user consent".
# O erro ocorre ANTES que este script sequer comece a rodar.
# A causa do problema está em uma política de segurança do Intune/MDE que exige consentimento para
# a instalação de software de terceiros em seu ambiente Linux, e que não é configurável via a interface
# do Intune que você acessa.
# NENHUM comando dentro do script (wget, dpkg, sudo, etc.) pode contornar essa exigência PRÉ-EXECUÇÃO.
# A única solução provável é através do suporte da Microsoft.
# --- FIM DA ADVERTÊNCIA CRÍTICA ---


echo "--- Iniciando a instalação automatizada do TeamViewer no Ubuntu (wget + dpkg) ---"
echo "Data e Hora de início: $(date)"
echo "Host: $(hostname)"
echo "Usuário de execução (quem executa o script): $(whoami)"
echo "ID do Usuário de execução: $(id -u)"

# 1. Criar e navegar para o diretório temporário
echo "INFO: Criando diretório temporário: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
if [ $? -ne 0 ]; then
    echo "ERRO: Não foi possível criar o diretório temporário $TEMP_DIR. Verifique as permissões."
    exit 1
fi
cd "$TEMP_DIR"
if [ $? -ne 0 ]; then
    echo "ERRO: Não foi possível mudar para o diretório $TEMP_DIR. Saindo."
    exit 1
fi
echo "INFO: Diretório temporário criado e navegado com sucesso."

# 2. Baixar o pacote TeamViewer .deb
echo "INFO: Baixando o pacote TeamViewer de: $TEAMVIEWER_DEB_URL"
# wget -q --show-progress "$TEAMVIEWER_DEB_URL" -O "$TEAMVIEWER_DEB_FILENAME" # --show-progress pode não funcionar bem em ambientes não interativos
wget -q "$TEAMVIEWER_DEB_URL" -O "$TEAMVIEWER_DEB_FILENAME"
if [ $? -ne 0 ]; then
    echo "ERRO: Falha ao baixar o pacote TeamViewer. Verifique a URL e a conexão com a internet."
    rm -rf "$TEMP_DIR" # Limpar antes de sair em caso de erro
    exit 1
fi
echo "INFO: Download do pacote TeamViewer concluído."
ls -lh "$TEAMVIEWER_DEB_FILENAME" # Verifica se o arquivo foi baixado

# 3. Instalar o TeamViewer usando dpkg e resolver dependências
echo "INFO: Instalação inicial do TeamViewer via dpkg..."
sudo /usr/bin/dpkg -i "./$TEAMVIEWER_DEB_FILENAME"

if [ $? -ne 0 ]; then
    echo "AVISO: Instalação dpkg falhou. Tentando corrigir dependências com apt --fix-broken install..."
    echo "INFO: Atualizando lista de pacotes apt..."
    sudo /usr/bin/apt update -y
    if [ $? -ne 0 ]; then
        echo "ERRO: Falha ao atualizar a lista de pacotes. Verifique a conexão ou os repositórios."
        rm -rf "$TEMP_DIR"; exit 1
    fi
    
    echo "INFO: Tentando corrigir dependências quebradas..."
    sudo /usr/bin/apt --fix-broken install -y
    if [ $? -ne 0 ]; then
        echo "ERRO: Falha ao corrigir dependências. Tentando instalar novamente o pacote .deb..."
        sudo /usr/bin/dpkg -i "./$TEAMVIEWER_DEB_FILENAME"
        if [ $? -ne 0 ]; then
            echo "ERRO FATAL: Instalação final do TeamViewer falhou após correção de dependências."
            rm -rf "$TEMP_DIR"; exit 1
        fi
    fi
fi
echo "INFO: Instalação do TeamViewer e resolução de dependências concluída."


# 4. Iniciar/Verificar o serviço TeamViewer
echo "INFO: Verificando e iniciando o serviço TeamViewer..."
sudo /usr/bin/systemctl daemon-reload
sudo /usr/bin/systemctl enable teamviewerd
sudo /usr/bin/systemctl start teamviewerd
sleep 3 # Dar um tempo menor para o serviço iniciar
SERVICE_STATUS=$(sudo /usr/bin/systemctl is-active teamviewerd)
if [ "$SERVICE_STATUS" == "active" ]; then
    echo "INFO: Serviço TeamViewer está ativo (running)."
else
    echo "AVISO: Serviço TeamViewer não parece estar ativo. Status: $SERVICE_STATUS"
    # Captura a saída completa do status para depuração
    sudo /usr/bin/systemctl status teamviewerd
fi


# 5. Configurar política de acesso para visualização remota (Full Access)
echo "INFO: Configurando política de acesso para visualização remota (FullAccess)..."
sudo /usr/bin/teamviewer setup config default Policy.IncomingConnectionPolicy "FullAccess"
if [ $? -ne 0 ]; then
    echo "AVISO: Falha ao configurar a política de acesso do TeamViewer."
fi


# 6. Atribuir o TeamViewer à sua conta (usando o token)
if [ -n "$TEAMVIEWER_ASSIGNMENT_TOKEN" ] && [ "$TEAMVIEWER_ASSIGNMENT_TOKEN" != "SEU_TOKEN_DE_ATRIBUICAO_AQUI" ]; then
    echo "INFO: Atribuindo o TeamViewer à sua conta usando o token..."
    sudo /usr/bin/teamviewer setup assign --alias "$DEVICE_ALIAS" --group "$TEAMVIEWER_GROUP" --grant-easy-access --token "$TEAMVIEWER_ASSIGNMENT_TOKEN"
    if [ $? -ne 0 ]; then
        echo "AVISO: Falha ao atribuir o TeamViewer. Verifique o token e os nomes de grupo/alias."
    else
        echo "INFO: TeamViewer atribuído com sucesso à sua conta."
    fi
else
    echo "AVISO: Nenhum token de atribuição válido fornecido ou o token padrão 'SEU_TOKEN_DE_ATRIBUICAO_AQUI' não foi substituído. Pulando a atribuição automática."
fi

# 7. Limpar arquivos temporários
echo "INFO: Limpando arquivos temporários em $TEMP_DIR..."
rm -rf "$TEMP_DIR"
if [ $? -ne 0 ]; then
    echo "AVISO: Falha ao remover o diretório temporário $TEMP_DIR. Pode ser necessário limpar manualmente."
fi

echo "--- Instalação do TeamViewer concluída! ---"
echo "Data e Hora de término: $(date)"
echo "O TeamViewer foi instalado, o serviço iniciado, visualização remota liberada e o dispositivo atribuído à sua conta (se o token foi fornecido)."
echo "Lembre-se de verificar firewalls locais/de rede (portas 5938, 80, 443) e o status no console do TeamViewer."

exit 0
