# MinIO Docker Server

Ce projet lance un serveur MinIO compatible S3 avec Docker Compose. Les donnees persistantes sont stockees dans `minio-data/data`, et chaque bucket apparaitra sous `minio-data/data/<nom-du-bucket>`.

## Demarrage local

1. Copie l'exemple d'environnement :

   ```powershell
   Copy-Item .env.example .env
   ```

2. Modifie `.env` et remplace obligatoirement :

   - `MINIO_ROOT_USER`
   - `MINIO_ROOT_PASSWORD`
   - `MINIO_APP_USER`
   - `MINIO_APP_PASSWORD`
   - `MINIO_BUCKETS`

3. Lance MinIO :

   ```powershell
   docker compose up -d
   ```

4. Verifie l'etat :

   ```powershell
   docker compose ps
   docker compose logs -f minio-bootstrap
   ```

Par defaut, l'API S3 ecoute sur `http://127.0.0.1:9000` et la console sur `http://127.0.0.1:9001`.

## Buckets

Les buckets sont crees automatiquement par le service `minio-bootstrap` a partir de `MINIO_BUCKETS`.

Exemple :

```env
MINIO_BUCKETS=app-data,backups,logs
```

MinIO ecrira les donnees dans :

```text
minio-data/data/app-data
minio-data/data/backups
minio-data/data/logs
```

Le script active aussi le versioning si `MINIO_ENABLE_VERSIONING=true`.

## Securite

- `.env`, `minio-data/` et `certs/` sont ignores par Git.
- Les ports sont limites a `127.0.0.1` par defaut. Pour exposer MinIO, utilise de preference un reverse proxy HTTPS.
- Le service Docker utilise `no-new-privileges` et retire les capabilities Linux.
- Un utilisateur applicatif optionnel est cree avec une policy limitee aux buckets de `MINIO_BUCKETS`.
- Ne donne pas les identifiants root aux applications. Utilise `MINIO_APP_USER` et `MINIO_APP_PASSWORD`.

## TLS / reverse proxy

Pour une exposition publique, garde `MINIO_API_BIND=127.0.0.1` et `MINIO_CONSOLE_BIND=127.0.0.1`, puis place Nginx, Caddy ou Traefik devant MinIO avec HTTPS.

Si tu exposes des URL publiques, renseigne aussi :

```env
MINIO_SERVER_URL=https://s3.example.com
MINIO_BROWSER_REDIRECT_URL=https://minio.example.com
```

## Deploiement

La pipeline GitHub Actions `.github/workflows/deploy-minio.yml` :

1. valide `docker compose config`;
2. se connecte en SSH avec un mot de passe;
3. copie `docker-compose.yml` et `scripts/` avec `tar` via SSH, sans supprimer `minio-data/` ni `certs/`;
4. ecrit le contenu de `DEPLOY_ENV_FILE` dans `.env` sur le serveur;
5. execute Compose v2 (`docker compose`) ou, a defaut, Compose v1 (`docker-compose`) pour mettre a jour la stack.

Secrets GitHub Actions requis :

```text
DEPLOY_HOST
DEPLOY_USER
DEPLOY_PATH
DEPLOY_PORT
DEPLOY_PASSWORD
DEPLOY_ENV_FILE
```

`DEPLOY_PORT` utilise `22` par defaut. `DEPLOY_ENV_FILE` doit contenir le contenu complet du fichier `.env` de production. La pipeline ne demande ni passphrase, ni cle privee/publique. Le compte `DEPLOY_USER` doit pouvoir ecrire dans `DEPLOY_PATH` et executer Docker Compose. Le serveur doit fournir soit le plugin Compose v2 (`docker compose`), soit la commande Compose v1 (`docker-compose`). Si Compose est absent sur un serveur utilisant `apt-get`, la pipeline tente d'installer `docker-compose-plugin` lorsque `DEPLOY_USER` est `root` ou dispose de `sudo` sans mot de passe.

Pour mettre a jour MinIO, modifie la version par defaut de l'image dans `docker-compose.yml`, commit, puis declenche la pipeline. Si `MINIO_VERSION` est defini dans le `.env` du serveur, cette valeur distante prendra le dessus. Attention : certaines releases source MinIO n'ont pas d'image Docker publique correspondante ; verifie toujours le tag Docker avant de le deployer.

## Commandes utiles

```powershell
docker compose pull
docker compose up -d --remove-orphans
docker compose logs -f minio
docker compose run --rm minio-bootstrap
docker compose down
```
