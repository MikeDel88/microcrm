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
| Push `feature/**`, `fix/**` | `ci.yml` | Tests back et front, build, Checkstyle, ESLint, SonarQube, Gitleaks | Retour rapide au développeur |
| PR vers `develop` ou `main` | `ci.yml` | Idem + CodeQL, Dependency Review, `npm audit`, build des images et test de fumée (`compose.test.yml`) ; **Trivy** si la cible est `main` ; job `ci-ok` | Condition de fusion |
| Push (fusion) sur `develop` | `cd.yml` | Build `back` et `front`, push GHCR (`<sha>`, `develop`, `SNAPSHOT`), attestation | Image d'intégration |
| Push (fusion) sur `main` | `cd.yml` | build → scan Trivy → release → promotion | Livrer une version |

Jobs de `cd.yml` sur `main` :

1. **build** : images `microcrm-back` et `microcrm-front` taguées `<sha>` et `main`.
2. **scan** : Trivy (CRITICAL, vulnérabilités sans correctif ignorées) sur `:<sha>`.
3. **release** : semantic-release (secret `RELEASE_TOKEN`) : version, `CHANGELOG.md` commité, tag `vX.Y.Z`, GitHub Release.
4. **promote** (si une version est créée) : retag de `:<sha>` en `:X.Y.Z` et `:latest`, **sans reconstruire**.
5. **notify-failure** : si un des jobs échoue.

`ci.yml` annule les exécutions concurrentes d'une même branche. `workflow_dispatch` est disponible sur les deux workflows ; en manuel, `cd.yml` construit sans publier et ne lance pas la release.

## 3. En cas d'échec

| Où | Conséquence | Action |
|----|-------------|--------|
| Push de branche | Check rouge, rien d'autre | Corriger et repousser |
| PR | `ci-ok` rouge : fusion bloquée | Corriger sur la branche de PR |
| `build` | Rien de publié ; issue ouverte | Relancer le job si cause temporaire, sinon PR de correction |
| `scan` (CVE critique) | Ni tag, ni changelog, ni release, ni `X.Y.Z` ; issue ouverte | Corriger la dépendance ou l'image de base, nouvelle PR |
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
