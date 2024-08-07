#!/bin/bash

# Function to update or create Cloudflare DNS record
update_cloudflare_dns() {
    local retries=5
    local initial_wait=60

    for ((i=0; i<retries; i++)); do
        # Initial wait to handle rate limits
        sleep $((initial_wait * i))

        # Check if the DNS record already exists
        response=$(curl -s -X GET "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records?name=${DOMAIN}&type=A" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
        -H "Content-Type: application/json")

        echo "Response from Cloudflare API: $response"

        record_id=$(echo $response | jq -r '.result[0].id')
        current_ip=$(echo $response | jq -r '.result[0].content')

        echo "Detected record ID: $record_id"
        echo "Current IP in DNS record: $current_ip"
        echo "Origin server IP: $ORIGIN_SERVER"

        if [ "$record_id" != "null" ] && [ "$record_id" != "" ]; then
            if [ "$current_ip" == "$ORIGIN_SERVER" ]; then
                echo "DNS record already up-to-date for ${DOMAIN}"
                return 0
            else
                echo "Updating existing DNS record for ${DOMAIN}"
                response=$(curl -s -w "%{http_code}" -o response.json -X PUT "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records/${record_id}" \
                -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
                -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
                -H "Content-Type: application/json" \
                --data '{"type":"A","name":"'${DOMAIN}'","content":"'"${ORIGIN_SERVER}"'","ttl":120,"proxied":false}')
            fi
        else
            echo "Creating new DNS record for ${DOMAIN}"
            response=$(curl -s -w "%{http_code}" -o response.json -X POST "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
            -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'${DOMAIN}'","content":"'"${ORIGIN_SERVER}"'","ttl":120,"proxied":false}')
        fi

        http_code=$(tail -n 1 <<< "$response")

        if [ "$http_code" -eq 200 ]; then
            echo "DNS record updated successfully"
            return 0
        elif [ "$http_code" -eq 429 ]; then
            echo "Rate limited. Waiting for $((initial_wait * (2**i))) seconds before retrying..."
            sleep $((initial_wait * (2**i)))
        else
            echo "Failed to update DNS record. HTTP status code: $http_code"
            cat response.json
            return 1
        fi
    done

    echo "Failed to update DNS record after $retries attempts"
    return 1
}

# Ensure ORIGIN_SERVER is set
if [ -z "$ORIGIN_SERVER" ]; then
    echo "ORIGIN_SERVER environment variable not set"
    exit 1
fi

# Update Cloudflare DNS
update_cloudflare_dns || exit 1

# Ensure DOMAIN is set
if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set"
    exit 1
fi

# Generate SSL certificate using Certbot
if [ ! -f "${CERTS_PATH}/${DOMAIN}/fullchain.pem" ]; then
    echo "Generating SSL certificates for $DOMAIN using Certbot"
    certbot certonly --nginx -n --agree-tos --email "${CLOUDFLARE_EMAIL}" -d "$DOMAIN"
    if [ $? -ne 0 ]; then
        echo "Failed to generate SSL certificates"
        exit 1
    fi
else
    echo "SSL certificates for $DOMAIN already exist"
fi

# Debugging: print the CERTS_PATH content
echo "Listing content of CERTS_PATH ($CERTS_PATH):"
ls -l "$CERTS_PATH/${DOMAIN}"

# Wait for the certificates to be available
for i in {1..10}; do
    if [ -f "${CERTS_PATH}/${DOMAIN}/fullchain.pem" ] && [ -f "${CERTS_PATH}/${DOMAIN}/privkey.pem" ]; then
        echo "Certificates found"
        break
    else
        echo "Waiting for certificates... Attempt $i"
        sleep 5
    fi
done

if [ ! -f "${CERTS_PATH}/${DOMAIN}/fullchain.pem" ] || [ ! -f "${CERTS_PATH}/${DOMAIN}/privkey.pem" ]; then
    echo "Certificates not found at ${CERTS_PATH} after waiting"
    exit 1
fi

# Generate Nginx configuration from template
envsubst '${DOMAIN} ${ORIGIN_SERVER} ${CERTS_PATH}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

# Create the default server block configuration file
cat > /etc/nginx/conf.d/default.conf <<EOL
server {
    listen 80;
    server_name ${DOMAIN};

    # Redirect HTTP to HTTPS
    return 308 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${CERTS_PATH}/${DOMAIN}/fullchain.pem;
    ssl_certificate_key ${CERTS_PATH}/${DOMAIN}/privkey.pem;

    # Serve a simple message for HTTPS requests
    location / {
        return 200 '<html><body><h1>This domain is used for CDN purposes only.</h1></body></html>';
        add_header Content-Type text/html;
    }
}
EOL

# Handle multiple applications
for app_num in $(seq 1 20); do
    app_domain_var="APP${app_num}_DOMAIN"
    app_target_var="APP${app_num}_TARGET"
    app_port_var="APP${app_num}_TARGET_PORT"

    app_domain="${!app_domain_var}"
    app_target="${!app_target_var}"
    app_port="${!app_port_var}"

    if [ -n "$app_domain" ] && [ -n "$app_target" ] && [ -n "$app_port" ]; then
        echo "Configuring application #$app_num: $app_domain -> $app_target:$app_port"

        cat >> /etc/nginx/conf.d/default.conf <<EOL
server {
    listen 80;
    server_name ${app_domain};

    location / {
        proxy_pass http://${app_target}:${app_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name ${app_domain};

    ssl_certificate ${CERTS_PATH}/${DOMAIN}/fullchain.pem;
    ssl_certificate_key ${CERTS_PATH}/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://${app_target}:${app_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
    fi
done

# Start Nginx
exec nginx -g "daemon off;"
