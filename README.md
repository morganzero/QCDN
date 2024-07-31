# QCDN

QCDN is a Docker-based CDN server using Nginx and Cloudflare for efficient and secure content delivery. This setup ensures optimal routing for faster performance.

## Prerequisites

- Docker installed on your system.
- Cloudflare account with API credentials.
- SSL certificates available on your system.

## Step-by-Step Setup

### 1. Prepare Your Environment Variables

Replace the placeholder values with your actual data. Ensure that each application has a unique subdomain specified by the `APPn_DOMAIN` variables.

### 2. Run QCDN Container

Use the following `docker run` command:

```sh
docker run -d \
    --name qcdn \
    -e CLOUDFLARE_EMAIL="your_cloudflare_email@example.com" \
    -e CLOUDFLARE_API_KEY="your_cloudflare_api_key" \
    -e ZONE_ID="your_zone_id" \
    -e DOMAIN="your_domain.com" \
    -e ORIGIN_SERVER="your_qcdn_server_ip_or_domain" \
    -e CERTS_PATH="/path/to/your/certs" \
    -e APP1_DOMAIN="plex-cdn.your_domain.com" \
    -e APP1_TARGET="your_plex_server_ip_or_domain" \
    -e APP1_TARGET_PORT="443" \
    -e APP2_DOMAIN="app2-cdn.your_domain.com" \
    -e APP2_TARGET="internal-web-app-ip-or-domain" \
    -e APP2_TARGET_PORT="8080" \
    -e APP3_DOMAIN="blog-cdn.your_domain.com" \
    -e APP3_TARGET="blog-server-ip-or-domain" \
    -e APP3_TARGET_PORT="80" \
    -v /path/to/your/certs:/path/to/your/certs:ro \
    -p 80:80 -p 443:443 \
    sushibox/qcdn:latest

```
### 3. Configure DNS Records in Cloudflare

Ensure the following DNS records are created in Cloudflare for your domain:

#### Plex

| Type | Name                 | Content                        | TTL  | Proxied |
|------|----------------------|--------------------------------|------|---------|
| A    | plex-cdn             | Public IP of QCDN machine      | Auto | False   |

#### Internal Web App

| Type | Name                 | Content                         | TTL  | Proxied |
|------|----------------------|---------------------------------|------|---------|
| A    | app2-cdn             | internal-web-app-ip-or-domain   | Auto | False   |

#### Blog

| Type | Name                 | Content                         | TTL  | Proxied |
|------|----------------------|---------------------------------|------|---------|
| A    | blog-cdn             | blog-server-ip-or-domain        | Auto | False   |

### 4. Configure Plex Network Custom URL

1. **Open Plex Web Interface**:
    - Go to `http://plex-server.your_domain.com:32400/web`.

2. **Navigate to Settings**:
    - Go to `Settings > Server > Network`.

3. **Set Custom Network URL**:
    - In the `Custom server access URLs` field, enter: `https://plex-cdn.your_domain.com`.

4. **Save Changes**:
    - Click `Save Changes` to apply the new network settings.

### Example with Multiple Applications

Here’s how you can configure multiple applications with unique subdomains:

```sh
docker run -d \
docker run -d \
    --name qcdn \
    -e CLOUDFLARE_EMAIL="your_cloudflare_email@example.com" \
    -e CLOUDFLARE_API_KEY="your_cloudflare_api_key" \
    -e ZONE_ID="your_zone_id" \
    -e DOMAIN="your_domain.com" \
    -e ORIGIN_SERVER="your_qcdn_server_ip_or_domain" \
    -e CERTS_PATH="/path/to/your/certs" \
    -e APP1_DOMAIN="plex-cdn.your_domain.com" \
    -e APP1_TARGET="your_plex_server_ip_or_domain" \
    -e APP1_TARGET_PORT="443" \
    -e APP2_DOMAIN="app2-cdn.your_domain.com" \
    -e APP2_TARGET="internal-web-app-ip-or-domain" \
    -e APP2_TARGET_PORT="8080" \
    -e APP3_DOMAIN="blog-cdn.your_domain.com" \
    -e APP3_TARGET="blog-server-ip-or-domain" \
    -e APP3_TARGET_PORT="80" \
    -v /path/to/your/certs:/path/to/your/certs:ro \
    -p 80:80 -p 443:443 \
    sushibox/qcdn:latest
```
### Summary

1. **Run QCDN Container**: Use the provided `docker run` command with unique subdomains for each application.
2. **Automatic DNS Management**: The `entrypoint.sh` script will manage the DNS records in Cloudflare.
3. **Configure Plex**: Set the `Custom server access URLs` in Plex to `https://plex-cdn.your_domain.com`.
