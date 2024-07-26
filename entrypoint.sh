#!/bin/bash

# Function to get the public IP address of the machine
get_public_ip() {
    curl -s https://api.ipify.org
}

# Function to update Cloudflare DNS with retry logic
update_cloudflare_dns() {
    local retries=5
    local wait=30

    for ((i=0; i<retries; i++)); do
        # Check if the DNS record already exists
        response=$(curl -s -X GET "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records?name=cdn.${DOMAIN}&type=A" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
        -H "Content-Type: application/json")

        record_id=$(echo $response | jq -r '.result[0].id')
        current_ip=$(echo $response | jq -r '.result[0].content')

        # Get the public IP address
        public_ip=$(get_public_ip)

        if [ "$record_id" != "null" ]; then
            if [ "$current_ip" == "$public_ip" ]; then
                echo "DNS record already up-to-date"
                return 0
            else
                echo "Updating existing DNS record"
                response=$(curl -s -o response.json -w "%{http_code}" -X PUT "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records/${record_id}" \
                -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
                -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
                -H "Content-Type: application/json" \
                --data '{"type":"A","name":"cdn.'${DOMAIN}'","content":"'"${public_ip}"'","ttl":120,"proxied":true}')
            fi
        else
            echo "Creating new DNS record"
            response=$(curl -s -o response.json -w "%{http_code}" -X POST "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
            -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"cdn.'${DOMAIN}'","content":"'"${public_ip}"'","ttl":120,"proxied":true}')
        fi

        http_code=$(cat response.json | jq -r '.http_code')

        if [ "$http_code" -eq 200 ]; then
            echo "DNS record updated successfully"
            return 0
        elif [ "$http_code" -eq 429 ]; then
            echo "Rate limited. Waiting for $wait seconds before retrying..."
            sleep $wait
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

# Ensure the certificates path is provided
if [ -z "$CERTS_PATH" ]; then
    echo "Certificates path not provided"
    exit 1
fi

# Ensure DOMAIN is set
if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set"
    exit 1
fi

# Wait for the certificates to be available
for i in {1..10}; do
    if [ -f "${CERTS_PATH}/fullchain.pem" ] && [ -f "${CERTS_PATH}/privkey.pem" ]; then
        echo "Certificates found"
        break
    else
        echo "Waiting for certificates..."
        sleep 5
    fi
done

if [ ! -f "${CERTS_PATH}/fullchain.pem" ] || [ ! -f "${CERTS_PATH}/privkey.pem" ]; then
    echo "Certificates not found at ${CERTS_PATH}"
    exit 1
fi

# Generate Nginx configuration from template
envsubst '${DOMAIN} ${ORIGIN_SERVER} ${CERTS_PATH}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/conf.d/default.conf

# Start Nginx
nginx -g "daemon off;"
