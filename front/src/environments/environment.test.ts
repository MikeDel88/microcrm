// Environnement de test (CI) : utilisé par `ng test --configuration=test` et `ng build --configuration=test`
export const environment = {
  name: 'test',
  production: false,
  apiBaseUrl: 'http://localhost:8080',
}
