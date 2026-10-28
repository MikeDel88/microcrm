<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM

*P7 - Développeur Full-Stack - Java et Angular - Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack*

MicroCRM est une application de démonstration : une version simplifiée d'un [CRM](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client) (*Customer Relationship Management*). Elle permet de créer, modifier et consulter des personnes et les organisations auxquelles elles sont rattachées.

Le code applicatif est fourni. Le travail de ce projet porte sur sa **chaîne d'intégration et de déploiement continus** :
- conteneurisation ;
- pipeline CI/CD ;
- analyse de la qualité et de la sécurité ;
- versions automatiques ;
- supervision et indicateurs.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

## Sommaire

1. [Architecture](#1-architecture)
2. [Stack technique](#2-stack-technique)
3. [Choix techniques](#3-choix-techniques)
4. [Instructions d'exécution](#4-instructions-dexécution)
5. [CI/CD](#5-cicd)
6. [Documentation](#6-documentation)
7. [Limites connues](#7-limites-connues)

## 1. Architecture

Le dépôt est un [monorepo](https://en.wikipedia.org/wiki/Monorepo) :
- `back/` : API REST Spring Boot ;
- `front/` : application Angular ;
- à la racine : la conteneurisation, les workflows CI/CD et la supervision.

```
                         ┌──────────────────────── GitHub ─────────────────────────┐
  développeur ── PR ───► │ ci.yml : build, tests, SonarQube Cloud  ──► ci-ok        │
                         │ cd.yml : images Docker, scan Trivy ──► GHCR              │
                         │ release.yml : version SemVer, changelog, release, X.Y.Z  │
                         └──────────────────────────────┬──────────────────────────┘
                                                        │ docker compose (TAG=X.Y.Z)
                                                        ▼
  navigateur ── HTTPS ──► microcrm-front (Caddy + Angular)    :80 / :443
             ── HTTP ───► microcrm-back  (Spring Boot + HSQLDB) :8080
                                   │ logs JSON, métriques
                                   ▼
                          stack ELK (Filebeat, Metricbeat ──► Elasticsearch ──► Kibana :5601)
```

## 2. Stack technique

| Couche | Technologie | Version |
|---|---|---|
| Back | Java, Spring Boot (Spring Data REST, JPA, Actuator), Gradle | 17, 3.2.5, 8.7 |
| Base de données | HSQLDB, en mémoire | fournie par Spring Boot |
| Front | Angular, TypeScript, Bulma (CSS) | 17.3, 5.4, 1.0 |
| Tests | JUnit 5 + JaCoCo (back), Jasmine + Karma (front) | – |
| Conteneurs | Docker (Dockerfile multi-stage), Docker Compose v2, Caddy | Caddy 2.11.7 |
| CI/CD | GitHub Actions, GHCR (registre d'images), semantic-release | – |
| Qualité et sécurité | SonarQube Cloud, Trivy, Checkstyle | – |
| Supervision | Elasticsearch, Logstash, Kibana, Filebeat, Metricbeat | 8.17.0 |

## 3. Choix techniques

Chaque choix est détaillé dans le document indiqué ; on en résume ici la justification.

### Conteneurisation ([08](documentation/08-conteneurisation.md))

| Choix | Justification |
|---|---|
| **Un Dockerfile multi-stage unique** à la racine | un seul contexte de build pour le monorepo ; les images finales ne contiennent que le résultat (pas de Node, de Gradle ni de sources), elles sont plus légères et moins exposées |
| **Un service par conteneur** (`front`, `back`) au lieu de l'image `standalone` d'origine | chaque service se construit, se met à jour et se supervise séparément |
| **Images de base à version fixe, Alpine, JRE seul** | builds reproductibles, images légères |
| **Utilisateur non root** dans les deux images | limite l'impact d'une compromission |
| **Caddy** pour servir le front | HTTPS automatique, redirection HTTP → HTTPS, compression, logs JSON, routage Angular (`try_files`) |
| **Healthchecks et `depends_on: service_healthy`** | le front ne démarre que lorsque l'API répond (`/actuator/health`) |
| **Profil Spring par variable d'environnement** | une même image pour tous les environnements : seule la configuration change (*build once, deploy many*) |

### Intégration continue ([07](documentation/07-pipeline-ci.md), [04](documentation/04-plan-testing-periodique.md))

| Choix | Justification |
|---|---|
| **GitHub Actions**, sur chaque PR vers `develop` et `main`, et sur push sur `main` | intégré au dépôt, sans serveur à maintenir |
| **Back et front en parallèle**, puis Sonar | temps de retour court : environ 2,5 min pour un run complet ([12](documentation/12-dora-kpi.md)) |
| **Un seul check obligatoire, `ci-ok`** | la protection de branche ne dépend pas du détail des jobs |
| **SonarQube Cloud avec quality gate bloquant** (*Clean as You Code*) | aucune régression de qualité ou de sécurité sur le nouveau code, sans bloquer le projet sur la dette héritée ([13](documentation/13-analyse-sonar.md)) |

### Livraison et versions ([09](documentation/09-deploiement.md), [10](documentation/10-release.md))

| Choix | Justification |
|---|---|
| **Scan Trivy avant le push** | aucune image avec une CVE critique corrigeable n'atteint le registre ; les exceptions sont documentées et **datées** (`.trivyignore`) |
| **GHCR** et **attestation de provenance** | registre intégré à GitHub ; chaque image est traçable jusqu'à son workflow et son commit |
| **semantic-release** avec *Conventional Commits* | numéro de version, changelog et release calculés à partir des commits, sans intervention manuelle |
| **Release candidate sur `develop`, version finale sur `main`** | chaque version est testée en préproduction avant la production ([16](documentation/16-plan-mise-a-jour.md)) |
| **Images retaguées en `X.Y.Z` sans rebuild** | l'image déployée est exactement celle qui a été scannée (même digest) |

### Supervision ([11](documentation/11-supervision-elk.md))

| Choix | Justification |
|---|---|
| **Logs JSON au format ECS** | logs structurés dès la source, filtrables dans Kibana sans parsing |
| **Filebeat lit la sortie des conteneurs** | l'application ne dépend pas d'ELK (principe *12-factor*) |
| **Stack ELK dans un projet Compose séparé** | démarrée et arrêtée indépendamment de l'application ; TLS et authentification activés |

## 4. Instructions d'exécution

### Prérequis

| Usage | Outils |
|---|---|
| Lancer avec Docker (recommandé) | Docker Engine 25 ou plus récent, Docker Compose v2 ; ports 80, 443 et 8080 libres |
| Lancer depuis les sources | JDK 17 ; Node.js 20 et npm 10 |
| Tests du front | Google Chrome ou Chromium |
| Supervision ELK | environ 3 Go de RAM libres ; `vm.max_map_count=262144` |

### A. Lancer l'application avec Docker Compose (recommandé)

```shell
docker compose up --build -d     # construit les images et démarre back puis front
docker compose ps                # les deux services doivent être "healthy"
docker compose down              # arrêt
```

| Service | URL |
|---|---|
| Application | https://localhost (certificat interne de Caddy : accepter l'avertissement du navigateur) |
| API | http://localhost:8080 (`/persons`, `/organizations`) |
| Santé de l'API | http://localhost:8080/actuator/health |

Le back démarre en profil `dev` par défaut. Pour un autre profil : `SPRING_PROFILES_ACTIVE=prod docker compose up --build -d`.

### B. Déployer une version publiée

Les images de chaque version sont publiques dans GHCR : rien n'est reconstruit.

```shell
TAG=1.1.3 docker compose -f compose.yml -f compose.release.yml pull
TAG=1.1.3 docker compose -f compose.yml -f compose.release.yml up -d
```

- Sous PowerShell : `$env:TAG = "1.1.3"`, puis les mêmes commandes.
- Pour revenir en arrière, relancer la commande avec la version précédente.
- Ordre, prérequis et tests de fumée : [14 Plan de déploiement](documentation/14-plan-deploiement.md).

### C. Lancer depuis les sources (développement)

**Back**, dans `back/` :

```shell
./gradlew build                  # Windows : gradlew.bat build (compile, teste, produit le JAR)
java -jar build/libs/microcrm.jar --spring.profiles.active=dev
```

L'API est disponible sur http://localhost:8080.

**Front**, dans `front/`, avec le back démarré :

```shell
npm ci                           # installation exacte depuis package-lock.json
npm start                        # ng serve
```

L'application est disponible sur http://localhost:4200.

### D. Lancer les tests

```shell
# Back : tests JUnit, couverture JaCoCo et Checkstyle
cd back && ./gradlew build

# Front : tests Karma en continu (navigateur)
cd front && npm test

# Front : comme en CI (Chrome headless, couverture, rapport JUnit)
cd front && CHROME_BIN=</chemin/vers/chrome> npm run test:ci
```

### E. Lancer la supervision (ELK)

```shell
cp .env.elk.example .env.elk     # puis changer les mots de passe et ENCRYPTION_KEY
./elk.sh up                      # Linux ; ./elk.sh down pour arrêter
# Windows : docker compose --env-file .env.elk -f compose.elk.yml up -d
```

Kibana est disponible sur http://localhost:5601 (utilisateur `elastic`). Création et import du tableau de bord : [11 Supervision ELK](documentation/11-supervision-elk.md).

## 5. CI/CD

| Workflow | Déclencheur | Rôle |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | PR vers `develop` / `main`, push sur `main` | build et tests back et front, analyse SonarQube Cloud, check `ci-ok` |
| [`cd.yml`](.github/workflows/cd.yml) | fusion sur `develop` / `main` | images Docker, scan Trivy, publication dans GHCR, attestation ; issue `publish-failure` en cas d'échec |
| [`release.yml`](.github/workflows/release.yml) | CD réussie, puis push du tag | version SemVer, `CHANGELOG.md`, tag `X.Y.Z` sur les images, release GitHub avec le JAR et le build du front |

Pour livrer, il suffit de fusionner une PR dont les commits suivent les *Conventional Commits* :
- `fix(...)` produit un correctif ;
- `feat(...)` produit une évolution ;
- `develop` produit une release candidate (`X.Y.Z-rc.N`), `main` une version finale.

Secrets nécessaires dans le dépôt : `SONAR_TOKEN_BACK`, `SONAR_TOKEN_FRONT`, `RELEASE_TOKEN`.

## 6. Documentation

| # | Document | Contenu |
|---|---|---|
| 01 | [Fonctionnement du projet](documentation/01-fonctionnement-du-projet.md) | présentation de l'application |
| 02 | [Analyse des tests existants](documentation/02-analyse-tests-existants.md) | état initial des tests |
| 03 | [Contraintes techniques CI/CD](documentation/03-contraintes-techniques-cicd.md) | limites de départ et priorités |
| 04 | [Plan de testing périodique](documentation/04-plan-testing-periodique.md) | quels tests, quand |
| 05 | [Plan de sécurité](documentation/05-plan-securite.md) | risques, mesures en place, plan d'action |
| 06 | [Principes de conteneurisation et de déploiement](documentation/06-conteneurisation-deploiement.md) | stratégie |
| 07 | [Pipeline CI](documentation/07-pipeline-ci.md) | `ci.yml` |
| 08 | [Conteneurisation](documentation/08-conteneurisation.md) | Dockerfile, Compose, choix techniques |
| 09 | [Déploiement](documentation/09-deploiement.md) | `cd.yml`, images, exceptions de sécurité |
| 10 | [Releases](documentation/10-release.md) | `release.yml`, versions, artefacts |
| 11 | [Supervision ELK](documentation/11-supervision-elk.md) | stack ELK, tableau de bord Kibana |
| 12 | [Métriques DORA et KPI](documentation/12-dora-kpi.md) | indicateurs et méthode de calcul |
| 13 | [Analyse SonarQube](documentation/13-analyse-sonar.md) | vulnérabilités, dette, alertes prioritaires |
| 14 | [Plan de déploiement](documentation/14-plan-deploiement.md) | comment, dans quel ordre, prérequis, retour arrière |
| 15 | [Plan de sauvegarde](documentation/15-plan-sauvegarde.md) | données, fréquence, méthode, restauration |
| 16 | [Plan de mise à jour](documentation/16-plan-mise-a-jour.md) | mises à jour, dépendances, préproduction |

## 7. Limites connues

Le détail et les actions prévues sont dans les plans [05](documentation/05-plan-securite.md) et [16](documentation/16-plan-mise-a-jour.md).

- **Pas d'authentification sur l'API**, et CORS ouvert : l'application ne doit pas être exposée publiquement en l'état.
- **Base HSQLDB en mémoire** : les données repartent du jeu de démonstration à chaque redémarrage.
- **URL de l'API fixée au build** (`http://localhost:8080`) : le front et le back doivent tourner sur la même machine.
- **Versions de départ conservées volontairement** : Spring Boot 3.2.5 et Angular 17 ne sont plus supportés. Les CVE du back sont acceptées jusqu'au 31/01/2027, et la migration est planifiée.
- **Déploiement manuel** : il n'y a pas encore de serveur de préproduction ni de production.
