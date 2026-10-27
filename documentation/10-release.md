# Releases GitHub automatisées

Objectif : produire automatiquement des **versions numérotées** (SemVer) de MicroCRM, avec une release GitHub, ses artefacts (JAR et build Angular) et un changelog à jour. Chaque commit fusionné sur `develop` produit une **release candidate**, et chaque fusion sur `main` une **version finale**.

Fichiers : `.github/workflows/release.yml`, `.releaserc.json` (configuration de semantic-release), `package.json` racine (outillage).

## Vue d'ensemble

```
fusion sur develop/main ─► CD (cd.yml) : images scannées et publiées dans GHCR
                                      │ succès
                                      ▼
                           job version : semantic-release
                             ├─ calcule la version depuis les commits
                             ├─ met à jour CHANGELOG.md + commit "chore(release): X.Y.Z"
                             └─ pousse le tag vX.Y.Z (ou vX.Y.Z-rc.N)
                                      │
push du tag v*.*.* ─────────► job publish : images GHCR retaguées X.Y.Z ─► build JAR + Angular ─► release GitHub + artefacts
```

**La release ne part qu'après une CD réussie** (déclencheur `workflow_run`). L'enchaînement complet est : CI (`ci-ok` sur la PR) → fusion → CD → release. Une version n'est donc créée que si les images Docker du même commit ont passé le scan et sont publiées. Si la CD échoue (scan Trivy par exemple), aucune version n'est créée.

Les deux jobs sont **découplés par le tag** : le job `publish` se déclenche sur n'importe quel tag `vX.Y.Z`, qu'il ait été créé par semantic-release ou poussé à la main. C'est la **détection de tag**.

### Détails du déclenchement après la CD

- **Seule une CD lancée par un push compte** : un lancement manuel de la CD ne publie aucune image et ne déclenche donc pas de release.
- **Seul le commit validé est versionné** : si la branche a reçu un commit plus récent entre la CD et la release, le job s'arrête sans rien publier. La CD de ce nouveau commit déclenchera sa propre release.
- **Branche réelle** : sur un événement `workflow_run`, GitHub fournit la référence de la branche par défaut (`main`). Le job extrait donc la branche de la CD et lance semantic-release de façon à ce qu'il lise cette branche dans git, avec `--no-ci`. Sans cela, une RC de `develop` serait calculée comme une version de `main`.
- **Pas de boucle** : le commit `chore(release)` relance la CD puis ce workflow, mais aucune nouvelle version n'est créée.

## Versions

| Branche | Version produite | Type de release |
|---------|------------------|-----------------|
| `develop` | `vX.Y.Z-rc.N` (ex. `v1.2.0-rc.1`, puis `-rc.2`…) | *Pre-release* (release candidate) |
| `main` | `vX.Y.Z` (ex. `v1.2.0`) | Release finale (*latest*) |

La version est calculée par semantic-release à partir des messages de commits (*Conventional Commits*) écrits depuis la dernière version :

| Commit | Effet |
|--------|-------|
| `fix: …` | Patch : `1.1.0` → `1.1.1` |
| `feat: …` | Minor : `1.1.0` → `1.2.0` |
| `feat!: …` ou `BREAKING CHANGE:` dans le corps | Major : `1.1.0` → `2.0.0` |
| `chore`, `docs`, `refactor`, `ci`, `test`… | Pas de nouvelle version |

## Changelog et commit de release

À chaque version, semantic-release :
1. ajoute une section à `CHANGELOG.md` (features, bug fixes, liens vers les commits) ;
2. commite le fichier : `chore(release): X.Y.Z` ;
3. pose le tag `vX.Y.Z` sur ce commit et le pousse.

Le commit de release ne déclenche pas de nouvelle version, car c'est un `chore` : il n'y a pas de boucle. Il ne contient pas `[skip ci]`, sinon GitHub ignorerait aussi le push du tag et la release ne serait jamais créée.

## Artefacts de la release

