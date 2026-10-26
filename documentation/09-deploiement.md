# Déploiement : publication des images Docker

Objectif : à chaque fusion, produire automatiquement des images Docker du front et du back. Ces images sont **scannées**, **publiées** dans le registre de conteneurs GitHub (GHCR) et **traçables** jusqu'au commit. Ce document applique la stratégie de [06-conteneurisation-deploiement.md](06-conteneurisation-deploiement.md).

Fichier : `.github/workflows/cd.yml`

## Vue d'ensemble

```
PR ─► ci.yml (ci-ok) ─► fusion ─► cd.yml : build ─► scan Trivy ─► push GHCR
                                              └─ échec ─► issue publish-failure
```

La CD n'appelle pas la CI. C'est la **protection de branche** qui garantit l'ordre : une PR ne peut être fusionnée que si `ci-ok` est vert (voir [07-pipeline-ci.md](07-pipeline-ci.md)). Seul du code testé et analysé arrive donc dans la CD.

## Déclencheurs

| Événement | Résultat |
|-----------|----------|
| Push sur `develop` (fusion d'une PR) | Images d'intégration publiées |
| Push sur `main` (fusion d'une PR) | Images candidates à la livraison publiées |
| Lancement manuel (`workflow_dispatch`) | Build et scan uniquement, **rien n'est publié** |

## Job `build`

Un job par image (matrice `back` / `front`, cibles du `Dockerfile`), exécutés en parallèle :

| Étape | Rôle |
|-------|------|
| Build local | Construit l'image dans le runner, sans la publier ; cache GitHub Actions entre les runs |
| Scan Trivy | Une vulnérabilité **CRITICAL** pour laquelle un correctif existe fait échouer le job. L'image n'est alors jamais poussée |
| Push GHCR | Publie l'image saine avec ses tags (le cache rend ce second build quasi instantané) |
| Attestation | Signe la provenance de l'image : quel workflow et quel commit l'ont produite |

Le job `notify-failure` ouvre une issue `publish-failure` si le build, le scan ou le push échoue. S'il en existe déjà une ouverte pour la branche, il la commente.

## Tags publiés

Images : `ghcr.io/mikedel88/microcrm-back` et `ghcr.io/mikedel88/microcrm-front`

| Tag | Quand | Usage |
|-----|-------|-------|
| `<sha>` (SHA complet du commit) | Chaque publication | **Immuable : à utiliser pour déployer** |
| `develop` / `main` | Selon la branche | Tag mobile : dernière image de la branche |
| `SNAPSHOT` | Sur `develop` | Tag mobile : dernière image d'intégration |

## Déployer une image publiée

`compose.release.yml` surcharge `compose.yml` : les images sont **tirées de GHCR** au lieu d'être construites, et le profil Spring `prod` est forcé.

```shell
docker login ghcr.io                     # si les packages sont privés
TAG=<sha> docker compose -f compose.yml -f compose.release.yml up -d
```

Pour revenir en arrière (**rollback**), relancer la même commande avec le SHA précédent. L'image est déjà dans le registre, aucun rebuild n'est nécessaire.

## Garanties

- **Aucune image vulnérable publiée** : le scan a lieu avant le push.
- **Seul du code validé est publié** : protection de branche et `ci-ok`.
- **Traçabilité** : tag SHA et attestation de provenance.
- **Moindre privilège** : `contents: read` par défaut ; `packages: write`, `id-token: write` et `attestations: write` sont accordés au seul job `build`. `GITHUB_TOKEN` suffit pour GHCR, aucun secret supplémentaire n'est nécessaire.
- **Pas d'écrasement** : deux publications d'une même branche s'enchaînent, aucune n'est annulée.

## Suivi

- **Actions > CD** : état de chaque run, avec les logs du build et du scan.
- **Page *Packages* du dépôt** : images publiées et tags disponibles.
- **Issues `publish-failure`** : échecs de publication.

## Évolutions prévues

- **Versions et releases GitHub** : mises en place par le workflow `release.yml` (voir [10-release.md](10-release.md)). Reste à retaguer l'image `<sha>` déjà publiée en `X.Y.Z`, sans rebuild.
- **Déploiement automatique** sur un serveur cible. Aujourd'hui, la commande compose est lancée manuellement.

## Limites

- L'URL de l'API du front est fixée au build (`http://localhost:8080`).
- La base HSQLDB est en mémoire : les données sont perdues à chaque redéploiement.
