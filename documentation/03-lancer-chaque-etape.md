# Lancer chaque étape

Prérequis locaux : JDK 17, Node 20, Docker (avec Compose), Chrome/Chromium pour Karma (`CHROME_BIN`).

## 1. Back (`cd back`)

| Étape | Commande | CI | Sortie |
|-------|----------|----|--------|
| Lancer en dev | `SPRING_PROFILES_ACTIVE=dev ./gradlew bootRun` | – | http://localhost:8080 |
| Tests | `./gradlew test` (profil `test` imposé par `build.gradle`) | `back-tests` | `build/reports`, `build/test-results`, JaCoCo XML |
| Lint | `./gradlew checkstyleMain checkstyleTest` (0 avertissement toléré) | `linter-back` | `build/reports/checkstyle` |
| Build | `./gradlew build -x test` | `build`, `codeql` | `build/libs/microcrm.jar` |

## 2. Front (`cd front`)

| Étape | Commande | CI | Sortie |
|-------|----------|----|--------|
| Dépendances | `npm ci` | tous les jobs front | – |
| Lancer en dev | `npm start` | – | http://localhost:4200 |
| Tests | `npm run test:ci` (config `test`, `ChromeHeadlessNoSandbox`, couverture) | `front-tests` | `coverage/microcrm/lcov.info` |
| Lint | `npm run lint -- --format html --output-file eslint-report.html` | `linter-front` | `eslint-report.html` |
| Build | `npm run build` | `build` | `dist/microcrm/browser` |

## 3. Qualité et sécurité

| Étape | Lancement | Remarque |
|-------|-----------|----------|
| SonarQube | Automatique en CI après les tests (`sonar`) | Lit `sonar-project.properties` et les rapports JaCoCo / lcov ; local : non prévu |
| Gitleaks | Automatique en CI (`secrets`) | Historique complet |
| CodeQL, Dependency Review, `npm audit` | Automatiques sur PR uniquement | `npm audit` est informatif (`--audit-level=none`) ; Dependency Review bloque à partir de *high* |
| Trivy local | `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity CRITICAL --ignore-unfixed microcrm-back` | Après un build Compose |

## 4. Docker et Compose (racine)

| Besoin | Commande |
|--------|----------|
| Développer avec le code local | `docker compose -f compose.yml -f compose.dev.yml up --build` |
| Reproduire le test de fumée de la CI | `docker compose -f compose.yml -f compose.test.yml up -d --build --wait --wait-timeout 120` puis `curl http://localhost:8080/organizations` ; arrêt : `docker compose -f compose.yml -f compose.test.yml down -v` |
| Image de `develop` (sans compiler) | `TAG=SNAPSHOT RELEASE_PROFILE=dev` + `compose.release.yml` — voir [Lancer une image publiée](#lancer-une-image-publiée-selon-los) |
| Version publiée | `TAG=1.2.0` + `compose.release.yml` (profil `prod` par défaut) — voir [Lancer une image publiée](#lancer-une-image-publiée-selon-los) |
| Une seule image | `docker build --target back -t microcrm-back .` (ou `front`) |

- Le front est servi sur https://localhost (certificat auto-signé de Caddy), l'API sur http://localhost:8080.
- `TAG` est obligatoire avec `compose.release.yml` ; `docker login ghcr.io` si les packages sont privés.
- Retour arrière : relancer avec le `TAG` d'une version précédente (`X.Y.Z` ou SHA), toujours présent dans GHCR.

### Lancer une image publiée (selon l'OS)

La syntaxe `VAR=valeur commande` ne marche qu'en bash/zsh. Exemple pour la version `1.2.0` ; pour l'image de `develop`, remplacer par `TAG=SNAPSHOT` et ajouter `RELEASE_PROFILE=dev`.

**Linux / macOS (bash, zsh) — et Git Bash sous Windows**

```shell
TAG=1.2.0 docker compose -f compose.yml -f compose.release.yml up -d
TAG=SNAPSHOT RELEASE_PROFILE=dev docker compose -f compose.yml -f compose.release.yml up -d
```

**Windows — PowerShell** (invite `PS C:\...>`)

```powershell
$env:TAG="1.2.0"; docker compose -f compose.yml -f compose.release.yml up -d
$env:TAG="SNAPSHOT"; $env:RELEASE_PROFILE="dev"; docker compose -f compose.yml -f compose.release.yml up -d
```

Les variables restent définies dans la session : `Remove-Item Env:TAG, Env:RELEASE_PROFILE` pour les effacer. Attention, `set` y est un alias de `Set-Variable` : la syntaxe cmd ne fonctionne pas.

**Windows — cmd**

```bat
set "TAG=1.2.0" && docker compose -f compose.yml -f compose.release.yml up -d
set "TAG=SNAPSHOT" && set "RELEASE_PROFILE=dev" && docker compose -f compose.yml -f compose.release.yml up -d
```

Garder les guillemets : sans eux, l'espace avant `&&` est inclus dans la valeur (tag invalide).

**Toutes plateformes** : écrire `TAG=1.2.0` (et éventuellement `RELEASE_PROFILE=dev`) dans un fichier `.env` à la racine, lu automatiquement par Compose, puis `docker compose -f compose.yml -f compose.release.yml up -d`.

## 5. Déclencher les workflows

| Pour lancer… | Faire |
|--------------|-------|
| `ci.yml` | Ouvrir ou mettre à jour une PR vers `develop` ou `main` (PR en brouillon pour un retour avant revue ; un simple push de branche ne déclenche plus la CI) |
| `cd.yml` sur `develop` | Fusionner une PR sur `develop` |
| `cd.yml` sur `main` (release) | Fusionner `develop` dans `main` avec au moins un `feat:` ou `fix:` |
| `nightly.yml` | Automatique chaque nuit (02 h UTC, depuis `main`) ; Actions → Nightly → *Run workflow* pour le lancer à la main |
| Relancer un job en échec | Onglet Actions → run → *Re-run failed jobs* |
| Lancement manuel | Actions → workflow → *Run workflow* (`workflow_dispatch`) ; `cd.yml` construit sans publier et ne lance pas la release |

## 6. Tester la release sans publier

```shell
npm ci                      # à la racine
GITHUB_TOKEN=<PAT> npx semantic-release --dry-run --no-ci --branches "$(git branch --show-current)"
```

Affiche la prochaine version et les notes, sans tag, push ni release.
