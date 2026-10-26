---
title: "MicroCRM – Plan de tests, de sécurité et de déploiement"
author: "Michael Delamarre"
---

# Plan de tests, de sécurité et de déploiement

Ce document résume les choix en place. Le détail se trouve dans [01 Pipeline CI/CD](01-pipeline-ci-cd.md), [03 Supervision ELK](03-supervision-elk.md) et [04 DORA et KPI](04-dora-kpi.md).

## 1. Plan de testing périodique

### 1.1 Types de tests

| Partie | Outils | Tests | Commande | Rapport |
|--------|--------|-------|----------|---------|
| **Back** (Spring Boot 4.1.1, Java 17) | JUnit 5, Spring Boot Test | `MicroCRMApplicationTests` : chargement du contexte Spring (`@SpringBootTest`)<br>`PersonRepositoryIntegrationTest` : intégration JPA sur la base en mémoire (`@DataJpaTest`) | `./gradlew test` (profil `test` imposé par `build.gradle`) | JaCoCo XML (couverture), rapports JUnit |
| **Front** (Angular) | Karma, Jasmine, Chrome headless | 6 fichiers de specs : composants (`app`, `main-dashboard`, `organization-details`, `person-details`) et services (`organization.service`, `person.service`) | `npm run test:ci` | lcov (couverture) |

Contrôles exécutés avec les tests :

| Contrôle | Outil | Ce qui est vérifié |
|----------|-------|--------------------|
| Build | Gradle (`build -x test`), Angular (`npm run build`) | Le code compile et produit le JAR et le bundle |
| Lint | Checkstyle (0 avertissement toléré), ESLint | Respect des conventions de code |
| Démarrage | `docker compose up -d --build` + healthchecks | Les images se construisent et démarrent : back sain (`/actuator/health`), front servi en HTTPS |
| Qualité | SonarQube Cloud | Couverture et quality gate (voir § 2) |

### 1.2 À quels moments

| Moment | Workflow | Tests exécutés |
|--------|----------|----------------|
| **Pull request** vers `develop` ou `main` (ouverture et chaque nouveau commit) | `ci.yml` | Tous : tests back et front, build, lint, Sonar, démarrage Compose, contrôles de sécurité ; job agrégé `ci-ok` |
| **Push sur une branche de travail** (`feature/**`, `fix/**`) | – | Aucun : la CI ne tourne que sur PR (ouvrir une PR en brouillon pour un retour rapide) |
| **Fusion** sur `develop` ou `main` | `cd.yml` | Pas de nouveaux tests : la protection de branche garantit que la CI est passée ; build et scan des images |
| **Manuel** | `ci.yml` / `cd.yml` (*Run workflow*) | Relance à la demande |
| **Périodique** (chaque nuit, 02 h UTC) | `nightly.yml` | Préparé dans `../../misc/ci`, **non actif** : SBOM et vulnérabilités des images publiées, `npm audit`, arbre Gradle |
| **En local** | `./gradlew test`, `npm run test:ci` | Avant d'ouvrir la PR |

### 1.3 Objectifs

| Objectif | Moyen |
|----------|-------|
| **Validation fonctionnelle** | Tests de composants et de services (front), tests d'intégration du repository et du contexte Spring (back) |
| **Non-régression** | Toute la suite est rejouée à chaque mise à jour de PR ; `ci-ok` est requis pour fusionner, une régression bloque donc la fusion |
| **Qualité** | Couverture mesurée (JaCoCo, lcov) et envoyée à Sonar ; lint bloquant ; quality gate bloquant |
| **Livrable fonctionnel** | Les images sont construites et démarrées avec healthchecks avant la fusion |

Indicateurs suivis ([04](04-dora-kpi.md)) : temps de build (92 s), temps des tests back (65 s) et front (61 s), couverture (36,9 %), taux d'échec de la CI.

**Limites et évolutions** : pas de tests end-to-end (Cypress, Playwright à choisir) ; couverture à remonter (objectif > 60 %, > 80 % sur le nouveau code) ; nightly à activer et à compléter par une suite de tests sans cache.

## 2. Plan de sécurité

### 2.1 Rôle de SonarQube Cloud

