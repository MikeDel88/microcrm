# Fonctionnement du projet

## Présentation

MicroCRM est un CRM (*Customer Relationship Management*) simplifié. Il permet de créer, modifier et consulter des **personnes** rattachées à des **organisations**.

## Monorepo

```
microcrm/
├── back/        API REST Java Spring Boot (Gradle)
├── front/       Application web Angular (SPA)
├── misc/        Caddyfile, supervisor.ini, captures d'écran
└── Dockerfile   Build multi-stage : cibles front, back et standalone
```

## Architecture

```
Navigateur ──► Front Angular (servi par Caddy, 80/443)
     │
     └──────► API REST Spring Data REST (:8080) ──► HSQLDB (en mémoire)
```

- **Back** : deux entités JPA, `Person` et `Organization`, reliées en `@ManyToMany`. Les repositories sont exposés automatiquement en REST par Spring Data REST (`/persons`, `/organizations`), sans contrôleur écrit à la main. `InitialDataFixture` charge un jeu de données au démarrage.
- **Front** : composants standalone (tableau de bord, fiche personne, fiche organisation) et services `PersonService` / `OrganizationService` qui appellent l'API (`http://localhost:8080`).

## Versions

| Élément      | Version |
|--------------|---------|
| Java         | 17      |
| Spring Boot  | 3.2.5   |
| Gradle       | 8.7     |
| Angular      | 17.3    |
| TypeScript   | 5.4     |
| RxJS         | 7.8     |

## Dépendances

**Back**
- `spring-boot-starter-data-jpa` : persistance JPA / Hibernate
- `spring-boot-starter-data-rest` : exposition REST des repositories
- `hsqldb` : base de données en mémoire
- `spring-boot-data-fixtures` (0.2.0) : données initiales
- `spring-boot-starter-test`, plugin `gradle-test-logger` : tests

**Front**
- `@angular/*` (17.3), `rxjs`, `zone.js`
- Tests : Karma + Jasmine

## Lancer le projet

```shell
# Back (http://localhost:8080)
cd back && ./gradlew build && java -jar build/libs/microcrm-0.0.1-SNAPSHOT.jar

# Front (http://localhost:4200)
cd front && npm install && npx @angular/cli serve

# Tests
cd back && ./gradlew test
cd front && npm test
```

Détails dans le [README](../README.md).
