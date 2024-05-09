#!/bin/bash

HOSTNAME="mail"
CRT_DIR="/etc/ssl/mail"

# HOME_DIR=$(dirname $0)
HOME_DIR=$(dirname -- "$(readlink -f -- "$0")")
# HOME_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

source $HOME_DIR/modules/control/module_management.sh $HOME_DIR

function main() {
  echo
  check_network_health 77.88.8.8
  get_network
  echo

  fix_net_config

  input_task "Upgrade packages?"
  if [[ $? -eq 0 ]]; then
    sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
    prints -g "\nDone!\n"
  fi

  input_task "Set a static IP address?"
  if [[ $? -eq 0 ]]; then
    find_gateway
    network_interfaces
    check_network_health 77.88.8.8
    prints -g "Done!\n"
  fi

  input_task "Configure time?"
  if [[ $? -eq 0 ]]; then
    sudo apt update &> /dev/null
    sudo apt install chrony -y

    sudo timedatectl set-timezone Europe/Moscow
    sudo systemctl enable chrony
    sudo systemctl restart chrony

    prints -g "\nDone!\n"
  fi

  input_domain
  input_dns

  input_task "Configure resolvconf?"
  if [[ $? -eq 0 ]]; then
    sudo sed -i "
    s|^.#DNS=.*$|DNS=${DNS}|
    s|^.#Domains=.*$|Domains=${DOMAIN}|
    " /etc/systemd/resolved.conf

    sudo systemctl enable systemd-resolved.service
    sudo systemctl start systemd-resolved.service

    sudo systemctl restart systemd-resolved.service
    #sudo systemctl status systemd-resolved.service

    echo

    sudo rm -f /etc/resolv.conf
    sudo ln -svi /run/systemd/resolve/resolv.conf /etc/resolv.conf

    prints -g "\nDone!\n"
  fi

  input_task_no "Configure Firewall?"
  if [[ $? -eq 0 ]]; then
    iptables &> /dev/null
    if [[ $? -eq 127 ]]; then
      sudo apt install iptables -y
    fi

    sudo iptables -F
    sudo iptables -I INPUT 1 -p tcp --match multiport --dports 25,110,143,465,587,993,995 -j ACCEPT
    sudo iptables -I INPUT 1 -p tcp --match multiport --dports 80,443 -j ACCEPT

    netfilter-persistent &> /dev/null
    if [[ $? -eq 127 ]]; then
      sudo apt install iptables-persistent -y
    fi

    sudo netfilter-persistent save

    prints -g "\nDone!\n"
  fi

  input_task "Configure hostname?"
  if [[ $? -eq 0 ]]; then
    sudo hostnamectl set-hostname ${HOSTNAME} &> /dev/null
    sudo sed -i "1s|.*$|127.0.0.1\tlocalhost ${HOSTNAME}|" /etc/hosts &> /dev/null

    check_network_configuration
    #echo; cat /etc/hosts | head -2
    prints -g "Done!\n"
  fi

  input_task "Configure nginx?"
  if [[ $? -eq 0 ]]; then
    nginx -v &> /dev/null
    if [[ $? -eq 127 ]]; then
      sudo rm -rf /etc/nginx &> /dev/null
      sudo apt update && sudo apt install nginx -y
      sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.default
    else
      check_nginx_default
    fi

    sudo sed -i "/client_max_body_size/d" /etc/nginx/nginx.conf
    sudo sed -i "17i client_max_body_size 30M;" /etc/nginx/nginx.conf
    sudo sed -i "s|client_max_body_size|\tclient_max_body_size|" /etc/nginx/nginx.conf
    sudo sed -i "s|# server_names_hash_bucket_size|server_names_hash_bucket_size|" /etc/nginx/nginx.conf

    sudo systemctl enable nginx
    sudo apt install php php-fpm phpmyadmin -y
    find_php_version

    sudo apt purge apache* -y
    sudo rm -rf /var/lib/apache2
    sudo apt autoremove -y
    sudo apt install acl apache2-utils -y

    sudo bash -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"

    sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/${FQDN}
    sudo rm -f /etc/nginx/sites-enabled/default &> /dev/null

    sudo sed -i "s|7.4|${php_version}|" $HOME_DIR/nginx/nginx.conf

    sudo sed -i "s|server_name _|server_name ${FQDN}|" /etc/nginx/sites-available/${FQDN}
    sudo sed -i "s|index.html|index.php index.html|" /etc/nginx/sites-available/${FQDN}

    sudo sed -i "s|#location|location|g" /etc/nginx/sites-available/${FQDN}
    sudo sed -i "63s|#}|}|" /etc/nginx/sites-available/${FQDN}

    sudo sed -i "69s|#||" /etc/nginx/sites-available/${FQDN}
    sudo sed -i "70s|#}|}|" /etc/nginx/sites-available/${FQDN}

    sudo sed -i "56r $HOME_DIR/nginx/nginx.conf" /etc/nginx/sites-available/${FQDN}

    prints -c "\nCheck configure nginx $( prints -p ${FQDN} )"
    prints -y "Press Enter.."; read

    sudo nano /etc/nginx/sites-available/${FQDN}
    sudo rm -f /etc/nginx/sites-enabled/${FQDN} &> /dev/null
    sudo ln -s /etc/nginx/sites-available/${FQDN} /etc/nginx/sites-enabled/${FQDN}

    sudo systemctl enable php${php_version}-fpm
    sudo systemctl restart php${php_version}-fpm

    check_nginx_config
    prints -g "\nDone!\n"
  fi

  # sudo mysql -u root -p -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('new_password');"
  input_task "Install database?"
  if [[ $? -eq 0 ]]; then
    sudo apt install mariadb-server -y
    sudo systemctl enable mariadb
    mysqladmin -u root password Administrator!
    sudo systemctl restart mariadb

    sudo mysql_secure_installation

    sudo apt install php-mysql php-mbstring php-imap -y
    sudo systemctl restart php${php_version}-fpm

    prints -g "\nDone!\n"
  fi

  # ---------------------------------------------------------------- #
  # Setup_Password	@e$99$~r#:O@
  # root@ilsem.ru		=/f8$/#2HzFtYvW:

  # admin@ilsem.ru	00Nh9?YF7M\jP,Md
  # test1@ilsem.ru	11Nh9?YF7M\jP,Md
  # test2@ilsem.ru	22Nh9?YF7M\jP,Md
  # ---------------------------------------------------------------- #
  input_task "Install PostfixAdmin?"
  if [[ $? -eq 0 ]]; then
    sudo wget https://sourceforge.net/projects/postfixadmin/files/latest/download -O postfixadmin.tar.gz

    if [[ $? -ne 0 ]]; then
      prints -r "\nDownload error!"
      exit
    fi

    sudo mkdir /var/www/html/postfixadmin
    sudo tar -C /var/www/html/postfixadmin -xvf postfixadmin.tar.gz --strip-components 1
    sudo mkdir /var/www/html/postfixadmin/templates_c
    sudo chown -R www-data:www-data /var/www/html/postfixadmin

    sudo mysql -u root -e "CREATE DATABASE postfix DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;"
    sudo mysql -u root -e "GRANT ALL ON postfix.* TO 'postfix'@'localhost' IDENTIFIED BY 'PostfixAdmin!';"

    sudo cp $HOME_DIR/conf/config.local.php /var/www/html/postfixadmin/

    prints -c "\nGo to site http://${IP}/postfixadmin/public/setup.php"
    prints -y "Press Enter to continue.."; read

    prints -g "Done!\n"
  fi

  input_task "Install Postfix?"
  if [[ $? -eq 0 ]]; then
    sudo apt install postfix postfix-mysql -y
    sudo groupadd -g 1024 vmail
    sudo useradd -d /home/mail -g 1024 -u 1024 vmail -m
    sudo chown vmail:vmail /home/mail

    prints -g "\nDone!\n"
  fi

  input_task "Configure Postfix?"
  if [[ $? -eq 0 ]]; then
    sudo sed -i "s|inet_protocols = all|inet_protocols = ipv4|" /etc/postfix/main.cf
    sudo sed -i "s|ssl/certs/ssl-cert-snakeoil.pem|ssl/mail/mail.crt|" /etc/postfix/main.cf
    sudo sed -i "s|ssl/private/ssl-cert-snakeoil.key|ssl/mail/mail.key|" /etc/postfix/main.cf
    sudo sed -i "s|^myhostname = .*$|myhostname = ${HOSTNAME}|" /etc/postfix/main.cf

    sudo bash -c "cat $HOME_DIR/conf/main.cf >> /etc/postfix/main.cf"

    # prints -c "\nCheck configure $(prints -p 'main.cf')"
    # prints -y "Press Enter.."; read
    # sudo nano /etc/postfix/main.cf

    sudo cp $HOME_DIR/conf/mysql_virtual_alias_maps.cf /etc/postfix/
    sudo cp $HOME_DIR/conf/mysql_virtual_domains_maps.cf /etc/postfix/
    sudo cp $HOME_DIR/conf/mysql_virtual_mailbox_maps.cf /etc/postfix/

    sudo bash -c "cat $HOME_DIR/conf/master.cf >> /etc/postfix/master.cf"

    sudo systemctl enable postfix
    sudo systemctl restart postfix

    prints -g "\nDone!\n"
  fi

  input_task "Generate Certificates?"
  if [[ $? -eq 0 ]]; then
    cd ${HOME_DIR}/certificate
    sudo mkdir out tmp csr &> /dev/null

    input_task "Generate new Root Certificate?"
    if [[ $? -eq 0 ]]; then
      genetate_root_cert
      prints -g "\nDone!\n"
    fi

    input_task "Generate new Mail Certificate?"
    if [[ $? -eq 0 ]]; then
      genetate_mail_cert
      prints -g "\nDone!\n"
    fi
  fi

  cd ${HOME_DIR}

  input_task "Install Dovecot?"
  if [[ $? -eq 0 ]]; then
    sudo apt install dovecot-imapd dovecot-pop3d dovecot-mysql -y

    # mail_location = mbox:~/mail:INBOX=/var/mail/%u
    sudo sed -i "s|^mail_location =.*$|mail_location = maildir:/home/mail/%d/%u/|" /etc/dovecot/conf.d/10-mail.conf

    sudo sed -i "101s|#mode.*$|mode = 0600|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "102s|#user.*$|user = vmail|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "103s|#group.*$|group = vmail|" /etc/dovecot/conf.d/10-master.conf

    sudo sed -i "107s|#unix|unix|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "108s|#  mode.*$|  mode = 0666|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "109s|#}|}|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "108a group = postfix" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "108a user = postfix" /etc/dovecot/conf.d/10-master.conf

    sudo sed -i "109s|user|    user|" /etc/dovecot/conf.d/10-master.conf
    sudo sed -i "110s|group|    group|" /etc/dovecot/conf.d/10-master.conf

    sudo bash -c "cat $HOME_DIR/conf/10-master.conf >> /etc/dovecot/conf.d/10-master.conf"

    # prints -c "\nCheck configure $(prints -p 'master.conf')"
    # prints -y "Press Enter.."; read
    # sudo nano /etc/dovecot/conf.d/10-master.conf

    sudo sed -i "s|!include auth-system.conf.ext|#!include auth-system.conf.ext|" /etc/dovecot/conf.d/10-auth.conf
    sudo sed -i "s|#!include auth-sql.conf.ext|!include auth-sql.conf.ext|" /etc/dovecot/conf.d/10-auth.conf

    sudo sed -i "s|^ssl =.*$|ssl = required|" /etc/dovecot/conf.d/10-ssl.conf
    sudo sed -i "s|^ssl_cert =.*$|ssl_cert = <${CRT_DIR}/mail.crt|" /etc/dovecot/conf.d/10-ssl.conf
    sudo sed -i "s|^ssl_key =.*$|ssl_key = <${CRT_DIR}/mail.key|" /etc/dovecot/conf.d/10-ssl.conf

    sudo sed -i 's|#lda_mailbox_autocreate = no|lda_mailbox_autocreate = yes|' /etc/dovecot/conf.d/15-lda.conf

    sudo bash -c "cat $HOME_DIR/conf/dovecot-sql.conf.ext >> /etc/dovecot/dovecot-sql.conf.ext"
    sudo sed -i "s/#listen = *, ::/listen = */" /etc/dovecot/dovecot.conf

    sudo systemctl enable dovecot
    sudo systemctl restart dovecot

    prints -g "\nDone!\n"
  fi

  input_task "Install RoundeCube?"
  if [[ $? -eq 0 ]]; then
    sudo wget https://github.com/roundcube/roundcubemail/releases/download/1.6.1/roundcubemail-1.6.1-complete.tar.gz

    if [[ $? -ne 0 ]]; then
      prints -r "\nDownload error!\n"
      exit
    fi

    sudo mkdir /var/www/html/webmail
    sudo tar -C /var/www/html/webmail -xvf roundcubemail-*.tar.gz --strip-components 1
    sudo cp /var/www/html/webmail/config/config.inc.php.sample /var/www/html/webmail/config/config.inc.php

    # $config['smtp_pass'] = ''
    sudo sed -i "s|'%p';|'';|" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "s|:pass@|:Administrator\!@|" /var/www/html/webmail/config/config.inc.php

    sudo sed -i "28s|\\$|\n\\$|" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['archive_mbox'] = 'Archive';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['trash_mbox'] = 'Trash';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['sent_mbox'] = 'Sent';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['junk_mbox'] = 'Junk';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['drafts_mbox'] = 'Drafts';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['enable_installer'] = true;" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "29a \$config['create_default_folders'] = true;" /var/www/html/webmail/config/config.inc.php

    prints -c "\nCheck configure $(prints -p 'config.inc.php')"
    prints -y "Press Enter.."; read
    sudo nano /var/www/html/webmail/config/config.inc.php

    sudo chown -R www-data:www-data /var/www/html/webmail

    sudo mysql -u root -e "CREATE DATABASE roundcubemail DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
    sudo mysql -u root -e "GRANT ALL PRIVILEGES ON roundcubemail.* TO roundcube@localhost IDENTIFIED BY 'Administrator!';"
    sudo mysql -u root roundcubemail < /var/www/html/webmail/SQL/mysql.initial.sql

    if [[ -z $php_version ]]; then
      find_php_version
    fi

    sudo apt install php${php_version}-curl curl -y
    sudo apt install php-pear php-intl php-ldap php-net-smtp php-gd php-imagick php-zip -y
    sudo apt install php-dev libmcrypt-dev -y
    sudo pecl channel-update pecl.php.net

    # mcrypt-1.0.5
    sudo pecl install mcrypt
    sudo bash -c "echo 'extension=mcrypt.so' > /etc/php/${php_version}/fpm/conf.d/99-mcrypt.ini"

    timezone="\"Europe/Moscow\""
    sudo sed -i "s|;date.timezone.*$|date.timezone = ${timezone}|" /etc/php/${php_version}/fpm/php.ini
    sudo sed -i "s|post_max_size.*$|post_max_size = 30M|" /etc/php/${php_version}/fpm/php.ini
    sudo sed -i "s|upload_max_filesize.*$|upload_max_filesize = 30M|" /etc/php/${php_version}/fpm/php.ini

    # sudo nano /etc/php/${php_version}/fpm/php.ini

    sudo systemctl restart php${php_version}-fpm
    sudo systemctl restart nginx

    prints -c "\nGo to site http://${IP}/webmail/installer/"
    prints -y "Press Enter.."; read

    sudo sed -i "s|\['enable_installer'\] = true|\['enable_installer'\] = false|" /var/www/html/webmail/config/config.inc.php

    sudo rm -R /var/www/html/webmail/installer

    prints -g "\nDone!\n"
  fi

  input_task "Install Plugin?"
  if [[ $? -eq 0 ]]; then
    sudo apt install dovecot-sieve dovecot-managesieved -y

    # sudo wget https://github.com/johndoh/roundcube-contextmenu/archive/refs/tags/3.3.1.tar.gz
    check_file_existence "roundcube-contextmenu-*.tar.gz"
    if [[ $? -eq 0 ]]; then
      sudo mkdir /var/www/html/webmail/plugins/contextmenu
      sudo tar -C /var/www/html/webmail/plugins/contextmenu -xvf roundcube-contextmenu-*.tar.gz --strip-components 1
      sudo chown www-data:www-data -R /var/www/html/webmail/plugins/contextmenu
    fi

    sudo sed -i "30a mail_home = /home/mail/%d/%u/sieve" /etc/dovecot/conf.d/10-mail.conf
    sudo sed -i "s|#mail_plugins.*$|mail_plugins = \$mail_plugins sieve|" /etc/dovecot/conf.d/15-lda.conf

    sudo sed -i "6s|#protocols|protocols|" /etc/dovecot/conf.d/20-managesieve.conf

    sudo sed -i "10s|#service|service|" /etc/dovecot/conf.d/20-managesieve.conf
    sudo sed -i "11s|#||" /etc/dovecot/conf.d/20-managesieve.conf
    sudo sed -i "12s|#||" /etc/dovecot/conf.d/20-managesieve.conf
    sudo sed -i "13s|#||" /etc/dovecot/conf.d/20-managesieve.conf
    sudo sed -i "29s|#||" /etc/dovecot/conf.d/20-managesieve.conf

    sudo sed -i "39s|sieve|#sieve|" /etc/dovecot/conf.d/90-sieve.conf

    sudo sed -i "39a sieve_global_dir = /etc/dovecot/sieve/global/" /etc/dovecot/conf.d/90-sieve.conf
    sudo sed -i "40s|^sieve|  sieve|" /etc/dovecot/conf.d/90-sieve.conf

    sudo sed -i "39a sieve_dir = /home/mail/%d/%u/sieve" /etc/dovecot/conf.d/90-sieve.conf
    sudo sed -i "40s|^sieve|  sieve|" /etc/dovecot/conf.d/90-sieve.conf

    sudo sed -i "39a sieve_global_path = /etc/dovecot/sieve/default.sieve" /etc/dovecot/conf.d/90-sieve.conf
    sudo sed -i "40s|^sieve|  sieve|" /etc/dovecot/conf.d/90-sieve.conf

    sudo sed -i "39a sieve = /home/mail/%d/%u/sieve/dovecot.sieve" /etc/dovecot/conf.d/90-sieve.conf
    sudo sed -i "40s|^sieve|  sieve|" /etc/dovecot/conf.d/90-sieve.conf

    sudo sed -i "39s|$|\n|" /etc/dovecot/conf.d/90-sieve.conf

    sudo mkdir -p /etc/dovecot/sieve/global
    sudo chown dovecot:dovecot -R /etc/dovecot/sieve
    sudo systemctl restart dovecot

    sudo sed -i "29i \$config['managesieve_host'] = 'localhost';" /var/www/html/webmail/config/config.inc.php
    sudo sed -i "s|'zipdownload',|'zipdownload',\n    'managesieve',\n    'contextmenu',|" /var/www/html/webmail/config/config.inc.php

    sudo systemctl restart php${php_version}-fpm

    prints -g "\nDone!\n"
  fi

  #sudo chown -R ${USER}:${USER} *
  #sudo chown root:root certificate/out/*

  input_task "Reboot system?"
  if [[ $? -eq 0 ]]; then
    prints -r "\nMachine will be reboot. Press Enter..."; read
    sudo reboot && exit
  fi
}

