#!/bin/bash
set -e

echo "DB_HOST: $DB_HOST"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: $DB_PASSWORD"

# Wait for the database to be ready
while ! mysqladmin ping -h"$DB_HOST" --silent; do
    echo "Waiting for database connection..."
    sleep 5
done

# Function to check if a specific table exists
check_table_exists() {
    local table_name="$1"
    local full_table_name="${DB_PREFIX}${table_name}"
    table_count=$(mysql -u "$DB_USER" --password="$DB_PASSWORD" -h "$DB_HOST" -D "$DB_NAME" -e "SHOW TABLES LIKE '$full_table_name';" | grep "$full_table_name" | wc -l)
    if [ "$table_count" -gt 0 ]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Wait for a specific table to be created
wait_for_table() {
    local table_name="$1"
    while ! check_table_exists "$table_name"; do
        echo "Waiting for table '$table_name' to be created in database '$DB_NAME'..."
        sleep 5
    done
    echo "Table '$table_name' exists."
}

# Check if 'user' table exists
if check_table_exists "user"; then
    echo "Table 'user' already exists. Proceeding with the update."

else
    echo "Table 'user' does not exist. Setting up MediaWiki..."
    php maintenance/install.php \
        --dbserver "$DB_HOST" \
        --dbtype mysql \
        --dbuser "$DB_USER" \
        --dbpass "$DB_PASSWORD" \
        --dbname "$DB_NAME" \
        --dbprefix "$DB_PREFIX" \
        --installdbuser "$DB_USER" \
        --installdbpass "$DB_PASSWORD" \
        --scriptpath "/" \
        --server "https://scwiki.kr" \
        --lang en \
        --pass admin_password \
        "$DB_NAME" "$DB_PASSWORD"

    mv LocalSettings.php LocalSettings-orginal.php
    cp -fv LocalSettings-Sample.php LocalSettings.php

    # Wait for 'slot' table to be created to avoid any race conditions
    wait_for_table "slots"
fi

php maintenance/update.php --quick

# Run the setupStore script for Semantic MediaWiki
php extensions/SemanticMediaWiki/maintenance/setupStore.php

# Run php-fpm
php-fpm