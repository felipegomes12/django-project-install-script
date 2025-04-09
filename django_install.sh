#!/bin/bash

# Caminho do diretório do projeto
PROJECT_DIR="/home/aplications/django"

# Verifica se as dependências do sistema estão instaladas
check_and_install_dependency() {
    # $1 é o nome do pacote
    dpkg -l | grep -qw $1 || sudo apt-get install -y $1
}

# Verifica se o git está instalado
check_and_install_dependency "git"

# Verifica se o MySQL client e suas dependências de desenvolvimento estão instalados
check_and_install_dependency "libmysqlclient-dev"
check_and_install_dependency "mysql-client"

# Verifica se o python3.11-venv está instalado para criação do ambiente virtual
check_and_install_dependency "python3.11-venv"
check_and_install_dependency "python3.11-dev"

# Verifica se o pacote gcc está instalado (necessário para compilar mysqlclient)
check_and_install_dependency "build-essential"

# verifica se o redis está instalado (necessario para o celery)
check_and_install_dependency "redis"

# Verifica se o nginx está instaldo (necessario para a aplicação)
check_and_install_dependency "nginx"

# Nome do usuário para o Gunicorn
USER_NAME="django_user"

# Verifica se o usuário django_user existe
if ! id "$USER_NAME" &>/dev/null; then
    echo "O usuário $USER_NAME não encontrado, criando..."
    # Cria o usuário sem diretório home e sem senha
    sudo useradd -s /bin/bash -M "$USER_NAME"
    # Remove a senha do usuário para que não seja solicitado login
    sudo passwd -d "$USER_NAME"
    echo "Usuário $USER_NAME criado."
else
    echo "O usuário $USER_NAME já existe."
fi

# Verifica se o diretório do projeto existe; se não, cria
if [ ! -d "$PROJECT_DIR" ]; then
    mkdir -p "$PROJECT_DIR"
    echo "Diretório $PROJECT_DIR criado."
fi

# Navega para o diretório do projeto
cd "$PROJECT_DIR" || exit

# Caminho para o arquivo rep_end.txt
FILE="/home/aplications/rep_end.txt"

# Verifica se o arquivo existe
if [ -f "$FILE" ]; then
    echo "O arquivo $FILE existe. Lendo a primeira linha..."
    # Lê a primeira linha do arquivo e define como REPEND
    REPEND=$(head -n 1 "$FILE")
    echo "A primeira linha do arquivo é: $REPEND"
else
    echo "O arquivo $FILE não existe."
    # Solicita o input do usuário
    read -p "Por favor, insira o endereço do repositório, caso seja privado juntamente com o token: " REPEND
    # Salva o valor inserido no arquivo rep_end.txt
    echo "$REPEND" > "$FILE"
    echo "Valor $REPEND salvo no arquivo $FILE."
fi

# Exibe o valor de REPEND
echo "A variável REPEND foi definida como: $REPEND"

# Verifica se o diretório é um repositório git; se não, clona o repositório
if [ ! -d ".git" ]; then
    echo "Repositório Git não encontrado. Clonando..."
    git clone $REPEND .
    if [ $? -ne 0 ]; then
        echo "Erro ao clonar o repositório Git."
        exit 1
    fi
    echo "Repositório Git clonado."
else
    echo "Repositório Git já existe, atualizando com git pull..."
    # Executa git stash, limpa arquivos não rastreados e faz o pull
    git stash
    git clean -f
    git clean -fd
    git pull $REPEND
    git stash drop
fi

# Ajuste as permissões
chown -R django_user:django_user /home/aplications/django

# Verifica se o ambiente virtual existe; se não, cria
if [ ! -d "venv" ]; then
    python3.11 -m venv venv
    echo "Ambiente virtual criado."
fi

# Ativa o ambiente virtual
source "$PROJECT_DIR/venv/bin/activate"

# Verifica se o arquivo requirements.txt existe
if [ ! -f "requirements.txt" ]; then
    echo "Arquivo requirements.txt não encontrado. Verifique se ele está presente."
    exit 1
fi

# Instala as dependências do arquivo requirements.txt
pip install --upgrade pip
pip install -r requirements.txt

# Caso o mysqlclient falhe, instale novamente com as dependências adequadas
if ! pip show mysqlclient > /dev/null 2>&1; then
    echo "mysqlclient não encontrado, tentando reinstalar com dependências."
    sudo apt-get install -y libmysqlclient-dev
    pip install mysqlclient
fi

echo "Dependências instaladas com sucesso."

# Verificar se o nhinx existe
if systemctl list-units --type=service | grep -q "nginx"; then
    echo "nginx encontrado."
    # Verificar se o nginx está ativo
    if systemctl is-active --quiet "nginx"; then
        echo "nginx está ativo."
    else
        systemctl enable nginx
        systemctl start nginx
        echo "nginx foi ativado."
    fi
else
    systemctl enable nginx
    systemctl start nginx
    echo "nginx foi ativado."
fi

# Diretório onde as configurações de sites do Nginx estão localizadas
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_SITES_DIR="/etc/nginx/sites-enabled"

# Nome do arquivo de configuração do site
SITE_CONFIG_FILE="django_project"

