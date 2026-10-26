# Releases GitHub automatisées

Objectif : produire automatiquement des **versions numérotées** (SemVer) de MicroCRM, avec une release GitHub, ses artefacts (JAR et build Angular) et un changelog à jour. Chaque commit fusionné sur `develop` produit une **release candidate**, et chaque fusion sur `main` une **version finale**.

Fichiers : `.github/workflows/release.yml`, `.releaserc.json` (configuration de semantic-release), `package.json` racine (outillage).

## Vue d'ensemble

```
fusion sur develop/main ─► job version : semantic-release
                             ├─ calcule la version depuis les commits
                             ├─ met à jour CHANGELOG.md + commit "chore(release): X.Y.Z"
                             └─ pousse le tag vX.Y.Z (ou vX.Y.Z-rc.N)
                                      │
push du tag v*.*.* ─────────► job publish : build JAR + Angular ─► release GitHub + artefacts
```

Les deux jobs sont **découplés par le tag** : le job `publish` se déclenche sur n'importe quel tag `vX.Y.Z`, qu'il ait été créé par semantic-release ou poussé à la main. C'est la **détection de tag**.

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

Les notes de la release reprennent la section de la version dans `CHANGELOG.md`. Pour un tag poussé à la main sans entrée dans le changelog, GitHub génère les notes automatiquement. Les tests ne sont pas relancés : le code a déjà passé la CI (`ci-ok`) avant la fusion.

## Créer une release manuellement

```shell
git tag v1.3.0 && git push origin v1.3.0      # version finale
git tag v1.3.0-rc.1 && git push origin v1.3.0-rc.1   # pre-release (le "-" suffit)
```

Si la release existe déjà, ses artefacts sont remplacés : relancer le job ne crée pas de doublon.

## Prérequis

- **Secret `RELEASE_TOKEN`** : PAT avec le droit `contents: write` sur le dépôt, autorisé à contourner la protection de `develop` et `main`. Il sert à pousser le commit de changelog et le tag. Un tag poussé avec le `GITHUB_TOKEN` par défaut ne déclencherait pas le job `publish`.
- **Commits conventionnels** sur les branches fusionnées (titres de PR en *squash merge*, par exemple).
- **Tags** : Faire cette fusion `main` → `develop` après chaque version finale, pour récupérer le commit de changelog.

## Suivre les résultats

- **Onglet *Releases*** : versions, notes et artefacts téléchargeables. Les RC sont marquées *Pre-release*.
- **Onglet *Actions* > Release** : logs du calcul de version et de la publication.
- **`CHANGELOG.md`** à la racine du dépôt.

## Limites et évolutions

- Les images Docker publiées par `cd.yml` gardent leurs tags `<sha>` et de branche : elles ne sont pas encore retaguées en `X.Y.Z`. Pour déployer, la référence reste le SHA du commit (voir [09-deploiement.md](09-deploiement.md)). Une évolution possible : retaguer l'image `<sha>` en `X.Y.Z` dans le job `publish`, sans rebuild.
- Le changelog est commité sur `develop` à chaque RC, ce qui ajoute un commit `chore(release)` par fusion.
