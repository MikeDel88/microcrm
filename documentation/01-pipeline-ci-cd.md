# Pipeline CI/CD

![Pipeline CI/CD](pipeline-cicd.jpeg)

## 1. Flux Git

`feature/**` ou `fix/**` → PR → `develop` → PR → `main`.

- Aucun push direct sur `develop` ni `main` : PR obligatoire, check `ci-ok` requis.
- Pas de branches `release/*` : la version est calculée par semantic-release sur `main`.
- Commits **conventionnels** obligatoires pour produire une release (voir § 5).

## 2. Quand, quoi, pourquoi

| Événement | Workflow | Contrôles | Pourquoi |
|-----------|----------|-----------|----------|
| PR vers `develop` ou `main` | `ci.yml` | Tests back et front, build, Checkstyle, ESLint, SonarQube, Gitleaks, CodeQL, Dependency Review, `npm audit`, build des images et test de fumée (`compose.test.yml`) ; **Trivy** (même seuil que la CD) ; job `ci-ok` | Condition de fusion |
| Push (fusion) sur `develop` | `cd.yml` | Build `back` et `front`, scan Trivy, puis push GHCR (`<sha>`, `develop`, `SNAPSHOT`), attestation | Image d'intégration |
| Push (fusion) sur `main` | `cd.yml` | build + scan Trivy avant push → release → promotion | Livrer une version |
| Chaque nuit (02 h UTC) ou manuel | `nightly.yml` | Sur les images GHCR `:develop` et `:main` : SBOM CycloneDX, rapport de vulnérabilités (toutes sévérités), contrôle CRITICAL ; `npm audit` en JSON ; arbre de dépendances Gradle | Détecter les CVE publiées après la fusion |

La CI ne se déclenche plus sur les push de branche (`feature/**`, `fix/**`) : elle ne tourne que sur PR, ce qui évite la double exécution (push + PR) et fait de `ci-ok` le reflet de tous les contrôles. Pour un retour avant revue, ouvrir une PR en brouillon ou lancer `ci.yml` à la main.

Les résultats de l'analyse Sonar de chaque PR se consultent sur SonarQube Cloud (onglet Pull Requests du projet). `nightly.yml` publie les artefacts `nightly-<service>-<branche>` (SBOM `*.cdx.json` et `vulns-*.json`), `nightly-npm-audit` et `nightly-gradle-dependencies`. Un échec de l'analyse nocturne (CVE critique corrigeable) crée une issue `nightly-failure`. Un workflow planifié ne tourne que depuis la branche par défaut : `nightly.yml` doit être fusionné sur `main`.

La CD n'est pas chaînée à la CI : la protection de branche sur `develop` et `main` (PR obligatoire, `ci-ok` requis) garantit que le code fusionné a passé la CI.

Jobs de `cd.yml` :

1. **build** (matrice `back`, `front`) : construction locale de l'image, **scan Trivy** (CRITICAL, vulnérabilités sans correctif ignorées), puis push GHCR taguée `<sha>` et nom de branche (`SNAPSHOT` sur `develop`) **uniquement si le scan est vert**. Une image vulnérable n'est donc jamais publiée.
2. **release** (`main`) : semantic-release (secret `RELEASE_TOKEN`) : version, `CHANGELOG.md` commité, tag `vX.Y.Z`, GitHub Release.
3. **promote** (si une version est créée) : retag de `:<sha>` en `:X.Y.Z` et `:latest`, **sans reconstruire**.
4. **notify-failure** : si un des jobs échoue.

`ci.yml` annule les exécutions concurrentes d'une même PR. `workflow_dispatch` est disponible sur les deux workflows ; en manuel, `cd.yml` construit sans publier et ne lance pas la release.

## 3. En cas d'échec

| Où | Conséquence | Action |
|----|-------------|--------|
| PR | `ci-ok` rouge : fusion bloquée | Corriger sur la branche de PR |
| `build` (construction ou push) | Rien de publié ; issue ouverte | Relancer le job si cause temporaire, sinon PR de correction |
| `build`, étape scan (CVE critique) | Image non poussée, ni changelog, ni release, ni `X.Y.Z` ; issue ouverte | Corriger la dépendance ou l'image de base, nouvelle PR |
| `release` | Pas de version ; issue ouverte | Vérifier `RELEASE_TOKEN` (expiration, bypass de la protection) |
| `promote` | Release créée, tags `X.Y.Z`/`latest` absents ; issue ouverte | Relancer le job (aucune reconstruction) |

`notify-failure` crée une issue « Échec de publication – <branche> » (label `publish-failure`) ou la commente si elle existe déjà. Elle n'est pas refermée automatiquement. Les issues doivent être activées sur le dépôt.

## 4. Tags d'images (GHCR)

| Tag | Où | Nature | Usage |
|-----|----|--------|-------|
| `<sha>` (40 caractères) | `develop`, `main` | Immuable | Référence de déploiement |
| `develop` / `main` | Branche | Mobile | Dernier build de la branche |
| `SNAPSHOT` | `develop` | Mobile | Dernière image d'intégration |
| `X.Y.Z` | `main` | Immuable | Version livrée (tag Git `vX.Y.Z`) |
| `latest` | `main` | Mobile | Dernière version stable |

Images : `ghcr.io/mikedel88/microcrm-back` et `microcrm-front`. Les tags mobiles ne servent pas à déployer.

## 5. Versionnement (semantic-release)

| Commit | Effet |
|--------|-------|
| `fix: …` | Version corrective (`1.0.0` → `1.0.1`) |
| `feat: …` | Version mineure (`1.0.0` → `1.1.0`) |
| `feat!: …` ou pied `BREAKING CHANGE:` | Version majeure |
| `chore:`, `docs:`, `ci:`… | Aucune release |

- Aucun tag n'existait avant la mise en place : la première release (`v1.0.0`) analyse tout l'historique.
- Le commit de changelog (`chore(release): X.Y.Z [skip ci]`) est poussé sur `main` avec le PAT : `develop` doit ensuite recevoir `main` (règle « branche à jour »).
- La `version` de `back/build.gradle` n'est pas utilisée pour les images.
