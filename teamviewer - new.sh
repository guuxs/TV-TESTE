#!/bin/bash
set -e  # Sair imediatamente se um comando falhar
set -x  # Imprimir comandos e argumentos à medida que são executados (útil para depuração)

# --- Configurações ---
TEAMVIEWER_DEB_URL="https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"
TEAMVIEWER_DEB_FILENAME="teamviewer_amd64.deb"
TEMP_DIR="/tmp/teamviewer_installer"

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

# Tentar corrigir o dpkg primeiro se estiver em estado "quebrado"
echo "INFO: Tentando corrigir o estado do dpkg..."
sudo /usr/bin/dpkg --configure -a || echo "AVISO: O comando 'dpkg --configure -a' retornou um erro, mas continuamos."
echo "INFO: Tentativa de correção do dpkg concluída."

# 1. Criar e navegar para o diretório temporário
echo "INFO: Criando diretório temporário: $TEMP_DIR"
# Usamos sudo aqui para garantir que o diretório seja criado com permissões adequadas
sudo mkdir -p "$TEMP_DIR" || { echo "ERRO: Não foi possível criar o diretório temporário $TEMP_DIR. Verifique as permissões."; exit 1; }
sudo chmod 777 "$TEMP_DIR" # Garante que todos possam escrever, mesmo que rode como user não-root
cd "$TEMP_DIR" || { echo "ERRO: Não foi possível mudar para o diretório $TEMP_DIR. Saindo."; exit 1; }
echo "INFO: Diretório temporário criado e navegado com sucesso."

# 2. Baixar o pacote TeamViewer .deb
echo "INFO: Baixando o pacote TeamViewer de: $TEAMVIEWER_DEB_URL"
# NOVO: Adicionar 'sudo' para o wget garantir permissão de escrita no diretório
sudo wget -q "$TEAMVIEWER_DEB_URL" -O "$TEAMVIEWER_DEB_FILENAME" || { echo "ERRO: Falha ao baixar o pacote TeamViewer. Verifique a URL e a conexão com a internet."; rm -rf "$TEMP_DIR"; exit 1; }
echo "INFO: Download do pacote TeamViewer concluído."
ls -lh "$TEAMVIEWER_DEB_FILENAME" # Este ls pode falhar se o sudo wget criar o arquivo com root e o user tnd_admin não tiver lido, mas o wget em si já passou.

# 3. Atualizar lista de pacotes e instalar dependências antes de instalar o .deb
echo "INFO: Atualizando a lista de pacotes e instalando dependências necessárias..."
sudo /usr/bin/apt update -y || { echo "ERRO: Falha ao atualizar a lista de pacotes. Verifique sua conexão com a internet."; rm -rf "$TEMP_DIR"; exit 1; }

echo "INFO: Instalando dependências: libminizip1 libxcb-xinerama0..."
sudo /usr/bin/apt install -y libminizip1 libxcb-xinerama0 || echo "AVISO: Falha ao instalar algumas dependências. Isso pode ser um problema."


# 4. Instalar o TeamViewer usando dpkg e resolver dependências (se ainda houver)
echo "INFO: Instalação final do TeamViewer via dpkg..."
sudo /usr/bin/dpkg -i "./$TEAMVIEWER_DEB_FILENAME"

if [ $? -ne 0 ]; then
    echo "AVISO: Instalação dpkg falhou (ainda). Tentando corrigir dependências com apt --fix-broken install..."
    sudo /usr/bin/apt --fix-broken install -y || { echo "ERRO FATAL: Falha ao corrigir dependências após tentativa de instalação. O TeamViewer não pode ser configurado."; rm -rf "$TEMP_DIR"; exit 1; }
    
    echo "INFO: Dependências corrigidas. Tentando instalar TeamViewer novamente para configurar..."
    sudo /usr/bin/dpkg -i "./$TEAMVIEWER_DEB_FILENAME" || { echo "ERRO FATAL: Instalação do TeamViewer falhou mesmo após correção de dependências."; rm -rf "$TEMP_DIR"; exit 1; }
fi
echo "INFO: Instalação do TeamViewer e resolução de dependências concluída com sucesso."


# 5. Iniciar/Verificar o serviço TeamViewer
echo "INFO: Verificando e iniciando o serviço TeamViewer..."
sudo /usr/bin/systemctl daemon-reload
sudo /usr/bin/systemctl enable teamviewerd

# Reiniciar o daemon para garantir um estado limpo, e esperar por ele.
echo "INFO: Parando e iniciando o daemon do TeamViewer para garantir um estado limpo..."
sudo /usr/bin/systemctl stop teamviewerd || true # Permite que falhe se não estiver rodando
sleep 3 # Pequena pausa antes de iniciar
sudo /usr/bin/systemctl start teamviewerd

# Loop de espera para o daemon TeamViewer estar realmente pronto
MAX_RETRIES=20 # Tentar 20 vezes (total de 100 segundos)
WAIT_TIME=5    # Esperar 5 segundos entre as tentativas
RETRY_COUNT=0
SERVICE_READY=false

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    echo "INFO: Verificando se o daemon do TeamViewer está pronto (Tentativa $((RETRY_COUNT+1))/$MAX_RETRIES)..."
    OUTPUT=$(sudo /usr/bin/teamviewer info 2>&1)
    echo "DEBUG: Output de 'teamviewer info': $OUTPUT"
    echo "$OUTPUT" | grep -q "TeamViewer ID:" && SERVICE_READY=true && break
    sleep "$WAIT_TIME"
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ "$SERVICE_READY" = true ]; then
    echo "INFO: Daemon do TeamViewer está pronto e rodando."
else
    echo "ERRO: O daemon do TeamViewer não iniciou ou não respondeu após múltiplas tentativas. Verifique 'sudo systemctl status teamviewerd' manualmente e o log completo do TeamViewer."
    sudo /usr/bin/systemctl status teamviewerd # Exibir o status completo para depuração
    rm -rf "$TEMP_DIR"; exit 1 # Sair com erro se o daemon não estiver pronto para configuração
fi

# 8. Limpar arquivos temporários
# Ajustar a limpeza para usar sudo, já que os arquivos serão criados por root
echo "INFO: Limpando arquivos temporários em $TEMP_DIR..."
sudo rm -rf "$TEMP_DIR" || echo "AVISO: Falha ao remover o diretório temporário $TEMP_DIR. Pode ser necessário limpar manualmente."

echo "--- Instalação do TeamViewer concluída! ---"
echo "Data e Hora de término: $(date)"
echo "O TeamViewer foi instalado e o serviço iniciado. A configuração de acesso e a atribuição podem ser feitas manualmente pelo aplicativo."
echo "Lembre-se de verificar firewalls locais/de rede (portas 5938, 80, 443) e o status no console do TeamViewer."

exit 0
