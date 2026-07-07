#!/bin/sh

# Commande à utiliser pour exécuter le script 
# sh ./deploy_openwrt-v1_21.sh | tee -a /root/deploy.log

# =========================================================
#  SCRIPT DE DÉPLOIEMENT OPENWRT
#  Version: 1.21
# =========================================================

# =========================================================
#  FONCTIONS UTILITAIRES
# =========================================================

ask_confirm() {
    LABEL="$1"
    VAR_TARGET="$2"
    while true; do
        read -p "$LABEL : " _INPUT
        read -p "   -> Confirmer \"$_INPUT\" ? (y/n) " _CONFIRM
        case "$_CONFIRM" in
            [yY][eE][sS]|[yY])
                eval "$VAR_TARGET=\"$_INPUT\""
                break
                ;;
            *)
                echo "   -> Saisie annulée, recommencez."
                ;;
        esac
    done
}

ask_ip() {
    LABEL="$1"
    VAR_TARGET="$2"
    while true; do
        read -p "$LABEL : " _IP
        _VALID=$(echo "$_IP" | awk -F'.' '
            NF==4 &&
            $1>=0 && $1<=255 &&
            $2>=0 && $2<=255 &&
            $3>=0 && $3<=255 &&
            $4>=0 && $4<=255 {print "ok"}')
        if [ "$_VALID" != "ok" ]; then
            echo "   -> Format IP invalide. Exemple attendu : 192.168.1.1"
            continue
        fi
        read -p "   -> Confirmer \"$_IP\" ? (y/n) " _CONFIRM
        case "$_CONFIRM" in
            [yY][eE][sS]|[yY])
                eval "$VAR_TARGET=\"$_IP\""
                break
                ;;
            *)
                echo "   -> Saisie annulée, recommencez."
                ;;
        esac
    done
}

# =========================================================

echo ">>> ÉTAPE 1 — Préparation de l'environnement..."
echo ""

mkdir -p /etc/profile.d

if ! grep -q "profile.d" /etc/profile; then
    echo 'for i in /etc/profile.d/*.sh; do [ -r "$i" ] && . "$i"; done' >> /etc/profile
fi

LOGFILE="/root/deploy_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"
echo "Déploiement démarré le $(date)" | tee -a "$LOGFILE"

echo ""
echo ">>> ÉTAPE 2 — Sauvegarde de la configuration actuelle..."
echo ""

BACKUP_DIR="/root/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [ -d /etc/config ]; then
    cp -r /etc/config "$BACKUP_DIR/"
    echo "   -> Configuration sauvegardée dans $BACKUP_DIR"
else
    echo "   -> Aucune configuration à sauvegarder"
fi

echo ""
echo ">>> ÉTAPE 3 - Mise à jour du serveur de temps..."
echo ""

# Configuration NTP
uci -q delete system.ntp.server
uci add_list system.ntp.server="0.fr.pool.ntp.org"
uci add_list system.ntp.server="1.fr.pool.ntp.org"
uci add_list system.ntp.server="2.fr.pool.ntp.org"
uci add_list system.ntp.server="3.fr.pool.ntp.org"
uci set system.ntp.enable_server='0'
uci set system.ntp.enabled='1'
uci set system.@system[0].timezone='CET-1CEST,M3.5.0,M10.5.0/3'
uci set system.@system[0].zonename='Europe/Paris'
uci commit system

ntpd -q -n -p 0.fr.pool.ntp.org
/etc/init.d/sysntpd start
echo "CET-1CEST,M3.5.0,M10.5.0/3" > /etc/TZ
/etc/init.d/system reload

echo ""
echo ">>> ÉTAPE 4 — Mise à jour de la liste des paquets OPKG..."
echo ""

if opkg update; then
    echo "   -> Liste des paquets mise à jour avec succès"
else
    echo "   -> ERREUR lors de la mise à jour OPKG"
    echo "   -> Vérifiez la connexion Internet"
    read -p "Continuer malgré l'erreur ? (y/n) " CONTINUE
    case "$CONTINUE" in
        [yY][eE][sS]|[yY]) ;;
        *) exit 1 ;;
    esac
fi

# Installation des paquets qui seront utilisés
PACKAGES="vim-full curl htop isc-dhcp-relay-ipv4 tcpdump"
echo "   Paquets à installer : $PACKAGES"
echo ""

INSTALL_FAILED=""
for pkg in $PACKAGES; do
    echo "   -> Installation de $pkg..."
    if opkg install "$pkg"; then
        echo "      ✓ $pkg installé avec succès"
    else
        echo "      ✗ ERREUR lors de l'installation de $pkg"
        INSTALL_FAILED="$INSTALL_FAILED $pkg"
    fi
