---
title: "MicroCRM – Plan CI/CD : tests, sécurité et déploiement"
author: "Michael Delamarre"
---

# Introduction

## Objectif du document

Définir **quand**, **comment** et **dans quel objectif** les tests, les contrôles de sécurité et le déploiement de MicroCRM sont exécutés automatiquement par la chaîne d'intégration et de déploiement continus (CI/CD).

## Périmètre

- Application : MicroCRM (monorepo)
  - `back/` : Spring Boot 4, Java 17, Gradle 8.14
  - `front/` : Angular 17, Karma/Jasmine
- Plateforme CI/CD : GitHub Actions
- Livrables conteneurisés : `Dockerfile` multi-stage (cibles `front` et `back`)

## Deux scénarios

Le document distingue deux scénarios, pour ne pas confondre ce qui est visé et ce qui est réalisable aujourd'hui :

| Scénario | Description | Chapitres |
|----------|-------------|-----------|
| **A. Pipeline idéal** | Architecture cible complète : quatre environnements (développement, test, pré-production, production), tests e2e nocturnes, sauvegarde et restauration, retour arrière, production avec approbation | 1 à 4 |
| **B. Contexte actuel du projet** | Version adaptée à l'état réel de MicroCRM : application de démonstration, base en mémoire, sans authentification, sans hébergement ni tests e2e | 5 |

Le scénario B est un **sous-ensemble** du scénario A : tout ce qu'il met en place est conforme au scénario A, et ce qu'il omet est repris par phases (chapitre 4, « Phasage »).

## Structure du document

1. Plan de testing périodique (scénario A)
2. Plan de sécurité (scénario A)
3. Principes de conteneurisation et de déploiement (scénario A)
4. Feuille de route : mise en place du pipeline idéal (scénario A)
5. Scénario adapté au contexte actuel du projet (scénario B)
6. Images Docker, Caddy et HEALTHCHECK (complément du chapitre 3)

## Glossaire

| Terme | Définition |
|-------|------------|
| CI | Intégration continue : build et tests à chaque modification |
| CD | Livraison / déploiement continu |
| SAST | Analyse statique du code source |
| SCA | Analyse des dépendances tierces |
