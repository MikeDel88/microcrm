---
title: "MicroCRM – Synthèse CI/CD : testing, sécurité, conteneurisation et déploiement"
author: "Michael Delamarre"
---

# Synthèse CI/CD de MicroCRM

## 1. Objet et contexte

Ce document définit **quand**, **comment** et **dans quel objectif** les tests, les contrôles de sécurité et la publication de MicroCRM sont exécutés automatiquement avec **GitHub Actions**. Il décrit le pipeline **réalisable dans le contexte actuel du projet** ; ce qui est écarté est repris en partie 5 comme axes d'amélioration.

| Élément | État actuel | Conséquence |
|---------|-------------|-------------|
| Application | Démonstration : personnes et organisations. Back Spring Boot 3 (Java 17, Gradle), front Angular 17 | Pipeline proportionné |
| Base de données | HSQLDB en mémoire | Pas de sauvegarde à prévoir |
| Authentification | Aucune | Risque signalé, non corrigé par le pipeline |
| Tests | 2 classes JUnit, 6 fichiers Karma, aucun e2e | Couverture à mesurer avant tout seuil |
| CI existant | Aucun | Tout est à créer |
| Hébergement | Non défini | Pas de déploiement sur serveur |
| Équipe | Un seul développeur supposé | Pas d'approbation d'un second relecteur |