done

if [ -n "$INSTALL_FAILED" ]; then
    echo ""
    echo "ATTENTION : Les paquets suivants n'ont pas pu être installés :$INSTALL_FAILED"
    echo ""
    read -p "Continuer malgré ces erreurs ? (y/n) " CONTINUE
    case "$CONTINUE" in
        [yY][eE][sS]|[yY]) ;;
        *) exit 1 ;;
    esac
fi

# --- Configuration de Vim ---
echo ""
echo "   -> Configuration de Vim..."
cat << 'EOFVIM' > /root/.vimrc
" Configuration de base pour Vim sous OpenWrt
syntax on           " Active la coloration syntaxique
set number          " Affiche les numéros de ligne
set autoindent      " Indentation automatique
set tabstop=4       " Taille d'une tabulation (4 espaces)
set shiftwidth=4    " Taille de l'indentation
set expandtab       " Remplace les tabulations par des espaces
set hlsearch        " Surligne les résultats de recherche
set incsearch       " Recherche incrémentale
set background=dark " Optimise les couleurs pour un terminal sombre
EOFVIM
echo "      ✓ /root/.vimrc généré avec succès"

echo ""
echo "Installation terminée, début de la configuration..."
sleep 2

echo ""
echo ">>> ÉTAPE 5 — Saisie des paramètres..."
echo ""

echo "Définition du port SSH distant (WAN)..."
echo ""
ask_confirm "Veuillez indiquer le numéro de port SSH" SSH_WAN_PORT

echo ""
echo ">>> ÉTAPE 6 — Configuration système..."
echo ""

# Récupération du 4ème octet de l'IP WAN
WAN_IP=$(uci -q get network.wan.ipaddr)
if [ -z "$WAN_IP" ] && command -v jsonfilter > /dev/null 2>&1; then
    WAN_IP=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@["ipv4-address"][0].address')
fi

if [ -z "$WAN_IP" ]; then
    echo "   -> IP WAN non détectée automatiquement."
    ask_ip "Veuillez saisir l'adresse IP WAN manuellement" WAN_IP
fi
OCTET_4=$(echo "$WAN_IP" | cut -d'.' -f4)
echo "   -> IP WAN détectée : $WAN_IP (octet 4 : $OCTET_4)"

# Configuration du Hostname
echo ""
echo ">>> Définition du Hostname..."
echo ""
ask_confirm "Veuillez indiquer le numéro du routeur" RTR_NUM
uci set system.@system[0].hostname="RTR-BBH-${OCTET_4}-${RTR_NUM}"
uci commit system
/etc/init.d/system reload

# Mot de passe Root
echo ""
echo ">>> Définition du nouveau mot de passe ROOT..."
echo ""
read -s -p "Veuillez saisir le mot de passe root : " ROOT_PW
echo ""
read -s -p "Confirmez le mot de passe root : " ROOT_PW2

if [ "$ROOT_PW" != "$ROOT_PW2" ]; then
    echo "   -> ERREUR : Les mots de passe ne correspondent pas. Abandon."
    exit 1
fi

printf "%s\n%s\n" "$ROOT_PW" "$ROOT_PW" | passwd root
unset ROOT_PW ROOT_PW2

echo ""
echo ">>> ÉTAPE 7 — Configuration des devices..."
echo ""

uci -q delete network.lan
uci -q delete network.wan6

# Suppression des devices existants par index decroissant (idempotence)
# Si le script a déjà été lance, les devices br-lan1/br-lan2/br-wlan existent
# déjà -- on les supprime tous avant de les recréer proprement
echo "   -> Nettoyage des devices existants..."
idx=0
while uci -q get network.@device[$idx] > /dev/null; do
    idx=$((idx + 1))
done
while [ $idx -gt 0 ]; do
    idx=$((idx - 1))
    dev_name=$(uci -q get network.@device[$idx].name)
    echo "      Suppression device[$idx] : $dev_name"
    uci delete network.@device[$idx]
done

# br-lan1 : lan + lan2
echo "   -> Creation br-lan1 (lan1 + lan2)"
uci add network device
uci set network.@device[-1].name='br-lan1'
uci set network.@device[-1].type='bridge'
uci add_list network.@device[-1].ports='lan1'
uci add_list network.@device[-1].ports='lan2'

