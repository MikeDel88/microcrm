# Plan de déploiement

Objectif : décrire simplement **comment** MicroCRM est déployé, **dans quel ordre** et **avec quels prérequis techniques**. Ce plan complète les principes posés en première partie ([06 Principes de conteneurisation et de déploiement](06-conteneurisation-deploiement.md)). Il s'appuie sur ce qui est en place :
- conteneurisation : [08](08-conteneurisation.md) ;
- publication des images : [09](09-deploiement.md) ;
- versions : [10](10-release.md) ;
- supervision : [11](11-supervision-elk.md) ;
- indicateurs : [12](12-dora-kpi.md) ;
- sécurité : [05](05-plan-securite.md).

État au **27/10/2026**.

## 1. Comment l'application est déployée

MicroCRM est déployé sous forme de **deux images Docker**, construites une seule fois par la CD puis réutilisées telles quelles (*build once, deploy many*) :

| Image | Contenu | Port |
|---|---|---|
| `ghcr.io/mikedel88/microcrm-front` | application Angular compilée, servie par Caddy (HTTPS, certificat interne) | 80, 443 |
| `ghcr.io/mikedel88/microcrm-back` | API Spring Boot (JAR), base HSQLDB en mémoire | 8080 |

La chaîne complète, de la modification du code à l'application en service :

```
 code ─► PR ─► CI (ci.yml) ─► fusion ─► CD (cd.yml) ─► release (release.yml) ─► déploiement ─► vérification ─► supervision
          build, tests,     protégée   build, scan     version, changelog,      compose        santé, tests    ELK, KPI
          Sonar : ci-ok    par ci-ok   Trivy, GHCR     release GitHub           release        de fumée
```

- **De la PR à la release, tout est automatique.** Chaque étape ne démarre que si la précédente a réussi : pas de fusion sans `ci-ok`, pas d'image sans scan, pas de version sans image.
- **Le déploiement lui-même est manuel.** On lance une commande Compose qui tire les images publiées. Il n'y a pas encore de serveur cible : l'application est déployée sur un poste local.

### Environnements

| Environnement | Branche | Images | Profil Spring | Commande |
|---|---|---|---|---|
| Développement | branche de travail | construites localement | `dev` | `docker compose up --build` |
| Intégration | `develop` | tag `X.Y.Z-rc.N` (et `<sha>`, `develop`, `SNAPSHOT`) | `prod` | compose de release |
| Production (cible) | `main` | tag `X.Y.Z` (et `<sha>`, `main`) | `prod` | compose de release |

La **même image** passe de l'intégration à la production : seule la configuration change, par le profil Spring.

### Quel tag déployer

On déploie une **version** avec son tag `X.Y.Z` (ou `X.Y.Z-rc.N` en intégration). Le job `publish` de `release.yml` ajoute ce tag à l'image que la CD a déjà scannée et publiée, sans la reconstruire et avec le même digest (voir [10](10-release.md)). Les tags `main`, `develop` et `SNAPSHOT` sont mobiles : ils changent à chaque fusion, et on ne les utilise jamais pour déployer.

**Versions antérieures** (v1.0.0 à v1.1.2) : elles ont été publiées avant cette évolution et n'ont pas de tag `X.Y.Z` dans GHCR. On déploie alors le SHA du **commit parent du tag**, le commit de fusion validé par la CD :

```shell
git rev-parse vX.Y.Z^        # SHA à déployer pour une version antérieure
# exemple : v1.1.2 -> 96bb73f… (fusion de la PR #34), image publiée par la CD #12
```

## 2. Dans quel ordre

### A. Livrer une nouvelle version (automatique)

| Étape | Déclencheur | Ce qui se passe | Contrôle avant l'étape suivante |
|---|---|---|---|
| 1. Pull request vers `develop` | développeur | CI : build, tests back et front, analyse Sonar | `ci-ok` vert, quality gate `OK` |
| 2. Fusion sur `develop` | revue de la PR | CD : images construites, scannées, publiées (`SNAPSHOT`) | scan Trivy sans CVE CRITICAL non acceptée |
| 3. Release candidate | CD réussie | `release.yml` : version `vX.Y.Z-rc.N`, pre-release GitHub | release créée |
| 4. Validation en intégration | équipe | déploiement de l'image `develop` (section B), tests de fumée | application saine |
| 5. PR `develop` → `main` | équipe | CI de nouveau | `ci-ok` vert |
| 6. Fusion sur `main` | revue de la PR | CD : images de livraison publiées | scan Trivy |
| 7. Version finale | CD réussie | `release.yml` : version `vX.Y.Z`, changelog, release GitHub avec le JAR et le build Angular | release publiée |

### B. Déployer une version (manuel)

L'ordre de démarrage compte : **le back d'abord, puis le front**. Compose le garantit : le front attend que le healthcheck du back (`/actuator/health`) soit vert (`depends_on: service_healthy`).

```shell
# 1. Récupérer les fichiers de déploiement (compose.yml, compose.release.yml) dans la version voulue
git fetch --tags && git checkout vX.Y.Z

# 2. Tirer les images de la version et démarrer (back, puis front dès que le back est healthy)
TAG=X.Y.Z docker compose -f compose.yml -f compose.release.yml up -d

# 3. Vérifier l'état : les deux services doivent être "healthy"
docker compose -f compose.yml -f compose.release.yml ps
```

