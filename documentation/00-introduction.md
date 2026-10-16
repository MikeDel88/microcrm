---
title: "MicroCRM – Documentation CI/CD"
author: "Michael Delamarre"
---

# Introduction

Cette documentation décrit la pipeline CI/CD **telle qu'elle est en place** : quand elle s'exécute, pourquoi, ce qui se passe en cas d'échec, comment la configurer et comment lancer chaque étape. Ce qui n'est pas encore en place est regroupé dans [06-evolutions.md](06-evolutions.md).

## Stack : état initial et état actuel

L'état initial est celui du premier commit (`323c2e1`, application fournie). Les versions ont été modifiées ensuite pour corriger des CVE (voir [04](04-securite.md#3-spring-boot-4-et-cve-historique)).

| Élément | **Initial** | **Actuel** |
|---------|-------------|------------|
| Spring Boot | 3.2.5 | **4.1.1** |
| Plugin `io.spring.dependency-management` | 1.1.4 | 1.1.7 |
| Gradle (wrapper) | 8.7 | **8.14.5** (aussi dans le `Dockerfile`) |
| Java | 17 (JDK build) ; **JRE 21** à l'exécution (`openjdk21-jre-headless`) | 17 partout (`eclipse-temurin:17-jre-alpine`) |
| Tomcat / Jackson | Versions du BOM Spring Boot | Surchargées : Tomcat 11.0.25, Jackson BOM 3.1.7 |
| Front | Angular 17.3, TypeScript 5.4 | Inchangé ; Node 20 figé (`node:20-alpine`) |
| Images de base | `node`, `gradle:jdk17` (non épinglées), `alpine:3.19` (3 cibles dont `standalone`) | `node:20-alpine`, `gradle:8.14.5-jdk17-alpine`, `caddy:2.11.7-alpine`, `eclipse-temurin:17-jre-alpine` |
| Qualité | Aucune | Checkstyle 10.17, ESLint, JaCoCo, SonarQube Cloud |
| CI/CD | Aucune | GitHub Actions : `ci.yml` et `cd.yml` |
| Release | Aucune | semantic-release (`.releaserc.json`, `package.json` à la racine) |
| Conteneurs | `Dockerfile` (dont une cible `standalone`, supprimée : voir [05 § 2](05-conteneurisation.md#2-suppression-de-la-cible-standalone)) et `.dockerignore` minimal, utilisateur root | Cibles `back` et `front` non-root, Compose, registre GHCR |

## Fichiers

| Document | Contenu |
|----------|---------|
| [01-pipeline-ci-cd.md](01-pipeline-ci-cd.md) | Branches, déclencheurs, jobs, échecs, tags d'images |
| [02-mise-en-place.md](02-mise-en-place.md) | Réglages GitHub, secrets, PAT, SonarQube Cloud |
| [03-lancer-chaque-etape.md](03-lancer-chaque-etape.md) | Commandes locales et déclenchement de chaque étape |
| [04-securite.md](04-securite.md) | Contrôles, seuils, historique Spring Boot / CVE |
| [05-conteneurisation.md](05-conteneurisation.md) | `Dockerfile`, Compose, Caddy, healthchecks |
| [06-evolutions.md](06-evolutions.md) | Ce qui reste à faire |
| [CICD-synthese.md](CICD-synthese.md) | Synthèse d'une page, avec le schéma |

## Glossaire

| Terme | Définition |
|-------|------------|
| CI | Intégration continue : build, tests et contrôles à chaque modification |
| CD | Livraison continue : ici, publication d'images versionnées (pas de déploiement automatique) |
| PAT | *Personal Access Token* : jeton généré depuis un compte GitHub, qui agit au nom de ce compte avec des droits limités |
| SHA | Identifiant du commit ; sert de tag immuable d'image |
| SAST | Analyse statique du code |