# br-lan2 : lan3 + lan4
echo "   -> Creation br-lan2 (lan3 + lan4)"
uci add network device
uci set network.@device[-1].name='br-lan2'
uci set network.@device[-1].type='bridge'
uci add_list network.@device[-1].ports='lan3'
uci add_list network.@device[-1].ports='lan4'

# br-wlan : WiFi (sans port physique)
echo "   -> Creation br-wlan (WiFi)"
uci add network device
uci set network.@device[-1].name='br-wlan'
uci set network.@device[-1].type='bridge'

echo ""
echo ">>> ÉTAPE 8 — Configuration des interfaces..."
echo ""

# Suppression des interfaces existantes (idempotence)
# lan1, lan2, wlan peuvent déjà exister si le script a déjà ete lance
echo "   -> Nettoyage des interfaces existantes..."
for iface in lan1 lan2 wlan; do
    if uci -q get network.$iface > /dev/null; then
        echo "      Suppression interface : $iface"
        uci delete network.$iface
    fi
done

# LAN 1
echo ""
echo ">>> Configuration du LAN 1"
echo ""
uci set network.lan1=interface
uci set network.lan1.proto='static'
uci set network.lan1.device='br-lan1'
ask_ip "Veuillez saisir l'adresse IP pour le LAN 1" LAN1
ask_ip "Veuillez saisir le masque de sous-reseau (netmask) pour le LAN 1" NETMASK1
uci set network.lan1.ipaddr="$LAN1"
uci set network.lan1.netmask="$NETMASK1"

# LAN 2
echo ""
echo ">>> Configuration du LAN 2"
echo ""
uci set network.lan2=interface
uci set network.lan2.proto='static'
uci set network.lan2.device='br-lan2'
ask_ip "Veuillez saisir l'adresse IP pour le LAN 2" LAN2
ask_ip "Veuillez saisir le masque de sous-reseau (netmask) pour le LAN 2" NETMASK2
uci set network.lan2.ipaddr="$LAN2"
uci set network.lan2.netmask="$NETMASK2"

# WLAN
echo ""
echo ">>> Configuration du WLAN (WiFi)"
echo ""
uci set network.wlan=interface
uci set network.wlan.device='br-wlan'
uci set network.wlan.proto='static'
ask_ip "Veuillez saisir l'adresse IP pour le WLAN" WLAN
ask_ip "Veuillez saisir le masque de sous-reseau (netmask) pour le WLAN" NETMASK3
uci set network.wlan.ipaddr="$WLAN"
uci set network.wlan.netmask="$NETMASK3"

echo ""
echo ">>> ÉTAPE 9 — Configuration WiFi..."
echo ""

while true; do
    read -s -p "Veuillez saisir le mot de passe WiFi : " WIFI_KEY
    echo ""
    read -s -p "Confirmez le mot de passe WiFi : " WIFI_KEY2
    echo ""
    if [ "$WIFI_KEY" = "$WIFI_KEY2" ]; then
        break
    fi
    echo "   -> ERREUR : Les mots de passe ne correspondent pas, recommencez."
done

# Radio 0 — Active
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.network='wlan'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid="AP0-BBH-$OCTET_4-$RTR_NUM"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key="$WIFI_KEY"

# Radios 1 et 2 — Désactivées
for i in 1 2; do
    uci set wireless.radio${i}.disabled='1'
    uci set wireless.default_radio${i}=wifi-iface
    uci set wireless.default_radio${i}.device="radio${i}"
    uci set wireless.default_radio${i}.network='wlan'
    uci set wireless.default_radio${i}.mode='ap'
    uci set wireless.default_radio${i}.ssid="AP${i}-BBH-$OCTET_4-$RTR_NUM"
    uci set wireless.default_radio${i}.encryption='psk2'
    uci set wireless.default_radio${i}.key="$WIFI_KEY"
done

unset WIFI_KEY WIFI_KEY2

echo ""
echo ">>> ÉTAPE 10 — Configuration DNS et DHCP Relay..."
echo ""

# Saisie des serveurs DNS et DHCP
echo ">>> Serveur(s) DNS"
echo ""
ask_ip "Veuillez indiquer l'adresse IP du serveur DNS Primaire" DNS1
echo ""
ask_ip "Veuillez indiquer l'adresse IP du serveur DNS Secondaire" DNS2
echo ""
echo ">>> Serveur(s) DHCP"
echo ""
ask_ip "Veuillez indiquer l'adresse IP du serveur DHCP (sur lan1)" DHCP_IP
echo ""

