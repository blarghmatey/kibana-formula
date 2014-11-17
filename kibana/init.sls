{% from "kibana/map.jinja" import kibana with context %}

{% set kibana_version = salt['pillar.get']('kibana:version', '3.1.2') %}
{% set elasticsearch_port = salt['pillar.get']('elasticsearch:port', 9200) %}
{% set elasticsearch_nodes = [] %}
{% for id, ip_addrs in salt['mine.get']('roles:elasticsearch', 'network.ip_addrs', expr_form='grain').items() %}
  {% do elasticsearch_nodes.append({'id': id, 'host': '{0}:{1}'.format(ip_addrs[0], elasticsearch_port)}) %}
{% endfor %}
{% set kibana_users = salt['pillar.get']('kibana:users', []) %}
{% set use_ssl = salt['pillar.get']('kibana:use_ssl', True) %}
{% if use_ssl %}
{% set upstream_protocol = 'https' %}
{% else %}
{% set upstream_protocol = 'http' %}
{% endif %}

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
    - unless: test -f /var/www/kibana-{{ kibana_version}}.tar.gz
    - cwd: /var/www
    - user: http
    - require:
        - file: target_dir

unpack_kibana:
  cmd.run:
    - name: tar -xvzf kibana-{{ kibana_version }}.tar.gz
    - unless: test -d /var/www/kibana-{{ kibana_version}}/
    - cwd: /var/www
    - user: http
    - require:
        - cmd: kibana_src

kibana_config_elasticsearch_host:
  file.replace:
    - name: /var/www/kibana-{{ kibana_version }}/config.js
    - pattern: 'elasticsearch: "http:\/\/".*?$'
    - repl: 'elasticsearch: {server: "{{ upstream_protocol }}://"+window.location.hostname, withCredentials: true},'

{% for user in kibana_users %}
kibana_htpasswd_{{ user.name }}:
  webutil.user_exists:
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
    - source: salt://kibana/files/nginx.conf
    - template: jinja
    - context:
        elasticsearch_nodes: {{ elasticsearch_nodes }}
        kibana_version: {{ kibana_version }}
        use_ssl: {{ use_ssl }}

enable_nginx_kibana_config:
  file.symlink:
    - name: /etc/nginx/sites-enabled/kibana
    - target: /etc/nginx/sites-available/kibana
    - require:
        - file: nginx_kibana_config

nginx_kibana_service:
  service.running:
    - enable: True
    - name: nginx
    - watch:
        - file: nginx_kibana_config
