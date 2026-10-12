---
title: "MicroCRM – Plan CI/CD : tests, sécurité et déploiement"
author: "Michael Delamarre"
---

# Introduction

## Objectif du document

Définir **quand**, **comment** et **dans quel objectif** les tests, les contrôles de sécurité et le déploiement de MicroCRM sont exécutés automatiquement par la chaîne d'intégration et de déploiement continus (CI/CD).

## Périmètre

- Application : MicroCRM (monorepo)
  - `back/` : Spring Boot 3, Java 17, Gradle
  - `front/` : Angular 17, Karma/Jasmine
- Plateforme CI/CD : GitHub Actions
- Livrables conteneurisés : `Dockerfile` multi-stage (cibles `front`, `back`, `standalone`)

## Structure du document

1. Plan de testing périodique
2. Plan de sécurité
3. Principes de conteneurisation et de déploiement

## Glossaire

| Terme | Définition |
|-------|------------|
| CI | Intégration continue : build et tests à chaque modification |
| CD | Livraison / déploiement continu |
| SAST | Analyse statique du code source |
| SCA | Analyse des dépendances tierces |
