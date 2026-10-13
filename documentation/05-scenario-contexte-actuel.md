# Scénario B : pipeline adapté au contexte actuel du projet

> Ce chapitre décrit ce qui est **réalisable aujourd'hui** sur MicroCRM. Le scénario A (chapitres 1 à 4) reste la cible ; le scénario B en est un sous-ensemble.

## 1. Contexte pris en compte

| Élément | État actuel | Conséquence |
|---------|-------------|-------------|
| Application | Démonstration : deux entités (personnes, organisations) | Pipeline proportionné |
| Base de données | HSQLDB **en mémoire**, rechargée au démarrage | Aucune sauvegarde ni restauration à prévoir |
| Authentification | Aucune | Signalée comme risque (A01, A07), non corrigée par le pipeline |
| Tests | 2 classes JUnit (back), 6 fichiers Karma (front), aucun e2e | Pas de tests e2e, couverture à mesurer d'abord |
| CI existant | Aucun | Tout est à créer |
| Hébergement | Non défini | Aucun déploiement vers un serveur |
| Équipe | Supposée : un seul développeur | Pas d'approbation d'un second relecteur |
| Dépôt GitHub | Visibilité à confirmer | Conditionne protection de branches et offre SonarQube Cloud |

## 2. Ce que le pipeline fait

### 2.1 Branches

Identique au scénario A : `features/*` ou `fix/*` → PR → `develop` → PR → `main`. Aucun push direct sur `develop` ni `main`. **Variante solo** : la PR et les vérifications obligatoires sont exigées, mais pas l'approbation d'un relecteur.

### 2.2 Événements et contrôles

| Événement | Contrôles |
|-----------|-----------|
| Push sur `features/*` ou `fix/*` | Tests unitaires et d'intégration (back et front), build, SonarQube Cloud, détection de secrets |
| PR vers `develop` | Idem, plus CodeQL, Dependency Review, `npm audit`, build de l'image et test de fumée (sans publication) |
| PR vers `main` | Idem, plus **scan Trivy** de l'image ; build et test de fumée s'exécutent dans le runner (`docker compose` ou `docker run`, sans serveur) |
| Fusion sur `develop` | Build, test de fumée, puis publication dans GHCR : tags SHA, `develop`, `X.Y.Z-SNAPSHOT` ; SBOM de l'image (Trivy) en artefact |
| Fusion sur `main` | Build, test de fumée, puis publication dans GHCR : tags SHA, `main`, `vX.Y.Z` ; SBOM joint à la release |
| Chaque nuit | Suite complète sans cache et audit des dépendances sur `develop` et `main` ; échec = notification + issue |
| Chaque semaine | Rebuild des images sans cache, scan Trivy et rescan des SBOM publiés ; revue des tests instables |

### 2.3 Seuils

- Couverture : **mesurer et publier sans bloquer** tant que la base de référence n'est pas connue (partie 1, § 5, phase 1).
- Vulnérabilités critiques et élevées : bloquantes sur PR (partie 2, § 4). Premier scan lu avant d'activer le blocage.
- Le quality gate de SonarQube Cloud est **adapté** : le seuil par défaut de 80 % de couverture sur le code nouveau est abaissé au départ.

### 2.4 Conteneurisation

