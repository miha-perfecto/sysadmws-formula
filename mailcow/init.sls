{% if pillar["mailcow"] is defined %}
docker_install_00:
  file.directory:
    - name: /etc/docker
    - mode: 700
docker_install_01:
  file.managed:
    - name: /etc/docker/daemon.json
    - contents: |
        { "iptables": true, "default-address-pools": [ {"base": "172.16.0.0/12", "size": 24} ] }
docker_install_02:
  pkgrepo.managed:
    - humanname: Docker CE Repository
    - name: deb [arch=amd64] https://download.docker.com/linux/{{ grains["os"]|lower }} {{ grains["oscodename"] }} stable
    - file: /etc/apt/sources.list.d/docker-ce.list
    - key_url: https://download.docker.com/linux/{{ grains["os"]|lower }}/gpg
docker_install_03:
  pkg.installed:
    - refresh: True
    - reload_modules: True
    - pkgs:
        - docker-ce: "{{ pillar["mailcow"]["docker-ce_version"] }}*"
        - python3-pip
docker_pip_install:
  pip.installed:
    - name: docker-py >= 1.10
    - reload_modules: True
docker_install_3:
  service.running:
    - name: docker
docker_install_4:
  cmd.run:
    - name: systemctl restart docker
    - onchanges:
        - file: /etc/docker/daemon.json
postfix_stop_and_disable:
  service.dead:
    - name: postfix
      enable: False
nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
nginx_files_1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - contents: |
        worker_processes 4;
        worker_rlimit_nofile 40000;
        events {
            worker_connections 8192;
            use epoll;
            multi_accept on;
        }
        http {
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
            sendfile on;
            tcp_nopush on;
            tcp_nodelay on;
            gzip on;
            gzip_comp_level 4;
            gzip_types text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;
            gzip_vary on;
            gzip_proxied any;
            client_max_body_size 1000m;
            log_format  main  '$remote_addr - [$time_local] "$host$request_uri" '
                              '$status $body_bytes_sent "$http_referer" '
                              '"$http_user_agent" "$proxy_add_x_forwarded_for"';
            server {
                listen 80;
                return 301 https://$host$request_uri;
            }

            server {
                listen 443 ssl;
                server_name {{ pillar["mailcow"]["servername"] }};
                access_log /var/log/nginx/{{ pillar["mailcow"]["servername"] }}-access.log main;
                error_log /var/log/nginx/{{ pillar["mailcow"]["servername"] }}-error.log;
                ssl_certificate /opt/acme/cert/mailcow_{{ pillar["mailcow"]["servername"] }}_fullchain.cer;
                ssl_certificate_key /opt/acme/cert/mailcow_{{ pillar["mailcow"]["servername"] }}_key.key;
                location / {
                    proxy_pass http://localhost:{{ pillar["mailcow"]["HTTP_PORT"] }};
                    include    proxy_params;
                    proxy_set_header    X-Real-IP          $remote_addr;
                    proxy_set_header    X-Forwarded-For    $proxy_add_x_forwarded_for;
                    proxy_set_header    X-Forwarded-Host   $host;
                    proxy_set_header    X-Forwarded-Proto  $scheme;
                    proxy_headers_hash_max_size 512;
                    proxy_headers_hash_bucket_size 128;
                }
            }
        }
nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

  {% if "haproxy" in pillar["mailcow"] %}

haproxy_install:
  pkg.installed:
    - pkgs:
      - haproxy
