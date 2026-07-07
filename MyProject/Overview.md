# 🌐 Infrastructure Réseau Hybride Multi-VLAN & Services Centralisés
## *Projet d'Administration Systèmes et Réseaux — HomeLab*

Ce projet formalise la refonte, la segmentation et la sécurisation de mon infrastructure réseau personnelle. L'architecture repose sur un modèle hybride où la topologie, le cloisonnement et le routage sont assurés par un routeur **OpenWrt**, tandis que l'intelligence et la gestion des services d'infrastructure (Identité, DNS, DHCP) sont centralisées sur un contrôleur de domaine **Debain 13 - Trixie**.

---

## 📌 1. Objectifs & Philosophie du Projet

Dans une topologie réseau standard, le routeur grand public ou de base gère l'indivisibilité des services (passerelle, DNS, DHCP). Cette approche monolithique montre rapidement ses limites dans un contexte d'apprentissage et de montée en compétences (HomeLab) ou lors du déploiement d'un environnement d'entreprise.

Les objectifs clés de cette architecture sont :
* **Segmentation et Sécurité :** Isoler les flux (Serveurs, Clients filaires, Wi-Fi) via des réseaux locaux virtuels (VLANs) pour appliquer des politiques de filtrage strictes.
* **Centralisation des Services :** Déléguer la gestion des adresses IP et de la résolution de noms à un unique serveur d'infrastructure (Active Directory), garantissant la cohérence des zones DNS directes et inverses.
* **Optimisation des Équipements :** Utiliser OpenWrt comme une passerelle de routage pure et performante, déchargée des rôles applicatifs secondaires.

---

## 🛠️ 2. Architecture Technique & Topologie

L'infrastructure s'organise autour d'un domaine local interne unique : **`antareshorizon.com`**

### Spécifications des Cœurs de Système
* **La Passerelle (`RTR-BBH-24-01`) :**
Routeur sous OS OpenWrt. Il assure le routage inter-VLAN et le transport des flux DHCP via ses interfaces de ponts réseaux (bridges)
* **Le Cerveau Réseau (`SRV-BBH-37120`) :**
        # 🖥️ Fiche d’Identité Serveur : VDBM-MAST-000

        * **Adresse IP :** `10.35.37.120`
        * **Système d'Exploitation :** Debian 13 (Trixie)
        * **Domaine local :** `antareshorizon.com`
        * **Accès Sécurisé :** SSH durci sur le port alternatif `54321` (Authentification par clés privées uniquement, accès root interdit à distance, filtrage par `Fail2Ban` et règles `nftables`).

        ---

        ## 🛠️ Services Réseau Gérés

        Ce serveur est le cœur de l'infrastructure réseau et de la sécurité du domaine `antareshorizon.com`. Il remplace l'ancien rôle DHCP/DNS de Windows Server 2025.

        ### 1. Attribution des adresses IP (`isc-dhcp-server`)
        Le serveur gère l'attribution dynamique et statique (réservations MAC) des adresses IP. Couplé à un agent de relais DHCP (IP Helper) configuré sur le routeur OpenWrt, il distribue les configurations réseau sur **3 scopes (VLANs) distincts** :
        * **Scope Principal (Gestion / Serveurs) :** `10.35.37.0/24`
        * **Scope Secondaire :** `10.35.38.0/24`
        * **Scope Tertiaire (IoT / Invités) :** `172.16.37.0/24`

        ### 2. Résolution DNS & Filtrage (`AdGuard Home`)
        AdGuard Home centralise les requêtes DNS de l'ensemble des équipements afin d'assurer la sécurité et le respect de la vie privée à la racine du réseau.
        * **Filtrage actif :** Blocage automatique d'environ 14% des requêtes (télémétrie Windows, trackers publicitaires, domaines malveillants).
        * **Confidentialité (DoH) :** Chiffrement des requêtes montantes (DNS-over-HTTPS) envoyées en mode parallèle vers des résolveurs sécurisés (Cloudflare / Quad9).
        * **DNS Local :** Gestion des réécritures DNS pour la résolution interne des services du domaine.

        ### 3. Reverse Proxy & Accessibilité (`Nginx Proxy Manager`)
        L'interface d'administration d'AdGuard Home (initialement sur le port `3000`) est intégrée derrière **Nginx Proxy Manager (NPM)**.
        * **Routage :** Accès simplifié via l'URL locale dédiée : `https://adguard.antareshorizon.com`.
        * **Sécurité :** Chiffrement des flux d'administration grâce au certificat SSL géré par NPM.

        ---

        > 🔒 **Note d'architecture :** La séparation stricte des rôles entre le moteur DHCP (`isc-dhcp-server`) et le résolveur DNS (`AdGuard Home`) garantit qu'une indisponibilité ou une mise à jour d'AdGuard n'interrompt pas l'attribution des adresses IP sur le réseau. L'ensemble de la configuration de sécurité de l'hôte est industrialisé via des playbooks **Ansible**.

### Cartographie des Sous-Réseaux (Interfaces Linux)
Le routeur OpenWrt n'utilise pas les désignations logiques de son interface graphique pour les services bas niveau, mais s'appuie sur la configuration réelle de ses ponts (bridges) réseaux *(Source : Analyse `ip addr show` du routeur, 2026)* :

| Interface Virtuelle | Bridge Linux Associé | Plage IP / Suffixe | Rôle & Usage | IP Passerelle |
| :--- | :--- | :--- | :--- | :--- |
| **lan1** | `br-lan1` | `10.35.37.0/24` | Zone Serveurs | `10.35.37.254` |
| **lan2** | `br-lan2` | `10.35.38.0/24` | Zone Clients Filaires (incluant le NAS d'infrastructure) | `10.35.38.254` |
| **Wlan** | `br-wlan` | `172.16.37.0/24` | Zone Sans-fil (Wi-Fi) | `172.16.37.254` |

---

## ⚙️ 3. Mécanisme du Relais DHCP (IPv4)

Puisque les clients des zones `br-lan2` (PC, NAS) et `br-wlan` (Wi-Fi) n'appartiennent pas au même domaine de diffusion (Broadcast) que le serveur DHCP (`10.35.37.120`), les requêtes de configuration initiales ne peuvent pas franchir les limites du routeur.

Pour résoudre cette problématique, le routeur embarque l'agent de relais officiel de l'ISC

### Configuration du Démon `dhcrelay4`
Le service a été configuré pour s'attacher manuellement aux interfaces physiques du noyau afin d'intercepter les requêtes réseaux locaux et les encapsuler en Unicast vers le serveur DHCP :

```bash
# Structure validée du fichier /etc/config/dhcrelay
config relay
    option server '10.35.37.120'
    list interface 'br-lan1'  # Interface de sortie vers le serveur Windows
    list interface 'br-lan2'  # Interface d'écoute des clients filaires
    list interface 'br-wlan'  # Interface d'écoute du réseau Wi-Fi

## ⚙️ 4. Déploiement de la configuration d'OpenWrt via un script

Afin de faciliter la configuration de mon router sous OS OpenWrt, j'ai écrit un script pour me permettre la personnalisation de l'ensemble des paramètres nécessaires au bon fonctionnement de mon réseau. Vous pouvez le consulter [ici](./deploy_openwrt-v1_21.sh)