- Corrections du `Dockerfile` : voir chapitre 3, § 2.2 (une partie est déjà appliquée ; restent `front` en non-root et les digests).
- URL de l'API rendue configurable à l'exécution (aujourd'hui `http://localhost:8080` fixée à la compilation dans `front/src/environments/environment.production.ts`), faute de quoi l'image ne fonctionne qu'en local.
- Un `compose.yml` unique, servant au **développement local** et au **test de fumée en CI**.

### 2.4 bis Environnements

- **Développement** (poste local) : profil `dev`, utilisé pour une feature ou un correctif.
- **Test** (runner GitHub Actions) : profil `test`, utilisé par la CI pour tous les tests ; jamais la configuration de dev.
- Pré-production et production : non mis en place (pas d'hébergement).

### 2.5 « Déploiement »

Sans hébergement, le déploiement se limite à la **publication des images** dans GHCR. Une personne peut lancer l'application avec `docker compose` en indiquant le tag voulu. La mise en ligne sur un serveur est reportée.

### 2.6 Retour arrière

Revenir à une version précédente consiste à relancer `docker compose` avec le tag immuable précédent (SHA ou `vX.Y.Z`), toujours disponible dans le registre. Aucun workflow dédié n'est nécessaire.

## 3. Ce qui est volontairement omis

| Élément du scénario A | Raison de l'omission | Condition de reprise |
|-----------------------|----------------------|----------------------|
| Environnements test déployé, pré-production, production | Pas d'hébergement | Hébergement défini |
| `deploy.yml` et `rollback.yml` | Rien à déployer | Environnement disponible |
| Tests e2e nocturnes | Aucun test e2e | Outil choisi et tests écrits |
| Sauvegarde et test de restauration | Base en mémoire | Base persistante |
| Approbation d'un second relecteur | Développeur seul | Équipe de plus d'une personne |
| OWASP Dependency-Check, signature des images | Redondants avec Dependency Review et Trivy ; coûteux en temps | Besoin d'une couverture plus large |
| Authentification et conformité RGPD | Hors périmètre du pipeline | Décision fonctionnelle |

## 4. Comparaison des deux scénarios

| Sujet | A. Pipeline idéal | B. Contexte actuel |
|-------|-------------------|--------------------|
| Environnements | développement (local), test, pré-production, production | Développement (local, profil `dev`) et test (runner CI, profil `test`) ; aucun environnement déployé |
| Déploiement | Automatique (test, pré-prod), manuel avec approbation (prod) | Publication des images dans GHCR |
| Tests e2e | Chaque nuit sur test et pré-production | Absents |
| Sauvegarde / restauration | Hebdomadaire | Non applicable |
| Retour arrière | Automatique et workflow manuel | Relance avec le tag précédent |
| Relecture | Second relecteur obligatoire | PR obligatoire, approbation non exigée |
| Analyse de dépendances | Dependency Review, `npm audit`, OWASP Dependency-Check | Dependency Review, `npm audit` |
| Workflows | `ci.yml`, `deploy.yml`, `rollback.yml`, `nightly.yml`, `weekly.yml` | `ci.yml`, `publish.yml`, `nightly.yml`, `weekly.yml` |

## 5. Mise en place du scénario B

### 5.1 Vue d'ensemble

La mise en place suit l'ordre ci-dessous. Les étapes 2 et 3 créent les environnements **développement** et **test** ; les autres s'appuient sur eux.

| # | Étape | Résultat |
|---|-------|----------|
| 1 | Créer `develop`, protéger `develop` et `main` | Modèle de branches en place (voir hypothèses, § 6) |
| 2 | **Environnement de développement** (§ 5.2) | Profil `dev`, lancement local documenté |
| 3 | **Environnement de test** (§ 5.3) | Profil `test`, utilisé par la CI |
| 4 | Préparer le code : Karma headless, JaCoCo, ESLint, SonarQube Cloud | Mesures de qualité disponibles |
| 5 | Écrire `ci.yml` (push, PR) puis activer la protection de branches | Tests exécutés dans l'environnement de test |
| 6 | Ajouter CodeQL, Dependency Review, détection de secrets, Dependabot | Contrôles de sécurité |
| 7 | Corriger le `Dockerfile`, écrire `compose.yml` (§ 5.4) | Image fonctionnelle dans les deux environnements |
| 8 | Build et test de fumée sur PR (scan sur `main`), puis `publish.yml` : build, test de fumée, scan, push GHCR et tags | Images publiées |
| 9 | Écrire `nightly.yml` (suite complète, audit, issue) et `weekly.yml` (rebuild, scan) | Contrôles périodiques |
| 10 | Valider (§ 5.5) | Parcours complet vérifié |

### 5.2 Environnement de développement (poste local)

Objectif : travailler sur une feature ou un fix avec une configuration propre, sans toucher à celle des tests.

1. **Back** : créer `back/src/main/resources/application-dev.properties` (HSQLDB en mémoire avec les données de démonstration de `InitialDataFixture`, SQL et logs détaillés). Activer le profil avec `SPRING_PROFILES_ACTIVE=dev` (ou `./gradlew bootRun --args='--spring.profiles.active=dev'`).
2. **Front** : `front/src/environments/environment.ts` (par défaut pour `ng serve`) définit `apiBaseUrl` ; `src/app/config.ts` expose `API_BASE_URL` à partir de cet environnement. Dans le scénario B, cette valeur ne sert **qu'au développement** : pour l'image, elle devient configurable (§ 5.4).
3. **Lancement** : soit `./gradlew bootRun` et `ng serve` séparément, soit `docker compose -f compose.yml -f compose.dev.yml up`.
4. **Règles** : aucun secret réel (valeurs factices uniquement) ; le travail se fait sur `features/*` ou `fix/*` ; les tests lancés ici servent au retour rapide et ne valident rien (la validation se fait dans l'environnement de test).

### 5.3 Environnement de test (runner GitHub Actions)

Objectif : exécuter tous les tests dans un environnement reproductible, jetable et indépendant du poste.

1. **Back** : créer `back/src/test/resources/application-test.properties` (HSQLDB en mémoire recréée à chaque exécution, jeu de données fixe, logs réduits). `build.gradle` impose `SPRING_PROFILES_ACTIVE=test` à la tâche `test`, en local comme en CI.
2. **Front** : `front/src/environments/environment.test.ts`, substitué par la configuration Angular `test` (`fileReplacements`) ; Karma en mode headless via `npm run test:ci` (`--configuration=test`, `ChromeHeadlessNoSandbox`, avec couverture), sans dépendance au back réel.
3. **Instance de test** : pour le test de fumée, `ci.yml` démarre l'image avec `docker compose -f compose.yml -f compose.test.yml up -d`, attend les healthchecks, vérifie `GET /organizations` et la page d'accueil (voir `exemples/ci.yml`), puis détruit les conteneurs (`down -v`). Rien ne persiste après l'exécution.
4. **Règles** : les tests ne s'exécutent jamais avec le profil `dev` ; l'environnement est recréé à chaque exécution (PR, push sur `develop`/`main`, nuit) ; pas de secret nécessaire, la base étant en mémoire.

### 5.4 Configuration commune

| Élément | Développement | Test |
|---------|---------------|------|
| Profil Spring | `dev` | `test` |
| Où | Poste du développeur | Runner GitHub Actions |
| Déclenchement | Manuel | PR, push sur `develop`/`main`, nuit |
| Base | HSQLDB en mémoire, données de démonstration | HSQLDB en mémoire, jeu de données fixe |
| Compose | `compose.yml` + `compose.dev.yml` (déjà créés à la racine) | `compose.yml` + `compose.test.yml` |
| Secrets | Aucun réel | Aucun nécessaire |

- L'**image est la même** dans les deux environnements ; seules la configuration (variables `SPRING_PROFILES_ACTIVE`, URL de l'API) et le fichier de surcharge Compose changent.
- Prérequis du `Dockerfile` : URL de l'API lue à l'exécution (aujourd'hui figée à la compilation dans `environment.production.ts`), sans quoi l'image ne fonctionne qu'en local.
- Quand un hébergement existera, les profils `preprod` et `prod` s'ajouteront selon le même modèle (chapitre 3, § 4.3).

### 5.5 Validation

1. Lancer l'application en développement (§ 5.2) et vérifier que le front joint le back.
2. Ouvrir une branche `features/test` → PR vers `develop` : vérifier dans les journaux que les tests tournent avec le profil `test` et que le test de fumée démarre puis détruit l'instance.
3. Fusionner sur `develop`, puis PR vers `main`, et vérifier les images publiées et leurs tags.
4. Casser volontairement un test : la PR doit être bloquée.

## 6. Hypothèses à confirmer

| Hypothèse | Si elle est fausse |
|-----------|--------------------|
| Dépôt **public** | En privé, la protection de branches peut exiger un plan GitHub payant, SonarQube Cloud est limité, et les minutes GitHub Actions sont plafonnées |
| Développeur **seul** | Avec plusieurs personnes, rétablir l'approbation d'un relecteur |
| Pas d'hébergement à court terme | Dès qu'un serveur existe, passer à la phase 2 du chapitre 4 |

## 7. Évolution vers le scénario A

Les phases du chapitre 4 sont l'itinéraire de passage de B à A : socle (déjà couvert par B), puis déploiement et environnements, puis éléments conditionnels (e2e, sauvegarde, rollback, production).