- **Analyse statique à chaque PR**, dans deux projets distincts : `mikedel88_microcrm_back` (Java, couverture JaCoCo) et `mikedel88_microcrm_front` (TypeScript, couverture lcov). Le back est analysé par le plugin Gradle `org.sonarqube` (configuration dans `build.gradle`), qui transmet classpath et classes main/test pour une analyse Java complète ; le front lit `../../front/sonar-project.properties`.
- **Quality gate bloquant** : le job attend le verdict de SonarCloud (`sonar.qualitygate.wait=true`). Un gate rouge fait échouer le job `sonar`, donc `ci-ok`, donc la fusion.
- Le gate par défaut porte sur le **nouveau code** : chaque PR doit être propre, sans exiger de corriger l'historique d'un coup.
- Les résultats se consultent dans l'onglet *Pull Requests* de chaque projet SonarCloud.

### 2.2 Problèmes surveillés

| Type | Ce que c'est | Valeur actuelle (nouveau code) | Objectif |
|------|--------------|--------------------------------|----------|
| **Vulnérabilités** | Faille exploitable (injection, configuration dangereuse…) | 0 | 0 |
| **Security hotspots** | Code sensible à revoir manuellement | 100 % revus | 100 % |
| **Bugs** | Erreur de fiabilité (comportement incorrect probable) | 0 | 0 |
| **Code smells** | Problème de maintenabilité (complexité, duplication, mauvaise pratique) | 0 | 0 |
| **Duplication** | Part de lignes dupliquées | 0,0 % | < 3 % |
| **Couverture** | Part du code exécutée par les tests | 36,9 % (globale) | > 60 %, > 80 % sur le nouveau code |

### 2.3 Bonnes pratiques dans la CI

**Gestion des secrets**
- Aucun secret dans le dépôt. **Gitleaks** analyse tout l'historique à chaque PR (bloquant). Le seul faux positif est justifié dans `.gitleaksignore`.
- Les secrets sont dans GitHub Actions : `SONAR_TOKEN_BACK`, `SONAR_TOKEN_FRONT`, `RELEASE_TOKEN`. Ils ne sont pas transmis aux PR venant de forks.
- `RELEASE_TOKEN` est un PAT *fine-grained*, limité au dépôt et avec expiration. En cas de fuite, on le révoque puis on le recrée.
- Les mots de passe ELK sont dans `.env.elk` (non versionné), créé à partir de `.env.elk.example`.

**Droits et branches**
- Permissions minimales : `contents: read` par défaut, élargies seulement pour le job qui en a besoin (`packages: write`, `security-events: write`, `contents: write` pour la release…).
- `develop` et `main` sont protégées : pas de push direct, PR et `ci-ok` obligatoires.

**Dépendances**

| Contrôle | Quand | Bloquant |
|----------|-------|----------|
| Dependency Review (vulnérabilités et licences des dépendances ajoutées) | PR | Oui, à partir de *high* |
| CodeQL (SAST Java/Kotlin et JS/TS) | PR | Selon la configuration GitHub |
| `npm audit` | PR | Non (informatif) |
| Trivy sur les images (sévérité CRITICAL, failles sans correctif ignorées) | PR et CD, **avant le push** | Oui |

- Versions maîtrisées : Gradle 8.14.5 (wrapper et `../../Dockerfile`), images `caddy:2.11.7-alpine` et `gradle:8.14.5-jdk17-alpine`. Les actions GitHub sont référencées par version majeure (`@v6`…).
- Quand une CVE touche une dépendance transitive, on force la version corrigée en attendant Spring Boot (`build.gradle` : Tomcat 11.0.25, Jackson 3.1.7).
- Traitement d'une vulnérabilité : lire le rapport, mettre à jour la dépendance ou l'image (ou forcer la version), puis relancer. Une image qui échoue au scan n'est jamais publiée.

**Images publiées** : attestation de provenance GitHub (`actions/attest`) à chaque publication.

### 2.4 Risques connus et évolutions

| Risque de l'application (non corrigé) | OWASP |
|---------------------------------------|-------|
| Aucune authentification ; l'API REST est ouverte en lecture et en écriture | A01, A07 |
| `@CrossOrigin` sans restriction ; pas d'en-têtes de sécurité dans Caddy ; URL de l'API en dur | A02 |
| Pas de journalisation de sécurité | A09 |

