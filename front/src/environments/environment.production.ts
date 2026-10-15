// Build de production (image Docker). L'URL de l'API sera lue à l'exécution (voir documentation, scénario B § 5.4).
export const environment = {
  name: 'production',
  production: true,
  apiBaseUrl: 'http://localhost:8080',
}