haproxy_config:
  file.managed:
    - name: /etc/haproxy/haproxy.conf
    - contents: |
        global
                log /dev/log    local0
                log /dev/log    local1 notice
                chroot /var/lib/haproxy
                stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
                stats timeout 30s
                user haproxy
                group haproxy
                daemon
                ca-base /etc/ssl/certs
                crt-base /etc/ssl/private
                ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
                ssl-default-bind-options no-sslv3
        defaults
                log     global
                mode    tcp
                option  tcplog
                option  dontlognull
                timeout client 1m
                timeout connect 7s
                timeout server  50000
                errorfile 400 /etc/haproxy/errors/400.http
                errorfile 403 /etc/haproxy/errors/403.http
                errorfile 408 /etc/haproxy/errors/408.http
                errorfile 500 /etc/haproxy/errors/500.http
                errorfile 502 /etc/haproxy/errors/502.http
                errorfile 503 /etc/haproxy/errors/503.http
                errorfile 504 /etc/haproxy/errors/504.http

        listen imap
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:143
                server imap 127.0.0.1:10143 send-proxy
        listen imaps
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:993
                server imaps 127.0.0.1:10993 send-proxy
        listen pop
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:110
                server pop 127.0.0.1:10110 send-proxy
        listen pops
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:995
                server pops 127.0.0.1:10995 send-proxy
        listen sieve
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:4190
                server sieve 127.0.0.1:14190 send-proxy
        listen submission
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:587
                server submission 127.0.0.1:10587 send-proxy
        listen smtps
                bind {{ pillar["mailcow"]["haproxy"]["EXTERNAL_IP"] }}:465
                server smtps 127.0.0.1:10465 send-proxy
  {% endif %}


nginx_cert:
  cmd.run:
    - shell: /bin/bash
    - name: "/opt/acme/home/{{ pillar["mailcow"]["acme_account"] }}/verify_and_issue.sh mailcow {{ pillar["mailcow"]["servername"] }}"

mailcow_clone_fom_git:
  git.cloned:
    - name: https://github.com/mailcow/mailcow-dockerized
    - target: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}

mailcow_config_generator_http_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *HTTP_PORT=.*$'
    - repl: 'HTTP_PORT={{ pillar["mailcow"]["HTTP_PORT"] }}'

mailcow_config_generator_http_bind:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *HTTP_BIND=.*$'
    - repl: 'HTTP_BIND={{ pillar["mailcow"]["HTTP_BIND"] }}'

mailcow_config_generator_https_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *HTTPS_PORT=.*$'
    - repl: 'HTTPS_PORT={{ pillar["mailcow"]["HTTPS_PORT"] }}'

mailcow_config_generator_https_bind:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *HTTPS_BIND=.*$'
    - repl: 'HTTPS_BIND={{ pillar["mailcow"]["HTTPS_BIND"] }}'

mailcow_config_generator_smtp_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *SMTP_PORT=.*$'
    - repl: 'SMTP_PORT={{ pillar["mailcow"]["SMTP_PORT"] }}'

mailcow_config_generator_smtps_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *SMTPS_PORT=.*$'
    - repl: 'SMTPS_PORT={{ pillar["mailcow"]["SMTPS_PORT"] }}'

mailcow_config_generator_imap_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *IMAP_PORT=.*$'
    - repl: 'IMAP_PORT={{ pillar["mailcow"]["IMAP_PORT"] }}'

mailcow_config_generator_imaps_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *IMAPS_PORT=.*$'
    - repl: 'IMAPS_PORT={{ pillar["mailcow"]["IMAPS_PORT"] }}'

mailcow_config_generator_pop_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *POP_PORT=.*$'
    - repl: 'POP_PORT={{ pillar["mailcow"]["POP_PORT"] }}'

mailcow_config_generator_pops_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *POPS_PORT=.*$'
    - repl: 'POPS_PORT={{ pillar["mailcow"]["POPS_PORT"] }}'

mailcow_config_generator_submission_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *SUBMISSION_PORT=.*$'
    - repl: 'SUBMISSION_PORT={{ pillar["mailcow"]["SUBMISSION_PORT"] }}'

mailcow_config_generator_acme_off:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh'
    - pattern: '^ *SKIP_LETS_ENCRYPT=.*$'
    - repl: 'SKIP_LETS_ENCRYPT={{ pillar["mailcow"]["SKIP_LETS_ENCRYPT"] }}'

mailcow_generate_config:
  cmd.run:
    - shell: /bin/bash
    - name: if [[ ! -e /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf ]]; then /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/generate_config.sh; fi
    - cwd: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/
    - env:
      - MAILCOW_HOSTNAME: {{ pillar["mailcow"]["servername"] }}
      - MAILCOW_TZ: {{ pillar["mailcow"]["MAILCOW_TZ"] }}

