# Feuille de route : mise en place de la CI/CD

> **Scénario A (pipeline idéal).** Le scénario B, adapté au contexte actuel, est décrit au chapitre 5.

Ce chapitre résume **dans quel ordre** mettre en place ce que décrivent les parties 1 à 3. Chaque étape renvoie à la section de référence.

| # | Étape | Résultat attendu | Référence |
|---|-------|------------------|-----------|
| 0 | Décisions préalables | Les points ouverts sont tranchés (voir ci-dessous) | Parties 1 à 3, « Points à valider » |
| 1 | Dépôt GitHub | Branche `develop`, environnements, `CODEOWNERS`, second relecteur | P2 § 5-6, P3 § 4 |
| 2 | Préparer le code | Tests et outils de qualité exécutables en ligne de commande | P1 § 4-5 |
| 3 | Workflow `ci.yml` puis protection des branches | Tests et qualité sur chaque push et PR ; PR obligatoire | P1 § 3.2, P2 § 6 |
| 4 | Sécurité sur PR | SAST, dépendances, secrets, seuils de gravité | P2 § 3-4 |
| 5 | Conteneurisation | `Dockerfile` corrigé, `compose.yml`, configuration à l'exécution | P3 § 1-2 |
| 6 | Images et publication | Build et test de fumée sur PR `develop` et `main` (scan sur `main`) ; après fusion : build, test, scan, puis publication GHCR | P3 § 3 |
| 7 | Déploiement `deploy.yml` | Test et pré-prod automatiques, prod après approbation, retour arrière | P3 § 4-5 |
| 8 | Exécution nocturne `nightly.yml` | Tests e2e sur test et pré-prod, issue en cas d'échec | P1 § 3.4 |
| 9 | Exécution hebdomadaire `weekly.yml` | Rebuild, scan, sauvegarde et test de restauration | P1 § 3.5-3.6 |
| 10 | Validation finale | Parcours complet vérifié, PDF généré | – |

## Étape 0 : décisions préalables

À trancher avant de commencer, car elles conditionnent plusieurs étapes :

- **Hébergement** cible (serveur avec Docker, plateforme managée) : détermine l'étape 7.
- **Base de données** : HSQLDB en mode fichier ou PostgreSQL ; elle est aujourd'hui en mémoire, donc sans persistance : détermine l'étape 9.
- **Méthode de sauvegarde** : volume ou dump.
- **Authentification** : oui ou non (sécurité, A01 et A07).
- **Outil e2e** : Cypress ou Playwright.
- **SonarQube Cloud** : dépôt public ou privé (limites de l'offre gratuite).
- **Version** : source unique entre `build.gradle` et `package.json`.

## Étape 1 : dépôt GitHub

- Créer la branche `develop` à partir de `main`.
- Créer les environnements GitHub `test`, `preprod` et `prod`, avec leurs secrets séparés ; approbation requise pour `prod`.
- Ajouter un fichier `CODEOWNERS` couvrant `.github/workflows/`, le `Dockerfile` et les fichiers Compose.
- Disposer d'un second compte relecteur.
- **Ne pas encore activer** les règles de protection : elles exigent des vérifications qui n'existent pas avant l'étape 3.

## Étape 2 : préparer le code

- Karma en `ChromeHeadless` avec option `--no-sandbox` pour la CI.
- Back : JaCoCo, Checkstyle ou SpotBugs. Front : ESLint (`ng lint`), couverture Karma.
- Configuration SonarQube Cloud (plugin Gradle `org.sonarqube`, import des rapports de couverture).
- Vérifier en local que `./gradlew test`, `ng test --watch=false` et les analyses passent avant de les mettre en CI.

## Étape 3 : `ci.yml` et protection des branches

- Déclencheurs : push sur `features/*` et `fix/*`, PR vers `develop` et `main`.
- Jobs en parallèle : tests back, tests front, qualité (SonarQube Cloud).
- Cache, annulation des exécutions concurrentes, permissions minimales.
- **Ensuite**, activer la protection de `develop` et `main` : PR obligatoire, une approbation, vérifications requises, aucun push direct (administrateurs inclus), force-push interdit.

## Étape 4 : sécurité sur PR

- CodeQL, Dependency Review, `npm audit`, OWASP Dependency-Check, Gitleaks ; Dependabot activé.
- Seuils de gravité : critique et élevée bloquent. Premier scan à lire avant de bloquer, pour ajuster le bruit initial.
- Ajouter ces contrôles aux vérifications requises.

## Étape 5 : conteneurisation

- `Dockerfile` : images épinglées, JDK aligné, utilisateur non-root, `HEALTHCHECK`, `-x test`.
- Rendre l'URL de l'API configurable à l'exécution (aujourd'hui en dur : `localhost:8080`), condition pour réutiliser la même image dans tous les environnements.
- `compose.yml` commun et surcharges par environnement ; volume pour la base.
- Créer les profils Spring `dev`, `test`, `preprod`, `prod` (`application-<profil>.properties`) : `dev` pour le travail sur une feature ou un fix, `test` pour l'exécution des tests (la CI active `test`, jamais `dev`).
- **Avant l'étape 6**, car la publication a besoin d'images correctes.

## Étape 6 : images et publication

