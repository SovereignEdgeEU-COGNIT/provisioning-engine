#!/usr/bin/env bash

ee_token=$1
password=$2
version=$3
test_user=$4

if [[ ! -f /usr/bin/oned ]]; then # install minione
    apt update
    apt install -y ca-certificates
    wget 'https://github.com/OpenNebula/minione/releases/latest/download/minione'
    bash ./minione --enterprise "$ee_token" --password "$password" --yes --force --sunstone-port 9869 --version "$version"
fi

app_components=$(onemarketapp export "Ttylinux - KVM" -d 1 "ttylinux")

app_template=$( echo "$app_components" | head -n 2 | tail -n 1 | cut -d ':' -f 2)
app_image=$(echo "$app_components" | tail -n 1 | cut -d ':' -f 2)


# create user to run Github Actions tests
oneuser create "$test_user" "$password"
# create empty virtual network to force service deployment failure
echo -e NAME=\"github_actions_no_lease\"\\nVN_MAD=\"bridge\"\\nAR=[TYPE=\"ETHERNET\",SIZE=\"0\"] | onevnet create

# configure oneflow to listen external requests

# - name: Create VM Templates for Github Actions
#   15 github_a oneadmin Github Actions FAILED_DEPLOY                                                                                                                 11/14 02:15:05
#    9 github_a oneadmin Github Actions

# "shutdown_action": "terminate-hard",

# - name: Create Service Templates for Github Actions
#  575 github_a oneadmin FAILED_DEPLOY                                                                                                                                11/14 02:18:12
#  276 github_a oneadmin DenyVMTemplate                                                                                                                               10/13 22:17:10
#  199 github_a oneadmin Function-Data    # add DAAS role after clone from Function                                                                                                                            10/10 22:54:20
#   63 github_a oneadmin Function

services="Function, Function-Data DenyVMTemplate FAILED_DEPLOY"

for s in $services; do
    onetemplate clone "$app_template" "$s"
    onetemplate chown "$s" "$test_user"
done

# - name: Create Service Templates for Github Actions
