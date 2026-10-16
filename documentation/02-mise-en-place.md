# Mise en place (réglages GitHub et secrets)

## 1. Secrets du dépôt (Settings → Secrets and variables → Actions)

| Secret | Utilisé par | Rôle |
|--------|-------------|------|
| `SONAR_TOKEN` | `ci.yml`, job `sonar` | Authentifie l'analyse SonarQube Cloud |
| `RELEASE_TOKEN` | `cd.yml`, job `release` | PAT : checkout et semantic-release (push du changelog et du tag sur `main` protégée) |
| `GITHUB_TOKEN` | `ci.yml`, `cd.yml` | Automatique : Gitleaks, GHCR, Trivy, issues |

Aucun secret n'est disponible pour les PR issues de forks.

### Créer `SONAR_TOKEN`

1. Sur SonarQube Cloud, importer le dépôt (organisation `mikedel88`, clé de projet `MikeDel88_microcrm`, voir `sonar-project.properties`).
2. Project → Administration → Analysis Method : **désactiver l'analyse automatique** (la CI envoie les rapports de couverture).
3. My Account → Security → générer un jeton.
4. Le coller dans le secret `SONAR_TOKEN`.

### Créer `RELEASE_TOKEN` (PAT)

Un PAT agit au nom de votre compte. Contrairement à `GITHUB_TOKEN` (éphémère, lié au bot), il est créé à la main et expire.

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token.
2. Repository access : uniquement `microcrm`. Expiration : 90 jours maximum conseillé.
3. Permissions : **Contents**, **Issues**, **Pull requests** en *Read and write*.
4. Copier le jeton (affiché une seule fois) dans le secret `RELEASE_TOKEN`.
5. Prévoir son renouvellement avant expiration, sinon le job `release` échoue.

## 2. Protection de `main` et `develop`

- Pull request obligatoire, check requis : **`ci-ok`** (seul check à exiger), force-push et suppression interdits.
- **Bypass pour le PAT** : le push du changelog et du tag se fait sans PR, au nom du propriétaire du PAT.
  - *Rulesets* : règle sur `main` → Bypass list → ajouter votre compte (ou *Repository admin*), mode *Always*.
  - *Branch protection* : décocher « Do not allow bypassing the above settings », ou ajouter votre compte dans « Allow specified actors to bypass required pull requests ».
  - Si une règle protège les tags `v*`, elle doit aussi l'autoriser.

## 3. Autres réglages

| Réglage | Pourquoi |
|---------|----------|
| Issues activées | `notify-failure` crée des issues |
| Dependency graph activé | Requis par Dependency Review |
| CodeQL en configuration avancée (workflow `ci.yml`) | Désactiver la configuration par défaut pour éviter le doublon |
| Packages GHCR : visibilité | Privés par défaut ; les rendre publics ou faire `docker login ghcr.io` pour les tirer |
| Actions → Workflow permissions | Les permissions sont déclarées dans les workflows |
| Branche `develop` créée à partir de `main` | Flux Git |

Gitleaks (`gitleaks-action`) fonctionne sans licence sur un dépôt personnel ; un dépôt d'organisation exige `GITLEAKS_LICENSE`.

## 4. Vérification de la mise en place

1. PR de test vers `develop` : tous les jobs de `ci.yml` passent et `ci-ok` est requis pour fusionner.
2. Fusion sur `develop` : les deux images apparaissent dans GHCR avec `<sha>`, `develop`, `SNAPSHOT`.
3. Avant la première release : `npx semantic-release --dry-run` (voir [03](03-lancer-chaque-etape.md)).
4. PR `develop` → `main` avec au moins un `feat:` ou `fix:` : tag `vX.Y.Z`, GitHub Release, `CHANGELOG.md`, images `X.Y.Z` et `latest`.