# peerdns et dns WAN configurés ici, après saisie de DNS1/DNS2
# et après que l'interface WAN existe (créée en étape 6)
uci set network.wan.peerdns='0'
uci set network.wan.dns="${DNS1} ${DNS2}"
uci commit network

# --- Configuration DNS via dnsmasq ---
# dnsmasq est utilisé UNIQUEMENT pour le DNS, pas pour le DHCP
# Le DHCP est géré par dhcrelay4 (isc-dhcp-relay-ipv4)

# Désactivation complète du DHCP local sur toutes les interfaces
# Suppression de dhcp.lan qui créait des plages parasites
uci -q delete dhcp.lan

uci -q get dhcp.lan1 > /dev/null || uci set dhcp.lan1=dhcp
uci set dhcp.lan1.interface='lan1'
uci set dhcp.lan1.ignore='1'

uci -q get dhcp.lan2 > /dev/null || uci set dhcp.lan2=dhcp
uci set dhcp.lan2.interface='lan2'
uci set dhcp.lan2.ignore='1'

uci -q get dhcp.wlan > /dev/null || uci set dhcp.wlan=dhcp
uci set dhcp.wlan.interface='wlan'
uci set dhcp.wlan.ignore='1'

# Configuration dnsmasq pour le DNS uniquement
if ! uci -q get dhcp.@dnsmasq[0] > /dev/null; then
    uci add dhcp dnsmasq
fi

uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="${DNS1}"
uci add_list dhcp.@dnsmasq[0].server="${DNS2}"
uci set dhcp.@dnsmasq[0].localservice='0'
uci set dhcp.@dnsmasq[0].nonegcache='1'
uci set dhcp.@dnsmasq[0].rebind_protection='0'

# Domaine de recherche
echo ">>> Configuration du domaine de recherche"
echo ""
read -p "Merci d'indiquer le nom de domaine local : " DOMAIN_NAME
uci set dhcp.@dnsmasq[0].domain="$DOMAIN_NAME"
uci set dhcp.@dnsmasq[0].local="/$DOMAIN_NAME/"
uci add_list dhcp.@dnsmasq[0].rebind_domain="$DOMAIN_NAME"

uci commit dhcp

# --- Configuration dhcrelay (isc-dhcp-relay-ipv4) ---
# dhcrelay relaie les requêtes DHCP de lan2 et wlan vers le serveur DHCP
echo ">>> Configuration du relay DHCP (dhcrelay) vers $DHCP_IP..."
echo "   -> lan1 : même segment que $DHCP_IP, DHCP direct"
echo "   -> lan2 et wlan : relay vers $DHCP_IP"

# Configuration du relay DHCP via dhcrelay4 (script init fourni par isc-dhcp-relay-ipv4)
# dhcrelay4 lit sa config depuis /etc/config/dhcrelay via UCI
cat > /etc/config/dhcrelay << EOF
config dhcrelay 'ipv4'
	option enabled '1'
	option dhcpserver '${DHCP_IP}'
	list interfaces 'lan2'
	list interfaces 'wlan'
    list interfaces 'lan1'
EOF

echo ""
echo ">>> ÉTAPE 11 — Application des règles Firewall & NAT..."
echo ""

# Suppression des zones non-wan par index décroissant
echo ">>> Nettoyage des zones existantes dans le firewall."
idx=0
while uci -q get firewall.@zone[$idx] > /dev/null; do
    idx=$((idx + 1))
done
while [ $idx -gt 0 ]; do
    idx=$((idx - 1))
    zone_name=$(uci -q get firewall.@zone[$idx].name)
    if [ "$zone_name" != "wan" ] && [ "$zone_name" != "lan" ]; then
        echo "   -> Suppression zone[$idx] : $zone_name"
        uci delete firewall.@zone[$idx]
    fi
done

# Suppression de tous les forwardings existants
echo ">>> Nettoyage des forwardings existants."
idx=0
while uci -q get firewall.@forwarding[$idx] > /dev/null; do
    idx=$((idx + 1))
done
while [ $idx -gt 0 ]; do
    idx=$((idx - 1))
    uci delete firewall.@forwarding[$idx]
done

# Suppression ciblée des règles gérées par le script uniquement
# Les règles par défaut OpenWrt et celles ajoutées manuellement sont conservées
MANAGED_RULES="Allow-SSH-WAN Allow-DHCP-Relay Allow-DNS \
               Allow-Kerberos Allow-Kpasswd \
               Allow-LDAP Allow-LDAPS Allow-GC-LDAP Allow-GC-LDAPS \
               Allow-NTP Allow-RPC Allow-RPC-Dynamic \
               Allow-SMB Allow-Netlogon Allow-Netlogon-TCP"