| Fichier | Contenu |
|---------|---------|
| `microcrm-X.Y.Z.jar` | API Spring Boot exécutable (`java -jar`) |
| `microcrm-front-X.Y.Z.zip` | Build Angular de production (`dist/microcrm/browser`), à servir par un serveur web |
| `SHA256SUMS.txt` | Sommes de contrôle pour vérifier l'intégrité des fichiers |

## Images Docker de la version

Avant de créer la release, le job `publish` ajoute le tag de version aux images déjà publiées par la CD : `ghcr.io/mikedel88/microcrm-back:X.Y.Z` et `ghcr.io/mikedel88/microcrm-front:X.Y.Z` (ou `X.Y.Z-rc.N` pour une RC).

- **Sans rebuild** : `docker buildx imagetools create` ajoute un tag à l'image existante. Le job vérifie ensuite que le tag `X.Y.Z` a **le même digest** que l'image source. L'image d'une version est donc celle que la CD a scannée par Trivy et attestée.
- **Quelle image** : le tag `vX.Y.Z` pointe sur le commit `chore(release)`, qui ne modifie que `CHANGELOG.md`. L'image retenue est celle de son **parent**, le commit dont la CD a réussi et qui a déclenché la version. Pour un tag posé à la main sur un autre commit, c'est l'image de ce commit qui est prise (ou, à défaut, celle de son parent).
- **Pas d'image, pas de release** : si aucune image n'existe pour ces commits, le job échoue avant de créer la release.
- Le résumé du run liste les deux images, leur commit source et leur digest.

Le job reçoit pour cela la permission `packages: write`. Le `GITHUB_TOKEN` suffit, aucun secret supplémentaire n'est nécessaire.

Les versions antérieures à cette évolution (v1.0.0 à v1.1.2) n'ont pas de tag `X.Y.Z` dans GHCR. Pour elles, on déploie le SHA du commit parent du tag (`git rev-parse vX.Y.Z^`).

## Notes de la release

Les notes de la release reprennent la section de la version dans `CHANGELOG.md`. Pour un tag poussé à la main sans entrée dans le changelog, GitHub génère les notes automatiquement. Les tests ne sont pas relancés : le code a déjà passé la CI (`ci-ok`) avant la fusion.

## Créer une release manuellement

```shell
git tag v1.3.0 && git push origin v1.3.0      # version finale
git tag v1.3.0-rc.1 && git push origin v1.3.0-rc.1   # pre-release (le "-" suffit)
```

Si la release existe déjà, ses artefacts sont remplacés : relancer le job ne crée pas de doublon.

## Prérequis

- **`release.yml` présent sur `main`** : GitHub n'active un déclencheur `workflow_run` que depuis la branche par défaut. Tant que le fichier n'y est pas fusionné, aucune release automatique ne part, même pour `develop`.
- **Secret `RELEASE_TOKEN`** : PAT avec le droit `contents: write` sur le dépôt, autorisé à contourner la protection de `develop` et `main`. Il sert à pousser le commit de changelog et le tag. Un tag poussé avec le `GITHUB_TOKEN` par défaut ne déclencherait pas le job `publish`.
- **Commits conventionnels** sur les branches fusionnées (titres de PR en *squash merge*, par exemple).
- **Tags** : Faire cette fusion `main` → `develop` après chaque version finale, pour récupérer le commit de changelog.

## Suivre les résultats

- **Onglet *Releases*** : versions, notes et artefacts téléchargeables. Les RC sont marquées *Pre-release*.
- **Onglet *Actions* > Release** : logs du calcul de version et de la publication.
- **`CHANGELOG.md`** à la racine du dépôt.

## Limites et évolutions

- Le commit `chore(release)` relance la CD, qui publie une image pour ce commit. Cette image n'est pas celle de la version (voir « Images Docker de la version »), mais elle occupe de la place dans GHCR.
- Le changelog est commité sur `develop` à chaque RC, ce qui ajoute un commit `chore(release)` par fusion.