# =================================================================================== #

function find_php_version {
  php_version=$( php -version | head -1 | cut -c5-7 )
  prints "\n$(prints -p "PHP $php_version") version detected"
  prints -y "Press Enter..."; read
}

function check_nginx_default {
  check_file_existence "/etc/nginx/nginx.conf.default"
  if [[ $? -eq 0 ]]; then
    sudo cp /etc/nginx/nginx.conf.default /etc/nginx/nginx.conf
  else
    prints -r "Recovery file not found!\n"
    input_task "Reinstall nginx?"
    if [[ $? -eq 0 ]]; then
      sudo apt purge nginx nginx-common nginx-core -y && sudo apt autoremove -y
      sudo rm -rf /etc/nginx &> /dev/null
      sudo apt update && sudo apt install nginx -y
    else
      prints -r "Installation aborted!\n\n"
      exit
    fi
  fi
}

function check_nginx_config {
  while true
  do
  nginx -t &> /dev/null
  if [[ $? -ne 0 ]]; then
    nginx -t
    prints -r "\nThe configuration is invalid! Please fix!"
    prints -y "Press Enter to continue..\n"; read
    sudo nano /etc/nginx/sites-available/${FQDN}
  else
    sudo systemctl restart nginx
    prints -g "\nNginx config is ok!"
    break
  fi
  done
}

main "$@"
exit
