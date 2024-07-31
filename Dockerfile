# Step 1: Build stage
FROM python:3.9-slim as builder

LABEL maintainer="morganzero@sushibox.dev"
LABEL description="QCDN is a Docker-based CDN server using Nginx and Cloudflare"

# Install necessary packages including Certbot
RUN apt-get update && apt-get install -y curl jq certbot && rm -rf /var/lib/apt/lists/*

# Install required Python packages
RUN pip install requests

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Step 2: Final stage
FROM nginx:alpine

LABEL maintainer="morganzero@sushibox.dev"
LABEL description="QCDN is a Docker-based CDN server using Nginx and Cloudflare"

# Copy the Nginx template configuration file
COPY nginx.conf /etc/nginx/templates/nginx.conf.template

# Copy the entrypoint script from the builder stage
COPY --from=builder /entrypoint.sh /entrypoint.sh

# Install bash and jq for the entrypoint script, and add Certbot
RUN apk add --no-cache bash jq certbot-nginx

# Set environment variables
ENV CLOUDFLARE_API_URL="https://api.cloudflare.com/client/v4"
ENV CLOUDFLARE_EMAIL=""
ENV CLOUDFLARE_API_KEY=""
ENV ZONE_ID=""
ENV DOMAIN=""
ENV CERTS_PATH="/etc/letsencrypt/live"

# Entry point
ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