- PR vers `develop` et `main` : build des cibles et test de fumée sur image jetable ; scan Trivy sur `main` en plus. Ce scan a révélé des CVE qui ont imposé le passage à Spring Boot 4 (voir [plan de sécurité § 7](02-plan-de-securite.md#retour-dexpérience--cve-détectées-par-trivy-et-passage-à-spring-boot-4)).
- Fusion sur `develop` ou `main` (`cd.yml`) : build des cibles `back` et `front` du `Dockerfile` (une image chacune) et publication dans GHCR avec les tags SHA et nom de branche, plus `SNAPSHOT` sur `develop`.
- Fusion sur `main` : **semantic-release** calcule la version d'après les commits conventionnels (`feat:` → mineure, `fix:` → correctif, `BREAKING CHANGE` → majeure), met à jour `CHANGELOG.md`, crée le tag `vX.Y.Z` et la GitHub Release. Les images `:sha` sont d'abord scannées (Trivy, critique bloquant) ; si semantic-release crée une version, elles sont **retaguées** `X.Y.Z` et `latest` sans reconstruction (même digest que le SHA testé). Sans commit `feat:`/`fix:`, aucune release.
- Les branches `release/*` du Git Flow ne sont pas utilisées : semantic-release remplace ce rôle. Flux : `feature/*`/`fix/*` → `develop` → `main`.
- **Secret `RELEASE_TOKEN`** : un PAT (Personal Access Token, jeton généré depuis le compte GitHub et agissant en son nom, à droits limités) est nécessaire pour que semantic-release pousse le commit du changelog sur `main` protégée. Fine-grained, limité au dépôt, avec `Contents`, `Issues` et `Pull requests` en lecture/écriture, expiration à renouveler (90 jours conseillé) ; son propriétaire doit pouvoir contourner la protection de `main`. Stocké dans les secrets Actions, jamais dans le dépôt.

## Étape 7 : déploiement

- `deploy.yml` : connexion à la machine cible, `docker compose pull` puis `up -d` avec le tag voulu.
- Test automatique (`develop`), pré-production automatique (`main`), production manuelle avec approbation, **même SHA que la pré-production**.
- Healthcheck, test de fumée, retour arrière automatique en cas d'échec.

## Étape 8 : exécution nocturne

- `nightly.yml` à 02:00 UTC, matrice `develop` et `main`, sans cache.
- Tests e2e sur test et pré-production, audit des dépendances.
- Échec : notification et création d'une issue, avec commentaire plutôt que doublon.
- **Prérequis** : environnements déployés (étape 7) et tests e2e écrits.

## Étape 9 : exécution hebdomadaire

- `weekly.yml` le dimanche à 03:00 UTC : rebuild sans cache, scan Trivy.
- Sauvegarde puis test de restauration de la base en pré-production.
- **Prérequis** : base persistante.

## Étape 10 : validation finale

Dérouler le parcours complet : branche `features/test` → PR → `develop` (déploiement test) → PR → `main` (déploiement pré-prod) → approbation → production. Provoquer ensuite un échec volontaire pour vérifier le retour arrière et l'issue nocturne. Générer enfin le PDF à partir des fichiers Markdown.

## Dépendances à respecter

- Étape 3 **avant** la protection des branches.
- Étape 5 **avant** l'étape 6.
- Étape 7 **avant** l'étape 8 (les e2e ont besoin d'instances déployées).
- Persistance de la base **avant** l'étape 9.

## Phasage et réalisme

MicroCRM est une application de démonstration : base en mémoire, aucune authentification, aucun test e2e, aucun CI existant, hébergement non défini. Le plan décrit l'**architecture cible** ; il se met en place en trois phases, chacune utile seule.

| Phase | Contenu | Étapes | Prérequis |
|-------|---------|--------|-----------|
| **1. Socle** | `ci.yml`, protection des branches, SonarQube Cloud, CodeQL, détection de secrets, Dependabot, correctifs du `Dockerfile`, publication GHCR | 1 à 4, 5 (Dockerfile), 6 (publication) | Dépôt GitHub uniquement |
| **2. Déploiement** | `compose.yml`, URL de l'API configurable, un premier environnement, test de fumée, pré-production, déploiement automatique | 5 (Compose), 7 (test, pré-prod) | Hébergement défini |
| **3. Conditionnel** | Tests e2e nocturnes, sauvegarde et test de restauration, `rollback.yml`, production avec approbation | 7 (prod), 8, 9 | Base persistante, tests e2e écrits, environnements déployés |

Ce qui est **volontairement lourd pour une démonstration** et peut être allégé sans remettre en cause le plan :

- plusieurs outils d'analyse qui se recoupent (SonarQube Cloud, CodeQL, OWASP Dependency-Check, Trivy) : en démarrer deux ou trois, ajouter les autres si le bruit reste acceptable ;
- quatre environnements (dev local, test, pré-production, production) : test et pré-production peuvent être fusionnés au départ ;
- signature des images (cosign) : non retenue en phase 1.

### Hypothèses à vérifier

| Hypothèse | Pourquoi elle compte |
|-----------|----------------------|
| **Visibilité du dépôt** (public ou privé) | La protection de branches, les approbations d'environnement et l'offre gratuite de SonarQube Cloud dépendent du plan GitHub et de la visibilité ; en privé, les minutes GitHub Actions sont aussi limitées |
| **Développeur seul ou équipe** | En solo, l'approbation d'un second relecteur est impraticable : variante « PR obligatoire sans approbation exigée » (plan de sécurité § 6) |
| **Hébergement disponible** | Sans serveur ou plateforme, les phases 2 et 3 restent théoriques |
| **Durée des pipelines** | À mesurer après la phase 1 ; cibles de 10 minutes sur push et 20 minutes sur PR (partie 1, § 5) |
| **Clé d'API NVD** pour OWASP Dependency-Check | Sans elle, les téléchargements de base de vulnérabilités sont très lents |
