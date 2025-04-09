# django project install script

nesse projeto estão disponiveis dois scripts linux usados para facilitar na instalação de um projeto django em produção. O script django_install.sh baixa e instala o mysql, git, nginx, entre outras dependencias, cria os serviços necessarios como gunicorn, celery, entre outros. Já o django_att.sh faz a atualização de acordo com a ultima versão disponivel no repositorio e reinicia todos os serviços.

## Instalação
### django_install.sh
bash

```bash
sudo curl -L https://raw.githubusercontent.com/felipegomes12/django-project-install-script/main/django_install.sh -o /usr/local/bin/django_install.sh
sudo chmod +x /usr/local/bin/django_install.sh
```
### django_att.sh
bash
```bash
sudo curl -L https://raw.githubusercontent.com/felipegomes12/django-project-install-script/main/django_att.sh -o /usr/local/bin/django_att.sh
sudo chmod +x /usr/local/bin/django_att.sh
```
## Uso
### django_install.sh
Executa a instalação do seu projeto, ao usar esse script ele vai perguntar o endereço
do repositorio para instalação e irá salvar, caso o repositorio seja privado deve ser
passado o token do repositorio para o download.
```shell
sudo django_install.sh
```
### django_att.sh
Quando chamado faz o stash e drop das mudanças presentes no diretorio local, baixa a nova
versão disponivel e reinicia todos os processos relacionados.
```shell
sudo django_att.sh
```
## requerimentos
- Sitema linux.
- Acesso ao root ou a senha do root.
- Link do repositorio publico ou link com token do repositorio caso seja privado.
- curl instalado.
## Permições
Qualquer um é livre para baixar os arquivos e alterar para suprir suas necessidades. Nenhum crédito é necessário.
