Un fichier `<workspace>.tfvars` par environnement. Ne jamais y mettre le
token Proxmox : il vient de `TF_VAR_pve_api_token` (ou de terraform.tfvars,
ignoré par git).