**Hypothèses à confirmer** : dépôt public (en privé, la protection de branches, l'offre SonarQube Cloud et les minutes GitHub Actions sont limitées) ; développeur seul ; pas d'hébergement à court terme.

## 2. Plan de testing périodique

### 2.1 Branches

`features/*` ou `fix/*` → PR → `develop` → PR → `main`. **Aucun push direct** sur `develop` ni `main` : toute modification passe par une pull request, imposée par les règles de protection de branche. Les workflows de fusion réagissent à l'événement `push` produit par la fusion, pas à un push de développeur.

### 2.2 Calendrier et contenu

| Fréquence | Déclencheur | Contrôles | Objectif |
|-----------|-------------|-----------|----------|
| Push sur `features/*` ou `fix/*` | `push` | Tests unitaires et d'intégration (back : `./gradlew test` ; front : `ng test --watch=false --browsers=ChromeHeadlessNoSandbox`), build, qualité de code (SonarQube Cloud, linters), détection de secrets | Retour rapide au développeur (cible : 10 min) |
| PR vers `develop` | `pull_request` | Idem, plus sécurité et dépendances (CodeQL, Dependency Review, `npm audit`), build de l'image et test de fumée sans publication | Condition de fusion |
| PR vers `main` | `pull_request` | Idem, plus scan Trivy de l'image (build et test de fumée dans le runner, comme pour `develop`) | Prouver que ce qui sera livré est construisible, sain et démarre (cible : 20 min) |
| Fusion sur `develop` / `main` | `push` (résultat de la fusion) | Mêmes contrôles ; build, test de fumée, scan puis publication des images | Vérifier que la branche reste livrable |
| Chaque nuit, 02:00 UTC | `schedule` | Suite complète sans cache, audit des dépendances, sur `develop` **et** `main` (matrice `ref`) | Détecter une régression survenue sans commit |
| Chaque semaine, dimanche 03:00 UTC | `schedule` | Rebuild des images sans cache, scan Trivy, rescan des SBOM, revue des tests instables | Contrôle approfondi |

### 2.3 Critères

- Tests, build et quality gate obligatoires ; sécurité obligatoire sur PR.
- **Couverture** : JaCoCo (back) et `--code-coverage` Karma (front). **Phase 1 : mesurer sans bloquer** ; phase 2 : seuil proche de la valeur mesurée, relevé progressivement. Le seuil par défaut de 80 % du quality gate SonarQube est abaissé au départ.
- Échec nocturne ou hebdomadaire : **notification et création d'une issue**. Si une issue est déjà ouverte pour la branche, un commentaire y est ajouté.
- Test instable : issue dédiée, désactivation temporaire commentée, jamais de suppression silencieuse ni de relance automatique généralisée.
- Rapports de tests et de couverture conservés comme artefacts du workflow.

## 3. Plan de sécurité

La démarche s'appuie sur l'**OWASP Top 10:2025**. Les contrôles automatisés ne couvrent qu'une partie des risques ; la revue de code obligatoire complète le dispositif.

### 3.1 Constats sur MicroCRM

- Aucune authentification ; Spring Data REST expose les dépôts en lecture et écriture (A01, A07).
- `@CrossOrigin` sans restriction (A02).
- Aucun en-tête de sécurité dans le `Caddyfile` (A02).
- Aucune journalisation configurée (A09).
- Images non épinglées, exécution en root (A02, A03).

### 3.2 Contrôles automatisés

| Contrôle | Outil | Quand |
|----------|-------|-------|
| Qualité et sécurité du code, quality gate | SonarQube Cloud | Push, PR, fusion |
| Détection de secrets | Gitleaks / secret scanning | Push, PR |
| Analyse statique (SAST) | CodeQL (Java, TypeScript) | PR |
| Dépendances et licences | Dependency Review, `npm audit` | PR ; `npm audit` aussi la nuit |
| Configuration du `Dockerfile` | hadolint | PR |
| Scan des images | Trivy | PR vers `main`, hebdomadaire |
| SBOM | Trivy (CycloneDX) | À chaque publication ; rescan hebdomadaire |
| Mises à jour de dépendances | Dependabot | Hebdomadaire |

Le SBOM (inventaire de tous les composants d'une image, y compris l'OS et le JRE) permet de savoir quelles versions livrées sont concernées par une vulnérabilité annoncée après coup.

### 3.3 Seuils et traitement

| Gravité | Sur PR | Délai de correction |
|---------|--------|---------------------|
| Critique (CVSS ≥ 9) | Bloque | 48 h |
| Élevée (7 à 8,9) | Bloque | 7 jours |
| Moyenne (4 à 6,9) | Avertit | 30 jours |
| Faible | Informe | Selon planification |

Les vulnérabilités sans correctif disponible sont consignées dans un fichier d'exceptions avec justification, responsable et **date d'expiration**. Le premier scan est lu avant d'activer le blocage, pour ajuster le bruit initial.

### 3.4 Secrets, branches et revue

- Aucun secret dans le dépôt ; secrets dans **GitHub Secrets** ; permissions des workflows minimales (`contents: read` par défaut) ; pas de secrets pour les PR de forks. En cas de fuite : révocation immédiate.
- Protection de `develop` et `main` : PR obligatoire, vérifications requises (tests, qualité, sécurité ; build de l'image et test de fumée ; sur `main`, en plus le scan), branche à jour, conversations résolues, force-push interdit, administrateurs inclus.
- **Variante solo** : l'approbation d'un relecteur n'est pas exigée, la PR et les vérifications le restent.
- `CODEOWNERS` sur `.github/workflows/` et le `Dockerfile`, qui contrôlent la chaîne de livraison.

## 4. Conteneurisation et déploiement

### 4.1 Rôle des fichiers

| | Dockerfile | Docker Compose |
|---|---|---|
| Répond à | *Comment construire une image ?* | *Comment faire tourner l'ensemble ?* |
| Utilisé par | Le job de build de la CI | Le développement local, le test de fumée en CI |

Le `Dockerfile` est multi-stage (compilation front et back, cibles `front` avec Caddy, `back` avec le JAR, `standalone`). Un `compose.yml` unique, à créer, décrit les services ; l'image est référencée par variable (`IMAGE_TAG`).

Quatre environnements, chacun avec sa configuration (profil Spring et variables) : **développement** (poste, profil `dev`), **test** (CI puis `develop`, profil `test`, où tournent tous les tests), **pré-production** (`main`) et **production** (promotion de la même image, après approbation).

### 4.2 Corrections prévues du `Dockerfile`

| Constat | Correction |
|---------|-----------|
| Images `node` et `gradle:jdk17` non épinglées | Épingler les versions (voire le digest) |
| JDK 17 au build, JRE 21 à l'exécution | Aligner les versions |
| Exécution en root | Utilisateur dédié (`USER`) |
| `EXPOSE 4200` sur l'image `back` (Spring écoute en principe sur 8080) | Vérifier et corriger |
| Aucun `HEALTHCHECK` | En ajouter un par cible |
| Tests relancés par `./gradlew build` dans l'image | `-x test`, déjà validés en amont |
| Deux processus dans `standalone` (supervisord) | Réserver cette cible au test de fumée et à la démonstration |
| URL de l'API en dur dans `front/src/app/config.ts` (`http://localhost:8080`) | Configuration lue à l'exécution (ou chemin relatif avec reverse proxy), sinon l'image ne fonctionne qu'en local |

### 4.3 Publication des images

Registre : **GitHub Container Registry**. Aucune image n'est construite sur un push de branche de travail ; sur PR, l'image est construite pour vérification seulement.

| Événement | Image | Tags |
|-----------|-------|------|
| PR vers `develop` ou `main` | Construite pour le test de fumée (et le scan sur `main`), non publiée | – |
| Fusion sur `develop` | Build, test de fumée, puis publiée | SHA du commit, `develop`, `X.Y.Z-SNAPSHOT` |
| Fusion sur `main` | Build, test de fumée, puis publiée | SHA du commit, `main`, `vX.Y.Z` |

Règles : le **SHA est immuable** et sert de référence pour déployer ; les tags de branche et `-SNAPSHOT` sont mobiles et ne servent jamais à déployer ; pas de tag `latest`. La version est lue dans `back/build.gradle`, jamais saisie à la main. Chaque image publiée est scannée et accompagnée de son SBOM (joint à la release pour `main`). Nettoyage : 20 derniers builds `develop` conservés, versions `vX.Y.Z` conservées.

**Valider avant la fusion, publier après** : build et test de fumée sont vérifiés sur la PR ; après la fusion, le workflow rejoue **build, test de fumée, scan, puis push**, afin de ne jamais publier une image qui n'a pas démarré. En cas d'échec après fusion, rien n'est publié ni déployé : relance du workflow si la cause est temporaire, sinon correctif ou revert par PR. Le tag de version et la release ne sont créés qu'après une publication réussie.

### 4.4 « Déploiement » et retour arrière

Sans hébergement, le déploiement se limite à la **publication des images**. L'application se lance avec `docker compose` en indiquant le tag voulu. Le **retour arrière** consiste à relancer avec le tag immuable précédent, toujours disponible dans le registre.

## 5. Axes d'amélioration et d'évolution

Ces éléments appartiennent au pipeline idéal. Ils sont reportés, chacun avec sa condition de reprise.

### 5.1 Pipeline idéal

| Évolution | Contenu | Condition de reprise |
|-----------|---------|----------------------|
| **Quatre environnements** | développement (poste local, configuration `dev`), test (CI puis `develop`, configuration `test`), pré-production (depuis `main`, réplique de la production), production | Hébergement défini |
| **Déploiement automatisé** | `deploy.yml` : connexion SSH, `docker compose pull` et `up -d` par SHA ; test et pré-production automatiques, production manuelle après approbation, **même image** promue sans reconstruction | Environnement disponible |
| **Retour arrière automatique** | Restauration de la version précédente si healthcheck ou test de fumée échoue ; workflow `rollback.yml` manuel | Premier environnement déployé |
| **Tests end-to-end nocturnes** | Sur test (`develop`) et pré-production (`main`), échec = notification et issue | Outil choisi (Cypress ou Playwright), tests écrits, environnements déployés |
| **Sauvegarde et test de restauration** | Hebdomadaire, en pré-production : sauvegarde, restauration isolée, comparaison des comptages, appel API. Sauvegarde du volume ou dump logique | Base persistante (HSQLDB en mode fichier avec volume, ou PostgreSQL) |
| **Second relecteur** | Approbation exigée sur `develop` et `main`, nouvelle approbation si le code change | Équipe de plus d'une personne |
| **Contrôles renforcés sur `main`** | Seuils de gravité plus stricts, e2e sur PR, branche source limitée à `develop` | Pipeline stabilisé |
| **Analyses complémentaires** | OWASP Dependency-Check (clé API NVD), signature des images (cosign) | Besoin de couverture plus large |
| **Règle de promotion** | Une issue nocturne ou hebdomadaire ouverte sur la pré-production est levée explicitement avant l'approbation de la production | Production en place |

### 5.2 Améliorations de l'application

- Introduire une **authentification et une autorisation** (Spring Security), restreindre CORS, limiter les ressources exposées par Spring Data REST (A01, A02, A07).
- Ajouter des **en-têtes de sécurité** dans Caddy (CSP, HSTS, X-Content-Type-Options) et une **journalisation** des événements de sécurité (A09).
- Gestionnaire d'erreurs global renvoyant des messages génériques (A10).
- Prendre en compte le **RGPD** (données de contacts) : minimisation, anonymisation hors production.
- Augmenter les tests (couverture, cas d'erreur, tests d'intégration sur l'accès aux données).
- Aligner les versions du front (`package.json`, `0.0.0`) et du back (`build.gradle`, `0.0.1-SNAPSHOT`).

### 5.3 Feuille de route

1. **Socle** (immédiat) : `ci.yml`, protection des branches, SonarQube Cloud, CodeQL, secrets, Dependabot, correctifs du `Dockerfile`, publication GHCR.
2. **Déploiement** : `compose.yml`, URL de l'API configurable, premier environnement, test de fumée, pré-production.
3. **Conditionnel** : e2e nocturnes, sauvegarde et restauration, `rollback.yml`, production avec approbation.

Une base de données persistante et un hébergement sont les deux prérequis qui débloquent la majeure partie des évolutions.

## Annexe : exemples de workflows GitHub Actions

Le dossier [`exemples/`](exemples/) traduit le calendrier de la partie 2 et les contrôles de la partie 3 en quatre workflows. Ils sont placés hors de `.github/workflows/` pour ne pas être activés avant que les prérequis soient en place.

| Fichier | Déclencheur | Rôle |
|---------|-------------|------|
| [`ci.yml`](exemples/ci.yml) | Push sur `features/**` et `fix/**`, PR vers `develop` et `main` | Tests, build, qualité, secrets ; sur PR : sécurité, dépendances, build et test de fumée de l'image, scan sur `main` |
| [`publish.yml`](exemples/publish.yml) | Fusion sur `develop` ou `main` | Build, test de fumée, scan, **puis** push dans GHCR (tags SHA, branche, version) ; SBOM ; release sur `main` ; issue en cas d'échec |
| [`nightly.yml`](exemples/nightly.yml) | Chaque nuit, 02:00 UTC | Tests et audit des dépendances sans cache, sur `develop` et `main` ; issue sans doublon en cas d'échec |
| [`weekly.yml`](exemples/weekly.yml) | Dimanche, 03:00 UTC | Rebuild des images sans cache et scan ; rescan des images publiées et des SBOM ; issue en cas d'échec |

**Le détail de `ci.yml`**

| Job | Déclencheur | Rôle |
|-----|-------------|------|
| `back-tests`, `front-tests`, `build` | Push et PR | Tests fonctionnels et build |
| `secrets` | Push et PR | Détection de secrets (Gitleaks) |
| `sonar` | Push et PR (pas les forks) | Qualité, couverture et quality gate (SonarQube Cloud) |
| `codeql`, `dependency-review`, `npm-audit`, `hadolint` | PR | Sécurité et dépendances |
| `docker-smoke` | PR | Build de l'image, test de fumée ; scan Trivy si la PR cible `main` |
| `ci-ok` | Toujours | Synthèse : **c'est la seule vérification à déclarer comme requise** dans la protection de branches |

**Prérequis**
- JaCoCo et `sonar-project.properties` ; secret `SONAR_TOKEN` ; dependency graph activé (dépôt public).
- Les corrections du `Dockerfile` et l'URL de l'API configurable à l'exécution.
- Pour `publish.yml` : la version de `back/build.gradle` sans suffixe `-SNAPSHOT` sur `main` (la PR `develop` → `main` retire le suffixe, sinon le workflow échoue volontairement). `weekly.yml` suppose une première publication.

**Limites** : les versions des actions sont à vérifier et à épingler par SHA ; aucun de ces workflows n'a été exécuté ; la création d'issue est dupliquée entre fichiers (une action composite l'éviterait). Les workflows du scénario A (`deploy.yml`, `rollback.yml`, e2e nocturnes, sauvegarde) ne sont pas fournis.
