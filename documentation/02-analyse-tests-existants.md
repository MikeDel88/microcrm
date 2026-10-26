# Analyse des tests existants (début de projet)

État des tests fournis avec le socle initial de MicroCRM.

## Synthèse

| Partie | Outils                     | Fichiers de test | Tests |
|--------|----------------------------|------------------|-------|
| Back   | JUnit 5 + Spring Boot Test | 2                | 2     |
| Front  | Jasmine + Karma            | 6                | 8     |

Lancement : `./gradlew test` (back), `npm test` (front, nécessite Chrome via `CHROME_BIN`).

## Back

| Test | Type | Ce qui est vérifié |
|------|------|--------------------|
| `MicroCRMApplicationTests.contextLoads` | `@SpringBootTest` | Le contexte Spring démarre (test de fumée) |
| `PersonRepositoryIntegrationTest.whenFindByEmail_thenReturnPerson` | `@DataJpaTest` (HSQLDB) | La requête `findByEmail` retrouve une personne |

**Limites**
- `found.get()` est appelé sans vérifier que le résultat est présent. Si la personne n'est pas trouvée, le test s'arrête sur une exception au lieu d'un échec d'assertion clair.
- L'import `SpringBootTest` n'est pas utilisé.
- Rien n'est testé sur :
  - les endpoints REST exposés par Spring Data REST ;
  - l'entité `Organization` et la relation `@ManyToMany` ;
  - le `@PreRemove` de `Person` ;
  - la configuration CORS ;
  - `InitialDataFixture`.
- Aucune mesure de couverture (pas de JaCoCo).

## Front

| Fichier | Tests | Ce qui est vérifié |
|---------|-------|--------------------|
| `app.component.spec.ts` | 3 | Création du composant, titre « MicroCRM », rendu du `<h1>` |
| `main-dashboard.component.spec.ts` | 1 | « should create » |
| `person-details.component.spec.ts` | 1 | « should create » |
| `organization-details.component.spec.ts` | 1 | « should create » |
| `person.service.spec.ts` | 1 | « should be created » |
| `organization.service.spec.ts` | 1 | « should be created » |

**Limites**
- Les appels HTTP ne sont jamais vérifiés : `HttpClientTestingModule` est importé, mais `HttpTestingController` n'est jamais utilisé.
- Aucune logique métier n'est testée : chargement des données, création, modification, suppression, ajout ou retrait d'une organisation.
- Deux specs (`person-details`, `organization-details`) ont un `describe` mal nommé : `'IndividualDetailsComponent'`.
- `RouterTestingModule` est déprécié.
- La couverture n'est pas produite par défaut, car le reporter `coverage` n'est pas activé dans `karma.conf.js`.

## Bilan

Les tests existants sont presque tous des **tests de fumée**. Ils détectent une application qui ne compile plus ou ne démarre plus, mais **pas les régressions fonctionnelles**. Seuls les tests back sont exécutés automatiquement, pendant le build Docker (`./gradlew build`). Aucune CI n'existe.

## Pistes d'amélioration

- Front : tester les services avec `HttpTestingController` et les composants avec des services simulés (mocks).
- Back : tester les endpoints REST (MockMvc ou `@SpringBootTest(webEnvironment = RANDOM_PORT)`) et la relation Person ↔ Organization.
- Mesurer la couverture (JaCoCo pour le back, `--code-coverage` pour le front).
- Lancer les tests automatiquement en CI à chaque pull request.
- Corriger les noms de `describe` et remplacer les API dépréciées.