mailcow_config_http_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *HTTP_PORT=.*$'
    - repl: 'HTTP_PORT={{ pillar["mailcow"]["HTTP_PORT"] }}'

mailcow_config_http_bind:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *HTTP_BIND=.*$'
    - repl: 'HTTP_BIND={{ pillar["mailcow"]["HTTP_BIND"] }}'

mailcow_config_https_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *HTTPS_PORT=.*$'
    - repl: 'HTTPS_PORT={{ pillar["mailcow"]["HTTPS_PORT"] }}'

mailcow_config_https_bind:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *HTTPS_BIND=.*$'
    - repl: 'HTTPS_BIND={{ pillar["mailcow"]["HTTPS_BIND"] }}'

mailcow_config_smtp_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *SMTP_PORT=.*$'
    - repl: 'SMTP_PORT={{ pillar["mailcow"]["SMTP_PORT"] }}'

mailcow_config_smtps_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *SMTPS_PORT=.*$'
    - repl: 'SMTPS_PORT={{ pillar["mailcow"]["SMTPS_PORT"] }}'

mailcow_config_imap_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *IMAP_PORT=.*$'
    - repl: 'IMAP_PORT={{ pillar["mailcow"]["IMAP_PORT"] }}'

mailcow_config_imaps_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *IMAPS_PORT=.*$'
    - repl: 'IMAPS_PORT={{ pillar["mailcow"]["IMAPS_PORT"] }}'

mailcow_config_pop_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *POP_PORT=.*$'
    - repl: 'POP_PORT={{ pillar["mailcow"]["POP_PORT"] }}'

mailcow_config_pops_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *POPS_PORT=.*$'
    - repl: 'POPS_PORT={{ pillar["mailcow"]["POPS_PORT"] }}'

mailcow_config_submission_local_port:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *SUBMISSION_PORT=.*$'
    - repl: 'SUBMISSION_PORT={{ pillar["mailcow"]["SUBMISSION_PORT"] }}'

mailcow_config_acme_off:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *SKIP_LETS_ENCRYPT=.*$'
    - repl: 'SKIP_LETS_ENCRYPT={{ pillar["mailcow"]["SKIP_LETS_ENCRYPT"] }}'

mailcow_config_timezone:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/mailcow.conf'
    - pattern: '^ *MAILCOW_TZ=.*$'
    - repl: 'MAILCOW_TZ={{ pillar["mailcow"]["MAILCOW_TZ"] }}'

mailcow_data_dir_1:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/data
    - mode: 755
    - makedirs: True
mailcow_data_dir_2:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/mail_crypt
    - mode: 755
    - makedirs: True
mailcow_data_dir_3:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/opt/solr/server/solr/dovecot-fts/data
    - mode: 755
    - makedirs: True
mailcow_data_dir_4:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/sogo_web
    - mode: 755
    - makedirs: True
mailcow_data_dir_5:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/sogo_backup
    - mode: 755
    - makedirs: True
mailcow_data_dir_6:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/vmail_index
    - mode: 755
    - makedirs: True
mailcow_data_dir_7:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/vmail
    - mode: 755
    - makedirs: True
mailcow_data_dir_8:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/lib/rspamd
    - mode: 755
    - makedirs: True
mailcow_data_dir_9:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/lib/mysql
    - mode: 755
    - makedirs: True
mailcow_data_dir_10:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/spool/postfix
    - mode: 755
    - makedirs: True
mailcow_data_dir_11:
  file.directory:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/volumes/var/run/mysqld
    - mode: 755
    - makedirs: True

