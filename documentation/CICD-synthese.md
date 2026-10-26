---
title: "MicroCRM – Synthèse CI/CD"
author: "Michael Delamarre"
---

# Synthèse CI/CD de MicroCRM

![Pipeline CI/CD](pipeline-cicd.jpeg)

## Ce qui est en place

| Étape | Déclencheur | Contrôles / actions |
|-------|-------------|---------------------|
| CI sur PR | PR vers `develop` / `main` (pas de CI sur simple push de branche ; push sur `main` : tests + Sonar) | Tests, build, lint, SonarQube (back et front, quality gate bloquant), Gitleaks, CodeQL, Dependency Review, `npm audit`, build des images et démarrage avec healthchecks ; Trivy ; `ci-ok` requis |
| Publication `develop` | Fusion sur `develop` | Build, scan Trivy, puis push GHCR `<sha>`, `develop`, `SNAPSHOT` |
| Release `main` | Fusion sur `main` | Build + scan Trivy avant push `<sha>` → semantic-release (tag, changelog, GitHub Release) → retag `X.Y.Z` et `latest` |
| Analyse nocturne (préparée, non active) | Chaque nuit (`misc/ci/nightly.yml`, à copier dans `.github/workflows/`) | SBOM CycloneDX et rapport de vulnérabilités des images `:develop` et `:main`, `npm audit`, dépendances Gradle ; rapports en artefacts |
| Échec de publication | Un job de `cd.yml` en échec | Issue créée ou commentée |

Flux : `feature/fix → develop → main`, sans branches `release/*`. La pipeline livre des **images versionnées** ; le déploiement n'est pas automatisé.

## Points clés

- **Scan avant publication** : l'image est construite et scannée localement, puis poussée seulement si Trivy est vert.
- **Une seule construction** : l'image testée (`<sha>`) est promue en `X.Y.Z`, sans reconstruction.
- **Version automatique** d'après les commits conventionnels (`fix:` correctif, `feat:` mineure, `feat!:` majeure).
- **Secrets** : `SONAR_TOKEN_BACK` et `SONAR_TOKEN_FRONT` (deux projets Sonar), `RELEASE_TOKEN` (PAT pour pousser changelog et tag sur `main` protégée).
- **Back** : Spring Boot 4.1.1, Gradle 8.14.5, Java 17 ; Tomcat et Jackson surchargés pour des CVE.
- **Images** : une par service (`back`, `front`) ; la cible `standalone` (Caddy + Java via supervisord) a été supprimée.
- **Compose** : `compose.yml` construit depuis le Dockerfile (CI) et porte les healthchecks (`front` attend `back` *healthy*), `compose.release.yml` exécute les images GHCR (`TAG` obligatoire, profil `prod`).

## Pour aller plus loin

[01 Pipeline CI/CD](01-pipeline-ci-cd.md) · [02 Tests, sécurité, déploiement](02-plan-tests-securite-deploiement.md) · [03 Supervision ELK](03-supervision-elk.md) · [04 DORA et KPI](04-dora-kpi.md)
