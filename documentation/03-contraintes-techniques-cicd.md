# Contraintes techniques à prendre en compte dans la CI/CD

Objectif : recenser, à partir du socle MicroCRM actuel, les points techniques que le futur pipeline CI/CD devra gérer.

## Monorepo à deux piles

| Constat | À prévoir dans la CI/CD |
|---------|-------------------------|
| Back en Java 17 + Gradle 8.7 (wrapper) | Installer un JDK 17, mettre en cache les dépendances Gradle |
| Front en Node + Angular 17 (`package-lock.json` présent) | Installer Node, utiliser `npm ci`, mettre en cache npm |
| Deux applications indépendantes dans un même dépôt | Des jobs séparés pour le back et le front, exécutés en parallèle |

## Build et tests

| Constat | À prévoir dans la CI/CD |
|---------|-------------------------|
| `back/gradlew` n'a pas le droit d'exécution | Corriger le droit dans git, ou ajouter un `chmod +x` |
| Les tests front (Karma) ont besoin de Chrome | Lancer Chrome headless (`ChromeHeadlessNoSandbox`) avec `--watch=false` |
| Les tests back utilisent HSQLDB en mémoire | Aucune base externe à fournir |
| Aucune mesure de couverture | Activer la couverture et publier les rapports |

## Docker

| Constat | À prévoir dans la CI/CD |
|---------|-------------------------|
| Images de base sans version fixe (`node`, `gradle:jdk17`, `alpine`) | Figer les versions pour que les builds soient reproductibles |
| Java 21 est installé dans l'image alors que le projet cible Java 17 | Aligner l'image d'exécution sur Java 17 |
| Le back expose le port 4200 au lieu de 8080 | Corriger le port exposé |
| Nom du JAR versionné et codé en dur | Utiliser un nom de JAR stable |
| Les conteneurs tournent en root | Créer un utilisateur dédié, sans privilèges |
| `./gradlew build` relance les tests pendant le build de l'image | Ne lancer les tests qu'une fois, dans la CI |
| Cible `standalone` : deux processus via supervisord | Construire une image par service |

## Configuration

| Constat | À prévoir dans la CI/CD |
|---------|-------------------------|
| URL de l'API codée en dur dans le front (`http://localhost:8080`) | Rendre l'URL configurable selon l'environnement |
| Un seul `application.properties` côté back | Créer des profils Spring par environnement |
| Caddy sert le front en HTTPS avec un certificat interne | En tenir compte dans les healthchecks et les tests |
| CORS ouvert à toutes les origines (`*`) | À restreindre selon l'environnement |

## Versionnement, qualité et exploitation

| Constat | À prévoir dans la CI/CD |
|---------|-------------------------|
| Versions figées (`0.0.1-SNAPSHOT`, `0.0.0`), aucun tag | Définir une stratégie de versionnement et de tags |
| Aucun registre d'images | Choisir un registre pour publier les images |
| Ni linter, ni analyse statique | Ajouter le lint et l'analyse de code |
| Aucun scan des dépendances, des images ni des secrets | Ajouter des contrôles de sécurité |
| Base en mémoire : données perdues à chaque redémarrage | Limite à connaître pour les tests de déploiement |
| Pas d'endpoint de santé, pas de logs structurés ni de métriques | Prévoir les healthchecks et la supervision |

## Priorités

1. **Bloquant pour la CI** : droit d'exécution de `gradlew`, Chrome headless pour les tests front.
2. **Nécessaire pour la CD** : corrections du Dockerfile, configuration par environnement, versionnement, registre.
3. **Recommandé** : qualité, sécurité, supervision.
