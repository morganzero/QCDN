#!/bin/bash

# Define the subdomain
SUBDOMAIN="cdn"

# Function to update or create Cloudflare DNS record for the subdomain
update_cloudflare_dns_for_subdomain() {
    local retries=5
    local initial_wait=60
    local full_domain="${SUBDOMAIN}.${DOMAIN}"

    for ((i=0; i<retries; i++)); do
        # Initial wait to handle rate limits
        sleep $((initial_wait * i))

        # Check if the DNS record already exists for the subdomain
        response=$(curl -s -X GET "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records?name=${full_domain}&type=A" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
        -H "Content-Type: application/json")

        echo "Response from Cloudflare API: $response"

        record_id=$(echo $response | jq -r '.result[0].id')
        current_ip=$(echo $response | jq -r '.result[0].content')

        echo "Detected record ID: $record_id"
        echo "Current IP in DNS record for ${full_domain}: $current_ip"
        echo "Origin server IP: $ORIGIN_SERVER"

        if [ "$record_id" != "null" ] && [ "$record_id" != "" ]; then
            if [ "$current_ip" == "$ORIGIN_SERVER" ]; then
                echo "DNS record already up-to-date for ${full_domain}"
                return 0
            else
                echo "Updating existing DNS record for ${full_domain}"
                response=$(curl -s -w "%{http_code}" -o response.json -X PUT "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records/${record_id}" \
                -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
                -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
                -H "Content-Type: application/json" \
                --data '{"type":"A","name":"'${full_domain}'","content":"'"${ORIGIN_SERVER}"'","ttl":120,"proxied":false}')
            fi
        else
            echo "Creating new DNS record for ${full_domain}"
            response=$(curl -s -w "%{http_code}" -o response.json -X POST "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
            -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'${full_domain}'","content":"'"${ORIGIN_SERVER}"'","ttl":120,"proxied":false}')
        fi

        http_code=$(tail -n 1 <<< "$response")

        if [ "$http_code" -eq 200 ]; then
            echo "DNS record updated successfully for ${full_domain}"
            return 0
        elif [ "$http_code" -eq 429 ]; then
            echo "Rate limited. Waiting for $((initial_wait * (2**i))) seconds before retrying..."
            sleep $((initial_wait * (2**i)))
        else
            echo "Failed to update DNS record for ${full_domain}. HTTP status code: $http_code"
            cat response.json
            return 1
        fi
    done

    echo "Failed to update DNS record after $retries attempts for ${full_domain}"
    return 1
}

# Ensure ORIGIN_SERVER and DOMAIN are set
if [ -z "$ORIGIN_SERVER" ]; then
    echo "ORIGIN_SERVER environment variable not set"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set"
    exit 1
fi

# Update Cloudflare DNS for the cdn subdomain
update_cloudflare_dns_for_subdomain || exit 1

# Generate Nginx configuration from template
envsubst '${DOMAIN} ${ORIGIN_SERVER} ${CERTS_PATH}' < /etc/nginx/templates/nginx.conf.template > /etc/nginx/nginx.conf

# Start Nginx
exec nginx -g "daemon off;"
