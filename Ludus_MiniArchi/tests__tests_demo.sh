#!/bin/bash
# Tests de demonstration - maquette Ludus (a lancer sur l'hote Proxmox, en root)
# Usage : bash tests_demo.sh        (pause entre chaque test)
#         bash tests_demo.sh auto   (enchaine sans pause)

C1=104; C2=105; API=106; DB=107
MM_IP=10.1.10.10; API_IP=10.1.10.20; DB_IP=10.1.30.10

# Execute une commande dans une VM et affiche out-data (+ err-data) lisiblement
run() {
  local id=$1; shift
  qm guest exec "$id" -- "$@" 2>&1 | python3 -c '
import sys, json
raw = sys.stdin.read()
try:
    d = json.loads(raw)
    sys.stdout.write(d.get("out-data", "") + d.get("err-data", ""))
except Exception:
    sys.stdout.write(raw)
'
}

titre() { echo; echo "=================================================="; echo "$1"; echo "=================================================="; }
attendu() { echo ">> Attendu : $1"; }
pause() { [ "$1" = "auto" ] || read -rp "[Entree pour continuer] " _; }

# Securite : quoi qu'il arrive, on relance PostgreSQL a la sortie
trap 'qm guest exec $DB -- systemctl start postgresql >/dev/null 2>&1' EXIT

MODE=$1

titre "TEST 1 - Mattermost depuis les deux clients (LAN -> DMZ)"
attendu "200 et 200"
echo -n "client-1 : "; run $C1 curl -s -o /dev/null -w "%{http_code}\n" http://$MM_IP:8065
echo -n "client-2 : "; run $C2 curl -s -o /dev/null -w "%{http_code}\n" http://$MM_IP:8065
pause $MODE

titre "TEST 2 - Chaine client -> API -> base"
attendu "API01 OK - 50 clients lus depuis DB01"
run $C1 curl -s http://$API_IP/
pause $MODE

titre "TEST 3 - Segmentation : le client ne joint pas la base"
attendu "REFUSE"
run $C1 bash -c "timeout 3 bash -c '</dev/tcp/$DB_IP/5432' && echo OUVERT || echo REFUSE"
pause $MODE

titre "TEST 4 - Filtrage inter-VLAN"
attendu "ping refuse, SSH REFUSE, Mattermost OUVERT"
echo "--- ping (ICMP non autorise) ---"
run $C1 ping -c 2 -W 2 $MM_IP
echo "--- SSH (TCP 22) ---"
run $C1 bash -c "timeout 3 bash -c '</dev/tcp/$MM_IP/22' && echo OUVERT || echo REFUSE"
echo "--- Mattermost (TCP 8065) ---"
run $C1 bash -c "timeout 3 bash -c '</dev/tcp/$MM_IP/8065' && echo OUVERT || echo REFUSE"
pause $MODE

titre "TEST 5 - Panne simulee de PostgreSQL"
echo "Arret de PostgreSQL sur DB01..."
run $DB systemctl stop postgresql
sleep 2
attendu "HTTP/1.1 500 + erreur base de donnees"
run $C1 curl -s -i http://$API_IP/
pause $MODE

echo
echo "Remise en route de PostgreSQL..."
run $DB systemctl start postgresql
sleep 4
attendu "API01 OK - 50 clients lus depuis DB01"
run $C1 curl -s http://$API_IP/

titre "FIN DES TESTS"
