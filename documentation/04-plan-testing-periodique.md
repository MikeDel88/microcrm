# Plan de testing périodique

Objectif : définir les tests qui seront exécutés automatiquement dans la future CI/CD, à quels moments, et dans quel but.

## Types de tests

| Partie | Test | Outil |
|--------|------|-------|
| Front | Tests unitaires des composants et des services, avec couverture | Karma + Jasmine (Chrome headless) |
| Front | Lint du code TypeScript et des templates | Linter Angular / TypeScript |
| Back | Tests unitaires et d'intégration (repositories, API REST), avec couverture | JUnit 5 + Spring Boot Test (HSQLDB en mémoire) |
| Back | Lint du code Java | Linter Java |
| Transverse | Build des deux applications | Gradle, Angular CLI |
| Transverse | Analyse de la qualité du code (duplication, complexité, couverture) | Outil d'analyse statique |
| Transverse | Analyse de sécurité : code, dépendances, secrets | Scanners de sécurité |
| Transverse | Build des images Docker, test de démarrage, scan des vulnérabilités | Docker, scanner d'images |

## Moments d'exécution

| Moment | Tests exécutés |
|--------|----------------|
| **Pull request** vers une branche principale | Tous les tests et contrôles ; la fusion est bloquée en cas d'échec |
| **Push sur la branche principale** (après fusion) | Tests front et back, analyse qualité, pour suivre la tendance |
| **Avant la publication d'une image** | Build et scan des images ; aucune image vulnérable n'est publiée |
| **Planifié (chaque nuit)** | Scan des dépendances et des images déjà publiées, pour repérer les CVE découvertes après la fusion |
| **En local** (avant chaque push) | `./gradlew test` et `npm test` |

## Objectifs

| Objectif | Tests associés |
|----------|----------------|
| **Validation fonctionnelle** | Tests unitaires et d'intégration, démarrage des conteneurs |
| **Non-régression** | Tests rejoués automatiquement à chaque PR et après chaque fusion |
| **Qualité** | Lint, analyse statique, quality gate, couverture minimale |
| **Sécurité** (complément) | Analyse du code, des dépendances, des secrets et des images |

## Points d'attention

- Les tests actuels sont surtout des tests de fumée (voir [02-analyse-tests-existants.md](02-analyse-tests-existants.md)). Il faudra les enrichir pour que la non-régression ait une vraie valeur.
- Le seuil de couverture sera fixé bas au départ, puis relevé progressivement.
- Les prérequis techniques (droit d'exécution de `gradlew`, Chrome headless) sont détaillés dans [03-contraintes-techniques-cicd.md](03-contraintes-techniques-cicd.md).
