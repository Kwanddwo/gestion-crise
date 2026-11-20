# Compte rendu : maquette Ludus sur Proxmox

Mise en place d'une infrastructure de démonstration avec **Ludus** sur **Proxmox** : réseau social d'entreprise (Mattermost), API et base de données, segmentation réseau en trois zones.

*Date : 19 novembre 2026*

---

## 1. Objectifs

- Prendre en main Ludus (templates, ranges, rôles Ansible, règles réseau).
- Déployer un serveur Mattermost et deux clients Linux de façon reproductible.
- Déployer une chaîne applicative minimale : **client → API → base de données**.
- Segmenter le réseau en trois VLAN et ne laisser passer que le trafic nécessaire.
- Valider le tout par des tests avant/après filtrage, y compris une panne simulée.

Cette maquette est une version **partielle** de l'architecture v2 du projet (voir section 8).

---

## 2. Architecture réalisée

### Principe de Ludus

| Notion | Rôle |
|---|---|
| **Template** | VM modèle construite une seule fois avec Packer, puis clonée |
| **Range** | Ensemble isolé de machines et réseaux (ici : ID `AD`, réseau `10.1.0.0/16`) |
| **Routeur** | Déployé automatiquement par Ludus : routage inter-VLAN, sortie Internet, filtrage |
| **Rôle Ansible** | Tâches appliquées à une VM après sa création |

### Plan d'adressage

| Machine | ID Proxmox | IP | VLAN | Rôle |
|---|---|---|---|---|
| AD-router-debian13-x64 | 102 | 10.1.10.254 | - | Routeur et pare-feu |
| AD-mattermost | 103 | 10.1.10.10 | 10 (DMZ) | Serveur Mattermost (port 8065) |
| AD-client-1 | 104 | 10.1.20.11 | 20 (LAN) | Client Linux |
| AD-client-2 | 105 | 10.1.20.12 | 20 (LAN) | Client Linux |
| AD-api01 | 106 | 10.1.10.20 | 10 (DMZ) | API (nginx + Python) |
| AD-db01 | 107 | 10.1.30.10 | 30 (SRV) | PostgreSQL |

Le routeur porte l'adresse `.254` de chaque VLAN. Format des adresses : `10.<n° range>.<VLAN>.<dernier octet>`.

```
                    Internet
                       |
              Routeur Ludus (.254)
        ┌──────────────┼───────────────┐
   VLAN 10 (DMZ)   VLAN 20 (LAN)   VLAN 30 (SRV)
   mattermost      client-1        db01
   api01           client-2
```

---

## 3. Démarche de mise en œuvre

1. **Installation de Ludus** sur l'hôte Proxmox, puis correction de la configuration (voir section 6).
2. **Construction des templates** : `debian-12-x64-server-template` (toutes les VM) et `debian-13-x64-server-template` (routeur Ludus).
3. **Description de la range** dans `config.yml`, envoyée avec `ludus range config set -f config.yml`, déployée avec `ludus range deploy`.
4. **Vérification du réseau** avant toute application : adresses, routage inter-VLAN (TTL 63 entre VLAN contre 64 dans le même VLAN), accès Internet.
5. **Installation de Mattermost** via le rôle `local_mattermost` (Docker, image `mattermost/mattermost-preview`).
6. **Extension** : rôles `local_postgres` (DB01) et `local_api` (API01), ajout du VLAN 30.
7. **Segmentation** : règles inter-VLAN appliquées avec `ludus range deploy -t network`.
8. **Tests** : avant/après filtrage, chaîne API → base, panne simulée.

Commandes utiles :

```bash
ludus ansible role add -d ./roles/local_mattermost --force
ludus ansible role add -d ./roles/local_postgres --force
ludus ansible role add -d ./roles/local_api --force
ludus range config set -f config.yml
ludus range deploy
ludus range deploy -t user-defined-roles   # rejoue uniquement les rôles
ludus range deploy -t network              # applique uniquement les règles réseau
```

---

## 4. Rôles Ansible

