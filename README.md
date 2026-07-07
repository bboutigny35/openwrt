# 🌐 Présentation d'OpenWrt & Fonctionnalités Réseau

<p align="center">
    <img src="./images/openwrt.png" alt="Logo OpenWrt">
</p>

**OpenWrt** est un système d'exploitation libre et open-source incontournable basé sur le noyau Linux, conçu spécifiquement pour les routeurs et les appareils embarqués. 

Contrairement aux micrologiciels (firmwares) d'usine propriétaires et figés, OpenWrt se distingue par sa flexibilité absolue, sa sécurité et sa nature modulaire. Il transforme un simple équipement matériel en un véritable serveur réseau entièrement personnalisable.

---

## 📌 Philosophie & Points Clés

Selon le site officiel [openwrt.org](https://openwrt.org/), le projet repose sur un principe fondamental : **offrir un contrôle total sur votre matériel**.

* **Un vrai système Linux embarqué :** OpenWrt propose un système de fichiers modifiable avec un gestionnaire de paquets dédié (`opkg`). Vous installez uniquement les fonctionnalités nécessaires, optimisant ainsi la mémoire et l'espace de stockage.
* **Stabilité et Performance :** En gérant plus efficacement les ressources (RAM et CPU), OpenWrt sature beaucoup moins lors de charges lourdes et redonne souvent une seconde jeunesse à du matériel vieillissant.
* **Sécurité réactive :** Le projet bénéficie d'une communauté internationale très active qui corrige rapidement les failles de sécurité, là où les constructeurs abandonnent souvent le support de leurs routeurs après un ou deux ans.
* **Interfaces de gestion :** Entièrement pilotable en ligne de commande (via SSH avec l'outil `uci`), il intègre également une interface web puissante, modulaire et intuitive appelée **LuCI**.

---

## 🛠️ Capacités de Gestion Réseau d'OpenWrt

La grande force d'OpenWrt réside dans l'étendue de ses fonctionnalités réseau. Voici une liste structurée de ce que l'OS permet de piloter :

### 1. Routage avancé & Segmentation
* **Gestion des VLANs (802.1Q) :** Permet de segmenter physiquement ou logiquement votre réseau en plusieurs sous-réseaux isolés pour sécuriser des appareils spécifiques (ex: objets connectés, serveurs de production, réseau invités).
* **Bridges (Ponts réseaux) :** Capacité à lier des interfaces physiques (ports Ethernet, interfaces Wi-Fi) au sein de ponts virtuels (ex: `br-lan`).
* **Routage dynamique :** Support des protocoles de routage d'entreprise (OSPF, BGP via des suites comme FRRouting/BIRD).

### 2. Services d'infrastructure de base
* **Serveur DHCP & DNS intégré (Dnsmasq) :** Gestion fine de l'attribution des adresses IP locales, de la résolution de noms, de la protection contre le *DNS Rebinding* et des redirections DNS.
* **Relais DHCP (`dhcrelay`) :** Capacité d'intercepter les requêtes DHCP de diffusion (broadcast) locales pour les transférer en Unicast à un serveur centralisé (comme un contrôleur de domaine Windows Server) situé dans un autre sous-réseau.
* **Gestion IPv6 native :** Support complet du Dual-Stack (IPv4/IPv6), des préfixes délégués (DHCPv6-PD) et des annonces de routeur (RA).

### 3. Sécurité & Pare-feu
* **Pare-feu moderne basé sur `fw4` (nftables) :** Configuration ultra-précise des règles de filtrage (entrées, sorties, transferts), du NAT (Network Address Translation) et de la redirection de ports (Port Forwarding).
* **Filtrage de contenu au niveau DNS :** Possibilité d'intégrer des bloqueurs de publicités ou de traqueurs directement sur le routeur (via des paquets comme `adblock-fast`).
* **Interception et redirection DNS :** Permet de forcer tous les appareils du réseau à utiliser un résolveur DNS spécifique, bloquant ainsi le contournement par des DNS configurés en dur sur les clients.

### 4. Réseaux Privés Virtuels (VPN)
* **WireGuard :** Support natif et extrêmement performant pour créer des tunnels VPN légers, que ce soit pour interconnecter des sites (Site-to-Site) ou pour accéder à une infrastructure locale à distance (Client-to-Site).
* **OpenVPN / IPsec / Tinc :** Gestion des protocoles VPN traditionnels pour une compatibilité maximale avec les anciennes infrastructures.

### 5. Wi-Fi & Sans-fil performant
* **Multi-SSID :** Possibilité de diffuser plusieurs réseaux Wi-Fi indépendants (ex: un Wi-Fi principal lié au réseau local et un Wi-Fi invité bridé sur un VLAN isolé) sur les mêmes cartes radio.
* **Roaming transparent (Itinérance) :** Support des normes 802.11r/k/v pour permettre aux appareils mobiles de basculer d'un point d'accès à un autre sans coupure de session.
* **Sécurité de pointe :** Support complet du chiffrement WPA3.

### 6. Optimisation de la bande passante (QoS)
* **SQM (Smart Queue Management) :** Utilisation d'algorithmes de file d'attente avancés (comme `Cake` ou `FQ-CoDel`) pour éradiquer le *Bufferbloat* (la latence qui explose lorsque la connexion est saturée), garantissant une connexion fluide pour le jeu en ligne ou la VoIP, même pendant de gros téléchargements.

---

## 📝 En résumé
OpenWrt retire les restrictions logicielles imposées par les constructeurs. Que ce soit pour optimiser un réseau domestique ou pour servir de passerelle robuste au cœur d'un **HomeLab**, il agit comme un couteau suisse réseau capable de s'adapter aux topologies les plus complexes.