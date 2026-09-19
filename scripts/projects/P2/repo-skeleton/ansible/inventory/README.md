`staging.ini`, `prod.ini` et `k3s.ini` sont GÉNÉRÉS par OpenTofu (PB.2) et
ignorés par git. `ops.ini` (lab-ops, monitoring, sauvegardes) est statique
et versionné. Les `group_vars/` sont versionnés ; `vault.yml` est chiffré.