echo ">>> Nettoyage des règles firewall gérées par le script..."
idx=0
while uci -q get firewall.@rule[$idx] > /dev/null; do
    idx=$((idx + 1))
done
while [ $idx -gt 0 ]; do
    idx=$((idx - 1))
    rule_name=$(uci -q get firewall.@rule[$idx].name)
    for managed in $MANAGED_RULES; do
        if [ "$rule_name" = "$managed" ]; then
            echo "   -> Suppression regle existante : $rule_name"
            uci delete firewall.@rule[$idx]
            break
        fi
    done
done

# Zone wlan
uci add firewall zone
uci set firewall.@zone[-1].name='wlan'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci add_list firewall.@zone[-1].network='wlan'

# Zone lan1
uci add firewall zone
uci set firewall.@zone[-1].name='lan1'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci add_list firewall.@zone[-1].network='lan1'

# Zone lan2
uci add firewall zone
uci set firewall.@zone[-1].name='lan2'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci add_list firewall.@zone[-1].network='lan2'

# Forwardings inter-zones
for src in lan1 lan2 wlan; do
    for dest in lan1 lan2 wlan wan; do
        [ "$src" = "$dest" ] && continue
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src="$src"
        uci set firewall.@forwarding[-1].dest="$dest"
    done
done

# SSH depuis WAN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-SSH-WAN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port="$SSH_WAN_PORT"
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

# DHCP relay (port 67) — sans restriction de zone
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DHCP-Relay'
uci set firewall.@rule[-1].dest_port='67'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

# DNS (TCP + UDP)
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-DNS'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='ACCEPT'

# Règles Microsoft Active Directory
# Format : NOM:PORT:PROTO (séparateur : pour compatibilité ash/POSIX)
# La boucle for multi-variables n'existe pas en ash — on utilise while+IFS+cut
AD_RULES="Allow-Kerberos:88:tcp udp
Allow-Kpasswd:464:tcp udp
Allow-LDAP:389:tcp udp
Allow-LDAPS:636:tcp
Allow-GC-LDAP:3268:tcp
Allow-GC-LDAPS:3269:tcp
Allow-NTP:123:udp
Allow-RPC:135:tcp
Allow-RPC-Dynamic:49152-65535:tcp
Allow-SMB:445:tcp
Allow-Netlogon:138:udp
Allow-Netlogon-TCP:139:tcp"

echo "$AD_RULES" | while IFS= read -r rule_line; do
    [ -z "$rule_line" ] && continue
    rule_name=$(echo "$rule_line" | cut -d: -f1)
    rule_port=$(echo "$rule_line" | cut -d: -f2)
    rule_proto=$(echo "$rule_line" | cut -d: -f3-)
    uci add firewall rule
    uci set firewall.@rule[-1].name="$rule_name"
    uci set firewall.@rule[-1].dest_port="$rule_port"
    uci set firewall.@rule[-1].proto="$rule_proto"
    uci set firewall.@rule[-1].target='ACCEPT'
done

uci commit wireless
uci commit network
uci commit firewall

echo ""
echo ">>> ÉTAPE 12 — Génération du banner SSH..."
echo ""

cat << 'EOF' > /etc/banner
.____    .__        __                           
|    |   |__| ____ |  | __  _________.__. ______ 
|    |   |  |/    \|  |/ / /  ___<   |  |/  ___/ 
|    |___|  |   |  \    <  \___ \ \___  |\___ \  
|_______ \__|___|  /__|_ \/____  >/ ____/____  > 
        \/       \/     \/     \/ \/         \/  

EOF

cat << 'EOFSTATS' > /etc/profile.d/99-custom-banner.sh
#!/bin/sh

GREEN="\033[32m"
RED="\033[31m"
BOLD="\033[1m"
BLUE="\033[34m"
RESET="\033[0m"

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    OS_INFO="$DISTRIB_DESCRIPTION"
else
    OS_INFO="OpenWRT"
fi

MODEL_INFO=$(cat /tmp/sysinfo/model 2>/dev/null | tr -d '\0')
[ -z "$MODEL_INFO" ] && MODEL_INFO="Unknown"

UPTIME=$(awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); if(d>0) printf "%dj %dh %dm", d, h, m; else printf "%dh %dm", h, m}' /proc/uptime)

if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp)
elif [ -f "/sys/class/hwmon/hwmon0/temp1_input" ]; then
    raw_temp=$(cat /sys/class/hwmon/hwmon0/temp1_input)
