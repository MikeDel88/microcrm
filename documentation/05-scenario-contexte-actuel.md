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

- Corrections du `Dockerfile` : versions épinglées, JDK aligné, utilisateur non-root, `HEALTHCHECK`, `-x test`.
- URL de l'API rendue configurable à l'exécution (aujourd'hui `http://localhost:8080` en dur dans `front/src/app/config.ts`), faute de quoi l'image ne fonctionne qu'en local.
- Un `compose.yml` unique, servant au **développement local** et au **test de fumée en CI**.

### 2.5 « Déploiement »

Sans hébergement, le déploiement se limite à la **publication des images** dans GHCR. Une personne peut lancer l'application avec `docker compose` en indiquant le tag voulu. La mise en ligne sur un serveur est reportée.

### 2.6 Retour arrière

Revenir à une version précédente consiste à relancer `docker compose` avec le tag immuable précédent (SHA ou `vX.Y.Z`), toujours disponible dans le registre. Aucun workflow dédié n'est nécessaire.

## 3. Ce qui est volontairement omis

| Élément du scénario A | Raison de l'omission | Condition de reprise |
|-----------------------|----------------------|----------------------|
| Environnements dev, pré-production, production | Pas d'hébergement | Hébergement défini |
| `deploy.yml` et `rollback.yml` | Rien à déployer | Environnement disponible |
| Tests e2e nocturnes | Aucun test e2e | Outil choisi et tests écrits |
| Sauvegarde et test de restauration | Base en mémoire | Base persistante |
| Approbation d'un second relecteur | Développeur seul | Équipe de plus d'une personne |
| OWASP Dependency-Check, signature des images | Redondants avec Dependency Review et Trivy ; coûteux en temps | Besoin d'une couverture plus large |
| Authentification et conformité RGPD | Hors périmètre du pipeline | Décision fonctionnelle |

## 4. Comparaison des deux scénarios

| Sujet | A. Pipeline idéal | B. Contexte actuel |
|-------|-------------------|--------------------|
| Environnements | dev, pré-production, production | Aucun (exécution locale ou dans le runner) |
| Déploiement | Automatique (dev, pré-prod), manuel avec approbation (prod) | Publication des images dans GHCR |
| Tests e2e | Chaque nuit sur dev et pré-production | Absents |
| Sauvegarde / restauration | Hebdomadaire | Non applicable |
| Retour arrière | Automatique et workflow manuel | Relance avec le tag précédent |
| Relecture | Second relecteur obligatoire | PR obligatoire, approbation non exigée |
| Analyse de dépendances | Dependency Review, `npm audit`, OWASP Dependency-Check | Dependency Review, `npm audit` |
| Workflows | `ci.yml`, `deploy.yml`, `rollback.yml`, `nightly.yml`, `weekly.yml` | `ci.yml`, `publish.yml`, `nightly.yml`, `weekly.yml` |

## 5. Mise en place du scénario B

1. Créer `develop` ; configurer la protection de `develop` et `main` (voir hypothèses ci-dessous).
2. Préparer le code : Karma headless, JaCoCo, ESLint, configuration SonarQube Cloud.
3. Écrire `ci.yml` (push, PR) puis activer la protection de branches.
4. Ajouter CodeQL, Dependency Review, détection de secrets, Dependabot.
5. Corriger le `Dockerfile`, rendre l'URL de l'API configurable, écrire `compose.yml`.
6. Ajouter le build et le test de fumée sur PR vers `develop` et `main` (scan sur `main`), puis `publish.yml` : build, test de fumée, scan, puis push GHCR et tags.
7. Écrire `nightly.yml` (suite complète, audit, issue) et `weekly.yml` (rebuild, scan).
8. Valider : branche `features/test` → PR → `develop` → PR → `main`, puis vérifier les images et leurs tags.

## 6. Hypothèses à confirmer

| Hypothèse | Si elle est fausse |
|-----------|--------------------|
| Dépôt **public** | En privé, la protection de branches peut exiger un plan GitHub payant, SonarQube Cloud est limité, et les minutes GitHub Actions sont plafonnées |
| Développeur **seul** | Avec plusieurs personnes, rétablir l'approbation d'un relecteur |
| Pas d'hébergement à court terme | Dès qu'un serveur existe, passer à la phase 2 du chapitre 4 |

## 7. Évolution vers le scénario A

Les phases du chapitre 4 sont l'itinéraire de passage de B à A : socle (déjà couvert par B), puis déploiement et environnements, puis éléments conditionnels (e2e, sauvegarde, rollback, production).