# Verifica se o arquivo de configuração já existe em sites-available
if [ ! -f "$NGINX_SITES_DIR/$SITE_CONFIG_FILE" ]; then
    echo "Arquivo de configuração do site $SITE_CONFIG_FILE não encontrado, criando..."

    # Cria a configuração do site
    cat > "$NGINX_SITES_DIR/$SITE_CONFIG_FILE" <<EOF
server {
    listen 8080;
    server_name 0.0.0.0;

    location / {
        proxy_pass http://unix:/home/aplications/django/PortalAutoEquip.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Adicionando diretivas de tempo limite
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }

    location /static/ {
        alias /home/aplications/django/static/;
    }

    location /media/ {
        alias /home/aplications/django/media/;
    }
}
EOF

    echo "Configuração do site criada em $NGINX_SITES_DIR/$SITE_CONFIG_FILE"

    # Cria o link simbólico no diretório sites-enabled para habilitar o site
    ln -s "$NGINX_SITES_DIR/$SITE_CONFIG_FILE" "$NGINX_ENABLED_SITES_DIR/$SITE_CONFIG_FILE"
    echo "Link simbólico criado em $NGINX_ENABLED_SITES_DIR/$SITE_CONFIG_FILE"

    # Reinicia o Nginx para aplicar a nova configuração
    systemctl restart nginx
    echo "Nginx reiniciado para aplicar a nova configuração."
else
    echo "A configuração do site $SITE_CONFIG_FILE já existe."
fi

#!/bin/bash

# Caminho onde os arquivos de serviço do systemd estão localizados
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="gunicorn.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=gunicorn daemon
After=network.target

[Service]
User=django_user
Group=django_user
WorkingDirectory=/home/aplications/django
ExecStart=/home/aplications/django/venv/bin/gunicorn --workers 9 --timeout 600 --bind unix:/home/aplications/django/PortalAutoEquip.sock PortalAutoEquip.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Caminho onde os arquivos de serviço do systemd estão localizados
SERVICE_NAME="celery.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Celery Service
After=network.target

[Service]
User=django_user
Group=www-data
WorkingDirectory=/home/aplications/django
ExecStartPre=/bin/sleep 20
ExecStart=/home/aplications/django/venv/bin/celery -A PortalAutoEquip worker --loglevel=info

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Caminho onde os arquivos de serviço do systemd estão localizados
SERVICE_NAME="celerybeat.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Celery Beat Service
After=network.target

[Service]
User=django_user
Group=www-data
WorkingDirectory=/home/aplications/django
ExecStartPre=/bin/sleep 20
ExecStart=/home/aplications/django/venv/bin/celery -A PortalAutoEquip beat --loglevel=info

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Caminho onde os arquivos de serviço do systemd estão localizados
SERVICE_NAME="celeryfilarapida.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Celery Worker for Fila Rápida
After=network.target

[Service]
User=django_user
Group=www-data
WorkingDirectory=/home/aplications/django
ExecStart=/home/aplications/django/venv/bin/celery -A PortalAutoEquip worker -Q fila_rapida --pool=solo -l info --hostname=fila_rapida@%h
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Caminho onde os arquivos de serviço do systemd estão localizados
SERVICE_NAME="celeryfilademorada.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Celery Worker for Fila Demorada
After=network.target

[Service]
User=django_user
Group=www-data
WorkingDirectory=/home/aplications/django
ExecStart=/home/aplications/django/venv/bin/celery -A PortalAutoEquip worker -Q fila_demorada --pool=solo -l info --hostname=fila_demorada@%h
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Caminho onde os arquivos de serviço do systemd estão localizados
SERVICE_NAME="celeryflower.service"
SERVICE_FILE="$SYSTEMD_DIR/$SERVICE_NAME"

# Verifica se o arquivo de serviço já existe
if [ ! -f "$SERVICE_FILE" ]; then
    echo "O serviço $SERVICE_NAME não encontrado, criando..."

    # Cria o arquivo de serviço para o Gunicorn
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Flower Service for Celery
After=network.target

[Service]
User=django_user
Group=www-data
WorkingDirectory=/home/aplications/django
Environment="FLOWER_UNAUTHENTICATED_API=true"
ExecStart=/home/aplications/django/venv/bin/celery -A PortalAutoEquip flower --port=5555
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    echo "Arquivo de serviço $SERVICE_NAME criado em $SERVICE_FILE"

    # Habilita o serviço para iniciar automaticamente no boot
    systemctl enable "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME habilitado para iniciar automaticamente no boot."

    # Inicia o serviço
    systemctl start "$SERVICE_NAME"
    echo "Serviço $SERVICE_NAME iniciado."
else
    echo "O serviço $SERVICE_NAME já existe."
fi

# Recarrega e reinicia os serviços
sudo systemctl daemon-reload
sudo systemctl restart gunicorn
sudo systemctl restart nginx
sudo systemctl restart celeryflower
sudo systemctl restart celeryfilarapida
sudo systemctl restart celeryfilademorada
sudo systemctl status gunicorn
sudo systemctl status nginx
sudo systemctl status celery
sudo systemctl status celerybeat
sudo systemctl status celeryflower
sudo systemctl status celeryfilarapida
sudo systemctl status celeryfilademorada