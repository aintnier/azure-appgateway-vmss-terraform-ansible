#!/bin/bash
# ============================================================================
# Cloud-Init Bootstrap Script - VMSS Instance Configuration
# Installs Ansible, writes config files, and executes the playbook
# in local-pull mode. Rendered by Terraform templatefile().
# ============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[cloud-init] Starting bootstrap for role: ${server_role}"

# ---
# 1. Install Ansible
# ---
apt-get update -y
apt-get install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible

# ---
# 2. Create config directory structure
# ---
mkdir -p /opt/config/templates

# ---
# 3. Write ansible.cfg
# ---
cat > /opt/config/ansible.cfg << 'ANSIBLE_CFG'
[defaults]
connection          = local
host_key_checking   = False
retry_files_enabled = False
gathering           = smart
fact_caching        = memory
stdout_callback     = yaml
ANSIBLE_CFG

# ---
# 4. Write playbook.yml
# ---
cat > /opt/config/playbook.yml << 'PLAYBOOK'
---
- name: Configure web server (Local Pull)
  hosts: localhost
  connection: local
  become: true

  vars:
    server_role: "frontend"
    backend_lb_ip: "10.0.3.10"

  tasks:
    - name: Install Nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true

    - name: Remove default Nginx site symlink
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent

    - name: Deploy root index page
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /var/www/html/index.html
        mode: "0644"

    - name: Create API directory
      ansible.builtin.file:
        path: /var/www/api
        state: directory
        mode: "0755"
      when: server_role == "backend"

    - name: Deploy API page
      ansible.builtin.template:
        src: templates/api.html.j2
        dest: /var/www/api/index.html
        mode: "0644"
      when: server_role == "backend"

    - name: Deploy Nginx config (frontend)
      ansible.builtin.template:
        src: templates/nginx-frontend.conf.j2
        dest: /etc/nginx/sites-available/default
        mode: "0644"
      when: server_role == "frontend"
      notify: Restart Nginx

    - name: Deploy Nginx config (backend)
      ansible.builtin.template:
        src: templates/nginx-backend.conf.j2
        dest: /etc/nginx/sites-available/default
        mode: "0644"
      when: server_role == "backend"
      notify: Restart Nginx

    - name: Enable Nginx site
      ansible.builtin.file:
        src: /etc/nginx/sites-available/default
        dest: /etc/nginx/sites-enabled/default
        state: link
      notify: Restart Nginx

    - name: Enable and start Nginx
      ansible.builtin.systemd:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Restart Nginx
      ansible.builtin.systemd:
        name: nginx
        state: restarted
PLAYBOOK

# ---
# 5. Write Jinja2 templates
# ---

cat > /opt/config/templates/index.html.j2 << 'INDEX_TPL'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"><title>Frontend Web Tier</title>
  <style>body{font-family:'Segoe UI',sans-serif;background:#1a1a2e;color:#eaeaea;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}.card{background:#16213e;border:1px solid #0f3460;border-radius:12px;padding:2rem 3rem;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.4)}h1{color:#e94560;margin-bottom:.5rem}.hostname{font-size:1.4rem;color:#53d8fb}.tier{color:#8a8a8a;font-size:.9rem;margin-top:1rem}</style>
</head>
<body>
  <div class="card">
    <h1>Frontend Web Tier</h1>
    <p class="hostname">Hostname: <strong>{{ ansible_hostname }}</strong></p>
    <p class="tier">Layer: VMSS Frontend &mdash; served by Nginx</p>
  </div>
</body>
</html>
INDEX_TPL

cat > /opt/config/templates/api.html.j2 << 'API_TPL'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"><title>Backend API Tier</title>
  <style>body{font-family:'Segoe UI',sans-serif;background:#0a0a23;color:#eaeaea;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}.card{background:#1b1b3a;border:1px solid #3a3a5c;border-radius:12px;padding:2rem 3rem;text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.5)}h1{color:#43b581;margin-bottom:.5rem}.hostname{font-size:1.4rem;color:#faa61a}.tier{color:#8a8a8a;font-size:.9rem;margin-top:1rem}pre{background:#0d0d1a;padding:1rem;border-radius:8px;text-align:left;color:#53d8fb;overflow-x:auto}</style>
</head>
<body>
  <div class="card">
    <h1>Backend API Tier</h1>
    <p class="hostname">Hostname: <strong>{{ ansible_hostname }}</strong></p>
    <p class="tier">Layer: VMSS Backend &mdash; API endpoint</p>
    <pre>{"status":"ok","tier":"backend","hostname":"{{ ansible_hostname }}","path":"/api"}</pre>
  </div>
</body>
</html>
API_TPL

cat > /opt/config/templates/nginx-frontend.conf.j2 << 'NGINX_FE'
server {
    listen 80 default_server;
    server_name _;
    location / {
        root /var/www/html;
        index index.html;
    }
    location /api {
        proxy_pass http://{{ backend_lb_ip }}/api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 10s;
    }
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }
}
NGINX_FE

cat > /opt/config/templates/nginx-backend.conf.j2 << 'NGINX_BE'
server {
    listen 80 default_server;
    server_name _;
    location / {
        root /var/www/html;
        index index.html;
    }
    location /api {
        alias /var/www/api;
        index index.html;
    }
    location /health {
        access_log off;
        return 200 'healthy';
        add_header Content-Type text/plain;
    }
}
NGINX_BE

# ---
# 6. Execute Ansible playbook in local-pull mode
# ---
echo "[cloud-init] Running ansible-playbook for role: ${server_role}"
cd /opt/config
ansible-playbook -c local playbook.yml \
  --extra-vars "server_role=${server_role} backend_lb_ip=${backend_lb_ip}"

echo "[cloud-init] Bootstrap complete for role: ${server_role}"