| Rôle | VM | Contenu |
|---|---|---|
| `local_mattermost` | AD-mattermost | Installe prérequis et Docker, lance Mattermost en conteneur (idempotent : ne recrée le conteneur que s'il ne tourne pas) |
| `local_postgres` | AD-db01 | Installe PostgreSQL, écoute sur `10.1.30.10`, autorise uniquement `10.1.10.20/32` via `pg_hba.conf`, crée le rôle, la base `mobilite` et 50 clients fictifs |
| `local_api` | AD-api01 | Installe nginx, Python et psycopg2 ; application Python sur `127.0.0.1:5000` derrière nginx (port 80), lancée par un service systemd |

Chaque rôle contient `meta/main.yml` (exigé par Ludus), `tasks/main.yml` et un dossier `files/` pour les fichiers copiés sur la VM.

L'API renvoie `API01 OK - N clients lus depuis DB01` (HTTP 200) ou un message d'erreur (HTTP 500) si la base est injoignable.

---

## 5. Segmentation et filtrage

**Principe** : moindre privilège. Tout trafic inter-VLAN est refusé par défaut (`REJECT`), puis on autorise le strict nécessaire. La sortie Internet reste ouverte.

| Règle | Source | Destination | Protocole / port |
|---|---|---|---|
| Clients vers Mattermost | VLAN 20 | VLAN 10 | TCP 8065 |
| Clients vers API | VLAN 20 | VLAN 10 | TCP 80 |
| API01 vers PostgreSQL | VLAN 10 | VLAN 30 | TCP 5432 |

Ludus refuse aussi tout trafic de la range vers l'hôte Proxmox, ce qui protège l'hyperviseur.

La restriction à la seule adresse d'API01 est assurée côté base par `pg_hba.conf` (défense en profondeur).

---

## 6. Tests réalisés

Les tests sont lancés depuis l'hôte Proxmox avec `qm guest exec` (agent QEMU), sans SSH ni VPN. Le script `tests/tests_demo.sh` les enchaîne.

| Test | Résultat | Ce que cela démontre |
|---|---|---|
| Client → Mattermost (TCP 8065) | HTTP 200 | flux LAN → DMZ autorisé |
| Client → API (`curl http://10.1.10.20/`) | `API01 OK - 50 clients lus depuis DB01` | LAN → DMZ autorisé et DMZ → SRV fonctionnel |
| Client → DB01 (TCP 5432) | refusé (`Connection refused`) | un poste du LAN ne joint pas la base |
| Client → Mattermost en SSH (TCP 22) | refusé | refus par défaut |
| Ping client → Mattermost | refusé (`Destination Port Unreachable`) | ICMP non autorisé |
| Arrêt de PostgreSQL puis requête API | HTTP 500, retour à `API01 OK` après redémarrage | une panne de la base est visible côté API |

Le refus est immédiat (et non un timeout) car l'action est `REJECT` : le routeur répond, alors qu'un `DROP` aurait fait disparaître le paquet.

**Démonstration Mattermost** : création de deux comptes (`alice`, `bob`) avec `mmctl` en mode local, puis publication d'un message depuis chaque client via l'API REST. La lecture du canal depuis le client 2 renvoie les deux messages, y compris celui émis depuis l'autre machine.

---

## 7. Difficultés rencontrées

| Symptôme | Cause | Correction |
|---|---|---|
| Services Ludus en redémarrage permanent (*encryption key must be 32 characters long*) | `database_encryption_key` vide | Clé de 32 caractères (`openssl rand -hex 16`) |
| *unsupported protocol scheme* au démarrage de `ludus-admin` | `proxmox_url` vide | URL de l'API Proxmox (port 8006), `proxmox_invalid_cert: true` |
| *attempt to write a readonly database* | Fichiers de base créés par `root`, service sous l'utilisateur `ludus` | `chown -R ludus:ludus` sur le dossier de la base |
| Build de template en quelques millisecondes | `proxmox_node` incorrect | Nom réel du nœud Proxmox |
| Déploiement : expiration de connexion vers l'hôte | `proxmox_hostname` incorrect | Nom réel de la machine |
| *template debian-13 does not exist* | Le routeur Ludus utilise Debian 13 | Construction du template `debian-13-x64-server-template` |
| Docker : *x509: certificate signed by unknown authority* | `ca-certificates` absent | Installation dans le rôle, redémarrage de Docker |
| *socket file ... doesn't exist* avec `mmctl --local` | Mode local désactivé par défaut | `MM_SERVICESETTINGS_ENABLELOCALMODE=true` au lancement du conteneur |
| Docker : *apparmor_parser not found* | Outil AppArmor absent | Installation du paquet `apparmor` |
| `ludus ansible role add` : *no meta/main.yml* | Un rôle Ludus doit suivre la structure Galaxy | Ajout d'un `meta/main.yml` minimal |
| Fichiers de rôle corrompus par un collage long | Blocs imbriqués fusionnés à la saisie | Contenu déplacé dans `files/`, relecture avec `cat` |
| Configuration de la range tronquée | Mauvais `head -n` | Contrôle avec `tail` et `grep -c vm_name` |

**Leçons** : lire le message exact des journaux avant de corriger ; préférer des fichiers dans `files/` plutôt que du texte imbriqué dans du YAML ; vérifier que le conteneur *tourne* réellement (et pas seulement qu'il existe) pour rendre un rôle rejouable.

---

## 8. Conclusion

Une maquette reproductible de six machines sur trois zones (DMZ, LAN, SRV) a été déployée avec Ludus. Le routage inter-VLAN fonctionne et le filtrage se limite au nécessaire : les clients n'atteignent que Mattermost et l'API, et seule la DMZ interroge la base. L'API lit bien les 50 clients, un client ne peut pas joindre la base directement, et l'arrêt de PostgreSQL provoque une erreur 500 visible côté API. L'ensemble étant décrit sous forme de code (YAML et rôles Ansible), il peut être détruit et reconstruit à l'identique, et servira de base à l'ajout progressif des briques prévues.