else
    raw_temp=""
fi

if [ -n "$raw_temp" ]; then
    val_temp=$((raw_temp / 1000))
    TEMP_STR="${val_temp} C"
else
    TEMP_STR="N/A"
fi

DISK=$(df -h /overlay 2>/dev/null | awk '/overlay/ {print $4}')
[ -z "$DISK" ] && DISK="N/A"

MEM_KB=$(free | awk '/Mem:/ {print $4}')
MEM_MB=$(awk "BEGIN {printf \"%.0fM\", $MEM_KB/1024}")

LAN1_IP=$(uci -q get network.lan1.ipaddr)
LAN1_MASK=$(uci -q get network.lan1.netmask)
[ -z "$LAN1_IP" ] && LAN1_IP="N/A"

LAN2_IP=$(uci -q get network.lan2.ipaddr)
LAN2_MASK=$(uci -q get network.lan2.netmask)
[ -z "$LAN2_IP" ] && LAN2_IP="N/A"

WLAN_IP=$(uci -q get network.wlan.ipaddr)
WLAN_MASK=$(uci -q get network.wlan.netmask)
[ -z "$WLAN_IP" ] && WLAN_IP="N/A"

SSID_ACTIVE=$(uci -q get wireless.default_radio0.ssid)
WIFI_ENC=$(uci -q get wireless.default_radio0.encryption)
[ -z "$SSID_ACTIVE" ] && SSID_ACTIVE="N/A"
[ -z "$WIFI_ENC" ]    && WIFI_ENC="N/A"

WIFI_CHAN=$(iw dev 2>/dev/null | awk '/channel/ {print $2; exit}')
[ -z "$WIFI_CHAN" ] && WIFI_CHAN="N/A"

WAN_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}')
[ -z "$WAN_IP" ] && WAN_IP="Non connecte"

WAN_GW=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
[ -z "$WAN_GW" ] && WAN_GW="N/A"

