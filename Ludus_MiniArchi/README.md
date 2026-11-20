# Maquette Ludus : Mattermost, API et base de données

Maquette reproductible sur Proxmox avec Ludus : 6 machines, 3 VLAN
(DMZ 10, LAN 20, SRV 30), filtrage inter-VLAN en refus par défaut.

## Contenu
- `config.yml` : description de la range (machines, VLAN, règles réseau)
- `roles/` : rôles Ansible (`local_mattermost`, `local_postgres`, `local_api`)
- `tests/tests_demo.sh` : script de tests de démonstration (à lancer sur l'hôte Proxmox)

## Déploiement
```bash
ludus ansible role add -d ./roles/local_mattermost --force
ludus ansible role add -d ./roles/local_postgres --force
ludus ansible role add -d ./roles/local_api --force
ludus range config set -f config.yml
ludus range deploy
```

## Tests
```bash
bash tests/tests_demo.sh
```

Les mots de passe présents sont des valeurs de laboratoire uniquement.
