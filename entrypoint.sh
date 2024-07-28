#!/bin/bash

# Function to update or create Cloudflare DNS record
update_cloudflare_dns() {
    local domain=$1
    local target=$2

    local retries=5
    local initial_wait=60

    for ((i=0; i<retries; i++)); do
        # Initial wait to handle rate limits
        sleep $((initial_wait * i))

        # Check if the DNS record already exists
        response=$(curl -s -X GET "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records?name=${domain}&type=A" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
        -H "Content-Type: application/json")

        echo "Response from Cloudflare API: $response"

        record_id=$(echo $response | jq -r '.result[0].id')
        current_ip=$(echo $response | jq -r '.result[0].content')

        echo "Detected record ID: $record_id"
        echo "Current IP in DNS record: $current_ip"
        echo "Origin server IP: $target"

        if [ "$record_id" != "null" ] && [ "$record_id" != "" ]; then
            if [ "$current_ip" == "$target" ]; then
                echo "DNS record already up-to-date for $domain"
                return 0
            else
                echo "Updating existing DNS record for $domain"
                response=$(curl -s -w "%{http_code}" -o response.json -X PUT "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records/${record_id}" \
                -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
                -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
                -H "Content-Type: application/json" \
                --data '{"type":"A","name":"'${domain}'","content":"'"${target}"'","ttl":120,"proxied":false}')
            fi
        else
            echo "Creating new DNS record for $domain"
            response=$(curl -s -w "%{http_code}" -o response.json -X POST "${CLOUDFLARE_API_URL}/zones/${ZONE_ID}/dns_records" \
            -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
            -H "X-Auth-Key: ${CLOUDFLARE_API_KEY}" \
            -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'${domain}'","content":"'"${target}"'","ttl":120,"proxied":false}')
        fi

        http_code=$(tail -n 1 <<< "$response")

        if [ "$http_code" -eq 200 ]; then
            echo "DNS record for $domain updated successfully"
            return 0
        elif [ "$http_code" -eq 429 ]; then
            echo "Rate limited. Waiting for $((initial_wait * (2**i))) seconds before retrying..."
            sleep $((initial_wait * (2**i)))
        else
            echo "Failed to update DNS record for $domain. HTTP status code: $http_code"
            cat response.json
            return 1
        fi
    done

    echo "Failed to update DNS record for $domain after $retries attempts"
    return 1
}

# Ensure ORIGIN_SERVER is set
if [ -z "$ORIGIN_SERVER" ]; then
    echo "ORIGIN_SERVER environment variable not set"
    exit 1
fi

# Update Cloudflare DNS for the main QCDN server
update_cloudflare_dns "cdn.${DOMAIN}" "$ORIGIN_SERVER" || exit 1

# Iterate over each APPn_DOMAIN and APPn_TARGET
for i in {1..20}; do
    domain_var="APP${i}_DOMAIN"
    target_var="APP${i}_TARGET"
    target_port_var="APP${i}_TARGET_PORT"

    domain="${!domain_var}"
    target="${!target_var}"
    target_port="${!target_port_var:-80}"

    if [ -n "$domain" ] && [ -n "$target" ]; then
        update_cloudflare_dns "$domain" "$target" || exit 1
    fi
done

# Ensure the certificates path is provided
if [ -z "$CERTS_PATH" ]; then
    echo "Certificates path not provided"
    exit 1
fi

# Debugging: print the CERTS_PATH content
echo "Listing content of CERTS_PATH ($CERTS_PATH):"
ls -l "$CERTS_PATH"

# Wait for the certificates to be available
for i in {1..10}; do
    if [ -f "${CERTS_PATH}/fullchain.pem" ] && [ -f "${CERTS_PATH}/privkey.pem}" ]; then
        echo "Certificates found"
        break
    else
        echo "Waiting for certificates... Attempt $i"
        sleep 5
    fi
done

if [ ! -f "${CERTS_PATH}/fullchain.pem" ] || [ ! -f "${CERTS_PATH}/privkey.pem" ]; then
    echo "Certificates not found at ${CERTS_PATH} after waiting"
    exit 1
fi

# Create a new Nginx configuration file
echo "Creating Nginx configuration"

cat <<EOF > /etc/nginx/nginx.conf
events {}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
EOF

# Generate Nginx configuration for each application
for i in {1..20}; do
  domain_var="APP${i}_DOMAIN"
  target_var="APP${i}_TARGET"
  target_port_var="APP${i}_TARGET_PORT"

  domain="${!domain_var}"
  target="${!target_var}"
  target_port="${!target_port_var:-80}"

  if [ -n "$domain" ] && [ -n "$target" ]; then
    cat <<EOF >> /etc/nginx/nginx.conf
    server {
        listen 80;
        server_name $domain;

        # Redirect HTTP to HTTPS
        return 308 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $domain;

        ssl_certificate ${CERTS_PATH}/fullchain.pem;
        ssl_certificate_key ${CERTS_PATH}/privkey.pem;

        location / {
            proxy_pass http://$target:$target_port;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_buffering off;
            proxy_set_header Connection "Keep-Alive";
            proxy_http_version 1.1;
        }
    }
EOF
  fi
done

# Close the http block
echo "}" >> /etc/nginx/nginx.conf

# Start Nginx
exec "$@"
