---
title: "MicroCRM – Synthèse CI/CD"
author: "Michael Delamarre"
---

# Synthèse CI/CD de MicroCRM

![Pipeline CI/CD](pipeline-cicd.jpeg)

## Ce qui est en place

| Étape | Déclencheur | Contrôles / actions |
|-------|-------------|---------------------|
| CI sur branche | Push `feature/**`, `fix/**` | Tests, build, lint, SonarQube, Gitleaks |
| CI sur PR | PR vers `develop` / `main` | Idem + CodeQL, Dependency Review, `npm audit`, build des images et test de fumée ; Trivy vers `main` ; `ci-ok` requis |
| Publication `develop` | Fusion sur `develop` | Images GHCR `<sha>`, `develop`, `SNAPSHOT` |
| Release `main` | Fusion sur `main` | Images `<sha>` → scan Trivy → semantic-release (tag, changelog, GitHub Release) → retag `X.Y.Z` et `latest` |
| Échec de publication | Un job de `cd.yml` en échec | Issue créée ou commentée |

Flux : `feature/fix → develop → main`, sans branches `release/*`. La pipeline livre des **images versionnées** ; le déploiement n'est pas automatisé.

## Points clés

- **Une seule construction** : l'image testée (`<sha>`) est promue en `X.Y.Z`, sans reconstruction.
- **Version automatique** d'après les commits conventionnels (`fix:` correctif, `feat:` mineure, `feat!:` majeure).
- **Secrets** : `SONAR_TOKEN` (analyse), `RELEASE_TOKEN` (PAT pour pousser changelog et tag sur `main` protégée).
- **Back** : Spring Boot 4.1.1, Gradle 8.14.5, Java 17 ; Tomcat et Jackson surchargés pour des CVE.
- **Images** : une par service (`back`, `front`) ; la cible `standalone` (Caddy + Java via supervisord) a été supprimée, raisons en [05 § 2](05-conteneurisation.md#2-suppression-de-la-cible-standalone).
- **Compose** : `compose.yml` construit depuis le Dockerfile (CI), `compose.release.yml` exécute les images GHCR (`TAG` obligatoire, profil `prod`).

## Pour aller plus loin

[01 Pipeline](01-pipeline-ci-cd.md) · [02 Mise en place](02-mise-en-place.md) · [03 Lancer chaque étape](03-lancer-chaque-etape.md) · [04 Sécurité](04-securite.md) · [05 Conteneurisation](05-conteneurisation.md) · [06 Évolutions](06-evolutions.md)
