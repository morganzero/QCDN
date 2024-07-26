# QCDN

QCDN is a Docker-based CDN server using Nginx and Cloudflare for efficient and secure content delivery. This setup ensures optimal routing for faster performance.

## How to Use

### Prerequisites

- Docker installed on your system.
- Cloudflare account with API credentials.
- SSL certificates available on your system.

### Docker Run Command

Replace the environment variable values with your actual data.

```sh
docker run -d \
    --name qcdn \
    -e CLOUDFLARE_EMAIL="your_cloudflare_email@example.com" \
    -e CLOUDFLARE_API_KEY="your_cloudflare_api_key" \
    -e ZONE_ID="your_zone_id" \
    -e DOMAIN="your_domain.com" \
    -e ORIGIN_SERVER="your_origin_server_ip_or_domain" \
    -e CERTS_PATH="/path/to/your/certs" \
    -v /path/to/your/certs:/path/to/your/certs:ro \
    -p 80:80 -p 443:443 \
    sushibox/qcdn:latest
```
