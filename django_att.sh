#!/bin/bash

# Caminho do diretório do projeto
cd /home/aplications/django || exit
git config --global --add safe.directory /home/aplications/django

# Caminho para o arquivo rep_end.txt
FILE="/home/aplications/rep_end.txt"
REPEND=$(head -n 1 "$FILE")

# Executa git stash, limpa arquivos não rastreados e faz o pull
git stash
git clean -f
git clean -fd
git pull $REPEND
git stash drop

chown -R django_user:django_user /home/aplications/django

source /home/aplications/django/venv/bin/activate

pip install -r requirements.txt

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