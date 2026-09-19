# infra/ — OpenTofu (provider bpg/proxmox)

Attendu au jalon PB.2 :

- `versions.tf`, `providers.tf`, `variables.tf`, `main.tf`, `cloud-init.tf`,
  `inventory.tf`, `outputs.tf`
- `templates/user-data.yaml.tftpl`, `templates/inventory.ini.tftpl`
- `envs/staging.tfvars`, `envs/prod.tfvars`, `envs/k3s.tfvars`
- un workspace par environnement : `tofu workspace new staging`

`monitoring/` (PB.8) contient la stack Prometheus/Alertmanager/Grafana/Loki
déployée sur lab-ops.