DNS_RAW=$(grep nameserver /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
[ -z "$DNS_RAW" ] && DNS_RAW="Local/Auto"
DNS_SRV=$(echo "$DNS_RAW" | cut -c 1-25)

LAN1_UP=$(ip link show br-lan1 2>/dev/null | grep -c "UP") || LAN1_UP=0
LAN2_UP=$(ip link show br-lan2 2>/dev/null | grep -c "UP") || LAN2_UP=0
[ "$LAN1_UP" -gt 0 ] && S_LAN1="${GREEN}● LAN1${RESET}" || S_LAN1="${RED}○ LAN1${RESET}"
[ "$LAN2_UP" -gt 0 ] && S_LAN2="${GREEN}● LAN2${RESET}" || S_LAN2="${RED}○ LAN2${RESET}"

if ping -q -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
    S_WAN="${GREEN}● NET (Direct)${RESET}"
elif wget -q --spider --timeout=3 --user-agent="Mozilla/5.0" http://captive.apple.com/hotspot-detect.html 2>/dev/null; then
    S_WAN="${GREEN}● NET (Proxy)${RESET}"
else
    S_WAN="${RED}○ NET (Erreur)${RESET}"
fi

RADIO0_STATE=$(uci -q get wireless.radio0.disabled)
if [ "$RADIO0_STATE" = "0" ] && iw dev 2>/dev/null | grep -q "Interface"; then
    S_WIFI="${GREEN}● WIFI${RESET}"
else
    S_WIFI="${RED}○ WIFI${RESET}"
fi

# --- Nouveaux espacements ajustés ---
L1=10
V1=31
GAP=4
L2=12

echo ""
printf "  ${BOLD}%-${L1}s:${RESET} %s\n" "Modele"  "$MODEL_INFO"
printf "  ${BOLD}%-${L1}s:${RESET} %s\n" "Systeme" "$OS_INFO"
echo ""
printf "  ${BLUE}%-44s%${GAP}s%-30s${RESET}\n" "SYSTEME" "" "RESEAU"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "Uptime"   "$UPTIME"       "" "IP WAN"     "$WAN_IP"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "Temp"     "$TEMP_STR"     "" "Passerelle" "$WAN_GW"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "Stockage" "$DISK libre"   "" "DNS Actifs" "$DNS_SRV"
printf "  %-${L1}s : %-${V1}s\n"                      "Memoire"  "$MEM_MB libre" 
echo ""
printf "  ${BLUE}%-44s%${GAP}s%-30s${RESET}\n" "INTERFACES" "" "WIFI"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "LAN1" "$LAN1_IP/$LAN1_MASK" "" "SSID"        "$SSID_ACTIVE"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "LAN2" "$LAN2_IP/$LAN2_MASK" "" "Chiffrement" "$WIFI_ENC"
printf "  %-${L1}s : %-${V1}s%${GAP}s%-${L2}s : %s\n" "WLAN" "$WLAN_IP/$WLAN_MASK" "" "Canal"       "$WIFI_CHAN"
echo ""
printf "  Statut :  %b  %b  %b  %b\n" "$S_LAN1" "$S_LAN2" "$S_WAN" "$S_WIFI"
echo ""
EOFSTATS

chmod +x /etc/profile.d/99-custom-banner.sh

echo ""
echo ">>> ÉTAPE 13 — Création du script de vérification..."
echo ""

cat << 'EOFVERIF' > /root/verify_config.sh
#!/bin/sh

# =========================================================
#  SCRIPT DE VERIFICATION POST-DEPLOIEMENT
#  Version: 1.21
# =========================================================

echo "=========================================="
echo " VERIFICATION DE LA CONFIGURATION"
echo " Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo ""

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

ERRORS=0
WARNINGS=0

check() {
    TEST_NAME="$1"
    TEST_CMD="$2"
    EXPECTED="$3"

    printf "%-40s : " "$TEST_NAME"
    RESULT=$(eval "$TEST_CMD" 2>/dev/null)

    if [ "$EXPECTED" = "not_empty" ]; then
        if [ -n "$RESULT" ]; then
            printf "${GREEN}✓${RESET} %s\n" "$RESULT"
        else
            printf "${RED}✗${RESET} Vide/Erreur\n"
            ERRORS=$((ERRORS + 1))
        fi
    elif [ "$EXPECTED" = "ping" ]; then
        if eval "$TEST_CMD" >/dev/null 2>&1; then
            printf "${GREEN}✓${RESET} OK\n"
        else
            printf "${YELLOW}⚠${RESET} Échec\n"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        if [ "$RESULT" = "$EXPECTED" ]; then
            printf "${GREEN}✓${RESET} %s\n" "$RESULT"
        else
            printf "${RED}✗${RESET} Attendu: %s, Obtenu: %s\n" "$EXPECTED" "$RESULT"
            ERRORS=$((ERRORS + 1))
        fi
    fi
}

echo "=== CONFIGURATION SYSTEME ==="
check "Hostname"  "uci get system.@system[0].hostname" "not_empty"
check "Timezone"  "uci get system.@system[0].timezone" "not_empty"

echo ""
echo "=== CONFIGURATION RESEAU ==="
check "IP LAN1"           "uci get network.lan1.ipaddr"  "not_empty"
check "IP LAN2"           "uci get network.lan2.ipaddr"  "not_empty"
check "IP WLAN"           "uci get network.wlan.ipaddr"  "not_empty"
check "PeerDNS desactive" "uci get network.wan.peerdns"  "0"

echo ""
echo "=== CONFIGURATION WIFI ==="
check "SSID radio0"     "uci get wireless.default_radio0.ssid"        "not_empty"
check "Encryption"      "uci get wireless.default_radio0.encryption"  "psk2"
check "Radio0 active"   "uci get wireless.radio0.disabled"            "0"
check "Radio1 inactive" "uci get wireless.radio1.disabled"            "1"
check "Radio2 inactive" "uci get wireless.radio2.disabled"            "1"

echo ""
echo "=== SERVICES ==="
check "DNSmasq actif"  "pgrep dnsmasq"  "not_empty"
check "dhcrelay4 actif" "pgrep dhcrelay" "not_empty"
check "Uhttpd actif"   "pgrep uhttpd"   "not_empty"

echo ""
echo "=== DHCP ==="
check "lan1 ignore DHCP local" "uci get dhcp.lan1.ignore" "1"
check "lan2 ignore DHCP local" "uci get dhcp.lan2.ignore" "1"
check "wlan ignore DHCP local" "uci get dhcp.wlan.ignore" "1"

echo ""
echo "=== CONNECTIVITE ==="
check "Ping 8.8.8.8"     "ping -q -c 1 -W 2 8.8.8.8"      "ping"
check "Ping DNS interne" "ping -q -c 1 -W 2 10.35.37.110" "ping"
check "Interface WAN UP" "ubus call network.interface.wan status | jsonfilter -e '@.up' | grep -q true && echo OK || echo KO" "OK"

echo ""
echo "=== FICHIERS ==="
check "Banner"              "test -f /etc/banner && echo OK || echo KO"                        "OK"
check "Banner dynamique"    "test -f /etc/profile.d/99-custom-banner.sh && echo OK || echo KO" "OK"
check "Script vérification" "test -f /root/verify_config.sh && echo OK || echo KO"             "OK"
check "Config dhcrelay"      "test -f /etc/config/dhcrelay && echo OK || echo KO"             "OK"

echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    printf " ${GREEN}✓ CONFIGURATION VALIDE${RESET}\n"
elif [ $ERRORS -eq 0 ]; then
    printf " ${YELLOW}⚠ Configuration OK avec %d avertissement(s)${RESET}\n" $WARNINGS
else
    printf " ${RED}✗ %d erreur(s) détectée(s)${RESET}\n" $ERRORS
fi
echo "=========================================="
echo ""

exit $ERRORS
EOFVERIF

chmod +x /root/verify_config.sh
echo "   -> Script de vérification créé : /root/verify_config.sh"

echo ""
echo ">>> ÉTAPE 14 — Persistance des fichiers après flash..."
echo ""

files_to_save="/etc/config/dhcrelay /etc/profile.d/99-custom-banner.sh /etc/banner /root/verify_config.sh"
for file in $files_to_save; do
    if [ ! -f "$file" ]; then
        echo "   ATTENTION: $file n'existe pas encore"
    fi
    if ! grep -Fxq "$file" /etc/sysupgrade.conf 2>/dev/null; then
        echo "$file" >> /etc/sysupgrade.conf
    fi
done

echo ""
echo ">>> ÉTAPE 15 — Redémarrage des services réseau..."
echo ""

ROUTER_LAN1_IP="$LAN1"

(
    echo "Relance du réseau..." >> "$LOGFILE"
    /etc/init.d/network restart

    # Attente que les bridges soient créés (20s min pour équipements lents)
    sleep 20
    waited=0
    while ! ip link show br-lan1 > /dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        [ $waited -ge 30 ] && break
    done
    echo "   -> Bridges détectés après $((15 + waited))s" >> "$LOGFILE"

    echo "Relance du firewall..." >> "$LOGFILE"
    /etc/init.d/firewall restart

    echo "Relance de DNSmasq..." >> "$LOGFILE"
    /etc/init.d/dnsmasq restart

    # Demarrage de dhcrelay4 une fois les bridges UP
    echo "Demarrage du relay DHCP (dhcrelay4)..." >> "$LOGFILE"
    /etc/init.d/dhcrelay4 enable
    /etc/init.d/dhcrelay4 start

    echo "Relance du log..." >> "$LOGFILE"
    /etc/init.d/log restart

    echo "Rechargement WiFi..." >> "$LOGFILE"
    wifi reload

    echo "Déploiement terminé avec succès en arrière-plan." >> "$LOGFILE"
) &

echo ""
echo "=========================================================="
echo " ATTENTION : Votre IP change (192.168.1.1 -> $ROUTER_LAN1_IP)"
echo " Votre session SSH va se clôturer dans quelques secondes."
echo "=========================================================="
sleep 2

# =========================================================
#  RÉSUMÉ FINAL
# =========================================================
echo ""
echo "=========================================="
echo ">>> DÉPLOIEMENT TERMINÉ AVEC SUCCÈS ! <<<"
echo "=========================================="
echo ""
echo "Paquets installés  : $PACKAGES"
if [ -n "$INSTALL_FAILED" ]; then
    echo "Paquets en échec   :$INSTALL_FAILED"
fi
echo ""
echo "Fichiers générés :"
echo "  - $LOGFILE"
echo "  - $BACKUP_DIR (sauvegarde config UCI)"
echo "  - /etc/config/dhcrelay"
echo "  - /etc/profile.d/99-custom-banner.sh"
echo "  - /root/verify_config.sh"
echo ""
echo "=========================================="
echo " PROCHAINES ÉTAPES"
echo "=========================================="
echo ""
echo "1. Rechargez l'environnement :"
echo "   source /etc/profile"
echo ""
echo "2. Vérifiez la configuration :"
echo "   /root/verify_config.sh"
echo ""
echo "3. Reconnectez-vous :"
echo "   ssh root@$ROUTER_LAN1_IP  (LAN1)"
echo "   ssh -p $SSH_WAN_PORT root@$WAN_IP  (WAN)"
echo ""
echo "4. En cas de problème, restaurez :"
echo "   cp -r $BACKUP_DIR/config/* /etc/config/"
echo "   /etc/init.d/network restart"
echo ""
echo "=========================================="
echo ""

exit 0