mailcow_docker_compose_owerride:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/docker-compose.override.yml
    - contents: |
        version: '2.1'
    {%- if "haproxy" in pillar["mailcow"] %}
        services:

            dovecot-mailcow:
              ports:
                - "${IMAP_PORT_HAPROXY:-127.0.0.1:10143}:10143"
                - "${IMAPS_PORT_HAPROXY:-127.0.0.1:10993}:10993"
                - "${POP_PORT_HAPROXY:-127.0.0.1:10110}:10110"
                - "${POPS_PORT_HAPROXY:-127.0.0.1:10995}:10995"
                - "${SIEVE_PORT_HAPROXY:-127.0.0.1:14190}:14190"

            postfix-mailcow:
              ports:
        #        - "${SMTP_PORT_HAPROXY:-127.0.0.1:10025}:10025"
                - "${SMTPS_PORT_HAPROXY:-127.0.0.1:10465}:10465"
                - "${SUBMISSION_PORT_HAPROXY:-127.0.0.1:10587}:10587"
                
    {%- endif %}
        volumes:
          vmail-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail'
          vmail-index-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/vmail_index'
          mysql-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/mysql'
          mysql-socket-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/run/mysqld'
          redis-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/data/'
          rspamd-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/lib/rspamd'
          solr-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/opt/solr/server/solr/dovecot-fts/data'
          postfix-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/var/spool/postfix'
          crypt-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/mail_crypt'
          sogo-web-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_web'
          sogo-userdata-backup-vol-1:
            driver: local
            driver_opts:
                type: 'none'
                o: 'bind'
                device: './volumes/sogo_backup'

  {% if pillar["mailcow"]["SKIP_LETS_ENCRYPT"] == 'y' %}

bind_ssl_certificate_for_services_in_docker:
  mount.mounted:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/cert.pem
    - device: /opt/acme/cert/{{ pillar["mailcow"]["servername"] }}/fullchain.cer
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

bind_ssl_key_for_services_in_docker:
  mount.mounted:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/key.pem
    - device: /opt/acme/cert/{{ pillar["mailcow"]["servername"] }}/{{ pillar["mailcow"]["servername"] }}.key
    - mkmnt: True
    - persist: True
    - fstype: none
    - opts: bind

create_script_rebind_ssl_for_services_in_docker:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/rebind-ssl-for-services.sh
    - mode: 0744
    - contents: |
        #!/bin/bash
        umount /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/cert.pem
        umount /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/key.pem
        mount --bind /opt/acme/cert/{{ pillar["mailcow"]["servername"] }}/fullchain.cer /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/cert.pem
        mount --bind /opt/acme/cert/{{ pillar["mailcow"]["servername"] }}/{{ pillar["mailcow"]["servername"] }}.key /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/assets/ssl/key.pem
        cd /opt/mailcow/{{ pillar["mailcow"]["servername"] }} && docker-compose restart
  {% endif %}
  {% if "haproxy" in pillar["mailcow"] %}

dovecote_extra_conf:
  file.managed:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/conf/dovecot/extra.conf
    - mode: 0644
    - contents: |
        haproxy_trusted_networks = 172.22.1.1

haproxy_reload:
  cmd.run:
    - shell: /bin/bash
    - name: service haproxy reload
  {% endif %}

rspamd_fishing_tank_enabled:
  file.replace:
    - name: '/opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/conf/rspamd/local.d/phishing.conf'
    - pattern: '^ *phishtank_enabled = .*$'
    - repl: 'phishtank_enabled = {{ pillar["mailcow"]["phishtank_enabled"] }};'

  {% if "drweb_milter_socket" in pillar["mailcow"] %}
postfix_smtpd_milters_drweb:
  file.replace:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/conf/postfix/extra.cf
    - pattern: '^ *smtpd_milters.*$'
    - repl: 'smtpd_milters = inet:rspamd:9900, {{ pillar["mailcow"]["drweb_milter_socket"] }}'
    - append_if_not_found: True

postfix_non_smtpd_milters_drweb:
  file.replace:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/data/conf/postfix/extra.cf
    - pattern: '^ *non_smtpd_milters.*$'
    - repl: 'non_smtpd_milters = $smtpd_milters'
    - append_if_not_found: True
  {% endif %}

mailcow_docker_compose_up:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}
    - name: cd /opt/mailcow/{{ pillar["mailcow"]["servername"] }} && docker-compose up -d

create_cron_rebind_ssl_for_services_in_docker:
  cron.present:
    - name: /opt/mailcow/{{ pillar["mailcow"]["servername"] }}/rebind-ssl-for-services.sh
    - identifier: rebind_ssl_certificates_for_services_in_docker
    - user: root
    - minute: 0
    - hour: 4

nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload
nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
{% endif %}