Sous PowerShell, l'étape 2 s'écrit : `$env:TAG = "X.Y.Z" ; docker compose -f compose.yml -f compose.release.yml up -d`. Pour une version v1.0.0 à v1.1.2, `TAG` prend le SHA du commit parent du tag (voir « Quel tag déployer »).

### C. Vérifier le déploiement (tests de fumée)

| Vérification | Commande | Résultat attendu |
|---|---|---|
| Santé du back | `curl -s http://localhost:8080/actuator/health` | `{"status":"UP"}` |
| API | `curl -s http://localhost:8080/persons` | réponse JSON (données de démonstration) |
| Front | `curl -sk -o /dev/null -w "%{http_code}" https://localhost/` | `200` |
| Version déployée | `docker compose -f compose.yml -f compose.release.yml images` | les deux images au tag `$TAG` |

### D. Superviser (optionnel)

On démarre ensuite la stack ELK, qui est indépendante de l'application (`./elk.sh up`, voir [11](11-supervision-elk.md)). Kibana affiche alors les logs du back et du front, et les erreurs `ERROR` sont suivies dans le tableau de bord.

### E. Revenir en arrière (*rollback*)

Si un test de fumée échoue, ou si des erreurs apparaissent dans Kibana, on relance la commande de la section B avec la **version précédente** :

```shell
# exemple : retour de 1.3.0 à 1.2.0
TAG=1.2.0 docker compose -f compose.yml -f compose.release.yml up -d
# version v1.0.0 à v1.1.2 (sans tag X.Y.Z dans GHCR) : SHA du commit parent du tag
TAG=$(git rev-parse v1.1.1^) docker compose -f compose.yml -f compose.release.yml up -d
```

Aucun rebuild n'est nécessaire : l'image précédente est toujours dans GHCR. La base étant en mémoire, les données repartent du jeu de démonstration.

## 3. Prérequis techniques

### Machine de déploiement

| Prérequis | Détail |
|---|---|
| Docker Engine et Docker Compose v2 | Les healthchecks utilisent `start_interval` : Docker Engine 25 ou plus récent. Poste de développement actuel : Docker 29.8 et Compose 5.5 |
| Ports libres | 80 et 443 (front), 8080 (back) |
| Accès réseau à `ghcr.io` | Les images sont **publiques** : aucun `docker login` n'est nécessaire pour les tirer |
| Fichiers de déploiement | `compose.yml` et `compose.release.yml` du dépôt, dans la version déployée |
| Git (recommandé) | Pour récupérer les fichiers Compose de la version (`git checkout vX.Y.Z`) et, pour les versions v1.0.0 à v1.1.2, retrouver le SHA à déployer (`git rev-parse vX.Y.Z^`) |
| Supervision (optionnel) | Environ 3 Go de RAM pour ELK ; `vm.max_map_count=262144` ; fichier `.env.elk` à créer depuis `.env.elk.example` (voir [11](11-supervision-elk.md)) |

### Dépôt GitHub (une fois pour toutes)

| Prérequis | Rôle |
|---|---|
| Protection de branche sur `develop` et `main` : PR obligatoire, check `ci-ok` requis | Garantit qu'aucun code non testé n'arrive dans la CD |
| Secrets `SONAR_TOKEN_BACK` et `SONAR_TOKEN_FRONT` | Analyse SonarQube Cloud dans la CI |
| Secret `RELEASE_TOKEN` (jeton personnel) | Permet à semantic-release de pousser le tag malgré la protection de branche, et de déclencher `publish` |
| `release.yml` présent sur `main` | Un déclencheur `workflow_run` ne s'active que depuis la branche par défaut |
| Permissions GHCR par défaut (`GITHUB_TOKEN`) | Publication des images, sans secret supplémentaire |

### Conditions pour déployer

On ne déploie une version que si :
- la release `vX.Y.Z` existe : CI, CD et release sont toutes passées ;
- aucune issue `publish-failure` n'est ouverte pour la branche ;
- les exceptions de sécurité de `.trivyignore` ne sont pas expirées (31/01/2027, voir [09](09-deploiement.md)).

## 4. Limites et suite

| Limite actuelle | Conséquence | Suite prévue |
|---|---|---|
| Déploiement manuel, sur poste local | Pas de déploiement continu, et les DORA s'arrêtent à la publication des images ([12](12-dora-kpi.md)) | Job de déploiement sur un serveur cible après `release.yml` |
| URL de l'API fixée au build (`http://localhost:8080`) | Le front ne fonctionne que si le back est sur la même machine | Servir l'API derrière Caddy, sur la même origine (`/api`) : corrige aussi CORS et le port 8080 exposé ([05](05-plan-securite.md), priorité 1) |
| Base HSQLDB en mémoire | Données perdues à chaque redéploiement ou rollback | Base persistante avec sauvegarde, avant toute production ([05](05-plan-securite.md), priorité 5) |
| Pas d'authentification sur l'API | Interdit toute exposition publique | Prérequis bloquant avant la mise en production ([05](05-plan-securite.md), R1) |
