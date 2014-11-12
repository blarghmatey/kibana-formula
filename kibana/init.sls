{% from "kibana/map.jinja" import kibana with context %}

{% set kibana_version = salt['pillar.get']('kibana:version', '3.1.2') %}
{% set elasticsearch_port = salt['pillar.get']('elasticsearch:port', 9200) %}
{% set elasticsearch_nodes = [] %}
{% for id, ip_addrs in salt['mine.get']('roles:elasticsearch', 'network.ip_addrs', expr_form='grain').items() %}
  {% do elasticsearch_nodes.append({'id': id, 'host': '{0}:{1}'.format(ip_addrs[0], elasticsearch_port)}) %}
{% endfor %}
{% set kibana_users = salt['pillar.get']('kibana:users', []) %}
{% set use_ssl = salt['pillar.get']('kibana:use_ssl', True) %}

include:
  - nginx

target_dir:
  file.directory:
    - name: /var/www
    - makedirs: True
    - user: http
    - group: http
    - recurse:
        - user
        - group

kibana_src:
  cmd.run:
    - name: wget https://download.elasticsearch.org/kibana/kibana/kibana-{{ kibana_version }}.tar.gz
    - unless: ls /var/www/ | grep -i kibana | wc -l
    - cwd: /var/www
    - require:
        - file: target_dir

unpack_kibana:
  cmd.run:
    - name: tar -xvzf kibana-{{ kibana-version }}.tar.gz
    - unless: ls /var/www/ | grep -i kibana | grep -v tar.gz | wc -l
    - cwd: /var/www
    - require:
        - cmd: kibana_src

{% for user in kibana_users %}
kibana_htpasswd_{{ user.name }}:
  htpasswd.user_exists:
    - name: {{ user.name }}
    - passwd: {{ user.password }}
    - htpasswd_file: /etc/nginx/kibana.htpasswd
    - options: s
{% endfor %}

{% if use_ssl %}
kibana_ssl_cert:
  file.managed:
    - name: /etc/nginx/ssl/kibana_ssl.crt
    - contents_pillar: kibana:ssl_cert
    - makedirs: True

kibana_ssl_key:
  file.managed:
    - name: /etc/nginx/ssl/kibana_ssl.key
    - contents_pillar: kibana:ssl_key
    - makedirs: True
{% endif %}

nginx_kibana_config:
  file.managed:
    - name: /etc/nginx/sites-available/kibana
    - src: salt://kibana/files/nginx.conf
    - template: jinja
    - context:
        elasticsearch_nodes: {{ elasticsearch_nodes }}
        kibana_version: {{ kibana_version }}

enable_nginx_kibana_config:
  file.symlink:
    - name: /etc/nginx/sites-enabled/kibana
    - target: /etc/nginx/sites-available/kibana
    - require:
        - file: nginx_config

nginx_kibana_service:
  service.running:
    - enable: True
    - name: nginx
    - watch:
        - file: nginx_config