À mettre en place : Dependabot, hadolint, signature des images (cosign), SBOM attaché aux images, actions épinglées par SHA, activation du nightly, `npm audit` bloquant.

## 3. Principes de conteneurisation et de déploiement

### 3.1 Rôle du Dockerfile

Un `../../Dockerfile` unique à la racine, **multi-étapes**, produit **une image par service** :

| Étape | Image de base | Rôle |
|-------|---------------|------|
| `front-build` | `node:20-alpine` | `npm ci` puis `npm run build` (bundle Angular) |
| `front` | `caddy:2.11.7-alpine` | Sert le bundle en HTTPS (certificat interne, redirection du port 80) ; image finale du front |
| `back-build` | `gradle:8.14.5-jdk17-alpine` | Télécharge les dépendances (couche mise en cache) puis `bootJar` |
| `back` | `eclipse-temurin:17-jre-alpine` | Exécute le JAR sur le port 8080 ; image finale du back |

Principes :
- Les images finales ne contiennent que l'exécution (JRE, Caddy), pas les outils de build : elles sont plus légères et exposent moins de surface d'attaque.
- Elles tournent avec un utilisateur **non-root** (`USER app`).
- Le `../../.dockerignore` limite le contexte de build (pas de `node_modules`, `build`, `.git`).
- L'ancienne cible `standalone` (Caddy et Java dans une seule image via supervisord) a été supprimée : elle tournait en root, mélangeait deux processus dans un conteneur et produisait une image à publier en plus.

### 3.2 Rôle de Docker Compose

| Fichier | Rôle |
|---------|------|
| `../../compose.yml` | Construit les deux images depuis le `../../Dockerfile` et les lance ensemble (back 8080, front 80/443). Healthchecks : back sur `/actuator/health`, front en HTTPS ; le front attend que le back soit *healthy*. Profil Spring par `SPRING_PROFILES_ACTIVE` (`dev` par défaut). Utilisé en local et par la CI (job `buildx`). |
| `../../compose.release.yml` | Surcharge pour exécuter les **images publiées** sur GHCR (`TAG` obligatoire, profil `prod`), sans compiler. |
| `../../compose.elk.yml` (+ `elk.sh up / down`) | Stack de supervision Elasticsearch, Kibana, Logstash, Filebeat, Metricbeat (TLS et authentification), projet Compose distinct : voir [03](03-supervision-elk.md). |

### 3.3 Stratégie de déploiement

**En place : publication d'images versionnées**

| Événement | Résultat dans GHCR (`ghcr.io/mikedel88/microcrm-{back,front}`) |
|-----------|---------------------------------------------------------------|
| Fusion sur `develop` | Build, scan Trivy, puis push des tags `<sha>`, `develop`, `SNAPSHOT` ; attestation |
| Fusion sur `main` | Build, scan, push de `<sha>` → **semantic-release** calcule la version d'après les commits conventionnels (tag `vX.Y.Z`, CHANGELOG, GitHub Release) → **promotion** : retag `X.Y.Z` et `latest` **sans reconstruire** |

- On construit une seule fois : l'image testée et scannée est celle qui est livrée.
- Le déploiement se fait avec `TAG=X.Y.Z docker compose -f compose.yml -f compose.release.yml up -d`.
- Retour arrière : relancer avec le `TAG` d'une version précédente, toujours présente dans GHCR.
- En cas d'échec de la CD, le job `notify-failure` ouvre ou commente une issue.

**Envisagé : déploiement automatisé**
- Workflow `deploy.yml` déclenché après la promotion : connexion SSH au serveur, puis `docker compose pull && up -d` avec le `TAG` publié.
- Environnements test, pré-production et production, avec approbation manuelle pour la production (*environments* GitHub).
- Rollback automatique si les healthchecks échouent après le déploiement.
- Prérequis : un hébergement, un nom de domaine (HTTPS public, en-têtes CSP et HSTS), l'URL de l'API lue à l'exécution plutôt qu'écrite en dur, et une base persistante à la place de HSQLDB en mémoire.
